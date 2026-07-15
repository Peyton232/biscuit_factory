class_name BuildingPlacer
extends Node
## Build-mode controller: pick a building (hotkey or build-bar button),
## left click to place, X for demolish mode, ESC/right click to cancel.
## Placement charges the Economy; the GridCursor asks this node whether
## the hovered cell is a valid target so its highlight can turn red.

## Emitted whenever the active tool changes (building selected, demolish
## toggled, or cancelled). UI reads tool_label()/selected_definition().
signal tool_changed

## Hotbar slots, in order — selected with the select_building_N actions
## (keys 1-7, one per array entry present) or by clicking the build bar.
## Array-based rather than a fixed number of named @export slots, so the
## hotbar isn't capped at a specific building count — see decisions.md.
@export var building_definitions: Array[BuildingDefinition] = []

@export var grid_manager: GridManager
@export var grid_cursor: GridCursor
@export var economy: Economy
## Gates placement to the currently-unlocked (walled) area — see
## FactoryBounds. Null means no bounds restriction (graceful fallback,
## same convention tier_manager/recipe_shop use elsewhere).
@export var factory_bounds: FactoryBounds
## Injected into placed ShippingBins alongside economy, below.
@export var lifetime_stats: LifetimeStats
## Injected into placed ProcessingBuildings so they can refuse to run a
## recipe that isn't unlocked yet — see ProcessingBuilding's class doc.
@export var recipe_shop: RecipeShop
## Parent for placed buildings.
@export var buildings_root: Node3D
## Gates which hotbar definitions are actually selectable; null means
## every definition is selectable (no lock system wired in). Buildings
## have no money-unlock step anymore (see progression.md) — this is a
## pure tier gate now, not a shop.
@export var tier_manager: TierManager

## One action per hotbar key. Extend both this and project.godot's input
## map together if the hotbar ever needs more slots than this.
const _SELECT_ACTIONS: Array[StringName] = [
	&"select_building_1",
	&"select_building_2",
	&"select_building_3",
	&"select_building_4",
	&"select_building_5",
	&"select_building_6",
	&"select_building_7",
	&"select_building_8",
	&"select_building_9",
	&"select_building_10",
]

const _BUILDING_PLACE_SOUND: AudioStream = preload("res://assets/sounds/effects/building_place.wav")

var _selected: BuildingDefinition = null
var _demolish_mode: bool = false


func _ready() -> void:
	grid_cursor.validity_check = _is_valid_target


## The hotbar's definitions, in slot order, for UI/hotkey use.
func definitions() -> Array[BuildingDefinition]:
	return building_definitions


func selected_definition() -> BuildingDefinition:
	return _selected


func is_demolish_mode() -> bool:
	return _demolish_mode


## Exposes _is_valid_target as a Callable for BuildingMover to borrow
## grid_cursor's single validity_check slot while a move is pending (and
## hand it back once done) — see BuildingMover's class doc.
func default_validity_check() -> Callable:
	return _is_valid_target


## Human-readable name of the active tool, for the HUD.
func tool_label() -> String:
	if _demolish_mode:
		return "Demolish"
	if _selected != null:
		return _selected.display_name
	return "None"


## No-ops if the definition's tier hasn't unlocked yet (see tier_manager)
## — the single choke point both hotkeys and build-bar clicks go
## through, so a tier-locked building can never be selected either way.
func select_definition(definition: BuildingDefinition) -> void:
	if tier_manager != null and not tier_manager.is_building_unlocked(definition):
		return
	_demolish_mode = false
	_selected = definition
	tool_changed.emit()


func select_demolish() -> void:
	_selected = null
	_demolish_mode = true
	tool_changed.emit()


func clear_tool() -> void:
	_selected = null
	_demolish_mode = false
	tool_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	for i: int in mini(_SELECT_ACTIONS.size(), building_definitions.size()):
		if event.is_action_pressed(_SELECT_ACTIONS[i]):
			select_definition(building_definitions[i])
			return
	if event.is_action_pressed("demolish"):
		select_demolish()
	elif event.is_action_pressed("cancel_placement"):
		# Only consume the event while a tool is active, so ESC still
		# reaches the pause menu when nothing is selected.
		if _selected != null or _demolish_mode:
			clear_tool()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_building"):
		# Consume every left click while a tool is active — even invalid
		# ones — so they never fall through and start a camera drag.
		# With no tool, the click passes to the CameraRig for drag-panning.
		if _selected != null or _demolish_mode:
			_activate()
			get_viewport().set_input_as_handled()


func _activate() -> void:
	if not grid_cursor.has_hover:
		return
	var cell: Vector2i = grid_cursor.hovered_cell
	if _demolish_mode:
		var occupant: Building = grid_manager.get_cell_occupant(cell) as Building
		if occupant != null:
			var refund: int = occupant.definition.cost
			economy.earn(refund)
			FloatingText.spawn(buildings_root, occupant.global_position + Vector3.UP * 2.1,
					"+$%d" % refund, Color(1.0, 0.84, 0.35))
			occupant.queue_free()
		return
	if _selected == null:
		return
	if factory_bounds != null and not factory_bounds.is_region_within_bounds(cell, _selected.size):
		return
	if not grid_manager.is_region_available(cell, _selected.size):
		return
	if not economy.try_spend(_selected.cost):
		return
	var building: Building = _selected.scene.instantiate() as Building
	assert(building != null, "BuildingDefinition.scene must have a Building root.")
	building.setup(grid_manager, cell, _selected)
	inject_dependencies(building)
	buildings_root.add_child(building)
	Sfx.spawn(self, _BUILDING_PLACE_SOUND)


## Wires the shared dependencies a freshly-created Building needs, based
## on its type. Shared by normal placement (_activate() above) and
## save/load restoration (see FactoryWorld), so the two paths can't
## drift apart from each other.
func inject_dependencies(building: Building) -> void:
	# Shipping bins pay the player, so they get the economy (and the
	# lifetime shipped-item tracker) injected.
	var bin: ShippingBin = building as ShippingBin
	if bin != null:
		bin.economy = economy
		bin.lifetime_stats = lifetime_stats
		bin.tier_manager = tier_manager
	# Processing stations need to check recipe locks themselves (see
	# ProcessingBuilding's class doc) — the GDD economy means not every
	# station has a free default recipe, so the old "the default is
	# always free" convention alone isn't safe anymore.
	var processing: ProcessingBuilding = building as ProcessingBuilding
	if processing != null:
		processing.recipe_shop = recipe_shop


## Whether clicking the given cell would do something with the active
## tool. Drives the cursor highlight color.
func _is_valid_target(cell: Vector2i) -> bool:
	if _demolish_mode:
		return grid_manager.is_cell_occupied(cell)
	if _selected == null:
		# Plain select mode: clicking any cell is a fine, non-error
		# outcome — an occupied one selects the building there (per
		# BuildingSelector), an empty one just deselects. The old
		# "occupied = invalid/red" check here reused demolish-mode's
		# framing, which reads as a warning over a perfectly selectable
		# building — reported as confusing/hard-to-click by players.
		return true
	if factory_bounds != null and not factory_bounds.is_region_within_bounds(cell, _selected.size):
		return false
	return grid_manager.is_region_available(cell, _selected.size) \
			and economy.can_afford(_selected.cost)
