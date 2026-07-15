class_name StatsPage
extends Control
## Read-only lifetime totals, shown from the pause menu. Populated once
## from LifetimeStats in _ready() rather than live-updating — same as
## RecipeBook/BuildingBook, which populate their card lists once per
## fresh instantiation; the pause menu pauses the scene tree while shown,
## so nothing tracked here can actually change while this window is open
## anyway. LifetimeStats is found via the "lifetime_stats" group rather
## than an @export, since this window is instantiated fresh each time via
## the pause menu's generic window loader, with no export path to
## gameplay-scene nodes — same pattern RecipeBook/BuildingBook use for
## RecipeShop/BuildingShop.

@onready var _money_label: Label = %MoneyLabel
@onready var _cats_label: Label = %CatsLabel
@onready var _playtime_label: Label = %PlaytimeLabel
@onready var _empty_label: Label = %EmptyLabel
@onready var _items_list: VBoxContainer = %ItemsList

## Same dark-brown FactoryHud/RecipeCard/BuildingCard already use for
## legibility against this page's new light-cream card background (✅
## 2026-07-14) — needed explicitly here since per-item Labels are built
## at runtime, same reasoning as RecipeCard's own _CARD_TEXT_COLOR.
const _CARD_TEXT_COLOR: Color = Color(0.18, 0.13, 0.09, 1)


func _ready() -> void:
	var stats: LifetimeStats = get_tree().get_first_node_in_group("lifetime_stats") as LifetimeStats
	if stats == null:
		return
	# Same "recipe_shop" group lookup RecipeBook already uses to find its
	# own gameplay-scene reference — this window is instantiated fresh
	# each time via the pause menu's generic window loader too, with no
	# export path to gameplay nodes. Used for display_name_for_item()
	# below so a display-only item rename (e.g. "danish" -> "Egg Danish")
	# shows correctly here instead of the stale capitalized id.
	var recipe_shop: RecipeShop = get_tree().get_first_node_in_group("recipe_shop") as RecipeShop
	_money_label.text = "Lifetime Money Earned: $%d" % stats.money_earned_total
	_cats_label.text = "Lifetime Cats Adopted: %d" % stats.cats_adopted_count
	_playtime_label.text = "Total Playtime: %s" % LifetimeStats.format_playtime(stats.playtime_seconds)
	_empty_label.visible = stats.items_shipped.is_empty()
	var items: Array[StringName] = stats.items_shipped.keys()
	items.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for item: StringName in items:
		var label := Label.new()
		var item_name: String = recipe_shop.display_name_for_item(item) if recipe_shop != null else String(item).capitalize()
		label.text = "%s: %d" % [item_name, stats.items_shipped[item]]
		label.add_theme_color_override("font_color", _CARD_TEXT_COLOR)
		_items_list.add_child(label)
