class_name BuildingSelector
extends Node
## Lets the player click any placed Building to select it and see (or,
## for a ProcessingBuilding, assign) its info: a Mixer/Oven's recipe,
## a Source's production rate, a ShippingBin's sell prices. Hit-tests
## via GridManager's occupancy map at GridCursor's hovered cell —
## buildings occupy fixed cells, unlike cats, so no radius/distance math
## is needed. Was ProcessingBuilding-only (StationSelector); broadened
## once Sources/ShippingBin also needed a click-to-inspect panel — see
## decisions.md.
##
## Only claims a click when it actually selected/deselected a building,
## so an empty click still falls through to BuildingPlacer/CameraRig
## exactly as if this node didn't exist. Sits directly before CatSelector
## in factory_world.tscn so CatSelector's first refusal on
## _unhandled_input still wins clicks on cats (see the tree-order note
## in decisions.md); BuildingSelector only sees clicks CatSelector didn't
## consume.

## Emitted when the selected building changes; null when deselected.
signal selection_changed(building: Building)

@export var grid_cursor: GridCursor
@export var grid_manager: GridManager
@export var placer: BuildingPlacer

var _selected: Building = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_building"):
		_on_click()
	elif event.is_action_pressed("cancel_placement") and _selected != null:
		_deselect()
		get_viewport().set_input_as_handled()


func _on_click() -> void:
	if placer.selected_definition() != null or placer.is_demolish_mode():
		return
	if not grid_cursor.has_hover:
		return
	var occupant: Building = grid_manager.get_cell_occupant(grid_cursor.hovered_cell) as Building
	if occupant != null:
		_select(occupant)
		get_viewport().set_input_as_handled()
	elif _selected != null:
		_deselect()


func _select(building: Building) -> void:
	if _selected != null and _selected.tree_exited.is_connected(_on_selected_removed):
		_selected.tree_exited.disconnect(_on_selected_removed)
	_selected = building
	_selected.tree_exited.connect(_on_selected_removed)
	selection_changed.emit(building)


func _deselect() -> void:
	if _selected != null and _selected.tree_exited.is_connected(_on_selected_removed):
		_selected.tree_exited.disconnect(_on_selected_removed)
	_selected = null
	selection_changed.emit(null)


## Demolishing the selected building must not leave a dangling reference
## or a stale panel showing a freed building.
func _on_selected_removed() -> void:
	_selected = null
	selection_changed.emit(null)
