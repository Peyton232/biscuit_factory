class_name GameCompleteDialog
extends PanelContainer
## Popup shown once, the moment the player reaches Tier Winner. Two beats
## reuse the same panel rather than two separate scenes, since both are
## just a centered message box with different text/button state:
## 1. "You've done it!" — waits for the player to click Continue before
##    FactoryWorld saves the game (see continue_pressed).
## 2. "Congratulations!" — shown with no button while FactoryWorld rolls
##    the credits scene in behind it.
##
## Purely a view, same split as CatNamingDialog/CatBatchAdoptDialog —
## FactoryWorld (which already owns capture_save_data()/scene loading)
## drives the actual save + credits-roll sequence around it.

signal continue_pressed

@onready var _message_label: Label = %MessageLabel
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	hide()
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())


## First beat: waits for the player to click Continue.
func show_message(text: String) -> void:
	_message_label.text = text
	_continue_button.show()
	show()


## Second beat: no button — FactoryWorld advances past this one on its
## own timer, there's nothing for the player to click.
func show_message_no_button(text: String) -> void:
	_message_label.text = text
	_continue_button.hide()
	show()
