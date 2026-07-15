class_name BuildingInventoryLabel
extends Label3D
## Floating readout beside a building summarizing its inventories: inputs
## as a checklist (green "✓ item" once at least one is on hand, red
## "x item" while still waiting on it) and outputs as "item x3" (hidden
## at zero, white). Refreshes from inventory change signals.
##
## **Implemented as a small pool of sibling Label3D lines**, not one
## multi-line Label3D — Label3D has no rich-text/per-substring color
## support (that's a Control-only RichTextLabel feature), so a single
## node's `modulate` can only recolor its ENTIRE text block, not "this
## line red, that line green" within one block. This node is line 0;
## `_line_at(i)` lazily creates/reuses sibling Label3D nodes for every
## line after the first, cloning this node's own visual settings
## (font_size, outline, pixel_size, billboard, alignment) so every line
## matches. The whole stack is kept vertically centered around this
## node's original (design-time) offset as the line count changes, same
## as a single Label3D's own multi-line text naturally would be.
##
## **Anchored the same way every billboarded building/cat element is:
## ground-level `position` (`Vector3(0, 0.05, 0)`, matching `Visual`)
## plus a pixel `offset`, never a literal world-space Y** (✅ fixed
## 2026-07-13 — this label used to set `position.y` directly to float
## above the building, which put it in the same "drifts relative to the
## building's own billboarded Visual as the camera pans" bug already
## documented and fixed for Cat's CarriedItem/NameLabel: a literal
## world-space delta doesn't project the same way a billboard's own
## `offset` does from every camera angle, so two billboarded elements
## anchored by different mechanisms visibly shear apart as the camera
## moves, even though both are rigidly parented to the same still
## building. Line-stacking math moved from world-meters (`font_size *
## pixel_size`) to raw pixels (`font_size` alone — the `pixel_size`
## factor cancels out once stacking happens in offset-pixel-space
## instead of world-space).
##
## **ShippingBin skips the input checklist entirely** — its
## current_inputs() is the player-configurable *accepted items* list
## (see ShippingBin), which can be a dozen entries long; showing a
## checklist line for every one of them floating over the bin was messy
## clutter, not useful information (a bin only cares whether it's about
## to ship something, not which of a long accept-list it's missing).

@export var building: Building

const _OK_COLOR := Color(0.35, 0.85, 0.35)
const _MISSING_COLOR := Color(0.95, 0.35, 0.3)
const _OUTPUT_COLOR := Color.WHITE

## The resting "how far above the building" height, in offset pixels —
## captured once from whatever this node's own .tscn-authored `offset.y`
## is, same role `_base_y` used to play for `position.y`.
var _base_offset_y: float = 0.0
var _extra_lines: Array[Label3D] = []


func _ready() -> void:
	_base_offset_y = offset.y
	position = Vector3(0, 0.05, 0)
	building.input_inventory.changed.connect(_refresh)
	building.output_inventory.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var lines: Array[Dictionary] = _build_lines()
	if lines.is_empty():
		text = ""
		offset.y = _base_offset_y
		for extra: Label3D in _extra_lines:
			extra.hide()
		return

	var line_height_px: float = font_size * 1.2
	var top_offset_px: float = line_height_px * (lines.size() - 1) * 0.5

	text = lines[0]["text"]
	modulate = lines[0]["color"]
	offset.y = _base_offset_y + top_offset_px

	for i: int in range(1, lines.size()):
		var line: Label3D = _line_at(i - 1)
		line.text = lines[i]["text"]
		line.modulate = lines[i]["color"]
		line.offset.y = _base_offset_y + top_offset_px - line_height_px * i
		line.show()
	for i: int in range(lines.size() - 1, _extra_lines.size()):
		_extra_lines[i].hide()


func _build_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if building is ProcessingBuilding and (building as ProcessingBuilding).recipe == null:
		# A freshly-placed station starts with no recipe at all (see
		# ProcessingBuilding's class doc) — current_inputs()/
		# current_outputs() are both empty in that state, so without this
		# the label would just be blank with no hint anything's wrong.
		# Reported as confusing: nothing seemed to indicate why a station
		# wasn't doing anything.
		lines.append({"text": "⚠ No recipe selected", "color": _MISSING_COLOR})
		return lines
	if not (building is ShippingBin):
		for item: StringName in building.current_inputs():
			var amount: int = building.input_inventory.count(item)
			if amount == 0:
				lines.append({"text": "x %s" % item, "color": _MISSING_COLOR})
			else:
				lines.append({"text": "✓ %s" % item, "color": _OK_COLOR})
	for item: StringName in building.current_outputs():
		var amount: int = building.output_inventory.count(item)
		if amount > 0:
			lines.append({"text": "%s x%d" % [item, amount], "color": _OUTPUT_COLOR})
	return lines


## Lazily creates (and caches) the i-th extra line as a sibling Label3D,
## cloning this node's own visual settings so every line matches.
func _line_at(i: int) -> Label3D:
	if i < _extra_lines.size():
		return _extra_lines[i]
	var line := Label3D.new()
	line.font_size = font_size
	line.outline_size = outline_size
	line.pixel_size = pixel_size
	line.billboard = billboard
	line.horizontal_alignment = horizontal_alignment
	line.vertical_alignment = vertical_alignment
	line.position = position
	get_parent().add_child(line)
	_extra_lines.append(line)
	return line
