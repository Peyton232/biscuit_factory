class_name BuildingProgressBar
extends Node3D
## Tiny world-space progress bar above a building, visible only while it
## has active progress (a ProcessingBuilding running a recipe batch, or
## an IngredientSource counting down to its next item). Reads the
## building's progress() each frame — see Building.progress(). Built from
## two textured quads (real art, ✅ 2026-07-14 — see decisions.md); no
## billboard needed since the camera yaw never rotates — a slight X tilt
## keeps it readable at the camera's pitch.

@export var building: Building
## Sized to Bar_Background_.png's own 140x14 (10:1) pixel aspect ratio —
## the quad's UVs stretch the art to fit whatever width/height is set
## here, so this is "resize the art," not "crop/tile it."
@export var width: float = 1.4
@export var height: float = 0.14
## Multiply tint over Bar_Fill.png — white (no tint) shows the art as
## authored for normal progress.
@export var fill_color: Color = Color(1.0, 1.0, 1.0)
## Tint shown when the work is done but the output inventory is full —
## the only case that still needs a color cue, since there's no separate
## "blocked" art.
@export var blocked_color: Color = Color(1.0, 0.75, 0.3)

## Bar_Fill.png is 140x8 (17.5:1) — proportionally shorter than the
## background's 140x14, so the fill quad's height is derived from this
## ratio rather than an arbitrary fraction of the background's height.
const _FILL_HEIGHT_RATIO: float = 8.0 / 14.0

const _BACKGROUND_TEXTURE: Texture2D = preload("res://assets/UI/Bar_Background_.png")
const _FILL_TEXTURE: Texture2D = preload("res://assets/UI/Bar_Fill.png")

var _fill: MeshInstance3D
var _fill_material: StandardMaterial3D


func _ready() -> void:
	rotation_degrees = Vector3(-35.0, 0.0, 0.0)
	# render_priority forces draw order explicitly. Relying on the quads'
	# tiny z_offset alone isn't enough: Godot sorts transparent objects by
	# distance to camera, and at some distances that flips background
	# in front of fill, making the bar look permanently empty/dark.
	_add_quad(_BACKGROUND_TEXTURE, Color.WHITE, Vector2(width, height), 0.0, 0)
	_fill = _add_quad(
		_FILL_TEXTURE, fill_color, Vector2(width, height * _FILL_HEIGHT_RATIO), 0.005, 1)
	_fill_material = _fill.mesh.surface_get_material(0) as StandardMaterial3D
	visible = false


func _process(_delta: float) -> void:
	var progress: float = building.progress()
	visible = progress > 0.0
	if visible:
		_fill.scale.x = maxf(progress, 0.001)
		_fill.position.x = -width * (1.0 - progress) * 0.5
		_fill_material.albedo_color = blocked_color if progress >= 1.0 else fill_color


func _add_quad(
	texture: Texture2D, modulate: Color, size: Vector2, z_offset: float, priority: int
) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.albedo_color = modulate
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.render_priority = priority

	var quad := QuadMesh.new()
	quad.size = size
	quad.material = material

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = quad
	mesh_instance.position.z = z_offset
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	return mesh_instance
