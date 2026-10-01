class_name CatSeparation
extends Node
## Keeps cats from standing inside each other. One node in
## `factory_world.tscn`; nudges cats apart every frame after they have
## moved.
##
## **Measured before building** (108 cats, 80 buildings, real save):
## ~16.7 cats — 15% of them — were visually overlapping someone at any
## given instant, **100% of sampled frames had at least one overlap**,
## and the closest approach was 0.00m, i.e. two cats exactly coincident.
## Roughly half the overlapping pairs were settled cats (IDLE dominated)
## sitting on each other; the rest were cats crossing in transit.
##
## **This is separation steering, not multi-agent pathfinding.** It does
## not stop two cats routing through the same corridor — it stops them
## occupying the same spot while they do. True avoidance (reservation
## tables, per-agent path replanning) is a far larger system, and the
## complaint is a visual one: cats overlapping, not cats taking bad
## routes. Separation is also the only option that leaves pathfinding,
## dispatch and the whole movement model untouched — cats are plain
## Node3Ds moved with `move_toward()`, with no physics bodies to lean on.
##
## **A spatial hash, not all-pairs.** Naive all-pairs over 108 cats
## measured 690us/frame *just for the distance checks* — 4.1% of a 16.6ms
## frame, before any separation maths, and O(n²) against a game that
## hands out an achievement for adopting 100 cats. Bucketing by
## `separation_radius` means each cat only tests the 3x3 buckets around
## it, which is O(n) in practice for any realistic spread.

## How close two cats have to be before they push apart, in metres. The
## drawn art is about 1.09m wide, so this is deliberately narrower than
## the sprite: pushing at full sprite width makes a crowd feel like it is
## repelling itself, and cats standing shoulder to shoulder reads fine.
@export_range(0.1, 2.0, 0.05) var separation_radius: float = 0.90
## Maximum push speed in metres per second. Well under Cat.move_speed
## (4.0) on purpose — a cat being nudged must still be able to out-walk
## the nudge toward its target, or it could never arrive.
##
## **Both defaults came from a sweep, not taste**, measured on the same
## 108-cat save: (radius, speed) of (0.75, 1.1) left 10.2 cats
## overlapping per frame, (0.75, 2.0) 9.8, (0.90, 2.0) 8.7, and
## (0.90, 3.0) got *worse* again at 9.3 — past a point the push
## overshoots and cats oscillate through each other. Deliveries completed
## over the same window were flat across every setting, including
## separation off, so none of this costs throughput.
@export_range(0.0, 4.0, 0.1) var separation_speed: float = 2.0
@export var cats_root: Node3D
## Used only to keep a nudged cat inside the factory. Optional, same
## graceful-if-unset convention as BuildingPlacer.factory_bounds.
@export var factory_bounds: FactoryBounds

## Runs after the cats have moved this frame. Higher priority = later,
## and Cat leaves its own at the default 0.
const _PROCESS_AFTER_CATS: int = 10

## Reused between frames so a busy factory isn't allocating a fresh
## dictionary of arrays 60 times a second.
var _buckets: Dictionary[Vector2i, Array] = {}
var _movable: Array[Cat] = []


func _ready() -> void:
	process_priority = _PROCESS_AFTER_CATS


func _process(delta: float) -> void:
	if cats_root == null:
		return
	_rebuild_buckets()
	for cat: Cat in _movable:
		var push: Vector2 = _push_for(cat)
		if push == Vector2.ZERO:
			continue
		var step: Vector2 = push.limit_length(1.0) * separation_speed * delta
		var moved := Vector3(cat.position.x + step.x, cat.position.y, cat.position.z + step.y)
		cat.position = _clamped(moved)


## Buckets every cat, and separately lists the ones that may be moved.
##
## **Stationed and held cats push but are never pushed.** A stationed cat
## is parked at its building's exact `station_offset` and its bounce/nap
## animation is anchored there, so shoving it off that spot looks worse
## than the overlap did; a held cat is following the cursor and belongs
## wherever the player is pointing. Both still occupy space, so they stay
## in the buckets and other cats route around them.
func _rebuild_buckets() -> void:
	for key: Vector2i in _buckets:
		_buckets[key].clear()
	_movable.clear()
	for child: Node in cats_root.get_children():
		var cat: Cat = child as Cat
		if cat == null:
			continue
		var key: Vector2i = _bucket_of(cat.position)
		if not _buckets.has(key):
			_buckets[key] = []
		_buckets[key].append(cat)
		if cat.is_anchored():
			continue
		_movable.append(cat)


func _bucket_of(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / separation_radius), floori(position.z / separation_radius))


func _push_for(cat: Cat) -> Vector2:
	var origin: Vector2i = _bucket_of(cat.position)
	var push := Vector2.ZERO
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			var bucket: Array = _buckets.get(origin + Vector2i(dx, dy), [])
			for other_node: Variant in bucket:
				var other: Cat = other_node
				if other == cat:
					continue
				var offset := Vector2(cat.position.x - other.position.x,
						cat.position.z - other.position.z)
				var distance: float = offset.length()
				if distance >= separation_radius:
					continue
				if distance < 0.001:
					# Exactly coincident, which really happens (the survey
					# measured a 0.00m approach). Pick a direction from the
					# pair's instance ids so the two cats push opposite ways
					# and stay that way, instead of both picking the same
					# arbitrary vector or jittering on a random one.
					var angle: float = float(cat.get_instance_id() % 628) * 0.01
					push += Vector2(cos(angle), sin(angle))
					continue
				# Linear falloff: strongest when fully overlapped, nothing
				# at the radius, so cats settle at a comfortable spacing
				# rather than bouncing off an edge.
				push += offset / distance * ((separation_radius - distance) / separation_radius)
	return push


func _clamped(position: Vector3) -> Vector3:
	if factory_bounds == null:
		return position
	var corner: Vector3 = factory_bounds.unlocked_world_corner()
	var size: Vector2 = factory_bounds.unlocked_world_size()
	return Vector3(
		clampf(position.x, corner.x, corner.x + size.x),
		position.y,
		clampf(position.z, corner.z, corner.z + size.y))
