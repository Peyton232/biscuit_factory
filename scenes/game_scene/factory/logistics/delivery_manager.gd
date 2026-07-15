class_name DeliveryManager
extends Node
## Owns the lifecycle of DeliveryJobs: creation (with validation and
## reservations), tracking, queries for future dispatch/cat systems, and
## removal on completion or cancellation. Buildings know nothing about
## jobs or cats — this manager only reads their inventories.

signal job_created(job: DeliveryJob)
signal job_completed(job: DeliveryJob)
signal job_cancelled(job: DeliveryJob)

## Parent node of all placed buildings.
@export var buildings_root: Node3D
## Parent node of all cats — used only to weigh nearby idle delivery cats
## a bit more favorably when ranking candidates (see _dispatch()); null
## is tolerated the same way other optional wiring points in this
## codebase are (that factor just contributes nothing).
@export var cats_root: Node3D
## Seconds between dispatch scans that turn building needs into jobs.
@export var dispatch_interval: float = 1.0
## Records every completed job as a lifetime delivery count (Bakery
## Report's "Total Deliveries").
@export var lifetime_stats: LifetimeStats

## Every second waited since a (destination, item) pair's last delivery
## is worth this many meters of extra priority in _dispatch()'s ranking —
## see _starvation_bonus_meters().
@export var starvation_meters_per_second: float = 0.5
## Cap on the total starvation bonus (see above), so a station nobody's
## fed in a very long time can outrank a moderately-closer competitor
## without swamping the ranking entirely.
@export var max_starvation_bonus_meters: float = 30.0
## How strongly the nearest idle delivery cat's distance to a candidate's
## pickup nudges that candidate's ranking — 0 = ignored entirely (the old
## Basic Pathing behavior), 1 = weighed exactly as heavily as the
## pickup-to-destination leg itself. Deliberately a fraction, not the
## dominant factor: this is a "prefer jobs a cat can actually start soon"
## nudge on top of the primary distance signal, not a replacement for it.
@export var cat_proximity_weight: float = 0.3

var _jobs: Array[DeliveryJob] = []
var _dispatch_timer: float = 0.0
## Running clock, seconds — accumulated every _process(), not wall time
## (same delta-accumulation idiom LifetimeStats.playtime_seconds already
## uses) — how long ago dispatch last runs from is measured against this,
## not Time.get_ticks_msec(), so it naturally stops advancing while the
## game is paused, consistent with every other in-game timer.
var _elapsed_seconds: float = 0.0
## "<destination instance id>:<item>" -> _elapsed_seconds at the last
## delivery of that item to that destination. A String key, not a
## Dictionary[Building, Dictionary[StringName, float]] — GDScript doesn't
## support nested typed collections (see decisions.md/RecipeShop's own
## note on this), and a compound key sidesteps it entirely. A pair with
## no entry yet (never delivered) is treated as maximally starved — see
## _starvation_bonus_meters() — rather than special-cased here.
var _last_delivered_at: Dictionary[String, float] = {}


func _ready() -> void:
	# Demolished buildings must not leave jobs pointing at freed nodes.
	buildings_root.child_exiting_tree.connect(_on_building_exiting)
	# Every building's inventories immediately trigger a fresh dispatch
	# scan on change (production, consumption, pickup, delivery) — see
	# _watch_building() below for why this matters on top of the
	# periodic scan.
	buildings_root.child_entered_tree.connect(_on_building_entered)
	for building: Building in buildings():
		_watch_building(building)


## Cancels every job that still depends on a building being removed:
## its pickup (until the item is collected) or its destination (until
## delivered). Cats notice their job died when they arrive.
func _on_building_exiting(node: Node) -> void:
	var building: Building = node as Building
	if building == null:
		return
	for job: DeliveryJob in _jobs.duplicate():
		var pickup_pending: bool = job.pickup == building \
				and (job.status == DeliveryJob.Status.PENDING
					or job.status == DeliveryJob.Status.ASSIGNED)
		var destination_pending: bool = job.destination == building \
				and job.status != DeliveryJob.Status.COMPLETED
		if pickup_pending or destination_pending:
			cancel_job(job)


func _on_building_entered(node: Node) -> void:
	var building: Building = node as Building
	if building != null:
		_watch_building(building)


## Connects a building's inventories so ANY change (production,
## consumption, a pickup, a delivery) immediately triggers a fresh
## dispatch scan, instead of only ever finding out up to
## dispatch_interval seconds later. **This is what actually closes the
## "cat grabs the far job when a much closer one is about to appear"
## race** (reported case: a cat reassigned off station duty to Delivery
## polls for work almost instantly via _enter_idle()'s zeroed poll
## timer — if the item it should obviously prefer (sitting in the very
## station it just left) hasn't been turned into a job yet because the
## periodic scan hasn't ticked, the cat has no closer option to compare
## against and correctly-but-unhelpfully claims whatever farther job
## already exists). Buildings tick before Cats in factory_world.tscn's
## child order, and _process() (unlike _unhandled_input) runs in
## forward tree order — so a same-frame production event's `changed`
## signal reaches this handler, and the resulting job exists, before
## that frame's Cat._process() ever polls for work. The periodic
## dispatch_timer scan (below) still runs too, as a harmless backstop —
## every mutation already emits `changed`, so it should rarely have
## anything new left to do, but it's cheap insurance.
func _watch_building(building: Building) -> void:
	building.input_inventory.changed.connect(_dispatch)
	building.output_inventory.changed.connect(_dispatch)


func _process(delta: float) -> void:
	_elapsed_seconds += delta
	_dispatch_timer += delta
	if _dispatch_timer < dispatch_interval:
		return
	_dispatch_timer = 0.0
	_dispatch()


## Global nearest-pair dispatch: builds every valid (pickup, destination,
## item) candidate, ranks by a weighted score, and creates jobs
## best-ranked first. **This used to be destination-centric** (iterate
## destinations, find each one's nearest pickup independently) — which
## fixed "which pickup serves this destination" but not its mirror
## image: with only one unit of an item available and TWO destinations
## wanting it, whichever destination happened to come first in
## `buildings_root`'s child order permanently won every future unit,
## regardless of which one was actually closer. Sorting all candidates
## globally instead of picking a side to prioritize first is what closes
## that gap (see decisions.md for the reported case — Sweet Dough feeding
## a far Oven instead of a near Cutting Station).
##
## **Two additions on top of that plain-distance baseline** (architecture.md
## calls the pre-2026-07-14 version "Basic Pathing" — see decisions.md for
## why both landed together): the ranking score also subtracts a
## starvation bonus (favors a destination that's gone longest without
## this specific item — see _starvation_bonus_meters()) and adds a small
## cat-proximity penalty (favors a pickup with an idle delivery cat
## actually nearby — see _nearest_idle_delivery_cat_distance()), scaled
## by cat_proximity_weight so it nudges rather than dominates the primary
## distance signal. Still no job priorities/stealing once a job exists —
## an in-flight job already committed to a farther pair isn't
## reconsidered even if a closer option appears moments later (see
## gameplay_overview.md/roadmap.md — deliberately not attempted yet, a
## bigger change than either addition here).
func _dispatch() -> void:
	var all_buildings: Array[Building] = buildings()
	var candidates: Array[Dictionary] = []
	for destination: Building in all_buildings:
		for item: StringName in destination.current_inputs():
			if not destination.wants_item(item):
				continue
			for pickup: Building in all_buildings:
				if pickup == destination or pickup.output_inventory.available_for_pickup(item) < 1:
					continue
				var dist: float = pickup.position.distance_to(destination.position)
				var score: float = dist \
						- _starvation_bonus_meters(destination, item) \
						+ _nearest_idle_delivery_cat_distance(pickup) * cat_proximity_weight
				candidates.append({
					"pickup": pickup,
					"destination": destination,
					"item": item,
					"score": score,
				})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
	for candidate: Dictionary in candidates:
		var pickup: Building = candidate["pickup"]
		var destination: Building = candidate["destination"]
		var item: StringName = candidate["item"]
		# Either side may have already been claimed by an earlier
		# (better-ranked) candidate this same pass — re-check both before
		# committing.
		if pickup.output_inventory.available_for_pickup(item) < 1:
			continue
		if not destination.wants_item(item):
			continue
		create_job(item, pickup, destination)


func _starvation_key(destination: Building, item: StringName) -> String:
	return "%d:%s" % [destination.get_instance_id(), item]


## How many meters of extra priority a candidate earns for its
## destination having gone a while without this specific item — a
## (destination, item) pair with no recorded delivery yet (never fed at
## all) reads as having waited _elapsed_seconds itself, i.e. maximally
## starved, with no special-casing needed. Capped at
## max_starvation_bonus_meters so a very long wait outranks a moderately
## closer competitor without swamping the ranking outright.
func _starvation_bonus_meters(destination: Building, item: StringName) -> float:
	var last_delivered: float = _last_delivered_at.get(_starvation_key(destination, item), 0.0)
	var waited_seconds: float = _elapsed_seconds - last_delivered
	return minf(waited_seconds * starvation_meters_per_second, max_starvation_bonus_meters)


## Distance from `pickup` to the nearest currently-idle DELIVERY cat, or
## 0.0 (neutral — contributes nothing either way) when there's no cat to
## compare against, since cats_root is optional wiring and every cat
## might already be busy. A missing/empty cats_root is the same
## "optional wiring point, null just means unused" convention this
## codebase uses elsewhere (tier_manager, recipe_shop, etc.).
func _nearest_idle_delivery_cat_distance(pickup: Building) -> float:
	if cats_root == null:
		return 0.0
	var nearest: float = INF
	for child: Node in cats_root.get_children():
		var cat: Cat = child as Cat
		if cat == null or cat.role != Cat.Role.DELIVERY or not cat.is_idle():
			continue
		nearest = minf(nearest, cat.position.distance_to(pickup.position))
	return nearest if nearest != INF else 0.0


## Creates, reserves, and tracks a job; null when the move is impossible
## (wrong item, nothing to pick up, or no input space).
func create_job(item: StringName, pickup: Building, destination: Building) -> DeliveryJob:
	if not destination.accepts_item(item):
		return null
	var job := DeliveryJob.new(item, pickup, destination)
	if not job.reserve():
		return null
	_jobs.append(job)
	job_created.emit(job)
	return job


## Jobs waiting for a cat, oldest first.
func available_jobs() -> Array[DeliveryJob]:
	var result: Array[DeliveryJob] = []
	for job: DeliveryJob in _jobs:
		if job.status == DeliveryJob.Status.PENDING:
			result.append(job)
	return result


func active_jobs() -> Array[DeliveryJob]:
	return _jobs.duplicate()


## Finalizes a delivered job and stops tracking it.
func complete_job(job: DeliveryJob) -> void:
	job.complete()
	_jobs.erase(job)
	_last_delivered_at[_starvation_key(job.destination, job.item)] = _elapsed_seconds
	if lifetime_stats != null:
		lifetime_stats.record_delivery_completed()
	job_completed.emit(job)


## Abandons a job, releasing its reservations, and stops tracking it.
func cancel_job(job: DeliveryJob) -> void:
	job.cancel()
	_jobs.erase(job)
	job_cancelled.emit(job)


## All placed buildings, for future dispatch scans.
func buildings() -> Array[Building]:
	var result: Array[Building] = []
	for child: Node in buildings_root.get_children():
		var building: Building = child as Building
		if building != null:
			result.append(building)
	return result
