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

## Emitted when this station's output warning appears or changes, so a
## readout can repaint without polling every building every frame. The
## warning state flips on a timer, not on an inventory change, so there
## is no other signal to hang it on. See is_output_stranded() and
## is_output_stalled().
signal output_status_changed()

## Which Cat role can staff this building. Set per scene (Mixer ->
## MIXER, Oven -> OVEN); a Cat claims station_cat by matching this.
@export var required_role: Cat.Role = Cat.Role.MIXER
## Recipes this station type is able to run. Set per scene (e.g. Mixer
## offers Dough and Batter, Oven offers Biscuit). The player picks the
## active one from these via assign_recipe().
@export var available_recipes: Array[Recipe] = []
## Offset from this building's position where a staffing Cat parks
## (Cat._arrive_at_station()). Negative X/Z parks at the building's
## top-left, screen-wise (camera never yaws, so world -X/-Z consistently
## reads as screen left/up). **Moved here from a flat Cat-level export
## (✅ 2026-07-15)** — it needs to vary per station *type* (the Assembly
## Table's cat sits lower than the others, see decorating_table.tscn),
## not per cat, and a cat visits many different station types over its
## lifetime.
@export var station_offset: Vector3 = Vector3(-0.8, 0.0, -0.8)
## How long this station may sit unable to start a batch — a finished one
## still occupying the output — before it stops counting as work for the
## cat parked here, freeing that cat to go somewhere it can be useful.
##
## **Measured, not guessed** (real Tier 5 save, 119 buildings, 93 cats,
## 600s): a healthy pickup completes in a median of 9.3s, p90 18.6s,
## p99 29.6s — while the pathological cases ran to 137s and beyond, with
## 24 station cats doing nothing whatsoever for the entire run. 45s sits
## about 1.5x above p99, so ordinary hand-offs are never disturbed and
## genuinely stuck stations release their cat in well under a minute.
## See decisions.md for the sweep this came from.
@export_range(5.0, 180.0, 1.0) var blocked_patience_seconds: float = 45.0

## How long a finished batch must sit *unclaimed* in the output before
## the station counts as stranded rather than mid-handoff. Comfortably
## longer than a healthy pickup takes to be scheduled: DeliveryManager
## listens to output_inventory.changed and dispatches in the same frame
## the batch lands, so a job that is ever going to exist already exists
## well inside this window.
const _STRANDED_AFTER_SECONDS: float = 2.0

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
## Seconds this station has been unable to start a batch because a
## finished one is still sitting in the output — for any reason.
var _blocked_seconds: float = 0.0
## Subset of the above: seconds the blocking item has also had no pickup
## reserved against it, i.e. nothing is even coming for it.
var _unclaimed_seconds: float = 0.0
var _output_stranded: bool = false
var _output_stalled: bool = false


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
	# The new recipe's output may well have a consumer even though the
	# old one didn't, so the station starts over as un-stranded rather
	# than inheriting the previous recipe's verdict.
	_clear_block_timers()


## Whether a batch is actually running right now. Public because "is
## this station doing anything" is a question its cat asks.
##
## **Deliberately not named `is_processing()`** — that shadows
## `Node.is_processing()` (whether the node's `_process` callback is
## enabled), which GDScript rejects as a parse error under this
## project's warnings-as-errors setting, and which silently answers a
## completely different question if it ever compiled.
func is_batch_running() -> bool:
	return _processing


## 0 when idle; otherwise 0..1 (clamped at 1 while waiting for output
## space, which shouldn't normally last long since a new batch can't
## start until the output is clear anyway). Progress bars read this.
func progress() -> float:
	if not _processing:
		return 0.0
	return clampf(_timer / recipe.processing_time, 0.0, 1.0)


## Whether there's productive work happening or imminent here: actively
## processing, OR every needed input is already on hand and the station
## can realistically start on them.
## False means genuinely nothing to do — station cats use this to decide
## whether to keep waiting here or wander to a different station.
##
## **A station that has been unable to start for `blocked_patience_
## seconds` reads as no work, which is what stops it pinning its cat
## there indefinitely.** Player report: "the cat was sitting at an oven
## that had all inputs needed, but still had an output item on it, and
## therefore he was stuck, because that output was not moving. He sat
## there doing nothing for a long time. I feel like the pathing should
## make that cat go to a different [station] after not being able to do
## anything for a while."
##
## The blocking condition is deliberately "output occupied", **not**
## "output occupied and unclaimed". An earlier attempt at this fix only
## released the cat when nothing had reserved the item, on the reasoning
## that a reserved item means a delivery cat is on its way. Measuring the
## reported save killed that: every stuck item there had a valid
## destination and a job — the deliveries were simply never getting
## round to it, and 24 station cats sat idle for a full 10 minutes with
## reservations in place the whole time. From the player's side it does
## not matter why the output is not moving.
##
## Patience rather than an instant release, because the ordinary gap
## between a batch finishing and a cat collecting it must keep counting
## as work or cats would churn off perfectly healthy stations — measured
## median 9.3s. See blocked_patience_seconds.
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
	# Two tiers, because the two diagnoses deserve different patience.
	# "Stranded" is provable within seconds — no job was ever created, so
	# nothing is coming, ever — and there is no reason to make the cat
	# stand there for the full patience window waiting for a pickup that
	# cannot happen. "Stalled" is the slow case, where a job does exist
	# and might still be serviced, so it gets the full window first.
	return not (_output_stalled or _output_stranded)


## True once the station has been unable to start a batch for
## `blocked_patience_seconds` — the output is occupied and not clearing.
## Drives both the cat's decision to move on (has_pending_work()) and the
## "waiting on pickup" warning on BuildingInventoryLabel.
func is_output_stalled() -> bool:
	return _output_stalled


## True once a finished batch has sat in the output for
## `_STRANDED_AFTER_SECONDS` with **no pickup even reserved** — no other
## building wants the item and no delivery job was ever created, so
## nothing is coming at all. A strictly worse diagnosis than stalled, and
## detectable much sooner, which is why it has its own (short) timer and
## its own label text. Purely a readout: the cat-releasing decision is
## `is_output_stalled()`, which covers this case too.
func is_output_stranded() -> bool:
	return _output_stranded


## Output occupied by a finished batch, so the next one cannot start.
func _is_output_blocked() -> bool:
	if recipe == null or _processing:
		return false
	return output_inventory.total_count() > 0


## ...and nobody has even claimed it. A *reserved* item means a
## DeliveryJob exists; `available_for_pickup()` is present-minus-reserved.
func _is_output_unclaimed() -> bool:
	return _is_output_blocked() and output_inventory.available_for_pickup(recipe.output) > 0


func _clear_block_timers() -> void:
	_blocked_seconds = 0.0
	_unclaimed_seconds = 0.0
	if _output_stranded or _output_stalled:
		_output_stranded = false
		_output_stalled = false
		output_status_changed.emit()


func _update_block_timers(delta: float) -> void:
	_blocked_seconds = _blocked_seconds + delta if _is_output_blocked() else 0.0
	_unclaimed_seconds = _unclaimed_seconds + delta if _is_output_unclaimed() else 0.0
	var stranded: bool = _unclaimed_seconds >= _STRANDED_AFTER_SECONDS
	var stalled: bool = _blocked_seconds >= blocked_patience_seconds
	if stranded == _output_stranded and stalled == _output_stalled:
		return
	_output_stranded = stranded
	_output_stalled = stalled
	output_status_changed.emit()


func _process(delta: float) -> void:
	# Ahead of the staffing check on purpose: once a cat leaves a
	# stranded station the station is still stranded, and the warning
	# has to keep showing rather than clearing the moment nobody is
	# standing there.
	_update_block_timers(delta)
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
