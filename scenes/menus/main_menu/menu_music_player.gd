class_name MenuMusicPlayer
extends AudioStreamPlayer
## Script override for `main_menu_with_animations.tscn`'s
## `BackgroundMusicPlayer` (an instance of the template's own
## `background_music_player.tscn` — `autoplay = true`, bus `Music`
## already set there; not edited, per this project's "don't edit
## addons/" convention). That scene has no loop-forcing logic of its own,
## so without this, `stream` would play through once and then go silent
## — the addon's `ProjectMusicController` autoload only crossfades
## between music players as they enter/exit the tree, it doesn't restart
## a track that reaches its natural end. See `LoopingAudioStream`'s own
## class doc for why the loop has to be forced here in code rather than
## via `stream`'s own `.wav.import` settings.
##
## Also swells the track up from silence when the title screen appears,
## rather than having it hit full volume on the game's very first frame
## — see `fade_in_seconds`.

## How long the title screen music takes to rise from silent to the
## volume authored on this node. The fade is done here rather than
## through `MusicController.fade_in_duration` (the addon autoload's own
## equivalent) for two reasons: that property lives on
## `project_music_controller.tscn` under `addons/`, so setting it would
## mean editing the template, and it applies to *every* music player the
## controller ever blends to, not just the title screen's.
@export_range(0.0, 10.0, 0.1) var fade_in_seconds: float = 2.5

## Matches TierMusicController/MusicController's own silence-floor
## convention elsewhere in this project.
const _SILENT_DB: float = -80.0

## The volume authored on this node, captured before the fade overwrites
## it — the fade's target, so tuning `volume_db` in the scene keeps
## working normally.
var _full_volume_db: float = 0.0


## Silencing happens in `_enter_tree()`, not `_ready()`: playback doesn't
## start from this node at all, it's started by `ProjectMusicController`
## from its `SceneTree.node_added` handler, which fires *between* those
## two callbacks. Silencing in `_ready()` would leave a frame of music at
## full volume before the fade ever begins.
func _enter_tree() -> void:
	_full_volume_db = volume_db
	if fade_in_seconds > 0.0:
		volume_db = _SILENT_DB


func _ready() -> void:
	LoopingAudioStream.force_full_loop(stream)
	if fade_in_seconds > 0.0:
		var tween: Tween = create_tween()
		tween.tween_method(_apply_fade_volume, 0.0, 1.0, fade_in_seconds)


## Tweened over *amplitude*, converted to dB here, rather than tweening
## `volume_db` straight from `_SILENT_DB` to `_full_volume_db`: a linear
## ramp in dB from a -80 floor spends over half its length below -40 dB
## (inaudible), so a 2.5s fade would read as roughly a second of silence
## followed by an abrupt 1s swell. A linear ramp in amplitude is the
## even, gradual rise this is meant to be.
func _apply_fade_volume(linear: float) -> void:
	volume_db = maxf(_SILENT_DB, _full_volume_db + linear_to_db(linear))
