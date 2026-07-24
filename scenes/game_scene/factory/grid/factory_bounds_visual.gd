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
## Fixed vertical (height) UV tiling, derived once from the wall's own
## constant height — see _place_wall_slabs()'s doc comment for why this
## has to be separate from the per-side horizontal scale.
const _WALL_HEIGHT_UV_SCALE: float = _WALL_HEIGHT / _WALL_UV_REPEAT_METERS

## Thin solid-color slab sitting directly on top of each wall side, so
## the top face reads as a flat cap instead of the brick texture (a
## BoxMesh can't show a different material per face — see this class's
## own doc comment — so this is a second, separate box rather than a
## material tweak on the wall slabs themselves). **A BoxMesh's brick
## material covers all six of its own faces, including its top — the cap
## exists specifically to hide that (otherwise a stray, badly-scaled
## brick pattern would show on top of the wall).** Raised 0.02 -> 0.08
## (✅ fixed — reported as brick color "poking through" the cap, worse at
## a distant/grazing viewing angle) — the cap's own clearance above the
## slab tops is exactly this height, and 0.02m left almost no depth-buffer
## headroom at typical camera distances/angles, making it a textbook
## z-fighting setup between the cap's top face and the slab's
## brick-textured top face. Still a thin, barely-visible rim at this
## height, just with real z-fighting headroom now.
const _WALL_CAP_HEIGHT: float = 0.08
## RGB(39, 66, 89) — a dark slate blue, player's own pick (✅ changed
## 2026-07-15, was plain black).
const _WALL_CAP_COLOR: Color = Color(39.0 / 255.0, 66.0 / 255.0, 89.0 / 255.0)

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
	# **ANISOTROPIC variant tried and reverted** — added for a "stretched
	# at a grazing angle" report, but this project runs on the
	# `gl_compatibility` renderer (project.godot), which has limited/
	# inconsistent anisotropic filtering support — the wall looked *worse*
	# (a smooth gradient with no visible brick pattern at all, not just
	# blurry) after switching, consistent with anisotropic silently
	# misbehaving on this renderer rather than helping. Back to plain
	# NEAREST_WITH_MIPMAPS while the real cause of the stretching report
	# gets re-investigated — see decisions.md.
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
	# **Every side's OUTER slab extends past the nominal corner; every
	# side's INNER slab stays at nominal length (✅ fixed — see
	# _place_wall_slabs()'s doc comment for the full corner-by-corner
	# reasoning)** — replaces the old "North/South both extend, East/West
	# both shorten" scheme, which avoided the original full-overlap
	# z-fighting but left a different bug: North/South's *inner* slab
	# extended right along with their outer, poking blue into territory
	# that should have been East/West's outer (pink) face at the exact
	# corner — reported as "a little bit sticking through" at the
	# corners. Outer always extending means adjacent sides' outer slabs
	# safely double-cover the true exterior corner (same color, no
	# visible z-fight); inner always staying at nominal length means no
	# side's inner ever reaches into a corner it doesn't belong in.
	var outer_full_sizes: Array[Vector3] = [
		Vector3(size.x + _WALL_THICKNESS, _WALL_HEIGHT, _WALL_THICKNESS),
		Vector3(size.x + _WALL_THICKNESS, _WALL_HEIGHT, _WALL_THICKNESS),
		Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size.y + _WALL_THICKNESS),
		Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size.y + _WALL_THICKNESS),
	]
	var inner_full_sizes: Array[Vector3] = [
		Vector3(size.x, _WALL_HEIGHT, _WALL_THICKNESS),
		Vector3(size.x, _WALL_HEIGHT, _WALL_THICKNESS),
		Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size.y - _WALL_THICKNESS),
		Vector3(_WALL_THICKNESS, _WALL_HEIGHT, size.y - _WALL_THICKNESS),
	]
	for i: int in 4:
		_place_wall_slabs(i, centers[i], outer_full_sizes[i], inner_full_sizes[i], _OUTWARD_DIRECTIONS[i])
		_place_wall_cap(i, centers[i], outer_full_sizes[i])


## Splits one side's footprint into an inner (toward the factory center)
## and outer (away from it) half-thickness slab, offset apart along
## outward_dir. **outer_full_size/inner_full_size are deliberately
## different lengths, not a shared full_size split into two halves (✅
## fixed — reported as brick color visibly "sticking through" at the
## corners)** — worked out by tracing the corner geometry into its four
## thickness-vs-thickness sub-squares (see decisions.md for the full
## derivation): at a corner, the *true exterior* point needs an OUTER
## (pink) slab reaching into it from *whichever* side gets there, and the
## *true interior* point needs an INNER (blue) slab — the bug was that
## the old scheme extended North/South's *inner* slab past the nominal
## corner right along with its outer, so for the thin sliver where
## North's inner overlapped West's own outer thickness band, blue showed
## where the exterior-facing pink was expected. Fixed by decoupling the
## two: every side's outer slab always extends past the nominal corner
## (`size + _WALL_THICKNESS`, so adjacent sides' outer slabs safely
## double-cover the true exterior corner — same color, no visible
## z-fight) while every side's inner slab stays at exactly nominal length
## (`size`, no extension) — verified corner-square-by-corner to leave
## zero gaps and zero wrong-colored patches. The two slabs share the same
## thickness-axis half-size and shift (unaffected by this — `_WALL_THICKNESS`
## itself never changes between inner/outer), only their *length* differs.
func _place_wall_slabs(side: int, center: Vector3, outer_full_size: Vector3, inner_full_size: Vector3, outward_dir: Vector3) -> void:
	var along_x: bool = absf(outward_dir.x) > 0.5
	var shift: Vector3 = outward_dir * _WALL_THICKNESS * 0.25

	var outer_half_size: Vector3 = outer_full_size
	var inner_half_size: Vector3 = inner_full_size
	var outer_length_meters: float
	var inner_length_meters: float
	if along_x:
		outer_half_size.x = _WALL_THICKNESS * 0.5
		inner_half_size.x = _WALL_THICKNESS * 0.5
		outer_length_meters = outer_full_size.z
		inner_length_meters = inner_full_size.z
	else:
		outer_half_size.z = _WALL_THICKNESS * 0.5
		inner_half_size.z = _WALL_THICKNESS * 0.5
		outer_length_meters = outer_full_size.x
		inner_length_meters = inner_full_size.x

	_set_slab(_inner_slabs[side], _inner_materials[side], center - shift, inner_half_size,
			Vector3(inner_length_meters / _WALL_UV_REPEAT_METERS, _WALL_HEIGHT_UV_SCALE, 1.0))
	_set_slab(_outer_slabs[side], _outer_materials[side], center + shift, outer_half_size,
			Vector3(outer_length_meters / _WALL_UV_REPEAT_METERS, _WALL_HEIGHT_UV_SCALE, 1.0))


func _set_slab(segment: MeshInstance3D, material: StandardMaterial3D, center: Vector3, size: Vector3, uv_scale: Vector3) -> void:
	(segment.mesh as BoxMesh).size = size
	segment.position = center + Vector3(0.0, _WALL_HEIGHT * 0.5, 0.0)
	material.uv1_scale = uv_scale


## Sits the flat black cap directly on top of the side's full footprint
## (inner + outer slabs together), just above _WALL_HEIGHT — its own top
## face (not the brick slabs' top, now hidden beneath it) is what the
## camera actually sees looking down on the wall.
func _place_wall_cap(side: int, center: Vector3, full_size: Vector3) -> void:
	var cap_size := Vector3(full_size.x, _WALL_CAP_HEIGHT, full_size.z)
	(_caps[side].mesh as BoxMesh).size = cap_size
	_caps[side].position = center + Vector3(0.0, _WALL_HEIGHT + _WALL_CAP_HEIGHT * 0.5, 0.0)
