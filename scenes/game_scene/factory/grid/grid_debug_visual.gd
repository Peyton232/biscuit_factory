class_name GridDebugVisual
extends MeshInstance3D
## Draws the grid as unshaded lines for development. Purely visual —
## toggle with the node's `visible` property. Rebuilt once at ready from
## the GridManager's dimensions.

@export var grid_manager: GridManager
@export var line_color: Color = Color(0.45, 0.4, 0.35, 0.35)
## Lift above the ground plane to avoid z-fighting.
@export var height_offset: float = 0.02


func _ready() -> void:
	mesh = _build_line_mesh()


func _build_line_mesh() -> ArrayMesh:
	var size: Vector2i = grid_manager.grid_size
	var cell: float = grid_manager.cell_size
	var corner: Vector3 = grid_manager.world_corner() + Vector3(0.0, height_offset, 0.0)
	var width: float = size.x * cell
	var depth: float = size.y * cell

	var points := PackedVector3Array()
	for x: int in size.x + 1:
		points.append(corner + Vector3(x * cell, 0.0, 0.0))
		points.append(corner + Vector3(x * cell, 0.0, depth))
	for z: int in size.y + 1:
		points.append(corner + Vector3(0.0, 0.0, z * cell))
		points.append(corner + Vector3(width, 0.0, z * cell))

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = line_color

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points

	var line_mesh := ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	line_mesh.surface_set_material(0, material)
	return line_mesh
