class_name RecipeBook
extends Control
## Recipe reference AND shop, shown from the pause menu: every known
## Recipe as a card (name, inputs -> output, processing time) in a
## scrollable list. Recipes are listed explicitly rather than scanned
## from disk, the same explicit-resource convention used elsewhere
## (BuildingPlacer's hotbar, CatShop's cat scene, etc.) so this stays a
## plain data list, not a runtime registry system.
##
## Doubles as the recipe shop: any recipe RecipeShop gates behind a
## price shows an "Unlock for $N" button on its card; an intermediate
## recipe with no price of its own (see RecipeShop.INTERNALLY_UNLOCKS)
## shows a disabled "Unlocks with <Recipe>" instead once its own tier is
## visible but it hasn't been bundled in yet. Only Whipped Cream (the
## sole default_unlocked recipe) shows its info with no lock affordance
## at all. This window is instanced fresh each time via
## the pause menu's generic window loader (see
## PauseMenu._load_and_show_menu()), which has no export wiring to
## gameplay-scene nodes, so RecipeShop/TierManager are found via their
## groups instead — see RecipeShop for why it registers there.
##
## **A recipe's card is hidden entirely until its own tier unlocks**
## (`TierManager.is_recipe_unlocked(recipe)`, found via the
## "tier_manager" group, same reasoning as RecipeShop above), on top of
## (not instead of) the existing price-lock affordance: a recipe can be
## `RecipeShop.default_unlocked` (free) and still not worth showing if
## its tier hasn't been reached yet — seeing "French Toast" in the book
## at Tier 1 with no way to ever make it would just be confusing.
## Advancing a tier reveals every recipe for it at once.
##
## **Every card's lock state and tier-visibility is also re-checked on
## every `visibility_changed` (not just once in `_ready()`, or on
## `tier_advanced`).** This window has two entry points with very
## different lifetimes: the pause menu's is instanced fresh each time
## (so `_ready()` alone is already correct there), but
## `FactoryHud.%RecipeBookWindow` is a single, permanently-embedded
## instance built once when `FactoryHud` first enters the tree and only
## ever `.show()`/`.hide()`n after that — which, for a **loaded** save,
## happens *before* `FactoryWorld.apply_save_data()` restores the real
## tier/recipe state (children `_ready()` before their parent). Loading
## straight into Tier 1 previously left this embedded copy permanently
## stuck showing Tier 0's card set, since nothing ever fired
## `tier_advanced` to make it re-check (a load calls
## `TierManager.load_state()`, a plain field assignment, not
## `advance_tier()`) — see decisions.md.

const _CARD_SCENE: PackedScene = preload("res://scenes/game_scene/factory/ui/recipe_card.tscn")
const _UNLOCK_SOUND: AudioStream = preload("res://assets/sounds/effects/recipe_unlock.wav")

## **Order matters** (✅ fixed — reported as "you see Rich Dough before
## the recipe that unlocks it"): within each tier, a final (shop_prices)
## recipe's card must come before any intermediate RecipeShop.INTERNALLY_
## UNLOCKS only grants for free once that final is bought — otherwise its
## "locked — buy X" hint points at a card the player hasn't scrolled to
## yet. See recipe_book.tscn's own `recipes` array for the corrected
## order; keep this invariant when adding a new recipe.
@export var recipes: Array[Recipe] = []

@onready var _card_list: VBoxContainer = %CardList

var _recipe_shop: RecipeShop = null
var _tier_manager: TierManager = null
var _cards: Dictionary[Recipe, RecipeCard] = {}


func _ready() -> void:
	_recipe_shop = get_tree().get_first_node_in_group("recipe_shop") as RecipeShop
	if _recipe_shop != null:
		_recipe_shop.recipe_unlocked.connect(_on_recipe_unlocked)
	_tier_manager = get_tree().get_first_node_in_group("tier_manager") as TierManager
	if _tier_manager != null:
		_tier_manager.tier_advanced.connect(_on_tier_advanced)
	for recipe: Recipe in recipes:
		var card: RecipeCard = _CARD_SCENE.instantiate()
		_card_list.add_child(card)
		card.set_recipe(recipe)
		card.unlock_pressed.connect(_on_unlock_pressed)
		_cards[recipe] = card
		_refresh_lock_state(recipe)
		_refresh_visibility(recipe)
	visibility_changed.connect(_refresh_all)


## Re-checks every card's lock state and tier-visibility against
## whatever RecipeShop/TierManager report right now. Cheap (a couple
## dozen dictionary lookups at most) and only runs while actually
## visible, so wiring it to visibility_changed costs nothing while the
## window sits hidden — see the class doc above for why _ready() alone
## isn't enough for the permanently-embedded HUD copy.
func _refresh_all() -> void:
	if not visible:
		return
	for recipe: Recipe in _cards:
		_refresh_lock_state(recipe)
		_refresh_visibility(recipe)


func _refresh_lock_state(recipe: Recipe) -> void:
	if _recipe_shop == null:
		return
	var unlocked: bool = _recipe_shop.is_unlocked(recipe)
	if _recipe_shop.shop_prices.has(recipe):
		_cards[recipe].set_lock_state(_recipe_shop.price_for(recipe), unlocked)
		return
	var parent: Recipe = _recipe_shop.bundled_parent(recipe)
	if parent == null:
		return
	_cards[recipe].set_lock_state(0, unlocked, false, parent.display_name)


## Hides the card entirely until the recipe's own tier unlocks (or
## always shows it if there's no TierManager — graceful fallback rather
## than hiding everything if it's missing).
func _refresh_visibility(recipe: Recipe) -> void:
	_cards[recipe].visible = _tier_manager == null or _tier_manager.is_recipe_unlocked(recipe)


func _on_unlock_pressed(recipe: Recipe) -> void:
	if _recipe_shop != null and _recipe_shop.try_unlock(recipe):
		Sfx.spawn(self, _UNLOCK_SOUND)
		_refresh_lock_state(recipe)


func _on_recipe_unlocked(recipe: Recipe) -> void:
	if _cards.has(recipe):
		_refresh_lock_state(recipe)


func _on_tier_advanced(_new_tier: int) -> void:
	for recipe: Recipe in _cards:
		_refresh_visibility(recipe)
