class_name AchievementTracker
extends Node
## Watches this run's gameplay and calls `Achievements.unlock()`. One
## node in `factory_world.tscn`; the conditions live here, the thresholds
## live in each `AchievementDefinition`, and the unlock state lives in
## the `Achievements` autoload.
##
## **Why the split**: achievements are account-wide and outlive any save
## (see AchievementsManager), but every condition is about *this* run's
## LifetimeStats/TierManager/cats. Putting the conditions in the autoload
## would force it to reach into a scene that mostly doesn't exist (main
## menu, credits); putting the state here would tie unlocks to a save
## slot, which is exactly what Steam's per-account model forbids. So:
## state above, conditions here.
##
## **Signal-driven where a signal exists, polled where one doesn't.**
## Cat adoption, shipments and tier advances all emit, so those are
## connected. The three that have no natural event — playtime, the
## cats-per-station ratio, and the corner walk — are checked on a slow
## timer rather than every frame; none of them can be missed by a second
## of latency, and polling 100 cats' positions every frame to service one
## hidden achievement is not a trade worth making.
##
## Every unlock is idempotent (see `Achievements.unlock()`), so a
## condition that keeps evaluating true after it fires costs nothing and
## no handler needs its own "already done" bookkeeping.

## How often the polled conditions are re-checked, in seconds.
const _POLL_SECONDS: float = 2.0

## How close (in metres) a cat has to get to a corner of the unlocked
## factory to count as having reached it.
const _CORNER_RADIUS: float = 2.5
## Fraction of the true diagonal a cat must actually have *walked*
## between touching opposite corners. Below 1.0 because a cat paths
## around buildings rather than along the diagonal, so its real distance
## is longer than the straight line — but it also can't be teleported or
## carried there, which is the point (Cat.total_distance_meters only
## accumulates in _follow_path()).
const _CORNER_WALK_FRACTION: float = 0.9

@export var lifetime_stats: LifetimeStats
@export var tier_manager: TierManager
@export var recipe_shop: RecipeShop
@export var tutorial_manager: TutorialManager
@export var factory_bounds: FactoryBounds
@export var cats_root: Node3D
@export var buildings_root: Node3D

var _poll_timer: float = 0.0
## cat instance id -> [corner index first touched, that cat's
## total_distance_meters at the moment it touched it]. See
## _check_corner_walk().
var _corner_progress: Dictionary[int, Array] = {}


func _ready() -> void:
	if lifetime_stats != null:
		lifetime_stats.cat_adopted.connect(_on_cat_adopted)
		lifetime_stats.item_shipped.connect(_on_item_shipped)
	if tier_manager != null:
		tier_manager.tier_advanced.connect(_on_tier_advanced)
	if recipe_shop != null:
		recipe_shop.recipe_unlocked.connect(_on_recipe_unlocked)
	if tutorial_manager != null:
		tutorial_manager.chapter_completed.connect(_on_tutorial_chapter_completed)
	# A loaded save can already satisfy conditions that were met before
	# achievements existed, or on a machine where they hadn't synced.
	_publish_progress()
	_check_polled()


## Progress belongs to this run, so it goes when the run does — see
## AchievementsManager._progress for why it isn't persisted.
func _exit_tree() -> void:
	Achievements.clear_progress()


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer < _POLL_SECONDS:
		return
	_poll_timer = 0.0
	_publish_progress()
	_check_polled()


## The one table mapping countable achievements to the number they count.
##
## **This publishes progress AND drives the unlock**, because
## `Achievements.set_progress()` unlocks on reaching the total. Before
## this existed, each handler below compared its own number against its
## own target, and the list UI would have needed a second copy of the
## same mapping to render "12 / 25" — two tables free to drift. Now the
## number the player reads is literally the number that decides the
## unlock.
##
## Cheap enough to call on every relevant signal and on the poll: it is a
## dozen dictionary reads, and `unlock()` is idempotent.
func _publish_progress() -> void:
	if lifetime_stats != null:
		var adopted: int = lifetime_stats.cats_adopted_count
		Achievements.set_progress(&"adopt_10_cats", adopted)
		Achievements.set_progress(&"adopt_50_cats", adopted)
		Achievements.set_progress(&"adopt_100_cats", adopted)
		for id: StringName in [&"ship_100_bread", &"ship_100_biscuits",
				&"ship_100_cakes", &"ship_100_cookies"]:
			var definition: AchievementDefinition = Achievements.definition(id)
			if definition != null:
				Achievements.set_progress(id, lifetime_stats.shipped_count(definition.item))
		Achievements.set_progress(&"ship_1000_total", lifetime_stats.total_items_shipped())
		Achievements.set_progress(&"big_money", lifetime_stats.money_earned_total)
		Achievements.set_progress(&"marathon_baker", int(lifetime_stats.playtime_seconds))
	if tier_manager != null:
		Achievements.set_progress(&"reach_tier_5", tier_manager.current_tier)
	if recipe_shop != null:
		# Total passed explicitly: it is however many recipes are actually
		# for sale, which would otherwise have to be copied into the .tres
		# and kept in step with the shop.
		Achievements.set_progress(&"unlock_every_recipe",
				recipe_shop.purchasable_unlocked_count(), recipe_shop.shop_prices.size())


# --- Signal-driven ---------------------------------------------------

func _on_cat_adopted() -> void:
	_publish_progress()


func _on_item_shipped(_item: StringName) -> void:
	_publish_progress()


func _on_tier_advanced(new_tier: int) -> void:
	_publish_progress()
	if new_tier >= TierManager.TIER_NAMES.size() - 1:
		Achievements.unlock(&"finish_game")
		# Speed Baker is only meaningful at the moment the game is
		# finished — it asks how long the whole run took, so it is
		# checked here rather than polled.
		if lifetime_stats != null \
				and lifetime_stats.playtime_seconds < float(_target(&"speed_baker")):
			Achievements.unlock(&"speed_baker")


func _on_recipe_unlocked(_recipe: Recipe) -> void:
	_publish_progress()


## The tutorial's Tier 1 chapter specifically ("Complete Tutorial (the
## one in tier 1)") — TutorialManager reports which chapter finished, so
## the base chapter doesn't also fire this.
func _on_tutorial_chapter_completed(chapter: StringName) -> void:
	if chapter == TutorialManager.CHAPTER_TIER_1:
		Achievements.unlock(&"complete_tutorial")


# --- Polled ----------------------------------------------------------

## The conditions that are NOT "reach a number", and so can't go through
## _publish_progress().
func _check_polled() -> void:
	_check_crazy_cat_lady()
	_check_corner_walk()


## "Crazy Cat Lady Bakery": far more cats than stations. Deliberately a
## ratio rather than another raw count — the Cats category already has
## 10/50/100 adopted, and since cats never leave, a plain "own N cats"
## here would just unlock alongside one of those. A bakery that is three
## parts cat to one part equipment is a different (and funnier) thing to
## have done on purpose.
func _check_crazy_cat_lady() -> void:
	if cats_root == null:
		return
	var cats: int = cats_root.get_child_count()
	if cats < _target(&"crazy_cat_lady"):
		return
	var stations: int = buildings_root.get_child_count() if buildings_root != null else 0
	if stations == 0 or float(cats) / float(stations) >= 3.0:
		Achievements.unlock(&"crazy_cat_lady")


## "The Long Commute": one cat walks the factory's full diagonal.
##
## Tracked as "touched a corner, then touched the opposite corner, having
## actually walked at least the diagonal in between". The distance clause
## is what makes it mean what it says: `Cat.total_distance_meters` only
## accumulates inside `_follow_path()`, so a cat that was picked up and
## dropped in the far corner gains no distance and doesn't qualify.
func _check_corner_walk() -> void:
	if factory_bounds == null or cats_root == null:
		return
	if Achievements.is_unlocked(&"corner_to_corner"):
		return
	var corner: Vector3 = factory_bounds.unlocked_world_corner()
	var size: Vector2 = factory_bounds.unlocked_world_size()
	var corners: Array[Vector3] = [
		corner,
		corner + Vector3(size.x, 0.0, 0.0),
		corner + Vector3(size.x, 0.0, size.y),
		corner + Vector3(0.0, 0.0, size.y),
	]
	var diagonal: float = Vector2(size.x, size.y).length()
	for child: Node in cats_root.get_children():
		var cat: Cat = child as Cat
		if cat == null:
			continue
		for i: int in corners.size():
			if Vector2(cat.position.x - corners[i].x, cat.position.z - corners[i].z).length() \
					> _CORNER_RADIUS:
				continue
			var key: int = cat.get_instance_id()
			if not _corner_progress.has(key):
				_corner_progress[key] = [i, cat.total_distance_meters]
				continue
			var first: Array = _corner_progress[key]
			# Opposite corner = two steps around a four-corner ring.
			if (int(first[0]) + 2) % 4 != i:
				continue
			if cat.total_distance_meters - float(first[1]) >= diagonal * _CORNER_WALK_FRACTION:
				Achievements.unlock(&"corner_to_corner")
				return


func _target(id: StringName) -> int:
	var definition: AchievementDefinition = Achievements.definition(id)
	return definition.target if definition != null else 0
