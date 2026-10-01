class_name TierMusicController
extends Node
## Layered/"vertical remix" tier music: one loopable track per tier
## (`tracks[0]` = Tier 0 ... `tracks[5]` = Tier 5), all of them always
## audibly playing at once for the entire session — only each layer's
## *volume* changes as tiers advance, never whether it's playing. Reaching
## tier N fades layer N in (0..N-1 stay exactly as they were); nothing
## ever fades back out (no mechanic loses a tier).
##
## **All layers share a single playback clock via `AudioStreamSynchronized`
## (Godot's built-in interactive-music stream), not N independent
## AudioStreamPlayers.** This is deliberate, not the literal "start the new
## layer at whatever second the others are currently at" the request
## described: seeding a freshly-started AudioStreamPlayer with a computed
## playback position still leaves it on its own independent playback
## clock afterward, so it and every earlier layer can drift apart, sample
## by sample, over a long session (buffer-scheduling jitter, resample
## rounding) with no way to correct it short of periodically re-seeking —
## which itself causes an audible micro-jump. A single synchronized stream
## has exactly one playback clock for every layer, so there is no
## drift to correct in the first place, for a session of any length. See
## decisions.md.
##
## Every tier's own .wav is forced into `LOOP_FORWARD` at `_ready()` via
## `LoopingAudioStream.force_full_loop()` (`scenes/audio/`, shared with
## `MenuMusicPlayer` — see its own class doc for why this has to happen in
## code rather than via each file's `.wav.import`, and a real bug that
## logic went through before landing here). Every track is authored to
## the exact same length (confirmed 108.292063s each) specifically so
## that shared loop point stays sample-aligned across all six layers
## forever, not just at tier-up time.
##
## Robust to save-load ordering: `FactoryWorld.apply_save_data()` (which
## restores `TierManager.current_tier`) runs from `FactoryWorld._ready()`,
## which fires *after* every child's own `_ready()` — including this
## one's — so reading `tier_manager.current_tier` once at `_ready()` would
## only ever see the fresh-game default. Instead this polls it every
## frame (same cheap-int-comparison idiom `FactoryHud` already uses for
## `%JobsLabel`/`%TierLabel`) and treats the first tick as a sentinel: it
## snaps every layer straight to its target volume with no fade (correct
## for both a brand-new game at Tier 0 and a loaded save already deep into
## the tiers), and only fades on every tick after that, when a change in
## `current_tier` means a live `advance_tier()` just happened.
##
## **Actual playback doesn't start in `_ready()`** — `_ready()` only builds
## the stream and gets every layer's volume tracking the current tier
## correctly (see above); `start_playback()` is a separate, explicit call
## `FactoryWorld` makes once it's decided *when* the player should first
## hear anything. That's immediately for a loaded save (already showing
## the correct tier the instant the factory appears), but only once
## `OpeningSequence`'s first message is dismissed for a brand new game —
## starting music the instant an empty factory with no cat yet visible
## loads would undercut that opening beat. Every layer's volume is already
## correct by the time `start_playback()` fires regardless of which path
## led there, since `_process()` above keeps tracking `current_tier`
## whether or not the player has actually started.

## One entry per tier, index 0..5 — Tier 0's track first. Sized/ordered to
## match TierManager.TIER_NAMES minus "Tier Winner" (Tier Winner reuses
## Tier 5's layer; the credits sequence keeps gameplay music playing
## underneath, see VictorySequence's own class doc).
@export var tracks: Array[AudioStream] = []

## How long a newly-unlocked layer takes to fade up from silent to full
## volume. Deliberately much longer than this project's UI fades
## (VictorySequence's screen fades are 0.6s) — a musical layer entrance
## reads as an abrupt cut at that speed; this is a slow, deliberate swell.
@export_range(0.5, 10.0, 0.1) var fade_seconds: float = 2.5

## Per-layer volume once active. 0 dB (unchanged) by default; lower this
## if six full-volume layers stacked at Tier 5 sit too loud in the mix.
@export_range(-80.0, 0.0, 0.5) var active_volume_db: float = 0.0

@export var tier_manager: TierManager

## Matches AudioStreamPlayer/MusicController's own silence-floor
## convention elsewhere in this project.
const _SILENT_DB: float = -80.0

var _stream: AudioStreamSynchronized
var _player: AudioStreamPlayer
var _tweens: Array[Tween] = []
var _started: bool = false

## Separate from `_tweens` above (which move each layer's own sync-stream
## volume): duck()/unduck() move `_player`'s own volume_db instead, so a
## caller ducking the whole mix for a beat (see FactoryWorld's ending
## sequence) never fights `_set_layer_active`'s per-layer fades for the
## same tween, and always has exactly one duck in flight at a time.
var _duck_tween: Tween

## -1 is a sentinel meaning "never synced yet" — see class doc's note on
## why the very first sync must be instant, not faded.
var _synced_tier: int = -1


func _ready() -> void:
	if tracks.is_empty():
		return
	_stream = AudioStreamSynchronized.new()
	_stream.stream_count = tracks.size()
	_tweens.resize(tracks.size())
	for i: int in tracks.size():
		LoopingAudioStream.force_full_loop(tracks[i])
		_stream.set_sync_stream(i, tracks[i])
		_stream.set_sync_stream_volume(i, _SILENT_DB)

	_player = AudioStreamPlayer.new()
	_player.bus = &"Music"
	_player.stream = _stream
	# autoplay is deliberately left false: the template's MusicController
	# autoload (project_music_controller.tscn) reparents/crossfades any
	# AudioStreamPlayer it finds with autoplay = true on this same bus,
	# which would fight this node for ownership of playback. Playback is
	# started explicitly, on request, via start_playback() below — which
	# also keeps this player invisible to that system while still routing
	# through "Music" so the options menu's music volume slider still
	# affects it like any other music.
	add_child(_player)


## See the class doc's note on why playback start is a separate, explicit
## call rather than something `_ready()` does unconditionally. Idempotent
## (a second call is a no-op) since callers may not always be able to
## guarantee this fires only once — e.g. FactoryWorld connects it to
## OpeningSequence.message_dismissed with CONNECT_ONE_SHOT already, but
## there's no cost to being defensive here too.
func start_playback() -> void:
	if _started or _player == null:
		return
	_started = true
	# call_deferred, not a direct call: MusicController.play_stream() (the
	# template's own equivalent path) does the same, since a stream player
	# added a prior frame still isn't guaranteed registered in the tree
	# for playback to begin the instant this is called (e.g. immediately
	# from FactoryWorld._ready(), the same frame this node's own _ready()
	# added _player as a child).
	_player.play.call_deferred()


func _process(_delta: float) -> void:
	if tier_manager == null or _stream == null:
		return
	var tier: int = clampi(tier_manager.current_tier, 0, tracks.size() - 1)
	if tier == _synced_tier:
		return
	var instant: bool = _synced_tier == -1
	_synced_tier = tier
	for i: int in tracks.size():
		_set_layer_active(i, i <= tier, instant)


func _set_layer_active(index: int, active: bool, instant: bool) -> void:
	var target_db: float = active_volume_db if active else _SILENT_DB
	if instant:
		_stream.set_sync_stream_volume(index, target_db)
		return
	var existing: Tween = _tweens[index]
	if existing != null and existing.is_valid():
		existing.kill()
	var tween: Tween = create_tween()
	tween.tween_method(
			_apply_layer_volume.bind(index),
			_stream.get_sync_stream_volume(index),
			target_db,
			fade_seconds)
	_tweens[index] = tween


func _apply_layer_volume(volume_db: float, index: int) -> void:
	_stream.set_sync_stream_volume(index, volume_db)


## Fades the whole mix (every layer at once, via the shared `_player`'s
## own volume_db) down to `target_linear` of its current level over
## `duration` seconds, and awaits that fade before returning — see
## FactoryWorld's ending sequence, which awaits this before playing
## `ending.wav` so the sting isn't buried under the still-playing tier
## music. `target_linear` is relative to the music's own volume, not the
## Master/Music bus sliders those already sit under.
func duck(target_linear: float, duration: float) -> void:
	await _tween_player_volume(linear_to_db(target_linear), duration)


## Fades back up to unducked (0 dB, i.e. whatever the per-layer tier
## volumes were already tracking) over `duration` seconds. Not awaited by
## FactoryWorld — the swell is meant to bleed into the start of the
## credits rather than block anything further.
func unduck(duration: float) -> void:
	await _tween_player_volume(0.0, duration)


func _tween_player_volume(target_db: float, duration: float) -> void:
	if _player == null:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(_player, "volume_db", target_db, duration)
	await _duck_tween.finished
