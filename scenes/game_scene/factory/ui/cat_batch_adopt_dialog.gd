class_name CatBatchAdoptDialog
extends PanelContainer
## Popup for adopting several cats of the same role at once — QOL
## request: post-Tier-3 the player often wants "5 more Delivery cats"
## rather than repeating the single-adopt-and-place flow N times. Purely
## a view: FactoryHud wires batch_confirmed to a loop of
## CatShop.buy_cat() calls (see FactoryHud._on_cat_batch_confirmed()),
## one per cat, each getting its own generated name from CatShop's
## shared name pool. Batch-adopted cats spawn at CatShop.spawn_position
## (+jitter) rather than through CatPlacer's click-to-place flow, since
## requiring N placement clicks in a row would defeat the point of
## buying several at once, quickly.
##
## The cost label previews the running total for the current quantity
## via CatShop.cost_for_quantity() — prices rise per cat, so this is
## never just quantity * current_cost() — and updates live as the
## quantity SpinBox changes.

signal batch_confirmed(quantity: int, role: Cat.Role)
signal cancelled

@onready var _quantity_spin: SpinBox = %QuantitySpin
@onready var _cost_label: Label = %CostLabel
@onready var _role_delivery_button: Button = %RoleDeliveryButton
@onready var _role_mixer_button: Button = %RoleMixerButton
@onready var _role_oven_button: Button = %RoleOvenButton
@onready var _role_cutter_button: Button = %RoleCutterButton
@onready var _role_assembler_button: Button = %RoleAssemblerButton
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton

## Set fresh each open() call, purely to compute the live cost preview —
## FactoryHud owns the actual spend/spawn loop on confirm, not this view.
var _cat_shop: CatShop = null


func _ready() -> void:
	hide()
	_quantity_spin.value_changed.connect(_on_quantity_changed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)


## See CatNamingDialog.open() for why the fade is cancelled here.
func open(cat_shop: CatShop) -> void:
	UiFade.cancel(self)
	_cat_shop = cat_shop
	_quantity_spin.value = 1
	_role_delivery_button.button_pressed = true
	_update_cost_label()
	show()


func _on_quantity_changed(_value: float) -> void:
	_update_cost_label()


func _update_cost_label() -> void:
	var quantity: int = int(_quantity_spin.value)
	_cost_label.text = "Total: $%d" % _cat_shop.cost_for_quantity(quantity)


func _on_confirm_pressed() -> void:
	UiFade.out(self)
	batch_confirmed.emit(int(_quantity_spin.value), _selected_role())


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
