class_name Economy
extends Node
## Tracks the player's money. Scene-local (lives in factory_world), so a
## new game always starts fresh. No income sources yet — only spending.

signal money_changed(money: int)

## $20 Milk Source + $40 Mixer + $15 Shipping Bin — exactly the tutorial's
## building set (see progression.md).
@export var starting_money: int = 75

var money: int = 0


func _ready() -> void:
	money = starting_money
	money_changed.emit(money)


func earn(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func can_afford(cost: int) -> bool:
	return cost <= money


## Deducts `cost` and returns true, or returns false if unaffordable.
func try_spend(cost: int) -> bool:
	if not can_afford(cost):
		return false
	money -= cost
	money_changed.emit(money)
	return true


## Overwrites money directly rather than earning/spending a delta — used
## only when restoring a saved game, where the new total isn't relative
## to the current one. Still emits money_changed so the HUD refreshes.
func set_money(amount: int) -> void:
	money = amount
	money_changed.emit(money)
