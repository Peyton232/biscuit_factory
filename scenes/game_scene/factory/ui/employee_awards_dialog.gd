class_name EmployeeAwardsDialog
extends PanelContainer
## Shown right after the Bakery Report, the final beat of
## VictorySequence's end-game flow (gameplay_overview.md's "Employee
## Awards"). Purely a view, same split as BakeryReportDialog:
## VictorySequence computes the actual winners (EmployeeAwards.compute())
## and calls show_awards(); this just builds/displays them and emits
## continue_pressed.
##
## **One small "slot" card per award, not a plain text list (✅
## 2026-07-15)** — each slot is its own smaller `PanelContainer` (reusing
## the same `recipe_card_normal` card art as the outer dialog, just at a
## smaller size) holding a bouncing `CatPortrait` of the actual winning
## cat above the same award-title/cat-name/value text that used to be the
## whole row. Built at runtime in `show_awards()`, same rebuild-on-show
## idiom BuildingInspectorPanel's recipe/checkbox lists already use, since
## the award count/content is genuinely dynamic (EmployeeAwards draws a
## random few from a pool each playthrough, 0-3 — same "however many slots
## actually have content" flexibility the old label-list had, just laid
## out in a row instead of a column now).

signal continue_pressed

## Matches every other dialog's cream-card text color (see
## cat_naming_dialog.tscn and friends) — applied in code here since these
## rows are built at runtime, not static scene nodes.
const _TEXT_COLOR := Color(0.18, 0.13, 0.09, 1)

## First-pass eyeballed size for the cat portrait within its slot — big
## enough to actually read as "a cat," small enough that three fit
## comfortably side by side in the dialog's own fixed width. Retune here
## if a real playtest screenshot shows it too cramped/too large.
const _PORTRAIT_SIZE := Vector2(84.0, 84.0)
## Deliberately wider than _PORTRAIT_SIZE.x — the award text (title +
## "name — value") wraps to several short, cramped lines if pinned to the
## same narrow width as the portrait itself, since the portrait is square
## but the text isn't.
const _LABEL_WIDTH: float = 140.0

@export var slot_card_style: StyleBox

@onready var _awards_row: HBoxContainer = %AwardsRow
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	hide()
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())


func show_awards(awards: Array[EmployeeAward]) -> void:
	for child: Node in _awards_row.get_children():
		child.queue_free()
	for award: EmployeeAward in awards:
		_awards_row.add_child(_build_slot(award))
	show()


## One award's "window": a smaller card holding the winning cat's
## bouncing portrait, then the same title/name/value text the old
## plain-label row showed.
func _build_slot(award: EmployeeAward) -> PanelContainer:
	var slot := PanelContainer.new()
	if slot_card_style != null:
		slot.add_theme_stylebox_override("panel", slot_card_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	slot.add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(layout)

	var portrait := CatPortrait.new()
	portrait.custom_minimum_size = _PORTRAIT_SIZE
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.set_cat(award.breed_index, award.fur_color_index)
	layout.add_child(portrait)

	var label := Label.new()
	label.text = "%s\n%s — %s" % [award.title, award.cat_name, award.value_text]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size = Vector2(_LABEL_WIDTH, 0.0)
	label.add_theme_color_override("font_color", _TEXT_COLOR)
	layout.add_child(label)

	return slot
