class_name GridCursor
extends Node3D
## Tracks which grid cell the mouse is hovering and highlights it.
## The highlight turns red over occupied cells. Placement systems read
## `has_hover` / `hovered_cell`, or listen to `hover_changed`.

## Emitted when the hovered cell changes. When `has_hover` is false the
## mouse is off the grid and `cell` holds the last hovered cell.
signal hover_changed(has_hover: bool, cell: Vector2i)

@export var grid_manager: GridManager
@export var free_color: Color = Color(1.0, 0.97, 0.75, 0.45)
@export var occupied_color: Color = Color(0.9, 0.3, 0.25, 0.55)
## Highlight quad size relative to the cell, so grid lines stay readable.
@export_range(0.5, 1.0) var quad_scale: float = 0.92
## Lift above the ground plane to avoid z-fighting.
@export var height_offset: float = 0.01

## Optional judge of whether the hovered cell is a valid click target
## (set by the BuildingPlacer): takes a Vector2i cell, returns bool.
## When unset, a cell is "valid" simply when unoccupied.
var validity_check: Callable = Callable()

var has_hover: bool = false
var hovered_cell: Vector2i = Vector2i.ZERO
## Raw (non-grid-snapped) ground point under the mouse, valid whenever
## has_hover is true. Used by systems that need exact position, not a cell
## (e.g. clicking to select a cat).
var world_point: Vector3 = Vector3.ZERO

var _highlight: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	_build_highlight()


func _process(_delta: float) -> void:
	_update_hover()


func _update_hover() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		_set_hover(false, hovered_cell)
		return

	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)
	if direction.y >= 0.0:
		# Ray parallel to the ground plane or pointing at the sky.
		_set_hover(false, hovered_cell)
		return

	var ground_point: Vector3 = origin - direction * (origin.y / direction.y)
	world_point = ground_point
	var cell: Vector2i = grid_manager.world_to_grid(ground_point)
	_set_hover(grid_manager.is_in_bounds(cell), cell)


func _set_hover(hovering: bool, cell: Vector2i) -> void:
	var changed: bool = hovering != has_hover or (hovering and cell != hovered_cell)
	has_hover = hovering
	if hovering:
		hovered_cell = cell
		_highlight.position = grid_manager.grid_to_world(cell) + Vector3.UP * height_offset
		# Refresh every frame: validity can change while the mouse is still
		# (occupancy updates, money runs out, tool switches).
		var valid: bool
		if validity_check.is_valid():
			valid = validity_check.call(cell)
		else:
			valid = not grid_manager.is_cell_occupied(cell)
		_material.albedo_color = free_color if valid else occupied_color
	_highlight.visible = hovering
	if changed:
		hover_changed.emit(has_hover, hovered_cell)


func _build_highlight() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = free_color

	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * grid_manager.cell_size * quad_scale
	quad.material = _material

	_highlight = MeshInstance3D.new()
	_highlight.name = "Highlight"
	_highlight.mesh = quad
	_highlight.visible = false
	add_child(_highlight)
