class_name IngredientSourceStack
extends Node3D
## Shows the actual item sprite(s) piling up on an Ingredient Source as
## its output fills, arranged in a single horizontal line — "have the
## items physically appear on top of them as they fill up" playtest
## feedback.
##
## **A line, not a pyramid (✅ changed 2026-07-14)**: the original 2/2/1
## pyramid assumed every source's crate art was roughly the same
## symmetric shape, which stopped holding once Milk/Butter/Egg/Sugar
## Sources all got their own real, differently-shaped art (see
## decisions.md) — a layered pyramid sat naturally on some crates and
## visibly floating/misaligned on others. A flat line laid out from the
## center outward tracks a crate's own (wider-than-tall) silhouette
## across every source's art instead of assuming one specific shape.
## Fill order is center-out, alternating sides — for item index i (1
## being the first item placed), the *visual* left-to-right order at
## full capacity (5) reads **5 3 1 2 4**: 1 is dead center, 2 sits one
## slot to its right, 3 one slot to its left, then 4/5 extend the line
## further right/left again. This also means the pile never looks
## lopsided at low counts (1 item is always centered, not stuck at one
## end waiting for the rest to arrive).
##
## **Distinct from `BuildingItemDisplay`** (used by every other
## building): a source only ever produces ONE item type, so quantity is
## the whole story here — this shows it as a growing line of identical
## icons rather than "one icon per distinct item present." Replaces
## `BuildingItemDisplay` on `ingredient_source.tscn` specifically (the
## two would otherwise show redundant/conflicting things for the same
## single item).
##
## **Anchored ground-level (`position = Vector3(0, 0.05, 0)` on both this
## container and every pooled icon) plus pixel `offset`s, never a
## literal world-space position** — same convention `BuildingItemDisplay`
## itself was fixed to use (see its own class doc/decisions.md for why a
## literal offset drifts relative to a differently-anchored billboarded
## sibling as the camera pans).
##
## **Height/spacing derived per-item from the actual texture, not one
## shared pixel constant (✅ fixed 2026-07-14, two passes same day)** —
## first pass converted `height_offset_px`/`horizontal_spacing_px` to
## world-meters exports (the same fix `CarriedItem._show_carried_item()`
## already established: `Sprite3D.offset` is scaled by *that sprite's
## own* `pixel_size`, and this icon's `pixel_size` includes a per-item
## `ItemVisuals.scale_for()` correction unrelated to "how high above
## ground" — a fixed pixel offset silently produced a different
## real-world height/spacing per item). That fix was real but
## incomplete: a *single* shared meters constant still can't fit five
## items of different native size at once — reported directly ("eggs
## need to be down a little to touch the platform... milk is floating by
## like a pixel or 2... flour needs to be just slightly closer
## together"), each needing a *different* correction. The fix instead
## computes both per item, per refresh, straight from `_texture.get_size()`:
## `height` puts the icon's *bottom edge* exactly at `surface_height_meters`
## (not its center — every item's own half-height is added on top, so
## every item's bottom touches the same surface regardless of how tall
## it individually renders), and `spacing` is `spacing_multiplier` ×
## that item's own rendered width (so a narrow item like milk gets
## tighter absolute spacing than a wide item like flour automatically,
## instead of one spacing value being simultaneously too tight for wide
## items and too loose for narrow ones). See decisions.md for the exact
## numbers this replaced and why a single constant couldn't work.

@export var source: IngredientSource
@export var icon_pixel_size: float = 0.015
## World height (meters) of the surface items rest on — the crate lid's
## own top edge. Every item's bottom edge lands exactly here regardless
## of that item's own height; see class doc.
@export var surface_height_meters: float = 0.5
## Gap between adjacent slots, as a multiple of *that item's own*
## rendered width — 1.0 would have icons just touching edge-to-edge;
## slightly above 1.0 leaves a small visible gap. See class doc.
@export var spacing_multiplier: float = 1.1

const _GROUND_ANCHOR: Vector3 = Vector3(0, 0.05, 0)

## Center-out fill order per count (index = how many items currently
## present) — each entry is an x offset in horizontal_spacing_px
## multiples, one per item, in placement order. See class doc for why
## center-out-alternating instead of a pyramid. A fixed per-count table
## (only 6 possible counts) rather than a generic algorithm, same
## reasoning the old pyramid table used — hand-placing each one keeps
## the exact "1 always centered, then alternate right/left" order
## explicit rather than approximated by a formula.
const _LAYOUTS: Array = [
	[],
	[0.0],
	[0.0, 1.0],
	[0.0, 1.0, -1.0],
	[0.0, 1.0, -1.0, 2.0],
	[0.0, 1.0, -1.0, 2.0, -2.0],
]

var _icons: Array[Sprite3D] = []
var _texture: Texture2D = null


func _ready() -> void:
	position = Vector3.ZERO
	source.output_inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var item: StringName = source.definition.outputs[0]
	if _texture == null:
		_texture = _texture_for(item)
	if _texture == null:
		return
	var count: int = clampi(source.output_inventory.count(item), 0, _LAYOUTS.size() - 1)
	var layout: Array = _LAYOUTS[count]
	var pixel_size: float = icon_pixel_size * ItemVisuals.scale_for(item)
	var native_size: Vector2 = _texture.get_size()
	var world_width: float = native_size.x * pixel_size
	var world_height: float = native_size.y * pixel_size
	# Bottom edge (not center) lands at surface_height_meters — see class doc.
	var height_meters: float = surface_height_meters + world_height * 0.5
	var spacing_meters: float = world_width * spacing_multiplier
	for i: int in range(count):
		var icon: Sprite3D = _icon_at(i)
		var x_slot: float = layout[i]
		icon.texture = _texture
		icon.pixel_size = pixel_size
		# Dividing by this icon's own pixel_size cancels its ItemVisuals
		# scale back out — same reasoning as CarriedItem's own fix.
		icon.offset = Vector2(x_slot * spacing_meters, height_meters) / pixel_size
		icon.show()
	for i: int in range(count, _icons.size()):
		_icons[i].hide()


func _texture_for(item: StringName) -> Texture2D:
	var path: String = "res://assets/sprites/items/%s.png" % item
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _icon_at(i: int) -> Sprite3D:
	if i < _icons.size():
		return _icons[i]
	var icon := Sprite3D.new()
	icon.position = _GROUND_ANCHOR
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.pixel_size = icon_pixel_size
	icon.texture_filter = 0
	icon.render_priority = 1
	icon.no_depth_test = true
	add_child(icon)
	_icons.append(icon)
	return icon
