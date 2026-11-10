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

## Seconds to fade up once hovered. Short: the reveal should feel like a
## response to the cursor, not an animation to sit through.
@export_range(0.0, 1.0, 0.01) var reveal_seconds: float = 0.12
## How long the text lingers after the cursor leaves, before it starts to
## go. Covers the common case of brushing past a building on the way to
## another one without the text snapping away.
@export_range(0.0, 3.0, 0.05) var hold_seconds: float = 0.6
## Seconds to fade back out. Deliberately much slower than the reveal —
## "appear when hovered over and then slow fade".
@export_range(0.0, 4.0, 0.05) var fade_seconds: float = 0.9
## Warning lines ("⚠ No recipe", "⚠ no location found", "⚠ waiting on
## pickup") stay visible without hovering.
##
## **On by default, and it is not a contradiction of the hover rule.**
## The clutter being solved here is the *routine* chatter — every station
## narrating its inputs at all times. Warnings are rare, mean something
## is actually wrong, and are the one case where needing to hover a
## building to discover the problem would hide it: a stalled station the
## player never happens to point at stays silently stalled. Set false for
## strict hover-only behaviour.
@export var always_show_warnings: bool = true

const _OK_COLOR := Color(0.35, 0.85, 0.35)
const _MISSING_COLOR := Color(0.95, 0.35, 0.3)
const _OUTPUT_COLOR := Color.WHITE

## The resting "how far above the building" height, in offset pixels —
## captured once from whatever this node's own .tscn-authored `offset.y`
## is, same role `_base_y` used to play for `position.y`.
var _base_offset_y: float = 0.0
var _extra_lines: Array[Label3D] = []
## Each visible line's colour at full opacity. The live `modulate` is
## this with the current alpha multiplied in, so a refresh mid-fade
## cannot snap the text back to solid.
var _line_colors: Array[Color] = []
var _alpha: float = 0.0
var _target_alpha: float = 0.0
## Counts down after the cursor leaves, before the fade starts.
var _hold_remaining: float = 0.0
## True while the current line set contains a ⚠ line.
var _has_warning: bool = false


func _ready() -> void:
	_base_offset_y = offset.y
	position = Vector3(0, 0.05, 0)
	building.input_inventory.changed.connect(_refresh)
	building.output_inventory.changed.connect(_refresh)
	building.hover_changed.connect(_on_hover_changed)
	# A station going stranded changes no inventory — it is a timer
	# elapsing on inventory that has stopped moving — so it needs its own
	# repaint trigger. See ProcessingBuilding.is_output_stranded().
	var processing: ProcessingBuilding = building as ProcessingBuilding
	if processing != null:
		processing.output_status_changed.connect(_refresh)
	_refresh()
	# Start hidden: nothing is hovered at load. A warning present from the
	# first frame still shows, via _forced_visible().
	_alpha = 1.0 if _forced_visible() else 0.0
	_target_alpha = _alpha
	_apply_alpha()
	set_process(false)


func _on_hover_changed(is_hovered: bool) -> void:
	if is_hovered:
		_hold_remaining = 0.0
		_target_alpha = 1.0
	else:
		_hold_remaining = hold_seconds
		_target_alpha = 1.0 if _forced_visible() else 0.0
	set_process(true)


## A warning overrides the hover rule — see always_show_warnings.
func _forced_visible() -> bool:
	return always_show_warnings and _has_warning


func _process(delta: float) -> void:
	if _hold_remaining > 0.0:
		_hold_remaining = maxf(0.0, _hold_remaining - delta)
		return
	if is_equal_approx(_alpha, _target_alpha):
		_alpha = _target_alpha
		_apply_alpha()
		set_process(false)
		return
	# Up fast, down slow; a zero duration means snap.
	var rising: bool = _target_alpha > _alpha
	var duration: float = reveal_seconds if rising else fade_seconds
	if duration <= 0.0:
		_alpha = _target_alpha
	else:
		_alpha = move_toward(_alpha, _target_alpha, delta / duration)
	_apply_alpha()


## Applies `_alpha` to every visible line, fading the outline with the
## fill. **Label3D keeps a separate `outline_modulate`** — fading only
## `modulate` would leave each glyph as a solid black outline around
## vanishing text, which reads as a rendering bug rather than a fade.
func _apply_alpha() -> void:
	for i: int in _line_colors.size():
		var line: Label3D = self if i == 0 else _extra_lines[i - 1]
		var c: Color = _line_colors[i]
		line.modulate = Color(c.r, c.g, c.b, c.a * _alpha)
		var o: Color = line.outline_modulate
		line.outline_modulate = Color(o.r, o.g, o.b, _alpha)


## Rebuilds the text. **Never writes `modulate` directly** — it records
## each line's full-opacity colour and hands off to _apply_alpha(), so an
## inventory change arriving mid-fade cannot snap the text back to solid.
func _refresh() -> void:
	var lines: Array[Dictionary] = _build_lines()
	_line_colors.clear()
	var was_warning: bool = _has_warning
	_has_warning = false
	for line_data: Dictionary in lines:
		if String(line_data["text"]).begins_with("⚠"):
			_has_warning = true
			break

	if lines.is_empty():
		text = ""
		offset.y = _base_offset_y
		for extra: Label3D in _extra_lines:
			extra.hide()
		_retarget(was_warning)
		return

	var line_height_px: float = font_size * 1.2
	var top_offset_px: float = line_height_px * (lines.size() - 1) * 0.5

	text = lines[0]["text"]
	_line_colors.append(lines[0]["color"])
	offset.y = _base_offset_y + top_offset_px

	for i: int in range(1, lines.size()):
		var line: Label3D = _line_at(i - 1)
		line.text = lines[i]["text"]
		line.offset.y = _base_offset_y + top_offset_px - line_height_px * i
		line.show()
		_line_colors.append(lines[i]["color"])
	for i: int in range(lines.size() - 1, _extra_lines.size()):
		_extra_lines[i].hide()

	_apply_alpha()
	_retarget(was_warning)


## A warning appearing (or clearing) changes whether this label should be
## visible without the cursor, so re-aim the fade — but only on the
## transition, so routine inventory churn doesn't keep waking _process().
func _retarget(was_warning: bool) -> void:
	if _has_warning == was_warning:
		return
	if building.hovered:
		return
	_target_alpha = 1.0 if _forced_visible() else 0.0
	_hold_remaining = 0.0
	set_process(true)


func _build_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if building is ProcessingBuilding and (building as ProcessingBuilding).recipe == null:
		# A freshly-placed station starts with no recipe at all (see
		# ProcessingBuilding's class doc) — current_inputs()/
		# current_outputs() are both empty in that state, so without this
		# the label would just be blank with no hint anything's wrong.
		# Reported as confusing: nothing seemed to indicate why a station
		# wasn't doing anything.
		# Deliberately terse. These labels are world-space text floating
		# over a 2m grid, so their width is what makes neighbours collide
		# — and "no recipe yet" is precisely the state several ADJACENT
		# stations are in at once, right after the player places a row of
		# them. Rendering a row of three showed the long form colliding
		# into unreadable mush ("No recipe selectedNo recipe selectedNo
		# recipe selected"); every other line this label emits is short
		# ("✓ milk", "cream x2"), so this one string was doing most of
		# the damage. See decisions.md.
		lines.append({"text": "⚠ No recipe", "color": _MISSING_COLOR})
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
	# A station whose finished batch isn't moving stops dead, and used to
	# do so with no visible reason at all — the output line above just sat
	# there at x1 while the player looked at an idle station wondering
	# what was wrong. The two texts are different diagnoses: "nothing
	# wants it" means no building takes the item and no bin sells it, so
	# it will never move; "waiting on pickup" means a delivery job exists
	# but no cat has got round to it, which points at delivery capacity
	# rather than at the recipe. Kept as terse as every other line here
	# for the same reason "⚠ No recipe" is (these are world-space labels
	# over a 2m grid; long strings collide into mush when neighbouring
	# stations show them at once).
	var processing: ProcessingBuilding = building as ProcessingBuilding
	if processing != null:
		if processing.is_output_stranded():
			lines.append({"text": "⚠ no location found", "color": _MISSING_COLOR})
		elif processing.is_output_stalled():
			lines.append({"text": "⚠ waiting on pickup", "color": _MISSING_COLOR})
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
