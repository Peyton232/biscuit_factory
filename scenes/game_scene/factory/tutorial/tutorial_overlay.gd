class_name TutorialOverlay
extends CanvasLayer
## Pure view for TutorialManager: an instruction panel (step text, a
## step counter, Next/Skip buttons) plus a highlight rectangle that can
## be pointed at any Control elsewhere in the HUD. Never touches
## gameplay state itself — TutorialManager decides what text to show and
## what to highlight; this just renders it.
##
## The highlight rect has mouse_filter = MOUSE_FILTER_IGNORE so it never
## blocks clicks on the real button it's drawn over — it's purely a
## visual pointer, positioned every call to set_highlight() (every frame,
## driven by TutorialManager) rather than once, since its target can move
## or appear/disappear (e.g. the Build flyout's own buttons only exist
## while the flyout is open).

signal next_pressed
signal skip_pressed

@onready var _text_label: Label = %TextLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _next_button: Button = %NextButton
@onready var _skip_button: Button = %SkipButton
@onready var _highlight: Panel = %Highlight

## Padding added around the highlighted control's own rect, so the
## border sits just outside it rather than flush against its edge.
const _HIGHLIGHT_PADDING: Vector2 = Vector2(6, 6)


func _ready() -> void:
	_next_button.pressed.connect(func() -> void: next_pressed.emit())
	_skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	_highlight.hide()


func show_step(text: String, step_num: int, total: int) -> void:
	show()
	_text_label.text = text
	_progress_label.text = "Step %d/%d" % [step_num, total]
	_next_button.show()
	_skip_button.show()


## Shows the closing message: hides Next (nothing left to advance
## through) and repurposes the Skip button into a Close button — without
## this the panel would sit on screen forever, since nothing else ever
## hides it once the tutorial finishes.
func show_finished(text: String) -> void:
	show()
	_text_label.text = text
	_progress_label.text = "Tutorial complete"
	_next_button.hide()
	_skip_button.text = "Close"
	_skip_button.show()
	set_highlight(null)


## Points the highlight rect at the given Control's current screen rect,
## or hides it if target is null (nothing to point at right now — e.g.
## the step's real target is inside a panel that isn't open yet).
func set_highlight(target: Control) -> void:
	if target == null or not target.is_visible_in_tree():
		_highlight.hide()
		return
	_highlight.show()
	_highlight.global_position = target.global_position - _HIGHLIGHT_PADDING
	_highlight.size = target.size + _HIGHLIGHT_PADDING * 2
