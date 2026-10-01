class_name OpeningSequence
extends Node
## Opening beat (gameplay_overview.md/roadmap.md's "Opening cutscene"
## backlog item): plays once, only at the very start of a genuinely new
## game — FactoryWorld only calls play() when SaveManager had no pending
## save to restore, the same new-game-only treatment TutorialManager
## already gives its own first step (a loaded/continued game never sees
## either).
##
## Runs entirely inside factory_world.tscn, watching the live, already-
## running factory the whole time (no covering overlay/slides) — a tight
## establishing zoom, then the first cat (Newby, `cats_root`'s first
## child — whichever cat that is, not hardcoded) walks onto screen from
## off-screen "below" the frame up to its real starting spot, followed by
## a short Text_Box.png message before handing control back to the
## player. **Replaces the earlier 5-slide flat-color narration cutscene**
## (see decisions.md) — no illustrated bakery/cat story art exists, and
## watching the real cat walk into its real (already-placed) factory
## reads better than color-card placeholders ever did.
##
## Skippable via ui_cancel (ESC) — that jumps
## straight to the reveal, same convention scrolling_credits.gd already
## uses for "ui_cancel skips to the end."

## Emitted the moment the player has moved past this opening's very first
## beat — either by pressing Next on the "Every great bakery starts
## somewhere..." message, or by pressing ESC at any point during the
## sequence (which bypasses the message entirely; skipping clearly means
## "let me into the game," so it counts the same as clicking through it).
## Guaranteed to fire exactly once per play() call regardless of path,
## including play()'s own early-return bail-outs — FactoryWorld uses this
## to time when TierMusicController first starts playing tier music for a
## brand new game, instead of the instant the (still-empty-feeling)
## factory scene loads. See TierMusicController's own class doc.
signal message_dismissed

@export var camera_rig: CameraRig
@export var factory_hud: CanvasLayer
@export var cats_root: Node3D
## TutorialManager's own view (see tutorial/tutorial_overlay.gd) — it
## starts showing its first step unconditionally on factory_world.tscn's
## own _ready(), same as this cutscene; the old slide-based version of
## this scene covered it for free (a full-screen opaque panel), but this
## one watches the live factory with nothing covering it, so it has to
## explicitly hide/reveal the tutorial's panel itself instead, right
## alongside factory_hud.
@export var tutorial_overlay: CanvasLayer

## Establishing zoom for the cat's walk-in — tighter than CameraRig's own
## start_zoom, "zoomed in on the factory" framing for the reveal. Only
## CameraRig's zoom is touched here, never its pan position (left exactly
## as authored, same "zoom-only" trick the old wide-establishing-shot
## version of this cutscene already used) — panning is only ever clamped
## to FactoryBounds once that node's own _ready() has run, so nudging
## position at this point risks racing that setup for no benefit; zoom
## has no such dependency.
const _CLOSE_ZOOM: float = 9.0

## How far south (+Z — see CameraRig's class doc: increasing Z reads as
## "toward the bottom of the screen" at this camera's pitch) of its real
## resting spot the cat starts, i.e. off-screen at _CLOSE_ZOOM. Stays
## safely inside FactoryBounds' 12x12-cell starting area (a 24m square
## centered on world origin) so the walk never crosses the wall visuals —
## first-pass eyeballed, like most of this project's cosmetic camera/
## cutscene tuning; retune here if a real playtest shows the cat starting
## still-visible or the walk feeling too short/long.
const _WALK_IN_OFFSET_METERS: float = 7.5

const _MESSAGE_TEXT: String = "Every great bakery starts somewhere..."

const _FADE_SECONDS: float = 0.8

@onready var _message_panel: PanelContainer = $Overlay/MessagePanel
@onready var _message_label: Label = $Overlay/MessagePanel/Margin/Layout/TextLabel
@onready var _next_button: Button = $Overlay/MessagePanel/Margin/Layout/Buttons/NextButton

var _cat: Cat = null
var _rest_position: Vector3
var _skipped: bool = false
var _next_requested: bool = false
## True for the whole play() run, not just while the message panel
## happens to be visible — ui_cancel needs to work during the walk-in
## too (the message panel itself only shows afterward, but a player
## mashing Escape shouldn't have to sit through the walk regardless).
var _playing: bool = false


func _ready() -> void:
	_message_panel.hide()
	_next_button.pressed.connect(_on_next_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if _playing and event.is_action_pressed("ui_cancel"):
		_skip()
		get_viewport().set_input_as_handled()


func _on_next_pressed() -> void:
	_request_next()


## Still reachable, just not as a button (✅ 2026-09-17 — "the welcome to
## the bakery says next and skip, let's have just the next button since
## they do the same thing"). By the time the message panel is on screen
## the walk-in has already finished, so Skip and Next did literally the
## same thing there, differing only in whether the panel's fade-out was
## animated. ESC keeps the genuine skip — the one that cuts the walk-in
## short while it is still playing, which no button ever offered anyway
## (the panel only appears once the walk is over).
func _skip() -> void:
	_skipped = true
	_request_next()


## Shared by both dismissal paths so message_dismissed fires exactly once
## regardless of which one the player used (see the signal's own doc).
func _request_next() -> void:
	if _next_requested:
		return
	_next_requested = true
	message_dismissed.emit()


## Runs the full beat once: pulls the camera in tight, teleports the
## first cat off-screen below its real starting spot, walks it back in,
## shows the short message, then hands control back to the player. Call
## once, only for a genuinely new game (see class doc). A no-op (returns
## immediately) if cats_root has no children yet — shouldn't happen in
## practice (the starting cat is always placed in the scene), but this
## runs before any player action could remove it either way.
func play() -> void:
	if cats_root.get_child_count() == 0:
		message_dismissed.emit()
		return
	_cat = cats_root.get_child(0) as Cat
	if _cat == null:
		message_dismissed.emit()
		return

	_playing = true
	factory_hud.hide()
	if tutorial_overlay != null:
		tutorial_overlay.hide()
	camera_rig.cinematic_mode = true
	camera_rig.snap_to(camera_rig.position, _CLOSE_ZOOM)

	_rest_position = _cat.position
	_cat.position = _rest_position + Vector3(0.0, 0.0, _WALK_IN_OFFSET_METERS)

	if not _skipped:
		_cat.walk_to(_rest_position)
		# Matches Cat._follow_path()'s own arrival tolerance for a lone
		# waypoint (interaction_distance, not the tighter waypoint_tolerance
		# it uses for intermediate legs) — that's the exact threshold
		# _tend_wander() stops advancing at and drops back to IDLE, so
		# waiting for anything tighter than this would hang forever.
		while not _skipped and _cat.position.distance_to(_rest_position) > _cat.interaction_distance:
			await get_tree().process_frame
	_cat.position = _rest_position

	_message_panel.modulate.a = 0.0
	_message_label.text = _MESSAGE_TEXT
	_message_panel.show()
	await _fade(_message_panel, 0.0, 1.0)
	while not _next_requested:
		await get_tree().process_frame
	await _fade(_message_panel, 1.0, 0.0)
	_message_panel.hide()

	factory_hud.show()
	if tutorial_overlay != null:
		tutorial_overlay.show()
	camera_rig.set_pan_target(camera_rig.position, camera_rig.start_zoom)
	camera_rig.cinematic_mode = false
	_playing = false


func _fade(node: CanvasItem, from_alpha: float, to_alpha: float) -> void:
	if _skipped:
		node.modulate.a = to_alpha
		return
	node.modulate.a = from_alpha
	var tween: Tween = create_tween()
	tween.tween_property(node, "modulate:a", to_alpha, _FADE_SECONDS)
	await tween.finished
