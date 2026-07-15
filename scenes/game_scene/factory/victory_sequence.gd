class_name VictorySequence
extends Node
## Victory Sequence + credits-over-the-live-bakery + Bakery Report +
## Employee Awards — the full "End Game Flow replacement" backlog
## (gameplay_overview.md's "Ending & replayability", roadmap.md's High
## Priority Backlog). play() hands control back to the player once the
## awards are dismissed (see decisions.md).
##
## play() is an awaitable coroutine FactoryWorld calls once, at the exact
## point the old flow used to call
## `SceneLoader.load_scene(AppConfig.ending_scene_path)` — a full scene
## swap that tore down the running factory. This never swaps scenes or
## pauses the tree, so cats/buildings/economy/music all keep simulating
## normally for the entire sequence; only camera_rig's own player input
## and factory_hud's interactivity are suspended for the duration.

@export var camera_rig: CameraRig
@export var factory_hud: CanvasLayer
@export var factory_bounds: FactoryBounds
@export var lifetime_stats: LifetimeStats
@export var recipe_shop: RecipeShop
@export var tier_manager: TierManager
## Read once, in _compute_pan_waypoints(), to frame the cinematic pan on
## where the player actually built rather than the full unlocked
## rectangle — see that function's own doc comment.
@export var buildings_root: Node3D
## Live cats at the moment the sequence plays — read once, right before
## showing the Employee Awards, to compute EmployeeAwards.compute()'s
## winners from each cat's actual lifetime stats. See its own class doc.
@export var cats_root: Node3D

## Bakery Rank: a fixed, personality-flavored set (not a difficulty
## ladder — every player who reaches this screen already cleared every
## tier) rather than the originally-floated Neighborhood/Town Favorite/
## Master/Royal progression. _compute_bakery_rank() checks these
## top-to-bottom, first match wins, so a run that qualifies for more than
## one (e.g. both fast AND frugal) gets a single deterministic answer
## rather than an arbitrary one. Thresholds are first-pass judgment
## calls (player's own numbers, 2026-07-13) — no reference curve for
## this the way progression.md has for tiers, so revisit after real
## playtests the way FactoryBounds' expansion-cost curve already was.
const _RANK_SPEEDY: String = "Speedy Bakery"
const _RANK_MARATHON: String = "Marathon Bakery"
const _RANK_CRAZY_CAT_LADY: String = "Crazy Cat Lady Bakery"
const _RANK_EMPIRE: String = "Bakery Empire"
const _RANK_BOOTSTRAP: String = "Bootstrap Bakery"
const _RANK_DEFAULT: String = "Master Bakery"

## Finished in under an hour.
const _SPEEDY_MAX_SECONDS: float = 3600.0
## Took over 3 hours — the player's own reported average playthrough is
## ~90 minutes, so this is a deliberately generous "took it slow and
## cozy" threshold, not a knock on pace.
const _MARATHON_MIN_SECONDS: float = 10800.0
## Adopted more than 200 cats through CatShop over the run (the starting
## cat, Newby, doesn't count — see LifetimeStats.cats_adopted_count).
const _CRAZY_CAT_LADY_MIN_CATS: int = 200
## Earned over $100,000 lifetime (LifetimeStats.money_earned_total, not
## current balance).
const _EMPIRE_MIN_MONEY: int = 100000
## Shipped no more than 20% over the game's own minimum required lifetime
## shipments (TierManager.total_required_shipments()) — shipped just
## enough to progress, not for profit.
const _BOOTSTRAP_MAX_OVERSHIP_FACTOR: float = 1.2

## Seconds for the full-screen black wipe in/out of cinematic mode —
## long enough to read as a deliberate beat, short enough not to feel
## like a loading screen.
const _FADE_SECONDS: float = 0.6
## Seconds spent gliding from one waypoint to the next — slow and
## steady, matching gameplay_overview.md's "slow cinematic camera pan":
## deliberately much slower than ordinary player-driven panning.
const _PAN_LEG_SECONDS: float = 10.0
## Waypoints as a fraction of the factory's own unlocked bounds (0..1 on
## each axis), swept in order and looped — a lap around the bakery's
## perimeter rather than fixed world coordinates, so it automatically
## adapts to however large the player has expanded the factory.
const _WAYPOINT_FRACTIONS: Array[Vector2] = [
	Vector2(0.25, 0.25), Vector2(0.75, 0.25), Vector2(0.75, 0.75), Vector2(0.25, 0.75),
]
## How much of the factory's own footprint to keep in view at once, as a
## multiple of its longer side — >1 leaves corners uncropped.
const _ZOOM_FOOTPRINT_FACTOR: float = 0.6
## Padding added around the placed-buildings bounding box (see
## _built_area_bounds()) so buildings sitting right at the edge of that
## box aren't cropped by the pan/zoom framing.
const _BUILT_AREA_PADDING_METERS: float = 8.0

@onready var _overlay: CanvasLayer = $Overlay
@onready var _transition_fade: ColorRect = $Overlay/TransitionFade
@onready var _credits_panel: ColorRect = $Overlay/CreditsPanel
@onready var _scrolling_credits: Control = $Overlay/CreditsPanel/ScrollingCredits
@onready var _bakery_report: BakeryReportDialog = $Overlay/BakeryReportDialog
@onready var _employee_awards: EmployeeAwardsDialog = $Overlay/EmployeeAwardsDialog

var _pan_waypoints: Array[Vector3] = []
var _pan_zoom: float = 0.0
var _leg_timer: float = 0.0
var _leg_index: int = 0
var _panning: bool = false


func _ready() -> void:
	_overlay.hide()
	_transition_fade.modulate.a = 0.0
	_credits_panel.modulate.a = 0.0
	# credits_label.tscn hardcodes a 1280px minimum width (sized for a
	# full-screen credits scene); this panel is only half that, so the
	# forced minimum would push the label past the panel's own edge.
	var label: Control = _scrolling_credits.find_child("CreditsLabel", true, false)
	if label != null:
		label.custom_minimum_size.x = 0.0


func _process(delta: float) -> void:
	if not _panning:
		return
	_leg_timer += delta
	var leg_t: float = clampf(_leg_timer / _PAN_LEG_SECONDS, 0.0, 1.0)
	var eased_t: float = smoothstep(0.0, 1.0, leg_t)
	var from: Vector3 = _pan_waypoints[_leg_index]
	var to: Vector3 = _pan_waypoints[(_leg_index + 1) % _pan_waypoints.size()]
	camera_rig.set_pan_target(from.lerp(to, eased_t), _pan_zoom)
	if leg_t >= 1.0:
		_leg_timer = 0.0
		_leg_index = (_leg_index + 1) % _pan_waypoints.size()


## Runs the full sequence once: fade to black, hand the camera/HUD to the
## cinematic pan, fade back in with credits rolling over the still-
## running factory, fade the credits out once they finish scrolling, show
## the Bakery Report, then hand everything back once the player dismisses
## it. Call once, when the player wins.
func play() -> void:
	_overlay.show()
	await _fade(_transition_fade, 0.0, 1.0)

	_compute_pan_waypoints()
	camera_rig.snap_to(_pan_waypoints[0], _pan_zoom)
	camera_rig.cinematic_mode = true
	factory_hud.hide()
	_leg_index = 0
	_leg_timer = 0.0
	_panning = true

	await _fade(_transition_fade, 1.0, 0.0)
	await _fade(_credits_panel, 0.0, 1.0)

	await _scrolling_credits.end_reached

	await _fade(_credits_panel, 1.0, 0.0)
	_panning = false

	_bakery_report.show_report(
			lifetime_stats.playtime_seconds,
			_compute_bakery_rank(),
			lifetime_stats.money_earned_total,
			lifetime_stats.cats_adopted_count,
			lifetime_stats.total_items_shipped(),
			recipe_shop.unlocked_count(),
			lifetime_stats.total_deliveries_completed,
			factory_bounds.unlocked_size)
	await _bakery_report.continue_pressed
	_bakery_report.hide()

	_employee_awards.show_awards(EmployeeAwards.compute(_live_cats()))
	await _employee_awards.continue_pressed
	_employee_awards.hide()

	factory_hud.show()
	camera_rig.cinematic_mode = false
	_overlay.hide()


func _live_cats() -> Array[Cat]:
	var cats: Array[Cat] = []
	for child: Node in cats_root.get_children():
		if child is Cat:
			cats.append(child as Cat)
	return cats


func _fade(node: CanvasItem, from_alpha: float, to_alpha: float) -> void:
	node.modulate.a = from_alpha
	var tween: Tween = create_tween()
	tween.tween_property(node, "modulate:a", to_alpha, _FADE_SECONDS)
	await tween.finished


## Snapshot of the current built-area footprint, taken once per play() —
## bounds could in principle expand mid-sequence, but re-deriving
## waypoints mid-pan for that edge case isn't worth it for a one-time
## victory lap.
##
## **Frames on the placed-buildings bounding box, not the full unlocked
## rectangle (✅ 2026-07-15)** — the pan/zoom used to always sweep all four
## quadrants of factory_bounds.unlocked_world_size(), which on a factory
## where the player expanded well past their actual built footprint (a
## very normal way to play — expansion is cheap insurance, not a promise
## to fill every cell) spent much of the cinematic panning over bare
## grass. `_built_area_bounds()` falls back to the full unlocked
## rectangle only if there happen to be no buildings at all (shouldn't
## normally be reachable at Tier Winner, but avoids a zero-size pan).
func _compute_pan_waypoints() -> void:
	var corner: Vector3
	var size: Vector2
	var built_rect: Rect2 = _built_area_bounds()
	if built_rect.size.x > 0.0 and built_rect.size.y > 0.0:
		corner = Vector3(built_rect.position.x, 0.0, built_rect.position.y)
		size = built_rect.size
	else:
		corner = factory_bounds.unlocked_world_corner()
		size = factory_bounds.unlocked_world_size()
	_pan_waypoints.clear()
	for fraction: Vector2 in _WAYPOINT_FRACTIONS:
		_pan_waypoints.append(corner + Vector3(size.x * fraction.x, 0.0, size.y * fraction.y))
	_pan_zoom = clampf(maxf(size.x, size.y) * _ZOOM_FOOTPRINT_FACTOR, camera_rig.min_zoom, camera_rig.max_zoom)


## World X/Z bounding rectangle of every placed building, padded by
## _BUILT_AREA_PADDING_METERS — empty (zero size) if buildings_root isn't
## wired or has no Building children yet.
func _built_area_bounds() -> Rect2:
	var rect := Rect2()
	if buildings_root == null:
		return rect
	var first: bool = true
	for child: Node in buildings_root.get_children():
		var building: Building = child as Building
		if building == null:
			continue
		var point := Vector2(building.position.x, building.position.z)
		if first:
			rect = Rect2(point, Vector2.ZERO)
			first = false
		else:
			rect = rect.expand(point)
	if not first:
		rect = rect.grow(_BUILT_AREA_PADDING_METERS)
	return rect


## First match wins — see the rank constants' doc comment above for why
## this order (and why it's a fixed list rather than a scored formula).
func _compute_bakery_rank() -> String:
	if lifetime_stats.playtime_seconds < _SPEEDY_MAX_SECONDS:
		return _RANK_SPEEDY
	if lifetime_stats.playtime_seconds > _MARATHON_MIN_SECONDS:
		return _RANK_MARATHON
	if lifetime_stats.cats_adopted_count > _CRAZY_CAT_LADY_MIN_CATS:
		return _RANK_CRAZY_CAT_LADY
	if lifetime_stats.money_earned_total > _EMPIRE_MIN_MONEY:
		return _RANK_EMPIRE
	var max_bootstrap_shipments: float = tier_manager.total_required_shipments() * _BOOTSTRAP_MAX_OVERSHIP_FACTOR
	if lifetime_stats.total_items_shipped() <= max_bootstrap_shipments:
		return _RANK_BOOTSTRAP
	return _RANK_DEFAULT
