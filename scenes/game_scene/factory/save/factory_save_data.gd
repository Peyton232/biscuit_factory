class_name FactorySaveData
extends Resource
## A full snapshot of one save slot's game state — built fresh by
## FactoryWorld.capture_save_data() and consumed by
## FactoryWorld.apply_save_data(). Saved/loaded whole via
## ResourceSaver.save()/ResourceLoader.load() to a user://save_slot_N.tres
## file (see SaveManager) — the same persistence idiom the template's
## own GlobalState already uses for its (unrelated, dormant-for-this-
## game) state layer.
##
## Deliberately excludes anything transient/reconstructible: in-flight
## DeliveryJobs, cat pathing/state, station claims, and in-progress
## processing batches are never saved — see decisions.md. Everything
## reloads idle and self-heals within moments via the existing
## dispatch/station-polling systems, consistent with this codebase's
## established tolerance for discarding in-progress work on
## reassignment/demolition elsewhere.

@export var saved_at_unix_time: int = 0

@export var money: int = 0

@export var current_tier: int = 0
## Set by TierManager.save_state()/load_state() — see its class doc for
## why this baseline (not just current_tier) must be saved explicitly.
@export var goal_baseline: Dictionary[String, int] = {}

## True once the player has ever reached Tier Winner in this slot — shown
## as a gold star by SaveSlotMenu. Set by FactoryWorld the moment Tier
## Winner is reached and re-captured on every save after that (including
## ones from continued post-win play), never cleared once true — see
## FactoryWorld's class doc.
@export var completed: bool = false

## Recipe.resource_path for every recipe the player has purchased (not
## default_unlocked ones — those are always free regardless of save
## state). See RecipeShop.save_state()/load_state().
@export var unlocked_recipe_paths: Array[String] = []

@export var items_shipped: Dictionary[String, int] = {}
@export var cats_adopted_count: int = 0
@export var money_earned_total: int = 0
@export var playtime_seconds: float = 0.0
@export var total_deliveries_completed: int = 0

@export var buildings: Array[BuildingSaveEntry] = []
@export var cats: Array[CatSaveEntry] = []

## Set by FactoryBounds.save_state()/load_state(). Vector2i.ZERO (its
## default) is treated by load_state() as "no save data" and left alone,
## since a real unlocked area is never zero-sized.
@export var factory_unlocked_size: Vector2i = Vector2i.ZERO
@export var factory_expansion_count: int = 0
