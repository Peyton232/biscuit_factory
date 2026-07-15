class_name ProcessingBuilding
extends Building
## A station that executes an assigned Recipe: consumes one of each of the
## recipe's input items, works for recipe.processing_time seconds, then
## adds the recipe's output item to its output inventory — but only once
## a Cat of the matching role has actually arrived and parked here
## (station_cat set AND cat_arrived true; claiming alone doesn't count).
## Never starts a new batch until the previous output has been collected,
## so the station never silently queues more than one finished item.
##
## Recipes are data, not code: which recipes THIS station type can run is
## set per scene (available_recipes), and which one is currently active
## (recipe) is player-chosen at runtime via BuildingSelector/
## BuildingInspectorPanel. **A freshly-placed station starts with no
## recipe selected at all** (`recipe == null`) — the player must
## explicitly assign one before it does anything; this used to default
## to `available_recipes[0]`, but silently picking a recipe for the
## player made it easy to miss that recipe selection is even a step
## (the tutorial now has a dedicated step for it, see decisions.md).
##
## **Production gates on recipe_shop.is_unlocked(recipe), not just on
## having a recipe assigned.** Historically available_recipes[0] (the
## default on placement) was always required to be a free/default_unlocked
## recipe, precisely so a freshly-placed station could never produce a
## paid recipe's output for free. The GDD's economy (see progression.md)
## makes that invariant impossible to keep for every station — the
## Assembly Table has no free recipe at all, every one of its recipes is
## priced. Rather than lean on an unenforceable convention, _try_start()
## now checks the lock directly: a locked recipe simply never starts a
## batch (or counts as "pending work" for a station cat), regardless of
## what's assigned or sitting in the input inventory. recipe_shop is
## injected by BuildingPlacer at placement, same mechanism as
## ShippingBin.economy/lifetime_stats.

## Which Cat role can staff this building. Set per scene (Mixer ->
## MIXER, Oven -> OVEN); a Cat claims station_cat by matching this.
@export var required_role: Cat.Role = Cat.Role.MIXER
## Recipes this station type is able to run. Set per scene (e.g. Mixer
## offers Dough and Batter, Oven offers Biscuit). The player picks the
## active one from these via assign_recipe().
@export var available_recipes: Array[Recipe] = []

## Injected by the BuildingPlacer when placed, same as ShippingBin.economy.
var recipe_shop: RecipeShop = null

## The Cat currently assigned to this building, or null if unclaimed.
## Set by Cat as soon as it decides to head here (so a second cat won't
## also target it while the first is still walking over) and cleared on
## reassignment/pickup/demolition. NOT sufficient on its own to gate
## work — see cat_arrived.
var station_cat: Cat = null
## True once station_cat has actually walked up and parked here. Work
## only happens once this is true; claiming a station is a reservation,
## not a presence — otherwise processing (and the progress bar) would
## start while the cat is still mid-walk toward it.
var cat_arrived: bool = false
## The recipe currently being run, or null until the player picks one
## via assign_recipe(). No longer defaults to available_recipes[0] — see
## the class doc above.
var recipe: Recipe = null

var _processing: bool = false
var _timer: float = 0.0


func current_inputs() -> Array[StringName]:
	return recipe.inputs if recipe != null else []


func current_outputs() -> Array[StringName]:
	return [recipe.output] if recipe != null else []


## Switches which recipe this station runs. Any batch already in
## progress is discarded (its consumed inputs are simply lost — an
## accepted rough edge, same spirit as other demolition/reassignment
## edges in this codebase) rather than finishing into the wrong output.
## Leftover stored inputs that no longer belong to any recipe input list
## are cleared too, so they don't sit stuck forever uncounted by the
## inventory label or the per-item delivery cap.
##
## **output_inventory is cleared too — this used to only clear inputs,
## which was a real deadlock bug, not just an inventory-label cosmetic
## issue**: if a batch finished into output_inventory and was never
## collected before the player reassigned the recipe,
## current_outputs()/current_inputs() immediately start reflecting the
## NEW recipe, so DeliveryManager's dispatch scan (which only ever looks
## at current_outputs()) can never see the stale item to route a cat to
## it — but _try_start() still refuses to begin a new batch as long as
## ANY item sits in output_inventory, regardless of which one. Net
## result: the station gets permanently stuck refusing to produce
## anything, ever again, with no visible symptom (the stale item doesn't
## even show on BuildingInventoryLabel, since that also reads
## current_outputs()). See decisions.md.
func assign_recipe(new_recipe: Recipe) -> void:
	if new_recipe == recipe:
		return
	recipe = new_recipe
	_processing = false
	_timer = 0.0
	input_inventory.clear()
	output_inventory.clear()


## 0 when idle; otherwise 0..1 (clamped at 1 while waiting for output
## space, which shouldn't normally last long since a new batch can't
## start until the output is clear anyway). Progress bars read this.
func progress() -> float:
	if not _processing:
		return 0.0
	return clampf(_timer / recipe.processing_time, 0.0, 1.0)


## Whether there's productive work happening or imminent here: actively
## processing, OR every needed input is already on hand (just waiting
## for the output to be collected before the next batch can start).
## False means genuinely nothing to do — station cats use this to decide
## whether to keep waiting here or wander to a different station.
func has_pending_work() -> bool:
	if recipe == null:
		return false
	if recipe_shop != null and not recipe_shop.is_unlocked(recipe):
		return false
	if _processing:
		return true
	for item: StringName in recipe.inputs:
		if input_inventory.count(item) < 1:
			return false
	return true


func _process(delta: float) -> void:
	if recipe == null or station_cat == null or not cat_arrived:
		return
	if not _processing:
		_try_start()
		return
	# Clamp so a frame hitch (scene load, GC pause) can't jump the timer
	# past the threshold in one step and make the bar skip its climb.
	_timer += minf(delta, 0.1)
	if _timer >= recipe.processing_time:
		_try_finish()


func _exit_tree() -> void:
	super._exit_tree()
	if station_cat != null:
		station_cat.notify_station_removed()


func _try_start() -> void:
	# A locked recipe never runs, regardless of what's assigned or
	# sitting in the input inventory — see the class doc above for why
	# this check exists instead of relying on a "default is always free"
	# convention.
	if recipe_shop != null and not recipe_shop.is_unlocked(recipe):
		return
	# Defensive self-heal: output_inventory should never hold anything
	# other than the current recipe's own output — assign_recipe()
	# clears it on every recipe switch specifically to guarantee this,
	# but a stray mismatch here (any future path that forgets to) must
	# never be allowed to permanently deadlock the station the way it
	# did before that fix (see decisions.md) — a mismatched leftover is
	# simply discarded rather than blocking production forever.
	if output_inventory.total_count() > 0 and output_inventory.count(recipe.output) == 0:
		output_inventory.clear()
	# Never start a new batch while the last one is still waiting for
	# pickup — the station holds at most one finished item at a time.
	if output_inventory.total_count() > 0:
		return
	for item: StringName in recipe.inputs:
		if input_inventory.count(item) < 1:
			return
	for item: StringName in recipe.inputs:
		input_inventory.remove(item)
	_processing = true
	_timer = 0.0


func _try_finish() -> void:
	var produced: StringName = recipe.output
	if output_inventory.add(produced):
		_processing = false
		station_cat.record_batch_completed(required_role)
		FloatingText.spawn(self, global_position + Vector3.UP * 2.1, "+%s" % produced)


## Adds the assigned recipe on top of Building's common save entry. An
## in-progress batch (_processing/_timer) is deliberately not saved —
## consistent with assign_recipe() already treating a discarded batch as
## an accepted rough edge elsewhere in this codebase.
func save_entry() -> BuildingSaveEntry:
	var entry: BuildingSaveEntry = super.save_entry()
	if recipe != null:
		entry.recipe_path = recipe.resource_path
	return entry


## Restores the assigned recipe by assigning `recipe` directly — NOT via
## assign_recipe(), which clears both inventories as a side effect
## (correct for a live reassignment, but it would wipe the very
## inventory contents super.load_entry() is about to restore).
func load_entry(entry: BuildingSaveEntry) -> void:
	if not entry.recipe_path.is_empty():
		recipe = load(entry.recipe_path) as Recipe
	super.load_entry(entry)
