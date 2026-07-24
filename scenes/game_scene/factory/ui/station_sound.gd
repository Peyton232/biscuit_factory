class_name StationSound
extends Node3D
## Looping sound feedback for a ProcessingBuilding, instanced per station
## scene (mirrors BuildingProgressBar's "one script, per-type export
## values set in each station's own .tscn" pattern). Plays ambient_sound
## on a loop, but only while this station is BOTH actively processing
## (building.progress() > 0.0) AND visible on screen
## (VisibleOnScreenNotifier3D) — with potentially dozens of stations
## running at once, looping ambience from every single one regardless of
## camera framing would be a wall of noise; gating on visibility keeps it
## to "what the player can currently see," and using AudioStreamPlayer3D
## (positional, distance-attenuated) means even several simultaneously-
## visible stations blend by distance instead of all stacking at full
## volume. VisibleOnScreenNotifier3D is Godot's own built-in "is this
## AABB inside the camera frustum right now" node — the idiomatic tool
## for exactly this, rather than hand-rolling frustum math.
##
## ambient_gap_seconds (default 0, a true back-to-back loop — Mixer/Oven/
## Cutting Station) adds a pause between repeats instead of restarting
## the instant the clip finishes — the Assembly Table uses a 0.6s gap so
## assembly_pop.wav reads as a repeating pulse timed to the work, not a
## continuous drone, for as long as the batch keeps processing. Restart
## timing (gap or not) is driven from _process() rather than restarting
## synchronously inside the `finished` signal handler, so both cases
## share one state machine instead of two separate code paths — the only
## cost is the true-loop case restarting on the next frame rather than
## the same frame `finished` fires, imperceptible for a looping ambience.
##
## Previously also had a one-shot `start_sound` (Sfx.spawn() on a
## ProcessingBuilding.batch_started signal) for the Assembly Table's
## "starts work" pop — removed once that pop became this looping,
## gapped ambient_sound instead, since nothing else used it. See
## decisions.md.

@export var building: ProcessingBuilding
@export var ambient_sound: AudioStream
## Pause after ambient_sound finishes before it plays again. 0 = loop
## back-to-back with no gap.
@export var ambient_gap_seconds: float = 0.0
## Volume _batch_envelope_db() ramps up to at full swing (mid-batch) —
## 0 dB (ambient_sound's own unmodified volume) by default, so every
## other station's behavior is unchanged; per-station tuning knob, same
## "one script, per-type export values set in each station's own .tscn"
## pattern as ambient_gap_seconds above. Mixer set to -1.94 dB (✅
## 2026-07-15 — "make the mixer noise about 20% lower as a whole") — a
## 20% reduction in linear amplitude is 20 * log10(0.8) ≈ -1.94 dB;
## dB is a log scale, so this is a genuinely smaller-sounding change than
## "-20" would be (-20 dB is roughly a 90% amplitude cut, not 20%).
@export var peak_volume_db: float = 0.0

## Roughly a station's own footprint plus its progress bar above it —
## doesn't need to be pixel-precise, just large enough that the ambience
## doesn't cut in/out right at a building's own edges.
const _VISIBILITY_AABB := AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 3.0, 2.4))
const _BUS: StringName = &"SFX"

## How long the ambient volume takes to ramp up at the start of a batch
## and back down at the end — a whole-batch envelope layered on top of
## the loop/gap mechanics above, not tied to ambient_sound's own clip
## length (which may loop several times within one batch — the Assembly
## Table's pulsing assembly_pop.wav, for instance). Reported as the
## instant on/off pop at a batch's start/end reading harsh.
const _FADE_SECONDS: float = 0.2
## Matches this project's usual silence floor (see TierMusicController/
## MusicController's own -80 dB convention).
const _SILENT_DB: float = -80.0

var _notifier: VisibleOnScreenNotifier3D
var _ambient_player: AudioStreamPlayer3D
## Counts down after ambient_sound finishes, while still active/visible,
## before _process() is allowed to restart it — see ambient_gap_seconds.
var _gap_timer: float = 0.0


func _ready() -> void:
	if ambient_sound == null:
		return
	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = _VISIBILITY_AABB
	add_child(_notifier)

	_ambient_player = AudioStreamPlayer3D.new()
	_ambient_player.stream = ambient_sound
	_ambient_player.bus = _BUS
	add_child(_ambient_player)
	_ambient_player.finished.connect(_on_ambient_finished)


func _process(delta: float) -> void:
	if ambient_sound == null:
		return
	var should_loop: bool = building.progress() > 0.0 and _notifier.is_on_screen()
	if not should_loop:
		_gap_timer = 0.0
		if _ambient_player.playing:
			_ambient_player.stop()
		return
	_ambient_player.volume_db = _batch_envelope_db()
	if _ambient_player.playing:
		return
	if _gap_timer > 0.0:
		_gap_timer -= delta
		return
	_ambient_player.play()


## Volume envelope for the *whole batch* (peak_volume_db in the middle,
## ramping to _SILENT_DB within _FADE_SECONDS of either end) — independent
## of whichever individual loop iteration of ambient_sound happens to be
## playing right now. Only called while building.progress() > 0.0, which
## guarantees building.recipe isn't null (see ProcessingBuilding.progress()).
func _batch_envelope_db() -> float:
	var elapsed: float = building.progress() * building.recipe.processing_time
	var remaining: float = building.recipe.processing_time - elapsed
	var fade_ratio: float = clampf(minf(elapsed, remaining) / _FADE_SECONDS, 0.0, 1.0)
	return lerpf(_SILENT_DB, peak_volume_db, fade_ratio)


func _on_ambient_finished() -> void:
	_gap_timer = ambient_gap_seconds
