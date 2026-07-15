class_name TierManager
extends Node
## Tracks the game's progression tier (0..6, index 6 = "Tier Winner") and
## gates which buildings/recipes are even visible in the UI — see
## progression.md for the full tier table this data mirrors.
##
## Advancing a tier is a manual player action, NOT automatic: reaching a
## tier's shipped-quantity goal(s) only makes can_advance() true; nothing
## actually changes until advance_tier() is called (wired to a HUD
## button/banner — see FactoryHud). advance_tier() also re-snapshots
## _goal_baseline for the new tier's goal item(s).
##
## Goal progress is deliberately `lifetime_stats.shipped_count(item) -
## _goal_baseline[item]`, NOT the raw lifetime count — Biscuits is a goal
## item for two different tiers (Tier 3->4 needs 20, Tier 5->Winner needs
## 50); a raw lifetime count would let the second goal arrive
## pre-satisfied by leftover shipments from the first. See decisions.md.
##
## Registers itself in the "tier_manager" group so windows instantiated
## fresh via the pause menu's generic loader (RecipeBook, BuildingBook)
## can find it, same pattern RecipeShop already uses for RecipeBook.

signal tier_advanced(new_tier: int)

const TIER_NAMES: Array[String] = [
	"Tier 0", "Tier 1", "Tier 2", "Tier 3", "Tier 4", "Tier 5", "Tier Winner",
]

## One goal per tier transition — index 0 is the goal to leave Tier 0 for
## Tier 1, and so on. Tier Winner (index 6) has no further goal, so this
## has TIER_NAMES.size() - 1 entries.
const _GOALS: Array[Dictionary] = [
	{&"whipped_cream": 5},
	{&"bread": 10, &"cream_bun": 5},
	{&"butter_roll": 10, &"croissant": 10, &"cream_pie": 5},
	{&"buttered_toast": 15, &"biscuit": 20},
	{&"frosted_sugar_cookie": 25, &"frosted_sweet_roll": 25},
	{&"biscuit": 50, &"frosted_cake": 20, &"meringue_pie": 20, &"danish": 20, &"french_toast": 20},
]

@export var lifetime_stats: LifetimeStats
## Granted a one-time $100 bonus on reaching Tier 1 specifically — Mixer
## ($40)/Oven ($60) and Tier 1's new recipe costs add up fast right after
## Tier 0 already spent the player down to near zero, so this exists
## purely to keep the "money rarely the bottleneck" balance philosophy
## (progression.md) true at the one tier transition where it's tightest.
## Not a generic per-tier reward — no other tier grants one.
@export var economy: Economy
const _TIER_1_BONUS: int = 100
## BuildingDefinition -> tier it becomes visible at. Not listed = tier 0
## (always visible), same "missing = unlocked" convention the old
## BuildingShop/RecipeShop shop_prices dictionaries used.
@export var building_tiers: Dictionary[BuildingDefinition, int] = {}
## Recipe -> tier it becomes visible at. Not listed = tier 0.
@export var recipe_tiers: Dictionary[Recipe, int] = {}
## Sellable item id -> tier it becomes available at (mirrors
## recipe_tiers' final/sellable recipes, keyed by their output item
## instead of the Recipe itself — ShippingBin deals in item ids, not
## Recipe resources). Not listed = tier 0. Used by ShippingBin to grow
## its accepted-items menu as tiers unlock, see decisions.md.
@export var item_tiers: Dictionary[StringName, int] = {}

var current_tier: int = 0

var _goal_baseline: Dictionary[StringName, int] = {}


func _ready() -> void:
	add_to_group("tier_manager")
	_snapshot_baseline()


func tier_name() -> String:
	return TIER_NAMES[current_tier]


func is_building_unlocked(definition: BuildingDefinition) -> bool:
	return current_tier >= building_tiers.get(definition, 0)


func is_recipe_unlocked(recipe: Recipe) -> bool:
	return current_tier >= recipe_tiers.get(recipe, 0)


func is_item_unlocked(item: StringName) -> bool:
	return current_tier >= item_tiers.get(item, 0)


## This tier's goal requirements (item -> quantity needed since the tier
## began), or empty once there's no further tier (Tier Winner).
func goal_requirements() -> Dictionary[StringName, int]:
	if current_tier >= _GOALS.size():
		return {}
	return _GOALS[current_tier]


## Sum of every tier's goal quantities across the whole game — the
## minimum a player's lifetime shipments could possibly be by the time
## they reach Tier Winner (a player who reaches Tier Winner has, by
## construction, shipped at least this many units in total — see the
## class doc's note on why goal_progress() diffs against a per-tier
## baseline rather than a raw lifetime count). Used by the Bakery
## Report's "Bootstrap Bakery" rank check (VictorySequence): lifetime
## shipments close to this minimum means the player shipped barely more
## than progression demanded rather than mass-producing for profit.
## Computed here rather than a second hardcoded number, so a future tier
## rebalance can't drift out of sync with it.
func total_required_shipments() -> int:
	var total: int = 0
	for goal: Dictionary in _GOALS:
		for item: StringName in goal:
			total += goal[item]
	return total


## Progress toward one of the current goal's items, counted only since
## this tier began (see class doc for why).
func goal_progress(item: StringName) -> int:
	return lifetime_stats.shipped_count(item) - _goal_baseline.get(item, 0)


func can_advance() -> bool:
	var goal: Dictionary = goal_requirements()
	if goal.is_empty() and current_tier >= _GOALS.size():
		return false
	for item: StringName in goal:
		if goal_progress(item) < goal[item]:
			return false
	return true


func advance_tier() -> void:
	if not can_advance():
		return
	current_tier += 1
	_snapshot_baseline()
	if current_tier == 1 and economy != null:
		economy.earn(_TIER_1_BONUS)
	tier_advanced.emit(current_tier)


func _snapshot_baseline() -> void:
	_goal_baseline.clear()
	for item: StringName in goal_requirements():
		_goal_baseline[item] = lifetime_stats.shipped_count(item)


## Writes current_tier and _goal_baseline into a save slot. The baseline
## must be saved explicitly, not just current_tier — it's not derivable
## from current_tier alone (Biscuits is a goal item for two different
## tiers; see the class doc above for why a raw lifetime count can't
## stand in for it).
func save_state(out: FactorySaveData) -> void:
	out.current_tier = current_tier
	for item: StringName in _goal_baseline:
		out.goal_baseline[String(item)] = _goal_baseline[item]


func load_state(data: FactorySaveData) -> void:
	current_tier = data.current_tier
	_goal_baseline.clear()
	for item: String in data.goal_baseline:
		_goal_baseline[StringName(item)] = data.goal_baseline[item]
