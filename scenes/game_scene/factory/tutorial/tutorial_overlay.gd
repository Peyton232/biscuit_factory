class_name TutorialOverlay
extends CanvasLayer
## Pure view for TutorialManager: an instruction panel (step text, a
## step counter, a Skip button) plus a highlight rectangle that can
## be pointed at any Control elsewhere in the HUD. Never touches
## gameplay state itself — TutorialManager decides what text to show and
## what to highlight; this just renders it.
##
## **There is deliberately no Next button** — every step advances by the
## player actually doing the thing it asks for (see TutorialManager), so
## Skip is the panel's only button, and the only way out of a step
## without completing it.
##
## The highlight rect has mouse_filter = MOUSE_FILTER_IGNORE so it never
## blocks clicks on the real button it's drawn over — it's purely a
## visual pointer, positioned every call to set_highlight() (every frame,
## driven by TutorialManager) rather than once, since its target can move
## or appear/disappear (e.g. the Build flyout's own buttons only exist
## while the flyout is open).

signal skip_pressed

@onready var _text_label: Label = %TextLabel
@onready var _progress_label: Label = %ProgressLabel
@onready var _skip_button: Button = %SkipButton
@onready var _highlight: Panel = %Highlight

## Padding added around the highlighted control's own rect, so the
## border sits just outside it rather than flush against its edge.
const _HIGHLIGHT_PADDING: Vector2 = Vector2(6, 6)

## The button is the same node throughout, so its label has to be set on
## EVERY transition, not just the one that changes it (✅ fixed
## 2026-09-17). show_finished() used to set "Close" and nothing ever set
## it back, so the Tier 1 chapter — which starts after the base chapter
## has already finished — displayed its steps under a button reading
## "Close" that still skipped the whole tutorial. Reported as "tutorial
## in tier 1 has a close button but that ends up making you skip the
## tutorial".
const _LABEL_SKIP: String = "Skip Tutorial"
const _LABEL_CLOSE: String = "Close"


func _ready() -> void:
	_skip_button.pressed.connect(func() -> void: skip_pressed.emit())
	_highlight.hide()


## Any step page, including the last one. The button says Skip on all of
## them because on all of them that is what it does: a step is only ever
## passed by completing its objective, so dismissing one early ends the
## tutorial. Only the summary page below gets to say Close.
func show_step(text: String, step_num: int, total: int) -> void:
	show()
	_text_label.text = text
	_progress_label.text = "Step %d/%d" % [step_num, total]
	_skip_button.text = _LABEL_SKIP
	_skip_button.show()


## The summary page, shown either on completion or after a skip — here
## the button genuinely only dismisses a panel, so here it says Close.
## Without this page the panel would sit on screen forever, since
## nothing else hides it once the tutorial ends. `heading` replaces the
## progress counter: a skipped tutorial saying "Tutorial complete" over
## its reminder text reads as a bug.
func show_finished(text: String, heading: String = "Tutorial complete") -> void:
	show()
	_text_label.text = text
	_progress_label.text = heading
	_skip_button.text = _LABEL_CLOSE
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
