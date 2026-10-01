class_name RecipeShop
extends Node
## Tracks which Recipes the player has unlocked, and lets them buy access
## to more via Economy. default_unlocked (just Whipped Cream) is free
## from the start; every recipe in shop_prices ("final"/sellable
## recipes) starts locked until purchased — a locked recipe still shows
## up in a ProcessingBuilding's available_recipes (it's part of that
## station's menu) but BuildingInspectorPanel won't let it be selected,
## and the Recipe Book sells it.
##
## **Every intermediate recipe (Basic Dough, Rich Dough, ... Meringue —
## see INTERNALLY_UNLOCKS below) has no price of its own and can't be
## bought directly** — it unlocks only as a side effect of buying the
## specific final recipe(s) that need it, per progression.md's
## Internally-Unlocks table (the GDD's literal bundling mechanic).
## This is the full mechanic — an earlier session shipped a simplified
## stand-in instead (every intermediate free the moment its own tier
## unlocked, regardless of purchases) as a deliberate, documented
## trade-off; playtest feedback asked for the literal table, see
## decisions.md for the switch-over.
##
## Registers itself in the "recipe_shop" group so RecipeBook (instanced
## fresh each time via the pause menu's generic window loader, with no
## export wiring to gameplay nodes) can still find it.

signal recipe_unlocked(recipe: Recipe)

## Final recipe -> every recipe (including itself) unlocked for free the
## moment that final recipe is purchased — progression.md's
## Internally-Unlocks table, flattened per row (each row already lists
## everything that becomes unlocked, so no recursive resolution is
## needed here). Hardcoded via preload rather than an @export edited
## through the inspector: this is a fixed content table, not something a
## designer tunes per save/level, and a hand-typed nested
## Dictionary[Recipe, Array[Recipe]] literal in .tscn text format is a
## real, easy-to-typo risk this project has been bitten by before with
## other resource-literal edge cases (see decisions.md's project.godot/
## font entries) — a plain GDScript dictionary of preloaded resources is
## far more reviewable and no less "data".
## Value type is a plain `Array`, not `Array[Recipe]` — GDScript (4.7)
## doesn't support nested typed collections ("Dictionary[Recipe,
## Array[Recipe]]" fails to parse); every element is still a Recipe at
## runtime, so `for x: Recipe in ...` loops below type-check fine anyway.
const INTERNALLY_UNLOCKS: Dictionary[Recipe, Array] = {
	preload("res://resources/recipes/bread.tres"): [
		preload("res://resources/recipes/basic_dough.tres"),
		preload("res://resources/recipes/bread.tres"),
	],
	preload("res://resources/recipes/cream_bun.tres"): [
		preload("res://resources/recipes/cream_bun.tres"),
	],
	preload("res://resources/recipes/bread_roll.tres"): [
		preload("res://resources/recipes/rich_dough.tres"),
		preload("res://resources/recipes/bread_roll.tres"),
	],
	# **Bundles Rich Dough + Bread Rolls too, not just itself (✅ fixed —
	# reported as "Bread Rolls should unlock when you buy Butter Rolls")**
	# — progression.md's table assumed Rich Dough/Bread Rolls would
	# already be unlocked by the time a player buys Butter Rolls, since
	# both are Tier 2 recipes reachable in either order; nothing enforces
	# that purchase order, so a player buying Butter Rolls first got a
	# recipe it could never actually produce (its Oven-made Bread Rolls
	# input was still locked). Duplicates bread_roll.tres's own bundle
	# here rather than relying on purchase order — _unlock_bundle() skips
	# anything already unlocked, so this is a no-op if Bread Rolls was
	# bought first, and the actual fix if it wasn't.
	preload("res://resources/recipes/butter_roll.tres"): [
		preload("res://resources/recipes/rich_dough.tres"),
		preload("res://resources/recipes/bread_roll.tres"),
		preload("res://resources/recipes/butter_roll.tres"),
	],
	# Same latent bug as Butter Rolls above (Croissants also needs Rich
	# Dough, another same-tier recipe with no enforced purchase order) —
	# bundled directly rather than assuming Bread Rolls was bought first.
	preload("res://resources/recipes/croissant.tres"): [
		preload("res://resources/recipes/rich_dough.tres"),
		preload("res://resources/recipes/croissant.tres"),
	],
	preload("res://resources/recipes/cream_pie.tres"): [
		preload("res://resources/recipes/pie_dough.tres"),
		preload("res://resources/recipes/cream_pie.tres"),
	],
	preload("res://resources/recipes/biscuit.tres"): [
		preload("res://resources/recipes/cut_biscuit.tres"),
		preload("res://resources/recipes/biscuit.tres"),
	],
	preload("res://resources/recipes/buttered_toast.tres"): [
		preload("res://resources/recipes/sliced_bread.tres"),
		preload("res://resources/recipes/toast.tres"),
		preload("res://resources/recipes/buttered_toast.tres"),
	],
	preload("res://resources/recipes/frosted_sweet_roll.tres"): [
		preload("res://resources/recipes/frosting.tres"),
		preload("res://resources/recipes/sweet_dough.tres"),
		preload("res://resources/recipes/sweet_roll.tres"),
		preload("res://resources/recipes/frosted_sweet_roll.tres"),
	],
	preload("res://resources/recipes/frosted_sugar_cookie.tres"): [
		preload("res://resources/recipes/cookie_cutout.tres"),
		preload("res://resources/recipes/sugar_cookie.tres"),
		preload("res://resources/recipes/frosted_sugar_cookie.tres"),
		preload("res://resources/recipes/frosting.tres"),
	],
	preload("res://resources/recipes/frosted_cake.tres"): [
		preload("res://resources/recipes/batter.tres"),
		preload("res://resources/recipes/cake_layer.tres"),
		preload("res://resources/recipes/frosted_cake.tres"),
	],
	preload("res://resources/recipes/meringue_pie.tres"): [
		preload("res://resources/recipes/meringue.tres"),
		preload("res://resources/recipes/meringue_pie.tres"),
	],
	preload("res://resources/recipes/danish.tres"): [
		preload("res://resources/recipes/danish.tres"),
	],
	preload("res://resources/recipes/french_toast.tres"): [
		preload("res://resources/recipes/french_toast.tres"),
	],
}

@export var economy: Economy
@export var default_unlocked: Array[Recipe] = []
## Recipe -> unlock price. Any recipe listed here starts locked and is
## directly purchasable; a recipe in INTERNALLY_UNLOCKS but not here has
## no price of its own (see class doc).
@export var shop_prices: Dictionary[Recipe, int] = {}

var _unlocked: Dictionary[Recipe, bool] = {}


func _ready() -> void:
	add_to_group("recipe_shop")
	for recipe: Recipe in default_unlocked:
		_unlocked[recipe] = true


func is_unlocked(recipe: Recipe) -> bool:
	return _unlocked.get(recipe, false)


## Display name for an item id showing up somewhere generic — currently
## just FactoryHud's tier-goal readout. An item's raw StringName id
## doesn't always match its readable name once a display-only rename
## happens (e.g. "danish" -> "Egg Danish", see roadmap.md/decisions.md) —
## a plain `String(item).capitalize()` would show the stale pre-rename
## name forever. Looks up whichever Recipe produces this item by
## scanning INTERNALLY_UNLOCKS's flattened values (covers every recipe
## in the game, final or intermediate) plus default_unlocked, and
## returns its display_name. Falls back to a plain capitalized id for
## items with no Recipe at all (raw ingredients: flour/sugar/milk/egg/
## butter), where the id already reads correctly as-is.
func display_name_for_item(item: StringName) -> String:
	for recipes: Array in INTERNALLY_UNLOCKS.values():
		for recipe: Recipe in recipes:
			if recipe.output == item:
				return recipe.display_name
	for recipe: Recipe in default_unlocked:
		if recipe.output == item:
			return recipe.display_name
	return String(item).capitalize()


## Total recipes unlocked so far (default_unlocked + every purchase/
## bundle-unlock since) — Bakery Report's "Total Recipes Unlocked".
## _unlocked only ever gains entries (see _unlock_bundle()), never loses
## them, so its size is exactly this count.
func unlocked_count() -> int:
	return _unlocked.size()


## Whether every recipe in the game is unlocked, for the "Full Cookbook"
## achievement. Derived from the shop's own tables rather than a
## hardcoded total: every recipe is either directly purchasable
## (shop_prices), bundled with one that is (INTERNALLY_UNLOCKS), or free
## from the start (default_unlocked) — so buying every shop_prices entry
## necessarily unlocks all of them, and "no shop recipe left locked" is
## the same question, asked cheaply.
func every_recipe_unlocked() -> bool:
	return purchasable_unlocked_count() == shop_prices.size()


## How many purchasable recipes are unlocked, for the "Full Cookbook"
## achievement's progress readout ("12 / 16"). Counts shop_prices
## entries specifically, not unlocked_count() — that one also counts
## default-unlocked and bundled intermediates, so it would never reach
## shop_prices.size() and the progress would read as stuck.
func purchasable_unlocked_count() -> int:
	var count: int = 0
	for recipe: Recipe in shop_prices:
		if is_unlocked(recipe):
			count += 1
	return count


func price_for(recipe: Recipe) -> int:
	return shop_prices.get(recipe, 0)


## The final recipe whose purchase unlocks `recipe` for free, for a
## recipe that has no price of its own (an intermediate) — used by the
## UI to explain a locked intermediate's card/button ("unlocks with
## Bread") instead of a misleading "$0" price. Returns null for a
## directly-purchasable (shop_prices) or default_unlocked recipe.
func bundled_parent(recipe: Recipe) -> Recipe:
	if shop_prices.has(recipe):
		return null
	for final_recipe: Recipe in INTERNALLY_UNLOCKS:
		if recipe in INTERNALLY_UNLOCKS[final_recipe]:
			return final_recipe
	return null


## Spends money and unlocks the given final recipe, plus every recipe
## INTERNALLY_UNLOCKS bundles with it, if affordable and not already
## unlocked; returns false otherwise. Only recipes with their own
## shop_prices entry can be bought this way — an intermediate recipe
## reaching here (it shouldn't, since the UI never offers it a buyable
## button) is refused rather than silently unlocked for its $0 default
## price, which would bypass the bundling entirely.
func try_unlock(recipe: Recipe) -> bool:
	if is_unlocked(recipe):
		return true
	if not shop_prices.has(recipe):
		return false
	if not economy.try_spend(price_for(recipe)):
		return false
	_unlock_bundle(recipe)
	return true


## Marks `final_recipe` and every recipe INTERNALLY_UNLOCKS bundles with
## it as unlocked (skipping any already unlocked), emitting
## recipe_unlocked for each newly-unlocked one. Shared by try_unlock()
## (a fresh purchase) and load_state() (restoring a save) — a save only
## persists the final recipe itself (see save_state() below), so
## restoring it must re-expand the same bundle try_unlock() would have,
## or a loaded game would silently lose access to already-paid-for
## intermediates like Basic Dough.
func _unlock_bundle(final_recipe: Recipe) -> void:
	for bundled: Recipe in INTERNALLY_UNLOCKS.get(final_recipe, [final_recipe]):
		if _unlocked.get(bundled, false):
			continue
		_unlocked[bundled] = true
		recipe_unlocked.emit(bundled)


## Saves every purchased (shop_prices) recipe currently unlocked, as
## resource_path strings — default_unlocked recipes aren't included,
## since they're always free regardless of save state and get re-seeded
## by _ready() on the next load anyway. Bundled intermediates aren't
## saved individually either — load_state() re-derives them from the
## final recipe via _unlock_bundle().
func save_state(out: FactorySaveData) -> void:
	for recipe: Recipe in shop_prices:
		if is_unlocked(recipe):
			out.unlocked_recipe_paths.append(recipe.resource_path)


## Adds each saved recipe on top of whatever _ready() already unlocked
## from default_unlocked — doesn't clear _unlocked first, since defaults
## should stay unlocked regardless. Routes through _unlock_bundle(), not
## a plain _unlocked[recipe] = true, so a restored final recipe's bundled
## intermediates (Basic Dough, etc.) come back too.
func load_state(data: FactorySaveData) -> void:
	for path: String in data.unlocked_recipe_paths:
		var recipe: Recipe = load(path) as Recipe
		if recipe != null:
			_unlock_bundle(recipe)
