class_name BuildingSelector
extends Node
## Lets the player click any placed Building to select it and see (or,
## for a ProcessingBuilding, assign) its info: a Mixer/Oven's recipe,
## a Source's production rate, a ShippingBin's sell prices. Was
## ProcessingBuilding-only (StationSelector); broadened once
## Sources/ShippingBin also needed a click-to-inspect panel — see
## decisions.md.
##
## **Selection hit-tests the building's own sprite in screen space
## (SpritePicker), not the grid cell under the cursor (✅ 2026-09-17).**
## The cell-occupancy test that used to do this had exactly the bug
## CatSelector had before its own rewrite, for exactly the same reason:
## a building is drawn as a tall billboard standing *up* out of its
## footprint (a Mixer is 2.76m tall over a 2-cell base), so the pixels
## making up most of what the player sees project to ground cells well
## behind the building. Only clicks near its base landed on its own
## cell — reported as "the same thing with the cat used to only be
## clickable on the bottom, buildings are that way too". Buildings use
## the alpha-accurate `is_opaque_at()` rather than the plain quad test
## cats use, since building art is small enough to sample (see
## SpritePicker's own note on why cats can't be).
##
## **Placement still keys off the ground CELL, not sprites** — see
## _on_click(). That split is deliberate: the build ghost tracks the
## hovered cell, so "click where the ghost is" has to keep working even
## when a tall building's sprite happens to cover that cell on screen.
##
## Only claims a click when it actually selected/deselected a building,
## so an empty click still falls through to BuildingPlacer/CameraRig
## exactly as if this node didn't exist. Sits directly before CatSelector
## in factory_world.tscn so CatSelector's first refusal on
## _unhandled_input still wins clicks on cats (see the tree-order note
## in decisions.md); BuildingSelector only sees clicks CatSelector didn't
## consume.
##
## **Clicking a building always selects it, even while a build tool is
## still armed (✅ earlier fix — see _on_click()).** Only an empty cell
## with a tool armed falls through to BuildingPlacer; this used to bail
## out of _on_click() entirely whenever any tool was armed, so placing a
## building and then immediately clicking it again (to assign a recipe)
## silently did nothing.

## Emitted when the selected building changes; null when deselected.
signal selection_changed(building: Building)

@export var grid_cursor: GridCursor
@export var grid_manager: GridManager
@export var placer: BuildingPlacer
## Searched for the building whose sprite is under the cursor.
@export var buildings_root: Node3D

var _selected: Building = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_building"):
		_on_click()
	elif event.is_action_pressed("cancel_placement") and _selected != null:
		_deselect()
		get_viewport().set_input_as_handled()


func _on_click() -> void:
	if placer.is_demolish_mode():
		return
	# A genuine new-placement click: a tool is armed and the cell the
	# ghost is sitting on is free. Checked on the CELL rather than on
	# sprites, and checked first, so placing a building behind a tall one
	# still works — its sprite may cover that cell on screen, but the
	# ghost is what the player is aiming with.
	if placer.selected_definition() != null and grid_cursor.has_hover \
			and grid_manager.get_cell_occupant(grid_cursor.hovered_cell) == null:
		return
	# Otherwise the click is a selection. Note this still selects with a
	# build tool armed (✅ earlier fix — "after placing a building I can't
	# immediately select it for a recipe, have to right-click first"): a
	# placed building is a strictly better click target than "attempt
	# another placement", which would silently fail on an occupied cell
	# anyway.
	var clicked: Building = _building_under_mouse()
	if clicked != null:
		_select(clicked)
		get_viewport().set_input_as_handled()
	elif _selected != null and grid_cursor.has_hover:
		_deselect()


## The building drawn under the mouse right now, or null. Mirrors
## CatSelector._cat_under_mouse(): front-most wins, so overlapping
## sprites pick whichever one the player can actually see.
func _building_under_mouse() -> Building:
	if buildings_root == null:
		return null
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen_point: Vector2 = get_viewport().get_mouse_position()
	var nearest: Building = null
	var nearest_distance: float = INF
	for child: Node in buildings_root.get_children():
		var building: Building = child as Building
		if building == null:
			continue
		var visual: Sprite3D = building.get_node_or_null("Visual") as Sprite3D
		if not SpritePicker.is_opaque_at(visual, camera, screen_point):
			continue
		var distance: float = camera.global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest = building
			nearest_distance = distance
	return nearest


## The building a click would select right now, or null — same targeting
## logic _on_click() uses, exposed read-only for HoverHighlight so the
## outline previews exactly what clicking would do (the same arrangement
## CatSelector.hovered_cat() already provides for cats).
func hovered_building() -> Building:
	if placer.is_demolish_mode():
		return null
	if placer.selected_definition() != null and grid_cursor.has_hover \
			and grid_manager.get_cell_occupant(grid_cursor.hovered_cell) == null:
		return null
	return _building_under_mouse()


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
