class_name CatSelector
extends Node
## Lets the player click a cat to select it (opening the cat inspector
## panel), pick it up and carry it to a new spot, or click empty ground
## to deselect. Reuses GridCursor's ground-projection math for hit
## testing (no physics colliders), consistent with the rest of the
## factory's mouse picking.
##
## Only claims a click when it actually did something (selected a cat,
## picked one up, or dropped one) — an empty-ground click is left alone
## so it still falls through to BuildingPlacer/CameraRig exactly as if
## this node didn't exist, preserving click-drag camera panning.
##
## **Stationed cats use a much smaller pick radius than everyone else**
## (stationed_pick_radius, not pick_radius) — a STATIONED cat parks at
## station_offset from its building (~1.13m from the building's own
## center, see Cat's class doc), well inside the enlarged 1.6m
## pick_radius meant for small moving targets. Since this node sits
## later in factory_world.tscn than BuildingSelector and so gets first
## refusal on every click (see the tree-order note in decisions.md), that
## let a click clearly aimed at the building underneath a stationed cat
## get eaten here instead — reported as "impossible to select or change
## a recipe for a station" whenever it had a cat parked on it. A
## stationed cat isn't a hard-to-click moving target anymore, so it
## doesn't need the enlarged radius; a small one still lets the player
## click the cat itself deliberately.

## Emitted when the selected cat changes; null when deselected.
signal selection_changed(cat: Cat)
## Emitted when a cat is picked up or dropped; null once dropped. Lets
## FactoryHud swap in a pinch cursor for exactly as long as a cat is
## actually being carried, mirroring BuildingMover.moving_changed.
signal held_changed(cat: Cat)

@export var grid_cursor: GridCursor
@export var placer: BuildingPlacer
@export var cats_root: Node3D
## How close (world units) a click needs to land to a cat to select it.
## Larger than the cat's own visual footprint on purpose — cats are a
## small, moving target, and players reported them "hard to click on"
## at the old 1.0 (which was roughly the sprite's own width).
@export var pick_radius: float = 1.6
## Pick radius used for STATIONED cats specifically (see class doc) —
## small, since a parked cat is a fixed target, not one the player needs
## help clicking; keeps the building underneath it clickable too.
@export var stationed_pick_radius: float = 0.5
## Height a held cat's origin floats at, so it visibly separates from the
## floor. Raised from the old 0.6 (✅ 2026-07-15, paired with Cat's own
## _HELD_VISUAL_Y) — the cat's sprite now hangs *below* this point rather
## than standing on it (reading as held by the scruff of the neck,
## dangling), so the anchor needs to sit higher for the dangling feet to
## still clear the ground.
@export var held_height: float = 1.1

var _selected: Cat = null
var _held: Cat = null


func _process(_delta: float) -> void:
	if _held != null and grid_cursor.has_hover:
		_held.position = grid_cursor.world_point + Vector3.UP * held_height


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("place_building"):
		_on_click()
	elif event.is_action_pressed("cancel_placement"):
		_on_cancel()


func _on_click() -> void:
	if _held != null:
		_drop_held_cat()
		get_viewport().set_input_as_handled()
		return
	if placer.selected_definition() != null or placer.is_demolish_mode():
		return
	if not grid_cursor.has_hover:
		return
	var clicked: Cat = _find_cat_near(grid_cursor.world_point)
	if clicked != null:
		_select(clicked)
		get_viewport().set_input_as_handled()
	elif _selected != null:
		_deselect()


func _on_cancel() -> void:
	if _held != null:
		# Dropping in place is simplest and always valid (no risk of
		# ending up off-grid or inside another building). end_held()
		# normalizes the Y back to ground level.
		_held.end_held(_held.position)
		_held = null
		held_changed.emit(null)
		get_viewport().set_input_as_handled()
	elif _selected != null:
		_deselect()
		get_viewport().set_input_as_handled()


## Whether a cat is currently being carried — FactoryHud reads this to
## decide when to show the pinch cursor.
func is_holding() -> bool:
	return _held != null


## Called by the cat inspector panel's "Pick Up" button.
func begin_hold() -> void:
	if _selected == null:
		return
	_held = _selected
	_held.begin_held()
	_deselect()
	held_changed.emit(_held)


func _select(cat: Cat) -> void:
	_selected = cat
	selection_changed.emit(cat)


func _deselect() -> void:
	_selected = null
	selection_changed.emit(null)


func _drop_held_cat() -> void:
	# If the cursor isn't over the grid, keep holding rather than
	# stranding the cat in HELD state with nothing left tracking it.
	if not grid_cursor.has_hover:
		return
	_held.end_held(grid_cursor.world_point)
	_held = null
	held_changed.emit(null)


## The cat a click would select right now, or null — same targeting
## logic _on_click() uses, exposed read-only for HoverHighlight so
## hovering previews exactly what clicking would do. Deliberately mirrors
## _on_click()'s own placer/held gating (no hover target while actively
## placing a building, demolishing, or already holding a cat).
func hovered_cat() -> Cat:
	if _held != null or placer.selected_definition() != null or placer.is_demolish_mode():
		return null
	if not grid_cursor.has_hover:
		return null
	return _find_cat_near(grid_cursor.world_point)


func _find_cat_near(world_point: Vector3) -> Cat:
	var nearest: Cat = null
	var nearest_dist: float = pick_radius
	for child: Node in cats_root.get_children():
		var cat: Cat = child as Cat
		if cat == null:
			continue
		var radius: float = stationed_pick_radius if cat.is_stationed() else pick_radius
		var dist: float = Vector2(cat.position.x, cat.position.z).distance_to(
				Vector2(world_point.x, world_point.z))
		if dist < radius and dist < nearest_dist:
			nearest = cat
			nearest_dist = dist
	return nearest
