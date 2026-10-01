class_name CatInspectorPanel
extends PanelContainer
## Small panel shown while a cat is selected: rename it, change its role,
## or pick it up to move it. Purely a view — FactoryHud wires its
## signals to the actual selected Cat.

signal name_changed(new_name: String)
signal role_selected(role: Cat.Role)
signal pick_up_pressed
## Petting is repeatable, so unlike the role/name signals this one
## deliberately does NOT dismiss the panel — see FactoryHud.
signal pet_pressed

@onready var _name_edit: LineEdit = %NameEdit
@onready var _role_delivery_button: Button = %RoleDeliveryButton
@onready var _role_mixer_button: Button = %RoleMixerButton
@onready var _role_oven_button: Button = %RoleOvenButton
@onready var _role_cutter_button: Button = %RoleCutterButton
@onready var _role_assembler_button: Button = %RoleAssemblerButton
@onready var _pick_up_button: Button = %PickUpButton
@onready var _pet_button: Button = %PetButton

## Role -> its toggle button, built in _ready() once every @onready button
## above exists. Used by both show_for_cat() and the tutorial system
## (role_button(), below) instead of a repeated per-role if-chain.
var _role_buttons: Dictionary[Cat.Role, Button] = {}


func _ready() -> void:
	hide()
	_role_buttons = {
		Cat.Role.DELIVERY: _role_delivery_button,
		Cat.Role.MIXER: _role_mixer_button,
		Cat.Role.OVEN: _role_oven_button,
		Cat.Role.CUTTER: _role_cutter_button,
		Cat.Role.ASSEMBLER: _role_assembler_button,
	}
	_name_edit.text_submitted.connect(func(new_text: String) -> void: name_changed.emit(new_text))
	for role: Cat.Role in _role_buttons:
		_role_buttons[role].pressed.connect(role_selected.emit.bind(role))
	_pick_up_button.pressed.connect(func() -> void: pick_up_pressed.emit())
	_pet_button.pressed.connect(func() -> void: pet_pressed.emit())


## Populates the panel for the given cat and shows it. Called by
## FactoryHud whenever the selection changes or the cat's role changes.
func show_for_cat(cat: Cat) -> void:
	_name_edit.text = cat.cat_name
	for role: Cat.Role in _role_buttons:
		_role_buttons[role].button_pressed = cat.role == role
	show()


## The toggle button for the given role — used by the tutorial system to
## highlight "assign this cat to the Mixer" without reaching into private
## node internals.
func role_button(role: Cat.Role) -> Button:
	return _role_buttons.get(role)
