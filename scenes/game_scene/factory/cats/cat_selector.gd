class_name CatSelector
extends Node
## Lets the player click a cat to select it (opening the cat inspector
## panel), pick it up and carry it to a new spot, or click empty ground
## to deselect.
##
## Only claims a click when it actually did something (selected a cat,
## picked one up, or dropped one) — an empty-ground click is left alone
## so it still falls through to BuildingPlacer/CameraRig exactly as if
## this node didn't exist, preserving click-drag camera panning.
##
## **Cats are picked in SCREEN space, against the sprite the player can
## actually see (SpritePicker), not by a radius around their feet on the
## ground plane** (✅ rewritten 2026-09-17 — "selecting a cat only works
## when clicking their body, but most players will try to click their
## heads"). The old ground-radius test inherited the rest of the
## factory's `GridCursor.world_point` picking, which is right for things
## whose clickable extent is their floor footprint and wrong for a
## billboard that stands up out of it: the pixel over a cat's head
## projects to a ground point about a metre BEHIND the cat, so head
## clicks missed. See SpritePicker's own class doc and decisions.md.
##
## **A stationed cat still can't steal clicks aimed at its station**
## (previously reported as "impossible to select or change a recipe for
## a station" whenever a cat was parked on it, and previously worked
## around with a deliberately tiny stationed-only pick radius): a cat
## standing behind its station is skipped wherever the station's own
## sprite is opaque in front of it — see _hidden_behind_station(). That
## is the real rule the radius hack was approximating, so the hack is
## gone: the cat is clickable exactly where it's visible (its head, at a
## Mixer) and nowhere it isn't.

## Emitted when the selected cat changes; null when deselected.
signal selection_changed(cat: Cat)
## Emitted when a cat is picked up or dropped; null once dropped. Lets
## FactoryHud swap in a pinch cursor for exactly as long as a cat is
## actually being carried, mirroring BuildingMover.moving_changed.
signal held_changed(cat: Cat)

@export var grid_cursor: GridCursor
@export var placer: BuildingPlacer
@export var cats_root: Node3D
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
	# Deliberately NOT gated on grid_cursor.has_hover the way it used to
	# be: that asks "is the ground under the mouse inside the factory",
	# which a click on a cat's head can fail (its ground point is a metre
	# behind it, possibly past the bounds) even though the cat itself is
	# plainly under the cursor. Deselecting on empty ground still is.
	var clicked: Cat = _cat_under_mouse()
	if clicked != null:
		_select(clicked)
		get_viewport().set_input_as_handled()
	elif _selected != null and grid_cursor.has_hover:
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
	return _cat_under_mouse()


## The cat drawn under the mouse right now, or null. Ties (overlapping
## sprites) go to whichever cat is nearest the camera — the one actually
## drawn on top, so clicking picks what the player sees.
func _cat_under_mouse() -> Cat:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen_point: Vector2 = get_viewport().get_mouse_position()
	var nearest: Cat = null
	var nearest_distance: float = INF
	for child: Node in cats_root.get_children():
		var cat: Cat = child as Cat
		if cat == null:
			continue
		if not SpritePicker.hits(cat.visual(), camera, screen_point):
			continue
		if _hidden_behind_station(cat, camera, screen_point):
			continue
		var distance: float = camera.global_position.distance_squared_to(cat.global_position)
		if distance < nearest_distance:
			nearest = cat
			nearest_distance = distance
	return nearest


## Whether this point falls on part of a stationed cat that its own
## station is drawn over — the cat's hidden body, not its visible head
## (see the class doc). Only the cat's own station is considered, not
## every building in the factory: parking behind a station is the one
## case the player actually hits, and it's the one a previous fix had to
## work around with a shrunken pick radius. A cat standing behind some
## unrelated building elsewhere is still clickable through it, which is
## the pre-existing behavior and has never been reported as a problem.
func _hidden_behind_station(cat: Cat, camera: Camera3D, screen_point: Vector2) -> bool:
	var station: ProcessingBuilding = cat.station()
	if station == null:
		return false
	var station_visual: Sprite3D = station.get_node_or_null("Visual") as Sprite3D
	if station_visual == null:
		return false
	var camera_position: Vector3 = camera.global_position
	if camera_position.distance_squared_to(station.global_position) \
			> camera_position.distance_squared_to(cat.global_position):
		# Cat is in front of its station — nothing to hide behind.
		return false
	return SpritePicker.is_opaque_at(station_visual, camera, screen_point)
