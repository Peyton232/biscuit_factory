class_name AchievementsManager
extends Node
## Account-wide achievement catalog, unlock state, and the single place
## anything gets unlocked. Autoloaded as `Achievements`.
##
## **Unlock state is stored per ACCOUNT, not per save slot** — in
## `PlayerConfig` (`user://player_config.cfg`), alongside settings,
## rather than in `FactorySaveData`. That is a deliberate match for how
## Steam achievements work: they belong to the Steam user, not to a save
## file, and they never un-earn. Storing them per slot would mean
## deleting a save silently revoked achievements, and would guarantee
## local state and Steam state disagreeing the moment Steam is wired up.
## The corollary is that unlocks survive starting a new game, which is
## correct for this kind of "you did this once" record.
##
## **`unlock()` is the single chokepoint, by design.** Nothing else
## writes unlock state, and everything that could ever want to observe an
## unlock — the toast, a future Steam layer, a stats page — goes through
## `achievement_unlocked`. Wiring Steam should be additive: subscribe to
## that signal and call `Steam.setAchievement(def.steam_api_name())`,
## plus a one-time reconcile at startup for unlocks earned offline or on
## another machine. See `pending_steam_sync()` for the latter.
##
## Conditions are NOT evaluated here. This node has no gameplay
## dependencies at all (it outlives factory_world and exists in the main
## menu too), so a per-run `AchievementTracker` inside factory_world
## watches gameplay signals and calls `unlock()`. That split is what lets
## achievements be account-wide while their conditions are per-save.

signal achievement_unlocked(definition: AchievementDefinition)

const _CONFIG_SECTION: String = "Achievements"

## The catalog, explicit rather than discovered from disk. Deliberate:
## this array IS the list that has to be mirrored into Steamworks, so it
## should be readable in one place and impossible to change by dropping a
## file in a folder. Same reasoning RecipeBook/CatShop use explicit lists
## for anything player-facing. Order within a category comes from each
## definition's own `sort_order`.
const DEFINITIONS: Array[AchievementDefinition] = [
	preload("res://resources/achievements/complete_tutorial.tres"),
	preload("res://resources/achievements/reach_tier_5.tres"),
	preload("res://resources/achievements/finish_game.tres"),
	preload("res://resources/achievements/adopt_10_cats.tres"),
	preload("res://resources/achievements/adopt_50_cats.tres"),
	preload("res://resources/achievements/adopt_100_cats.tres"),
	preload("res://resources/achievements/ship_100_bread.tres"),
	preload("res://resources/achievements/ship_100_biscuits.tres"),
	preload("res://resources/achievements/ship_100_cakes.tres"),
	preload("res://resources/achievements/ship_100_cookies.tres"),
	preload("res://resources/achievements/ship_1000_total.tres"),
	preload("res://resources/achievements/speed_baker.tres"),
	preload("res://resources/achievements/marathon_baker.tres"),
	preload("res://resources/achievements/unlock_every_recipe.tres"),
	preload("res://resources/achievements/big_money.tres"),
	preload("res://resources/achievements/crazy_cat_lady.tres"),
	preload("res://resources/achievements/corner_to_corner.tres"),
]

var _by_id: Dictionary[StringName, AchievementDefinition] = {}
## id -> Vector2i(current, total) for countable achievements, published
## by AchievementTracker while a run exists.
##
## **In-memory and run-scoped on purpose, unlike unlock state.** Unlocks
## are account-wide because Steam's are; progress is not — it belongs to
## one save, and there are three slots. Persisting "last known progress"
## account-wide would show a number from whichever save was played most
## recently, which is worse than showing none. So the list shows progress
## while a game is running and just Locked/Unlocked from the main menu.
var _progress: Dictionary[StringName, Vector2i] = {}


func _ready() -> void:
	for definition: AchievementDefinition in DEFINITIONS:
		assert(not _by_id.has(definition.id),
				"Duplicate achievement id: %s" % definition.id)
		_by_id[definition.id] = definition


## Every achievement, in catalog order grouped by category then
## sort_order — the order the list UI and the Steamworks config should
## both use.
func all_sorted() -> Array[AchievementDefinition]:
	var sorted: Array[AchievementDefinition] = DEFINITIONS.duplicate()
	sorted.sort_custom(func(a: AchievementDefinition, b: AchievementDefinition) -> bool:
		if a.category != b.category:
			return a.category < b.category
		return a.sort_order < b.sort_order)
	return sorted


func definition(id: StringName) -> AchievementDefinition:
	return _by_id.get(id)


func is_unlocked(id: StringName) -> bool:
	return PlayerConfig.get_config(_CONFIG_SECTION, String(id), false)


func unlocked_count() -> int:
	var count: int = 0
	for definition: AchievementDefinition in DEFINITIONS:
		if is_unlocked(definition.id):
			count += 1
	return count


## Unlocks `id` if it isn't already. **Idempotent and safe to spam** —
## trackers call this from per-frame polls and from signal handlers that
## may fire repeatedly, so "already unlocked" has to be a cheap no-op
## rather than a caller's responsibility. Returns true only on the
## transition, so a caller can tell a fresh unlock from a repeat.
func unlock(id: StringName) -> bool:
	var definition: AchievementDefinition = _by_id.get(id)
	if definition == null:
		push_warning("Unknown achievement id: %s" % id)
		return false
	if is_unlocked(id):
		return false
	PlayerConfig.set_config(_CONFIG_SECTION, String(id), true)
	achievement_unlocked.emit(definition)
	return true


## Records how far along a countable achievement is, and unlocks it once
## it gets there. `total` defaults to the definition's own `target`;
## pass one explicitly where the total is data-derived rather than
## authored (Full Cookbook's total is however many purchasable recipes
## exist, which would otherwise have to be duplicated into the .tres and
## kept in sync).
##
## **Unlocking lives here rather than in the tracker** so that "the
## number reached its goal" is expressed exactly once, and the same
## number the player reads in the list is the one that decides the
## unlock. They cannot disagree. Achievements whose condition is not
## simply "reach a number" (Speed Baker's time limit, Crazy Cat Lady's
## ratio) publish no progress and keep their own checks — see
## AchievementDefinition.progress_format.
func set_progress(id: StringName, current: int, total: int = -1) -> void:
	var definition: AchievementDefinition = _by_id.get(id)
	if definition == null:
		push_warning("Unknown achievement id: %s" % id)
		return
	var effective: int = total if total >= 0 else definition.target
	_progress[id] = Vector2i(current, effective)
	if effective > 0 and current >= effective:
		unlock(id)


## Vector2i(current, total), or ZERO if nothing has been published for
## this achievement (no run in progress, or it isn't countable).
func progress(id: StringName) -> Vector2i:
	return _progress.get(id, Vector2i.ZERO)


func has_progress(id: StringName) -> bool:
	return _progress.has(id) and _progress[id].y > 0


## Dropped when a run ends so the main menu doesn't show a stale number
## from the save that just closed. Called by AchievementTracker._exit_tree().
func clear_progress() -> void:
	_progress.clear()


## Everything currently unlocked locally, for a future Steam layer to
## push at startup. Steam is the source of truth for *display*, but a
## player can earn achievements offline (or before Steam was wired up),
## so the first sync has to be local -> Steam for anything Steam doesn't
## already have. Steam -> local matters too if they played on another
## machine; that direction is `unlock()` per returned id, which is why
## unlock() emits (so the toast can be suppressed by the caller if it
## wants a silent reconcile — see the Steam notes in decisions.md).
func pending_steam_sync() -> Array[AchievementDefinition]:
	var unlocked: Array[AchievementDefinition] = []
	for definition: AchievementDefinition in DEFINITIONS:
		if is_unlocked(definition.id):
			unlocked.append(definition)
	return unlocked


## Debug/testing only: wipes every unlock. Not reachable from the game
## UI — an accidental "reset achievements" button is a bad day for a
## player, and on Steam it would also need `Steam.clearAchievement()`
## per id to actually take effect.
func reset_all() -> void:
	for definition: AchievementDefinition in DEFINITIONS:
		PlayerConfig.erase_section_key(_CONFIG_SECTION, String(definition.id))
