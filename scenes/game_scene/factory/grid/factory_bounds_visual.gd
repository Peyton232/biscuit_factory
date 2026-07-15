class_name FactoryBoundsVisual
extends Node3D
## Draws the boundary "walls" and the inner factory floor around whatever
## area FactoryBounds currently has unlocked. Placeholder visuals — real
## hand-drawn tiling textures (✅ 2026-07-13: grass-texture.png,
## pink-brick.png, blue-brick.png), but still simple primitive meshes,
## no custom modeling — rebuilds itself on FactoryBounds.expanded.
##
## **The inner floor's UV scale is recomputed on every resize, not left
## fixed** — a PlaneMesh's UV coordinates span 0..1 across its own
## geometry regardless of world size, so a fixed uv1_scale on a plane
## that's about to grow would silently change the apparent texture
## density. _FLOOR_UV_SCALE_PER_METER is the original full-grid Ground
## plane's own established density (its uv1_scale of 16.667 divided by
## its 200m size, both still visible in factory_world.tscn's git history/
## the mat_ground edit that added this feature) — re-derive both
## together the same way if floor tiling ever changes, same spirit as
## the Ground/floor.png note in architecture.md (which also documents
## that the actual current texture is tile2.0.png, not floor.png as
## previously written — a pre-existing doc/asset drift unrelated to this
## feature, flagged rather than silently perpetuated).
##
## **Each wall "side" is two thin slabs, not one box with one material**
## (✅ 2026-07-13, replacing a single flat-colored BoxMesh per side) —
## a `BoxMesh` has exactly one surface/material for all six faces, so
## there's no way to show blue brick on the inside and pink brick on the
## outside of the *same* box. Instead each side is built from an inner
## slab (facing the factory interior, blue) and an outer slab (facing the
## grass, pink — ✅ swapped 2026-07-15, factory_world.tscn had these two
## backwards since the split was first built; see decisions.md), each
## spanning half the wall's thickness, so together they still occupy the
## same footprint the single box used to. Simpler than the alternative
## (one box plus two oriented face-quads with rotation math per side) and
## needs no per-side orientation logic at all — just a per-side "which
## way is outward" unit vector to offset the two slabs apart from the
## shared centerline.
##
## **North/South walls are the "long" pair, East/West the "short" pair —
## not both extended (✅ fixed 2026-07-15)**: every side used to extend
## by a full `_WALL_THICKNESS` past the unlocked area's own edge so
## adjacent corners would meet, but *both* directions extending left each
## corner with two full walls' worth of solid geometry occupying the
## exact same `_WALL_THICKNESS`² square — genuine Z-fighting between two
## coincident opaque faces (reported as flicker at the corners), not just
## a thin seam. North/South stayed extended (`size.x + _WALL_THICKNESS`);
## East/West are now *shortened* instead (`size.y - _WALL_THICKNESS`) to
## fit exactly in the gap North/South's own extended ends already leave,
## a standard mitered/butted corner with zero overlapping geometry. The
## wall caps (`_place_wall_cap()`) reuse the same `full_sizes` values, so
## this one change fixes both the brick slabs' and the caps' corners at
## once.

@export var factory_bounds: FactoryBounds
@export var floor_texture: Texture2D
@export var inner_wall_texture: Texture2D
@export var outer_wall_texture: Texture2D

const _FLOOR_UV_SCALE_PER_METER: float = 16.667 / 200.0
const _FLOOR_ALBEDO: Color = Color(0.93, 0.87, 0.78, 1)
const _FLOOR_HEIGHT_OFFSET: float = 0.005

const _WALL_HEIGHT: float = 1.6
const _WALL_THICKNESS: float = 0.3
## World meters spanned by one texture repeat on a wall face — chosen to
## read as a plausible brick-course scale, not derived from anything
## structural (unlike the floor's grid-aligned scale, bricks don't need
## to line up with anything).
const _WALL_UV_REPEAT_METERS: float = 1.2

## Thin solid-color slab sitting directly on top of each wall side, so
## the top face reads as a flat black cap instead of the brick texture
## (a BoxMesh can't show a different material per face — see this
## class's own doc comment — so this is a second, separate box rather
## than a material tweak on the wall slabs themselves).
const _WALL_CAP_HEIGHT: float = 0.02
const _WALL_CAP_COLOR: Color = Color(0, 0, 0)

var _floor_instance: MeshInstance3D
var _floor_material: StandardMaterial3D

## Per side (North/South/East/West): the slab facing the factory
## interior, and its own material (so each side's uv1_scale can be tuned
## to that side's own length independently).
var _inner_slabs: Array[MeshInstance3D] = []
var _inner_materials: Array[StandardMaterial3D] = []
## Same, for the slab facing outward toward the grass.
var _outer_slabs: Array[MeshInstance3D] = []
var _outer_materials: Array[StandardMaterial3D] = []
## One flat black cap per side, spanning the side's full footprint (both
## slabs together) — see _WALL_CAP_HEIGHT doc above.
var _caps: Array[MeshInstance3D] = []
## Shared by every cap: same flat color everywhere, no texture/uv1_scale
## to tune per side, so one material (not one per side) is enough.
var _cap_material: StandardMaterial3D

## Unit vector pointing away from the factory center, one per side, in
## the same North/South/East/West order _refresh() places walls in.
const _OUTWARD_DIRECTIONS: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(1, 0, 0),
]


func _ready() -> void:
	_build_floor()
	_build_walls()
	factory_bounds.expanded.connect(_refresh)
	_refresh()


func _build_floor() -> void:
	_floor_material = StandardMaterial3D.new()
	_floor_material.albedo_color = _FLOOR_ALBEDO
	_floor_material.albedo_texture = floor_texture

	var mesh := PlaneMesh.new()
	mesh.material = _floor_material

	_floor_instance = MeshInstance3D.new()
	_floor_instance.mesh = mesh
	add_child(_floor_instance)


func _build_walls() -> void:
	_cap_material = StandardMaterial3D.new()
	_cap_material.albedo_color = _WALL_CAP_COLOR
	_cap_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for _side: int in 4:
		_inner_slabs.append(_make_slab(inner_wall_texture, _inner_materials))
		_outer_slabs.append(_make_slab(outer_wall_texture, _outer_materials))
		_caps.append(_make_cap())


func _make_slab(texture: Texture2D, materials_out: Array[StandardMaterial3D]) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	# NEAREST_WITH_MIPMAPS, not the default LINEAR_WITH_MIPMAPS: this
	# project's crisp pixel-art look (every Sprite3D uses NEAREST) was
	# getting blurred out on the walls by linear filtering, worst at a
	# grazing angle/while panning across a highly-repeated small texture
	# — mipmaps are kept (unlike Sprite3D's icons) since a tiled surface
	# actually viewed at distance/an angle needs them to avoid shimmering,
	# which plain NEAREST with no mips would do instead of blurring.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	materials_out.append(material)

	var mesh := BoxMesh.new()
	mesh.material = material

	var segment := MeshInstance3D.new()
	segment.mesh = mesh
	add_child(segment)
	return segment


func _make_cap() -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.material = _cap_material

	var cap := MeshInstance3D.new()
	cap.mesh = mesh
	add_child(cap)
	return cap


func _refresh() -> void:
	var corner: Vector3 = factory_bounds.unlocked_world_corner()
	var size: Vector2 = factory_bounds.unlocked_world_size()
	var center: Vector3 = corner + Vector3(size.x * 0.5, 0.0, size.y * 0.5)

	var floor_mesh: PlaneMesh = _floor_instance.mesh as PlaneMesh
	floor_mesh.size = size
	_floor_material.uv1_scale = Vector3(size.x, size.y, size.x) * _FLOOR_UV_SCALE_PER_METER
	_floor_instance.position = center + Vector3(0.0, _FLOOR_HEIGHT_OFFSET, 0.0)

	# North, South, East, West — each side's full size (length +
	# thickness, so corners meet cleanly) and centerline position, same
	# as before the inner/outer slab split.
	var centers: Array[Vector3] = [
		center + Vector3(0.0, 0.0, -size.y * 0.5),
		center + Vector3(0.0, 0.0, size.y * 0.5),
		center + Vector3(-size.x * 0.5, 0.0, 0.0),
		center + Vector3(size.x * 0.5, 0.0, 0.0),
	]
	# North/South stay extended past the corner; East/West are shortened
	# to fit exactly in the gap that leaves, instead of also extending —
	# see this class's doc comment for why both used to extend (real
	# Z-fighting from fully-overlapping corner geometry).
	var full_sizes: Array[Vector3] = [
		Vector3(size.x + _WALL_THICKNESS, _WALL_HEIGHT, _WALL_THICKNESS),
		Vector3(size.x + _WALL_THICKNESS, _WALL_HEIGHT, _WALL_THICKNESS),
		Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size.y - _WALL_THICKNESS),
		Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size.y - _WALL_THICKNESS),
	]
	for i: int in 4:
		_place_wall_slabs(i, centers[i], full_sizes[i], _OUTWARD_DIRECTIONS[i])
		_place_wall_cap(i, centers[i], full_sizes[i])


## Splits one side's full-thickness footprint into an inner (toward the
## factory center) and outer (away from it) half-thickness slab, offset
## apart along outward_dir so together they still fill the same space.
func _place_wall_slabs(side: int, center: Vector3, full_size: Vector3, outward_dir: Vector3) -> void:
	var along_x: bool = absf(outward_dir.x) > 0.5
	var half_size: Vector3 = full_size
	var length_meters: float
	if along_x:
		half_size.x = full_size.x * 0.5
		length_meters = full_size.z
	else:
		half_size.z = full_size.z * 0.5
		length_meters = full_size.x
	var shift: Vector3 = outward_dir * (half_size.x if along_x else half_size.z) * 0.5

	var uv_scale: float = length_meters / _WALL_UV_REPEAT_METERS
	_set_slab(_inner_slabs[side], _inner_materials[side], center - shift, half_size, uv_scale)
	_set_slab(_outer_slabs[side], _outer_materials[side], center + shift, half_size, uv_scale)


func _set_slab(segment: MeshInstance3D, material: StandardMaterial3D, center: Vector3, size: Vector3, uv_scale: float) -> void:
	(segment.mesh as BoxMesh).size = size
	segment.position = center + Vector3(0.0, _WALL_HEIGHT * 0.5, 0.0)
	material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)


## Sits the flat black cap directly on top of the side's full footprint
## (inner + outer slabs together), just above _WALL_HEIGHT — its own top
## face (not the brick slabs' top, now hidden beneath it) is what the
## camera actually sees looking down on the wall.
func _place_wall_cap(side: int, center: Vector3, full_size: Vector3) -> void:
	var cap_size := Vector3(full_size.x, _WALL_CAP_HEIGHT, full_size.z)
	(_caps[side].mesh as BoxMesh).size = cap_size
	_caps[side].position = center + Vector3(0.0, _WALL_HEIGHT + _WALL_CAP_HEIGHT * 0.5, 0.0)
