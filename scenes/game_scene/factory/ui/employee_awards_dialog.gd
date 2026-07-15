class_name EmployeeAwardsDialog
extends PanelContainer
## Shown right after the Bakery Report, the final beat of
## VictorySequence's end-game flow (gameplay_overview.md's "Employee
## Awards"). Purely a view, same split as BakeryReportDialog:
## VictorySequence computes the actual winners (EmployeeAwards.compute())
## and calls show_awards(); this just formats and displays them and
## emits continue_pressed.
##
## **One Label per award, rebuilt every call** — same rebuild-on-show
## idiom BuildingInspectorPanel's recipe/checkbox lists already use,
## since the award count/content is genuinely dynamic (EmployeeAwards
## draws a random few from a pool each playthrough), unlike
## BakeryReportDialog's fixed, always-present stat set.

signal continue_pressed

@onready var _awards_list: VBoxContainer = %AwardsList
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	hide()
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())


func show_awards(awards: Array[EmployeeAward]) -> void:
	for child: Node in _awards_list.get_children():
		child.queue_free()
	for award: EmployeeAward in awards:
		var label := Label.new()
		label.text = "%s\n%s — %s" % [award.title, award.cat_name, award.value_text]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_awards_list.add_child(label)
	show()
