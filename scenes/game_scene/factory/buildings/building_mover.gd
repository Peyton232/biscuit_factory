class_name BuildingMover
extends Node
## Lets the player relocate an already-placed building instead of only
## being able to demolish (refund) and rebuild it from scratch —
## "add demolish tutorial or make a way to move buildings" / "maybe add
## move mode for buildings" playtest feedback.
##
## Moving is always free (no cost, no refund) — the point isn't money
## (demolish-then-rebuild already nets to $0), it's **state**: a freshly
## placed building always starts with no recipe and an empty inventory
## (see ProcessingBuilding's class doc), so demolish-and-rebuild silently
## discards whatever the original had. A move preserves all of that.
##
## **Implementation: capture full state, free the old node, place +
## restore a fresh one** — the exact same idea save/load already relies
## on (Building.save_entry()/load_entry(), including every subclass
## override: ProcessingBuilding's recipe, ShippingBin's accepted items).
## Freeing the old building via `.free()` (synchronous, not queue_free()
## — see FactoryWorld's save/load entry in decisions.md for the same
## reasoning: occupancy must actually clear before this same call checks
## the new cell) also triggers every safety net removal already has for
## free, with no new cancellation code needed here: DeliveryManager
## cancels any job pointing at it (buildings_root.child_exiting_tree),
## and ProcessingBuilding releases its station cat (_exit_tree() calls
## notify_station_removed(), which becomes upset — an accepted rough
## edge for a move, same spirit as other reassignment/demolition edges
## in this codebase; re-attaching a station cat at the new location
## wasn't worth the added complexity for what's a rare, low-stakes case).
##
## Mirrors CatPlacer's click-to-place flow (ghost preview via
## BuildingGhost, left click confirms, right-click/ESC cancels) and its
## mutual-exclusion approach: begin_move() clears the active build tool
## first (before is_moving() becomes true), so the resulting
## tool_changed signal can't loop back and cancel the move that's about
## to start — see FactoryHud._on_tool_changed(), which cancels an active
## move the same way it already cancels an active cat placement.

signal moving_changed

@export var grid_manager: GridManager
@export var grid_cursor: GridCursor
@export var buildings_root: Node3D
@export var building_placer: BuildingPlacer
## Same graceful-if-unset convention as BuildingPlacer.factory_bounds.
@export var factory_bounds: FactoryBounds

var _building: Building = null
var _definition: BuildingDefinition = null
var _saved_entry: BuildingSaveEntry = null


func is_moving() -> bool:
	return _building != null


func moving_definition() -> BuildingDefinition:
	return _definition


## Human-readable label for FactoryHud's tool readout while moving.
func tool_label() -> String:
	return "Moving %s (click to place)" % _definition.display_name


## Starts a move for an already-placed building. Captures its full state
## up front (recipe, inventory, accepted items, ...) via save_entry() —
## the same snapshot re-placement will restore via load_entry() once the
## player picks a destination.
func begin_move(building: Building) -> void:
	building_placer.clear_tool()
	_building = building
	_definition = building.definition
	_saved_entry = building.save_entry()
	grid_cursor.validity_check = building_placer.default_validity_check()
	moving_changed.emit()


func cancel_move() -> void:
	if not is_moving():
		return
	_building = null
	_definition = null
	_saved_entry = null
	grid_cursor.validity_check = building_placer.default_validity_check()
	moving_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_moving():
		return
	if event.is_action_pressed("cancel_placement"):
		cancel_move()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_building"):
		# Consume every click while a move is pending — even ones that miss
		# the grid or land somewhere invalid — so it never falls through and
		# starts a camera drag, same reasoning as BuildingPlacer's own
		# place_building handling.
		_confirm()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	if not grid_cursor.has_hover:
		return
	var new_cell: Vector2i = grid_cursor.hovered_cell
	var old_cell: Vector2i = _building.cell
	if new_cell == old_cell:
		# Clicking the building's own current spot: nothing to do, but
		# still worth ending the move rather than leaving it pending
		# (matches clicking "confirm" reading as "I'm done here").
		cancel_move()
		return
	if factory_bounds != null and not factory_bounds.is_region_within_bounds(new_cell, _definition.size):
		return
	if not grid_manager.is_region_available(new_cell, _definition.size):
		return
	_building.free()
	var building: Building = _definition.scene.instantiate() as Building
	building.setup(grid_manager, new_cell, _definition)
	building_placer.inject_dependencies(building)
	buildings_root.add_child(building)
	building.load_entry(_saved_entry)
	cancel_move()
