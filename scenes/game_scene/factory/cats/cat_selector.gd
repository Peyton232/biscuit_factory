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
## floor. Paired with Cat's own _HELD_VISUAL_Y (the sprite hangs *below*
## this point rather than standing on it, reading as held by the scruff
## of the neck, dangling) — needs to clear _HELD_VISUAL_Y's downward pull
## by a modest margin so the dangling feet stay above the ground.
## **No longer just a lift distance from the ground point (✅ fixed —
## "the cursor is literally below the cat when we pick them up," and
## explicitly not by shrinking the cat)** — see _held_target_position()'s
## doc comment for the actual mechanism. This value is now purely "how
## high off the ground does the grab point float" with zero cursor-
## alignment cost, since alignment is exact at any height — which is
## exactly what let `_HELD_VISUAL_Y` get raised to put the grab point at
## the cat's actual neck (see its own doc comment) without reintroducing
## any drift: raised 0.8 -> 1.5m to clear that larger pull and keep the
## now much-lower-hanging feet visibly above the ground (~0.2m
## clearance).
@export var held_height: float = 1.5

var _selected: Cat = null
var _held: Cat = null


func _process(_delta: float) -> void:
	if _held != null and grid_cursor.has_hover:
		_held.position = _held_target_position()


## Where a held cat's grab point (node origin) belongs, given the current
## mouse position and camera — **intersects the mouse ray with the
## horizontal plane at y = held_height directly, instead of intersecting
## the y = 0 ground plane and then lifting the result straight up in
## world space** (the old approach, and the bug: a ray-plane intersection
## always reprojects to the exact screen pixel it was cast from, for
## *any* plane height — but a point produced by lifting an *already-
## intersected* ground point up in world Y is a different point off that
## ray entirely, and drifts away from the cursor's actual screen position
## under this camera's perspective, worse at higher held_height/lower
## zoom. That drift was the real bug reported as "the cursor is under
## the cat" — confirmed numerically (see decisions.md) — not something a
## shrink/resize hack could fix, since it doesn't touch the
## mismatch between how the two points are derived**. Raycasting the
## target plane directly is exact at any zoom and any held_height, with
## no tuning required — same math GridCursor/CameraRig already use for
## their own y=0 raycasts, just generalized to an arbitrary plane height.
func _held_target_position() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return grid_cursor.world_point + Vector3.UP * held_height
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = camera.project_ray_normal(mouse_pos)
	if direction.y >= 0.0:
		# Ray parallel to horizontal planes or pointing upward — can't
		# intersect; same degenerate case GridCursor's own ground raycast
		# guards against.
		return grid_cursor.world_point + Vector3.UP * held_height
	var t: float = (origin.y - held_height) / direction.y
	return origin - direction * t


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
