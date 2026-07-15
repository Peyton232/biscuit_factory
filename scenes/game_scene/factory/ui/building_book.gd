class_name BuildingBook
extends Control
## Building reference, shown from the pause menu: every known
## BuildingDefinition as a card (icon, name, cost) in a scrollable list.
## Buildings have no money-unlock step anymore (see progression.md) —
## a card for a building whose tier hasn't unlocked yet is hidden
## entirely (not shown disabled), refreshed whenever TierManager
## advances. TierManager is found via its "tier_manager" group rather
## than an @export, since this window is instantiated fresh each time
## via the pause menu's generic window loader, with no export wiring to
## gameplay-scene nodes — same pattern RecipeBook uses for RecipeShop.

const _CARD_SCENE: PackedScene = preload("res://scenes/game_scene/factory/ui/building_card.tscn")

@export var building_definitions: Array[BuildingDefinition] = []

@onready var _card_list: VBoxContainer = %CardList

var _tier_manager: TierManager = null
var _cards: Dictionary[BuildingDefinition, BuildingCard] = {}


func _ready() -> void:
	_tier_manager = get_tree().get_first_node_in_group("tier_manager") as TierManager
	if _tier_manager != null:
		_tier_manager.tier_advanced.connect(_on_tier_advanced)
	for definition: BuildingDefinition in building_definitions:
		var card: BuildingCard = _CARD_SCENE.instantiate()
		_card_list.add_child(card)
		card.set_definition(definition)
		_cards[definition] = card
		_refresh_visibility(definition)


func _refresh_visibility(definition: BuildingDefinition) -> void:
	_cards[definition].visible = _tier_manager == null or _tier_manager.is_building_unlocked(definition)


func _on_tier_advanced(_new_tier: int) -> void:
	for definition: BuildingDefinition in _cards:
		_refresh_visibility(definition)
