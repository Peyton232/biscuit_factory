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
## both this container AND every pooled icon, with `surface_height_px`/
## `surface_left_px`/`surface_right_px` (pixels, applied via
## `Sprite3D.offset`) doing all the "how high above ground, how far
## apart" work instead — never a literal world-space Y/Z.** First pass (2026-07-13) used a literal
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
## `surface_height_px` is still the per-building "where's the counter"
## tuning knob the first pass already anticipated needing — just
## expressed in offset pixels now instead of world meters, carrying over
## the same values (divided by icon_pixel_size) rather than re-guessing.
##
## **Layout is measured, not spaced (✅ rewritten 2026-09-25).** Inputs
## are packed left-to-right from `surface_left_px`; the output is pinned
## flush to `surface_right_px`, per "have outputs be right aligned on the
## building and inputs left aligned, and make sure they dont overlap".
## Every position comes from the item's *own* rendered width
## (`texture.get_width() * ItemVisuals.scale_for(item)`), never a shared
## constant — the player put it exactly right: "some items like butter
## are wider than something like eggs, so a default offset for everything
## may not work". Measured, the spread is more than 2x: `cut_biscuit`
## renders 48 offset-px wide against `milk`'s 16, while the old
## `icon_spacing_px` was a flat 21 for all of them, so wide items
## overlapped and narrow ones left holes.
##
## **Non-overlap is guaranteed by construction, not by tuning.** Packing
## by real widths is only half of it: the worst recipe in the game (the
## Oven's Meringue Pie) needs 130.2 offset-px of item across a building
## only ~133 wide, so at full size there is genuinely no arrangement that
## fits with gaps. `_fit_scale()` shrinks the whole row uniformly by
## whatever factor it takes, which keeps the items' relative sizes honest
## and makes "icons never touch" a property of the code. It returns 1.0
## for the common case, so most rows are untouched.
##
## The old per-icon knobs (`icon_spacing_px`, `row_offset_x_px`,
## `separate_output_position`, `output_offset_px`) are gone. They
## described *where each icon goes*, which meant every new recipe was a
## fresh tuning problem; `surface_left_px`/`surface_right_px` describe
## *where the surface is* and let the layout derive the rest.
## `output_surface_height_px` survives as the one genuine per-building
## exception, for art whose finished-item surface sits at a different
## height from where its inputs rest.
##
## **Skips ShippingBin's inputs**, same exception BuildingInventoryLabel
## already makes — a bin's current_inputs() is its long, player-
## configurable accept list, not what's actually piled up; a dozen small
## icons for "would accept if present" would be noise, not information.
##
## **Every icon's offset cancels its own `ItemVisuals.scale_for()` back
## out (✅ fixed — reported as "Cream Pie does not go in the oven": the
## Oven's `whipped_cream` icon sat sunk well inside its window instead of
## on the counter alongside `pie_dough`).** `Sprite3D.offset` is in
## *that sprite's own* texture-pixel space, so it gets scaled by
## `icon.pixel_size` when Godot projects it into world space —
## `_set_icon_texture()` already multiplies `icon_pixel_size` by
## `ItemVisuals.scale_for(item)` per icon (so a native-art-heavy item like
## whipped_cream, `scale_for` 0.52, doesn't render oversized), but
## `_layout_row()`/`_populate_output()` used to apply the exact same
## `height_offset_px`/`icon_spacing_px` to every icon
## regardless of its own scale — a shrunk item's *anchor point*, not just
## its rendered size, ended up proportionally lower/closer than a
## scale-1.0 row-mate's. Same root cause, and same fix, as `CarriedItem`'s
## held-item offset and `IngredientSourceStack`'s pile layout (both
## already divide by the icon's own final `pixel_size`/scale before
## assigning `offset`) — see decisions.md.
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
## flipped frame to frame. _row_icon_at()/_layout() now assign
## each icon its own priority (row index, then the output above every row
## slot) so draw order is deterministic instead of an unstable tie.

@export var building: Building
@export var icon_pixel_size: float = 0.015
## How high above the ground this building's usable surface reads, in
## offset pixels — the per-building "where's the counter" knob.
##
## **Items rest their BOTTOM edge on this line, not their centre
## (✅ 2026-10-01).** Reported as "a lot of items look like they are in
## the table instead of on the table": item art varies in height as much
## as it does in width (`butter` is 11px tall, `whipped_cream` 50), so
## anchoring every icon by its centre sank a tall item half its height
## into the counter while a short one floated above it. Bottom-anchoring
## is the vertical twin of the measured-width packing below, and it is
## what makes one number per building mean the same thing for every item.
@export var surface_height_px: float = 50.0
## The span of that surface items may occupy, in the same offset pixels,
## measured from the building's own centre. Inputs are packed from
## `surface_left_px` rightwards; the output is pinned to
## `surface_right_px`. A building 2m wide spans roughly -66..+66 here.
##
## **This replaced `icon_spacing_px`/`row_offset_x_px`/
## `separate_output_position`/`output_offset_px` (✅ 2026-09-25).** Those
## described *where each icon goes*; these describe *where the surface
## is* and let the layout work the placement out from measured item
## widths. See the class doc.
@export var surface_left_px: float = -62.0
@export var surface_right_px: float = 62.0
## Clear space left between neighbouring icons, and between the last
## input and the output.
@export var icon_gap_px: float = 4.0
## Output surface height, when a building's finished-item surface sits
## higher or lower than where its inputs rest. Negative means "same as
## the inputs".
@export var output_surface_height_px: float = -1.0
## Floor on the automatic shrink a crowded row applies to fit (see
## _fit_scale()). Below this the row would read as tiny rather than
## tidy, so it stops shrinking and reports the overflow instead.
@export_range(0.3, 1.0, 0.05) var min_fit_scale: float = 0.5

var _row_icons: Array[Sprite3D] = []
var _output_icon: Sprite3D = null

const _GROUND_ANCHOR: Vector3 = Vector3(0, 0.05, 0)


func _ready() -> void:
	position = Vector3.ZERO
	building.input_inventory.changed.connect(_refresh)
	building.output_inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_layout(_current_input_items(), _current_output_items())


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


## Places every visible icon: inputs packed left-to-right from
## `surface_left_px`, the output pinned flush to `surface_right_px`.
##
## **Everything is computed from each item's own measured width**, never
## from a shared spacing constant — that is the whole point of this
## rewrite. Item art varies more than twice over (`cut_biscuit` renders
## 48 offset-px wide, `milk` 16), so the old fixed `icon_spacing_px` of
## 21 both overlapped the wide items and left gaping holes between the
## narrow ones.
func _layout(inputs: Array[StringName], outputs: Array[StringName]) -> void:
	var has_output: bool = not outputs.is_empty()
	var fit: float = _fit_scale(inputs, outputs)

	var cursor: float = surface_left_px
	for i: int in inputs.size():
		var icon: Sprite3D = _row_icon_at(i)
		_set_icon_texture(icon, inputs[i], fit)
		var w: float = _width_px(inputs[i], fit)
		_place(icon, cursor + w * 0.5, surface_height_px)
		cursor += w + icon_gap_px
	for i: int in range(inputs.size(), _row_icons.size()):
		_row_icons[i].hide()

	if not has_output:
		if _output_icon != null:
			_output_icon.hide()
		return
	if _output_icon == null:
		_output_icon = _make_icon()
		# Above every possible row slot's own priority (see _row_icon_at())
		# — see class doc's render_priority note.
		_output_icon.render_priority = _OUTPUT_RENDER_PRIORITY
	_set_icon_texture(_output_icon, outputs[0], fit)
	var out_w: float = _width_px(outputs[0], fit)
	var out_height: float = output_surface_height_px if output_surface_height_px >= 0.0 \
			else surface_height_px
	_place(_output_icon, surface_right_px - out_w * 0.5, out_height)


## How much every icon in this row has to shrink for the whole row to sit
## inside the surface without touching. 1.0 whenever it already fits,
## which is the common case.
##
## **This is what makes "items never overlap" a property of the code
## rather than of per-building tuning.** Measured worst case is the
## Oven's Meringue Pie at 130.2 offset-px of item across a 2m building
## that is only ~133 wide, so on the crowded recipes there is genuinely
## no arrangement at full size — something has to give, and a uniform
## shrink of the whole row keeps the items' relative sizes honest while
## guaranteeing the fit. Gaps are deliberately excluded from the scaling:
## shrinking the clear space along with the art would defeat the point.
func _fit_scale(inputs: Array[StringName], outputs: Array[StringName]) -> float:
	var natural: float = 0.0
	for item: StringName in inputs:
		natural += _width_px(item, 1.0)
	if not outputs.is_empty():
		natural += _width_px(outputs[0], 1.0)
	if natural <= 0.0:
		return 1.0
	# One gap between each pair of inputs, plus one before the output.
	var gaps: int = maxi(0, inputs.size() - 1) + (1 if not outputs.is_empty() and not inputs.is_empty() else 0)
	var available: float = (surface_right_px - surface_left_px) - icon_gap_px * gaps
	return clampf(available / natural, min_fit_scale, 1.0)


## An item's rendered width in offset pixels — its texture width times
## its own ItemVisuals correction. The single measurement the whole
## layout is built on.
func _width_px(item: StringName, fit: float) -> float:
	var texture: Texture2D = _texture_for(item)
	if texture == null:
		return 0.0
	return float(texture.get_width()) * ItemVisuals.scale_for(item) * fit


## Writes a position expressed in shared offset-pixel space onto an icon
## whose own `offset` is in *its own* texture pixels — see the class
## doc's offset-cancellation note.
##
## `surface_px` is where the item's **bottom edge** goes; the half-height
## term that turns that into a centre is added in the sprite's own pixel
## space, where it is simply half the texture, independent of any scale.
func _place(icon: Sprite3D, x_px: float, surface_px: float) -> void:
	var scale: float = _scale_for_icon(icon)
	var half_height: float = icon.texture.get_height() * 0.5
	icon.offset = Vector2(x_px / scale, surface_px / scale + half_height)


## The rectangles every visible icon currently occupies, in shared
## offset-pixel space. Exists so `StationItemShowcase` can assert that no
## two of them intersect across every building/recipe/state in the game,
## instead of the overlap check being someone squinting at a screenshot.
func icon_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for icon: Sprite3D in _row_icons:
		if icon.visible:
			rects.append(_rect_of(icon))
	if _output_icon != null and _output_icon.visible:
		rects.append(_rect_of(_output_icon))
	return rects


func _rect_of(icon: Sprite3D) -> Rect2:
	var scale: float = _scale_for_icon(icon)
	var centre: Vector2 = icon.offset * scale
	var size := Vector2(icon.texture.get_width(), icon.texture.get_height()) * scale
	return Rect2(centre - size * 0.5, size)


func _set_icon_texture(icon: Sprite3D, item: StringName, fit: float) -> void:
	var texture: Texture2D = _texture_for(item)
	if texture == null:
		icon.hide()
		return
	icon.texture = texture
	icon.pixel_size = icon_pixel_size * ItemVisuals.scale_for(item) * fit
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
## (largest is 4, the Mixer's Batter — see recipes.md).
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


## This icon's own ItemVisuals.scale_for() factor, recovered from the
## pixel_size _set_icon_texture() already applied — see class doc's
## offset-cancellation note.
func _scale_for_icon(icon: Sprite3D) -> float:
	return icon.pixel_size / icon_pixel_size
