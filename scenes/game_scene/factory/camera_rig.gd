class_name CameraRig
extends Node3D
## Player camera for viewing the factory floor.
##
## The rig node stays at ground height and pans across the X/Z plane;
## the child Camera3D is placed behind and above it at a fixed downward
## angle, at a distance controlled by the zoom level. Panning reuses the
## remappable move_* input actions, so keyboard and gamepad both work.

@export_group("Panning")
## Pan speed in meters per second at minimum zoom.
@export var pan_speed: float = 15.0
## Extra pan speed added per meter of zoom distance, so panning
## covers more ground when zoomed out.
@export var pan_speed_per_zoom: float = 0.5

@export_group("Zoom")
## Downward angle of the camera toward the floor, in degrees.
@export_range(20.0, 80.0) var pitch_degrees: float = 50.0
## Zoom distance change per mouse wheel tick, in meters.
@export var zoom_step: float = 3.0
@export var min_zoom: float = 8.0
## Lowered from 60 -> 45 (✅ 2026-07-15) — reported as "visual bugs" on a
## large, built-out factory at max zoom-out. The bigger contributor was
## the grass Ground plane's texture filter (NEAREST with no mipmaps,
## aliasing/shimmering badly once its densely-repeating pattern is seen
## at the shallow, grazing angle a high zoom-out produces — see
## factory_world.tscn's mat_ground, fixed alongside this), but a lower
## ceiling on the angle/distance in the first place is a reasonable
## complementary guard, and matches what was actually asked for. First-
## pass number, not derived from anything — revisit if a real factory at
## the new ceiling still looks off.
@export var max_zoom: float = 45.0
## Zoom distance at startup, clamped to the limits above.
@export var start_zoom: float = 12.0

@export_group("Bounds")
## Preferred pan-clamp source: the currently-unlocked (walled) area, not
## the full grid — see _clamp_target_position(). Optional; null falls
## back to grid_manager below.
@export var factory_bounds: FactoryBounds
## Fallback when factory_bounds isn't set: clamps to the full grid
## instead. Optional; leaving both unset disables pan clamping entirely.
@export var grid_manager: GridManager
## How far past the walls (or grid edge, in the fallback case) the
## camera may pan, in meters.
@export var pan_margin: float = 12.0

@export_group("Smoothing")
## Higher values feel snappier; lower values glide more.
@export var pan_smoothing: float = 10.0
@export var zoom_smoothing: float = 8.0

@onready var _camera: Camera3D = $Camera3D

var _target_position: Vector3
var _target_zoom: float
var _zoom: float
var _dragging := false

## True while an external driver (VictorySequence's cinematic pan, so
## far the only one) is steering the camera — suspends the player's own
## WASD/zoom/drag input entirely, but leaves the target-chasing
## smoothing in _process() running, so whatever that driver feeds into
## set_pan_target() below still glides in with the same easing as
## ordinary player panning, just aimed at a different source.
var cinematic_mode: bool = false


func _ready() -> void:
	_target_position = position
	_target_zoom = clampf(start_zoom, min_zoom, max_zoom)
	_zoom = _target_zoom
	_update_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if cinematic_mode:
		return
	if event.is_action_pressed("camera_zoom_in"):
		if _mouse_over_ui():
			return
		_target_zoom = maxf(_target_zoom - zoom_step, min_zoom)
	elif event.is_action_pressed("camera_zoom_out"):
		if _mouse_over_ui():
			return
		_target_zoom = minf(_target_zoom + zoom_step, max_zoom)
	elif event.is_action_pressed("camera_drag"):
		_dragging = true
	elif event.is_action_released("camera_drag"):
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		# Keep the ground point that was grabbed pinned under the cursor.
		var before := _ground_point(event.position - event.relative)
		var after := _ground_point(event.position)
		_target_position += before - after


func _process(delta: float) -> void:
	if not cinematic_mode and not _is_typing():
		var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var motion := Vector3(input.x, 0.0, input.y)
		var speed := pan_speed + (_zoom - min_zoom) * pan_speed_per_zoom
		_target_position += motion * speed * delta
		_clamp_target_position()

	# Exponential smoothing, framerate-independent. Still runs in
	# cinematic_mode — that's what makes an external driver's
	# set_pan_target() calls glide in smoothly instead of snapping.
	position = position.lerp(_target_position, 1.0 - exp(-pan_smoothing * delta))
	_zoom = lerpf(_zoom, _target_zoom, 1.0 - exp(-zoom_smoothing * delta))
	_update_camera_transform()


## Lets an external driver (cinematic_mode) steer the camera the same
## way ordinary player panning does — glides toward the given world
## position/zoom at this rig's own pan_smoothing/zoom_smoothing rates.
func set_pan_target(world_position: Vector3, zoom: float) -> void:
	_target_position = world_position
	_target_zoom = clampf(zoom, min_zoom, max_zoom)


## Instantly places the camera (position + zoom) with no smoothing — for
## a cinematic driver to cut to a starting point under cover of a fade,
## rather than visibly gliding in from wherever the camera was left.
func snap_to(world_position: Vector3, zoom: float) -> void:
	position = world_position
	_target_position = world_position
	_zoom = clampf(zoom, min_zoom, max_zoom)
	_target_zoom = _zoom
	_update_camera_transform()


func _update_camera_transform() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * _zoom
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


## Keeps the pan target within pan_margin of the walls (factory_bounds),
## or the full grid if factory_bounds isn't wired. **Deliberately the
## walls, not the full 100x100 grid** (✅ 2026-07-13) — the grid is sized
## for pathfinding/expansion headroom, not for how far a player should
## ever actually be able to see; clamping to it let the camera pan far
## enough past the (much smaller, especially early-game) walled area to
## see the grass end and the skybox/void beyond it.
func _clamp_target_position() -> void:
	var corner: Vector3
	var size: Vector2
	if factory_bounds != null:
		corner = factory_bounds.unlocked_world_corner()
		size = factory_bounds.unlocked_world_size()
	elif grid_manager != null:
		corner = grid_manager.world_corner()
		size = Vector2(grid_manager.grid_size.x, grid_manager.grid_size.y) * grid_manager.cell_size
	else:
		return
	_target_position.x = clampf(_target_position.x, corner.x - pan_margin, corner.x + size.x + pan_margin)
	_target_position.z = clampf(_target_position.z, corner.z - pan_margin, corner.z + size.y + pan_margin)


## Projects a screen position onto the ground plane (y = 0).
func _ground_point(screen_pos: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(screen_pos)
	var direction := _camera.project_ray_normal(screen_pos)
	return origin - direction * (origin.y / direction.y)


## True while a text field (naming a cat, etc.) has keyboard focus.
## Needed because Input.get_vector() above polls raw physical key state,
## which — unlike an _input()/_gui_input() event — completely ignores UI
## focus: typing "wasd" into a LineEdit would otherwise pan the camera at
## the same time, since panning never consults the GUI focus system on
## its own.
func _is_typing() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## True while the mouse is over any UI control. Mouse-wheel zoom checks
## this so scrolling a UI list (Recipe Book, etc.) never also zooms the
## world camera underneath it — a ScrollContainer only consumes a wheel
## event itself while it still has room to scroll, so at the top/bottom
## of a long list the same wheel tick used to fall through to this node's
## _unhandled_input unconsumed.
func _mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null
