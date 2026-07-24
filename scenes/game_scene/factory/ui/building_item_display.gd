class_name BuildingItemDisplay
extends Node3D
## Shows the actual item sprite(s) currently sitting in a building's
## input/output inventories, at half the size Cat's CarriedItem uses for
## a hauled item — "drop actual items on stations" playtest feedback.
## Previously a station's held items were only visible as
## BuildingInventoryLabel's text counts ("milk x3"), with no sprite.
##
## One icon per distinct item currently present (count > 0), not one per
## unit — the text label already carries the count; this is purely a
## "what does it actually look like" visual, laid out in a small row.
## Pooled Sprite3D children, refreshed the same way BuildingInventoryLabel
## refreshes: on Inventory.changed.
##
## **Anchored the same way every billboarded building/cat element is:
## ground-level `position` (`Vector3(0, 0.05, 0)`, matching `Visual`) on
## both this container AND every pooled icon, with `height_offset_px`/
## `icon_spacing_px` (pixels, applied via `Sprite3D.offset`) doing all
## the "how high above ground, how far apart" work instead — never a
## literal world-space Y/Z.** First pass (2026-07-13) used a literal
## world-space `position` (both on this container node, per-building in
## each `.tscn`, and via `position.x` for the row layout) — reported
## (with a screenshot) as items not sitting on their building and
## visibly sliding around relative to it as the camera panned. That's
## the exact "drifts relative to a billboarded sibling" bug already
## documented and fixed for Cat's CarriedItem/NameLabel: a literal
## world-space offset doesn't project the same way a billboard's own
## `offset` does from every camera angle, so a billboarded icon anchored
## by raw `position` visibly shears apart from the building's own
## billboarded `Visual` (anchored by `offset`) as the camera moves, even
## though both are rigidly parented to the same still building.
## `height_offset_px` is still the per-building "where's the counter"
## tuning knob the first pass already anticipated needing — just
## expressed in offset pixels now instead of world meters, carrying over
## the same values (divided by icon_pixel_size) rather than re-guessing.
##
## **`separate_output_position` (✅ added 2026-07-14)**: some buildings'
## art has a dedicated "finished item" prop the input row would
## otherwise overlap — DecoratingTable's cake stand specifically (a
## static pedestal drawn into the sprite itself; a single centered row
## spanning inputs+output landed squarely on top of it and the other
## countertop props, reported as "items all over it randomly"). When
## true, the output icon is positioned independently at
## `output_offset_px` instead of continuing the input row. Default
## false, so every other building (Mixer/Oven/PrepTable/ShippingBin)
## keeps its original single-row behavior verbatim — this is additive,
## not a change to the common case.
##
## **Skips ShippingBin's inputs**, same exception BuildingInventoryLabel
## already makes — a bin's current_inputs() is its long, player-
## configurable accept list, not what's actually piled up; a dozen small
## icons for "would accept if present" would be noise, not information.
##
## **Every pooled icon gets a distinct render_priority (✅ fixed —
## reported as "Z fighting on items in buildings", worst on the Oven)** —
## every icon shares the exact same Node3D `position` (_GROUND_ANCHOR;
## the row layout is entirely a billboard-space `offset` trick, see above),
## so with `no_depth_test = true` and every icon at the *same* fixed
## `render_priority = 1`, two-or-more-item buildings (an Oven mid-recipe
## showing both its input and output, most stations once they're actually
## working) had no real tiebreaker between coincident, depth-test-disabled
## transparent quads — Godot falls back to camera-distance sorting, which
## is itself a tie for sprites at the same position, so the draw order
## flipped frame to frame. _row_icon_at()/_make_output_icon() now assign
## each icon its own priority (row index, then the output above every row
## slot) so draw order is deterministic instead of an unstable tie.

@export var building: Building
@export var icon_pixel_size: float = 0.015
## How far apart consecutive icons sit in a multi-item row, in offset
## pixels (scaled by icon_pixel_size like everything else here).
@export var icon_spacing_px: float = 21.0
## How high above the ground this building's "counter" reads, in offset
## pixels — the per-building tuning knob (see class doc).
@export var height_offset_px: float = 50.0
## Horizontal shift of the input row's own center, in offset pixels —
## 0 (default) keeps every building's original centered-on-the-building
## row. Only meaningful once separate_output_position pulls the output
## out of that row too (e.g. DecoratingTable shifts its input row left
## so it clears the cake stand the now-independent output sits on).
@export var row_offset_x_px: float = 0.0
## See class doc — false keeps the output in the same row as the inputs
## (every building's original behavior).
@export var separate_output_position: bool = false
## Where the output icon sits when separate_output_position is true —
## offset pixels, same convention as height_offset_px/icon_spacing_px.
## Unused when separate_output_position is false.
@export var output_offset_px: Vector2 = Vector2.ZERO

var _row_icons: Array[Sprite3D] = []
var _output_icon: Sprite3D = null

const _GROUND_ANCHOR: Vector3 = Vector3(0, 0.05, 0)


func _ready() -> void:
	position = Vector3.ZERO
	building.input_inventory.changed.connect(_refresh)
	building.output_inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var inputs: Array[StringName] = _current_input_items()
	var outputs: Array[StringName] = _current_output_items()
	if separate_output_position:
		_populate_row(inputs)
		_populate_output(outputs)
	else:
		_populate_row(inputs + outputs)
		if _output_icon != null:
			_output_icon.hide()


func _current_input_items() -> Array[StringName]:
	var items: Array[StringName] = []
	if building is ShippingBin:
		return items
	for item: StringName in building.current_inputs():
		if building.input_inventory.count(item) > 0:
			items.append(item)
	return items


func _current_output_items() -> Array[StringName]:
	var items: Array[StringName] = []
	for item: StringName in building.current_outputs():
		if building.output_inventory.count(item) > 0:
			items.append(item)
	return items


func _populate_row(items: Array[StringName]) -> void:
	for i: int in range(items.size()):
		_set_icon_texture(_row_icon_at(i), items[i])
	for i: int in range(items.size(), _row_icons.size()):
		_row_icons[i].hide()
	_layout_row(items.size())


## Only ever one output icon — every station's output_capacity is 1 (see
## architecture.md's ProcessingBuilding section), so there's never more
## than one distinct output item to show at once.
func _populate_output(outputs: Array[StringName]) -> void:
	if outputs.is_empty():
		if _output_icon != null:
			_output_icon.hide()
		return
	if _output_icon == null:
		_output_icon = _make_icon()
		# Above every possible row slot's own priority (see _row_icon_at())
		# — see class doc's render_priority note.
		_output_icon.render_priority = _OUTPUT_RENDER_PRIORITY
	_set_icon_texture(_output_icon, outputs[0])
	_output_icon.offset = output_offset_px


func _set_icon_texture(icon: Sprite3D, item: StringName) -> void:
	var texture: Texture2D = _texture_for(item)
	if texture == null:
		icon.hide()
		return
	icon.texture = texture
	icon.pixel_size = icon_pixel_size * ItemVisuals.scale_for(item)
	icon.show()


func _texture_for(item: StringName) -> Texture2D:
	var path: String = "res://assets/sprites/items/%s.png" % item
	if not ResourceLoader.exists(path):
		return null
	return load(path)


func _row_icon_at(i: int) -> Sprite3D:
	if i < _row_icons.size():
		return _row_icons[i]
	var icon: Sprite3D = _make_icon()
	# See class doc's render_priority note — index-based, not a shared
	# constant, so simultaneously-visible row icons never tie.
	icon.render_priority = 1 + i
	_row_icons.append(icon)
	return icon


## Headroom above every row icon's own render_priority (1 + index — see
## _row_icon_at()) — a building would need more than this many
## simultaneous row icons before the output icon's priority could
## collide with one, far beyond any real input/output count in this game
## (largest is 3, Assembly Table's Frosted Cake — see recipes.md).
const _OUTPUT_RENDER_PRIORITY: int = 50


func _make_icon() -> Sprite3D:
	var icon := Sprite3D.new()
	icon.position = _GROUND_ANCHOR
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.pixel_size = icon_pixel_size
	icon.texture_filter = 0
	icon.no_depth_test = true
	add_child(icon)
	return icon


func _layout_row(count: int) -> void:
	var total_width_px: float = float(count - 1) * icon_spacing_px
	for i: int in range(count):
		var x: float = row_offset_x_px - total_width_px * 0.5 + float(i) * icon_spacing_px
		_row_icons[i].offset = Vector2(x, height_offset_px)
