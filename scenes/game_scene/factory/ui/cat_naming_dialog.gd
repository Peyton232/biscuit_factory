class_name CatNamingDialog
extends PanelContainer
## Popup shown before a new cat is adopted: the player must name the cat
## and pick its starting role before it spawns. Purely a view —
## FactoryHud wires name_confirmed to CatShop.adopt_cat_at() (via
## CatPlacer, see decisions.md) and only spends money/spawns on confirm;
## cancelling (or leaving the name blank) never charges the player.
##
## **The name field opens pre-filled with a random suggestion**
## (`CatShop.next_suggested_name()`, passed in by FactoryHud — this view
## doesn't own the name bank itself, since CatBatchAdoptDialog also needs
## suggestions and the bank/pool is shared shop-wide state, not a concern
## of either dialog), not blank — the player can accept it as-is or just
## start typing to replace it (open() selects the whole suggestion so
## the first keystroke overwrites it rather than inserting into the
## middle). See CatShop.NAME_BANK for why color/pattern names are
## excluded from the bank entirely.

signal name_confirmed(cat_name: String, role: Cat.Role)
signal cancelled

@onready var _cost_label: Label = %CostLabel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _role_delivery_button: Button = %RoleDeliveryButton
@onready var _role_mixer_button: Button = %RoleMixerButton
@onready var _role_oven_button: Button = %RoleOvenButton
@onready var _role_cutter_button: Button = %RoleCutterButton
@onready var _role_assembler_button: Button = %RoleAssemblerButton
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton


func _ready() -> void:
	hide()
	_name_edit.text_changed.connect(_on_text_changed)
	_name_edit.text_submitted.connect(_on_text_submitted)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


## Opens the dialog for a fresh adoption at the given cost, pre-filled
## with the given suggested name (see class doc above) rather than blank.
## UiFade.cancel() first: this dialog now fades itself out on confirm or
## cancel, and reopening during that fade would otherwise inherit the
## in-flight tween and vanish again a moment later.
func open(cost: int, suggested_name: String) -> void:
	UiFade.cancel(self)
	_cost_label.text = "Adopt Cat — $%d" % cost
	_name_edit.text = suggested_name
	_role_delivery_button.button_pressed = true
	_confirm_button.disabled = false
	show()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_text_changed(new_text: String) -> void:
	_confirm_button.disabled = new_text.strip_edges().is_empty()


func _on_text_submitted(new_text: String) -> void:
	if not new_text.strip_edges().is_empty():
		_confirm(new_text)


func _on_confirm_pressed() -> void:
	_confirm(_name_edit.text)


func _confirm(raw_name: String) -> void:
	UiFade.out(self)
	name_confirmed.emit(raw_name.strip_edges(), _selected_role())


func _selected_role() -> Cat.Role:
	if _role_mixer_button.button_pressed:
		return Cat.Role.MIXER
	if _role_oven_button.button_pressed:
		return Cat.Role.OVEN
	if _role_cutter_button.button_pressed:
		return Cat.Role.CUTTER
	if _role_assembler_button.button_pressed:
		return Cat.Role.ASSEMBLER
	return Cat.Role.DELIVERY


func _on_cancel_pressed() -> void:
	UiFade.out(self)
	cancelled.emit()
