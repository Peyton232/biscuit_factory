class_name Cat
extends Node3D
## A cat that either delivers items between buildings (role DELIVERY) or
## staffs a processing building (role MIXER/OVEN/CUTTER/ASSEMBLER — one
## per station type: Mixer/Oven/Cutting Station/Assembly Table, see
## recipes.md), enabling it to work. The player can rename a cat, change
## its role, or pick it up and drop it elsewhere at any time.
##
## Delivery: idles until the DeliveryManager has a job, walks the hovered
## building's grid path to the pickup, carries the item to the
## destination, and returns to idling. Station roles: idles until an
## unstaffed matching building exists, walks there, and "stations" itself
## (motionless) so the building's own processing logic can run. Cats
## always claim the nearest available job/station to their own position,
## so moving a cat changes what it prefers to do next.
##
## AI/manager separation: the cat only calls available_jobs()/
## complete_job()/cancel_job() on the DeliveryManager, buildings() to
## search for stations, and transitions on its own job. It never touches
## building inventories directly, and never processes on a station's
## behalf — ProcessingBuilding does its own work, gated on station_cat
## AND cat_arrived (claiming a station while still walking there must
## not start the work — only physically arriving does).

enum Role { DELIVERY, MIXER, OVEN, CUTTER, ASSEMBLER }

enum State { IDLE, TO_PICKUP, TO_DESTINATION, TO_STATION, STATIONED, UPSET, HELD, WANDER }

## Fur color variants, applied as a multiply tint on the sprite sheet's
## natural orange tabby coloring via Sprite3D.modulate (there's no
## separate hand-drawn art per color) — CatShop picks one at random per
## adoption via set_fur_color(). Index 0 is the untinted default.
const FUR_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(0.55, 0.55, 0.58),
	Color(0.95, 0.9, 0.78),
	Color(0.22, 0.2, 0.22),
	Color(0.55, 0.38, 0.22),
]

## Visual's own designed rest height (cat.tscn's Visual.position.y) — the
## station-bounce animation offsets from this, the same "modify _visual.
## position, reset to the resting value when done" idiom _shake() already
## uses for its own transient offset on the X axis.
const _VISUAL_REST_Y: float = 0.05

## CarriedItem's designed pixel_size (cat.tscn) before any per-item
## correction from ItemVisuals.scale_for() — the same Sprite3D is reused
## across every item a Cat ever carries, so this can't just be left at
## the .tscn's fixed value the way a single-purpose Visual node can.
const _CARRIED_ITEM_BASE_PIXEL_SIZE: float = 0.03

## World-space height (meters, above CarriedItem's own ground anchor)
## its *center* should sit at, regardless of which item it's showing —
## cat.tscn's original fixed `offset = Vector2(0, 30)` at the base
## pixel_size above (30 * 0.03), preserved here as a named constant
## instead of a magic number now that offset has to be recomputed per
## item (see _show_carried_item()).
const _CARRIED_ITEM_HAND_HEIGHT_METERS: float = 0.9

@export var delivery_manager: DeliveryManager
@export var grid_manager: GridManager
## Walking speed in meters per second.
@export var move_speed: float = 4.0
## How close to a building's center counts as arrived.
@export var interaction_distance: float = 1.3
## How close to an intermediate path waypoint counts as reached.
@export var waypoint_tolerance: float = 0.4
## Seconds between job/station checks while idle.
@export var idle_poll_interval: float = 0.4
## How long the cat shakes when a job or station falls through.
@export var upset_duration: float = 0.7
## Offset from a station building's position while stationed, so the cat
## doesn't render exactly on top of the building sprite. Negative X/Z
## parks the cat at the building's top-left, screen-wise (camera never
## yaws, so world -X/-Z consistently reads as screen left/up).
@export var station_offset: Vector3 = Vector3(-0.8, 0.0, -0.8)
## How long a station must have nothing to do before a stationed cat
## looks for a different one to wander to.
@export var station_wander_delay: float = 3.0
## Sprite sheet walk cycle: frames advanced per second while walking.
@export var walk_frame_rate: float = 8.0
## How high a stationed cat bobs up and down, in meters. Purely cosmetic
## idle motion so a parked cat doesn't read as a frozen prop.
@export var station_bounce_height: float = 0.05
## Bounce cycles per second while stationed.
@export var station_bounce_speed: float = 1.6

@export_group("Wander")
## How far from its idle spot a cat wanders, in meters. Keeps it milling
## around nearby rather than roaming the whole factory.
@export var wander_radius: float = 5.0
## Shortest/longest time (seconds) a cat stands still before wandering
## again; randomized per cat so a group of idle cats doesn't move in sync.
@export var wander_delay_min: float = 3.0
@export var wander_delay_max: float = 8.0

## Initial name/role. Set via set_cat_name()/set_role() at runtime so the
## floating label and any station assignment stay in sync.
@export var cat_name: String = "Cat"
@export var role: Role = Role.DELIVERY

var _state: State = State.IDLE
var _job: DeliveryJob = null
var _station: ProcessingBuilding = null
var _path: Array[Vector3] = []
var _path_index: int = 0
var _poll_timer: float = 0.0
var _upset_timer: float = 0.0
var _station_idle_timer: float = 0.0
var _anim_timer: float = 0.0
var _station_bounce_timer: float = 0.0
## World position the cat last had actual work finish at; wander targets
## are picked near this, not near wherever the previous wander leg ended,
## so repeated wandering can't cumulatively drift the cat far away.
var _idle_anchor: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
## Index into FUR_COLORS, set by set_fur_color() — stored (not just
## applied to the sprite) so save_entry() can read back which tint this
## cat has, since Sprite3D.modulate itself has no reverse lookup back to
## an index.
var fur_color_index: int = 0

## Lifetime stats, tracked purely for the end-of-game Employee Awards
## (see EmployeeAwards) — never reset mid-game, persisted across save/
## load via save_entry()/load_lifetime_stats(). Each one backs a
## specific award: total_deliveries_completed/total_delivery_seconds ->
## Employee of the Month/Fastest Delivery Cat, station_batches_completed
## -> Master Baker/Most <Role> Jobs, total_busy_seconds/
## total_idle_seconds -> Workaholic/Professional Napper,
## total_distance_meters -> Explorer, roles_held -> Jack of All Trades.
var total_deliveries_completed: int = 0
var total_delivery_seconds: float = 0.0
var total_busy_seconds: float = 0.0
var total_idle_seconds: float = 0.0
var total_distance_meters: float = 0.0
## Completed batches per station role this cat has ever staffed — a flat
## per-role count, not just a total, so both Master Baker (sum) and
## "Most <Role> Jobs" (one entry) read from the same data. Only
## MIXER/OVEN/CUTTER/ASSEMBLER keys are ever populated (see
## ProcessingBuilding._try_finish()); DELIVERY never appears here.
var station_batches_completed: Dictionary[Role, int] = {}
## Every distinct role this cat has ever been assigned, including its
## starting one — a Set (values unused, only key presence matters), same
## idiom this codebase already uses elsewhere for "is this present at
## all" dictionaries (e.g. FactoryBounds/TierManager's gating maps).
var roles_held: Dictionary[Role, bool] = {}

## Running accumulator for the delivery currently in progress (TO_PICKUP
## + TO_DESTINATION only) — folded into total_delivery_seconds/
## total_deliveries_completed on a successful drop-off, reset to 0 the
## moment a new delivery job is claimed. Not itself part of the
## award-facing stats above.
var _current_delivery_seconds: float = 0.0

@onready var _visual: Sprite3D = $Visual
@onready var _carried_item: Sprite3D = $CarriedItem
@onready var _name_label: Label3D = $NameLabel


func _ready() -> void:
	_update_name_label()
	_idle_anchor = position
	_wander_timer = randf_range(wander_delay_min, wander_delay_max)
	roles_held[role] = true


func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			_look_for_work(delta)
		State.TO_PICKUP:
			if _follow_path(delta):
				_arrive_at_pickup()
		State.TO_DESTINATION:
			if _follow_path(delta):
				_arrive_at_destination()
		State.TO_STATION:
			if _follow_path(delta):
				_arrive_at_station()
		State.STATIONED:
			_tend_station(delta)
		State.HELD:
			pass
		State.UPSET:
			_shake(delta)
		State.WANDER:
			_tend_wander(delta)
	_update_walk_animation(delta)
	_update_station_bounce(delta)
	_update_lifetime_timers(delta)


## Buckets every frame into total_busy_seconds or total_idle_seconds by
## current state — see the class doc above for which award each one
## feeds. HELD (player dragging the cat) and UPSET (job/station fell
## through mid-walk) count as neither work nor leisure, so both are
## excluded rather than lumped into one bucket or the other.
func _update_lifetime_timers(delta: float) -> void:
	match _state:
		State.IDLE, State.WANDER:
			total_idle_seconds += delta
		State.TO_PICKUP, State.TO_DESTINATION, State.TO_STATION, State.STATIONED:
			total_busy_seconds += delta
	if _state == State.TO_PICKUP or _state == State.TO_DESTINATION:
		_current_delivery_seconds += delta


## Loops the sprite sheet's walk cycle while actually walking toward
## something; holds on the first frame otherwise (idle, stationed, held,
## shaking) so the cat doesn't appear to "walk in place".
func _update_walk_animation(delta: float) -> void:
	var walking: bool = _state == State.TO_PICKUP or _state == State.TO_DESTINATION \
			or _state == State.TO_STATION or _state == State.WANDER
	if not walking:
		_anim_timer = 0.0
		_visual.frame = 0
		return
	_anim_timer += delta
	var frame_duration: float = 1.0 / walk_frame_rate
	if _anim_timer >= frame_duration:
		_anim_timer -= frame_duration
		_visual.frame = (_visual.frame + 1) % _visual.hframes


## Gentle up/down bob while the station is actively working (its
## progress bar visibly moving — same progress() > 0 condition
## BuildingProgressBar itself uses to decide whether to show at all),
## not just whenever a cat happens to be parked there — purely cosmetic,
## so a bored cat waiting on ingredients doesn't bounce like it's busy.
## Resets to the sprite's own resting height whenever not actively
## bouncing, same "offset while active, snap back to rest when not"
## idiom _shake() uses for its own transient X offset.
func _update_station_bounce(delta: float) -> void:
	if _state != State.STATIONED or _station == null or _station.progress() <= 0.0:
		_station_bounce_timer = 0.0
		_visual.position.y = _VISUAL_REST_Y
		return
	_station_bounce_timer += delta
	var lift: float = (sin(_station_bounce_timer * station_bounce_speed * TAU) + 1.0) * 0.5
	_visual.position.y = _VISUAL_REST_Y + lift * station_bounce_height


## Tints the sprite to one of FUR_COLORS. Index is clamped/wrapped so
## callers can pass any int (e.g. a fresh randi() % N isn't required).
func set_fur_color(color_index: int) -> void:
	fur_color_index = color_index % FUR_COLORS.size()
	_visual.modulate = FUR_COLORS[fur_color_index]


## Renames the cat; visible on its floating name label immediately.
func set_cat_name(new_name: String) -> void:
	cat_name = new_name
	_update_name_label()


## Switches role, abandoning any current job/station assignment first.
func set_role(new_role: Role) -> void:
	if new_role == role:
		return
	_abandon_current_work()
	role = new_role
	roles_held[new_role] = true
	_update_name_label()
	_enter_idle()


## Called by CatSelector when the player picks this cat up. Drops any
## work in progress; the cat floats with the cursor until dropped.
func begin_held() -> void:
	_abandon_current_work()
	_state = State.HELD


## Called by CatSelector when the player drops a held cat back down.
## Always settles at ground level, regardless of the Y given (the cat
## floats above the ground while held).
func end_held(world_position: Vector3) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_enter_idle()


## Scripted straight-line walk to target_position, reusing WANDER's own
## path-follow + the shared _process() animation/facing updates (both
## keyed off _state, not a separate code path) — used only by the
## opening cutscene's "cat walks onto screen" beat. Bypasses grid
## pathfinding (a straight line off-screen has nothing to route around)
## and the job/station AI entirely; safe this early since a brand-new
## game has no buildings yet for _tend_wander()'s own job/station poll
## to find. The cat settles into ordinary IDLE (and starts really
## looking for work) the instant it arrives, exactly like a real wander
## leg ending.
func walk_to(target_position: Vector3) -> void:
	_path = [target_position]
	_path_index = 0
	_state = State.WANDER


## Whether this cat is currently parked at (and staffing) a station.
## CatSelector uses this to shrink its click pick radius for stationed
## cats specifically — see its own doc comment for why.
func is_stationed() -> bool:
	return _state == State.STATIONED


## Whether this cat is genuinely free (not already working toward/at a
## job or station, not being held, not shaking off a failed one).
## DeliveryManager's dispatch uses this to find idle DELIVERY cats near a
## pickup — see its "weigh closer cats" scoring. WANDER doesn't count:
## a wandering cat is still just ambient idle motion (it breaks off
## immediately for real work, see _tend_wander()) and is exactly as
## available as one standing still.
func is_idle() -> bool:
	return _state == State.IDLE or _state == State.WANDER


## This cat's save-relevant state — see CatSaveEntry/CatShop.restore_cat().
## Current job/station/path are deliberately excluded (see
## FactorySaveData's class doc); a restored cat always comes back IDLE at
## its saved position and re-acquires work on its own next poll.
func save_entry() -> CatSaveEntry:
	var entry := CatSaveEntry.new()
	entry.cat_name = cat_name
	entry.role = role
	entry.position = position
	entry.fur_color_index = fur_color_index
	entry.total_deliveries_completed = total_deliveries_completed
	entry.total_delivery_seconds = total_delivery_seconds
	entry.total_busy_seconds = total_busy_seconds
	entry.total_idle_seconds = total_idle_seconds
	entry.total_distance_meters = total_distance_meters
	for held_role: Role in roles_held:
		entry.roles_held.append(held_role)
	for batch_role: Role in station_batches_completed:
		entry.station_batches_completed[batch_role] = station_batches_completed[batch_role]
	return entry


## Restores the Employee Awards stats save_entry() captures above — kept
## separate from a generic load_entry() (unlike Building) since Cat's
## restore path (CatShop.restore_cat()) already calls granular setters
## per piece of state (set_cat_name/set_role/set_fur_color) rather than
## one combined loader; this just adds one more call in that same style.
func load_lifetime_stats(entry: CatSaveEntry) -> void:
	total_deliveries_completed = entry.total_deliveries_completed
	total_delivery_seconds = entry.total_delivery_seconds
	total_busy_seconds = entry.total_busy_seconds
	total_idle_seconds = entry.total_idle_seconds
	total_distance_meters = entry.total_distance_meters
	for held_role: int in entry.roles_held:
		roles_held[held_role as Role] = true
	for batch_role: int in entry.station_batches_completed:
		station_batches_completed[batch_role as Role] = entry.station_batches_completed[batch_role]


## Called by ProcessingBuilding._try_finish() on the cat currently
## staffing it, once per completed batch — feeds Master Baker (sum
## across every role) and the per-role "Most <Role> Jobs" awards.
func record_batch_completed(for_role: Role) -> void:
	station_batches_completed[for_role] = station_batches_completed.get(for_role, 0) + 1


## The one place a cat re-enters IDLE with genuinely nothing to do (job
## completed, upset shake finished, dropped by the player, or reassigned) —
## resets the wander anchor to here so future wandering stays tethered to
## wherever the cat actually finished its last task, not to the last
## wander leg's endpoint.
func _enter_idle() -> void:
	_state = State.IDLE
	_poll_timer = 0.0
	_idle_anchor = position
	_wander_timer = randf_range(wander_delay_min, wander_delay_max)


func _abandon_current_work() -> void:
	if _job != null:
		delivery_manager.cancel_job(_job)
		_job = null
	if _carried_item.visible:
		_drop_item_on_ground()
	if _station != null:
		_station.station_cat = null
		_station.cat_arrived = false
		_station = null
	_path = []


## Called by a ProcessingBuilding when it's demolished out from under a
## cat that was heading to or standing at it.
func notify_station_removed() -> void:
	_station = null
	if _state == State.TO_STATION or _state == State.STATIONED:
		_become_upset()


func _look_for_work(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = idle_poll_interval
		if role == Role.DELIVERY:
			_look_for_delivery_job()
		else:
			_look_for_station()
		if _state != State.IDLE:
			return
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_begin_wander()


func _look_for_delivery_job() -> void:
	var jobs: Array[DeliveryJob] = delivery_manager.available_jobs()
	if jobs.is_empty():
		return
	var nearest: DeliveryJob = jobs[0]
	var nearest_dist: float = position.distance_to(nearest.pickup.position)
	for job: DeliveryJob in jobs:
		var dist: float = position.distance_to(job.pickup.position)
		if dist < nearest_dist:
			nearest = job
			nearest_dist = dist
	_job = nearest
	_job.assign(self)
	_current_delivery_seconds = 0.0
	_begin_path_to(_job.pickup)
	_state = State.TO_PICKUP


func _look_for_station() -> void:
	var target: ProcessingBuilding = _find_nearest_unstaffed_station()
	if target == null:
		return
	_station = target
	# Claim immediately (before walking there) so a second cat polling
	# later this same frame won't also target it.
	target.station_cat = self
	_begin_path_to_station(target)
	_state = State.TO_STATION


## Nearest unstaffed matching-role station. When require_pending_work is
## true, only stations with has_pending_work() count — used when
## wandering away from an already-staffed station, so a cat only leaves
## for somewhere strictly better, not just any other empty spot.
func _find_nearest_unstaffed_station(require_pending_work: bool = false) -> ProcessingBuilding:
	var best: ProcessingBuilding = null
	var best_dist: float = INF
	for building: Building in delivery_manager.buildings():
		var candidate: ProcessingBuilding = building as ProcessingBuilding
		if candidate == null or candidate.required_role != role or candidate.station_cat != null:
			continue
		if require_pending_work and not candidate.has_pending_work():
			continue
		var dist: float = position.distance_to(candidate.position)
		if dist < best_dist:
			best = candidate
			best_dist = dist
	return best


func _arrive_at_pickup() -> void:
	if _job.status != DeliveryJob.Status.ASSIGNED:
		# Job died while we walked (e.g. a building was demolished).
		_become_upset()
		return
	_job.mark_picked_up()
	_show_carried_item(_job.item)
	_begin_path_to(_job.destination)
	_state = State.TO_DESTINATION


func _arrive_at_destination() -> void:
	if _job.status != DeliveryJob.Status.IN_TRANSIT:
		_become_upset()
		return
	delivery_manager.complete_job(_job)
	_job = null
	_carried_item.visible = false
	total_deliveries_completed += 1
	total_delivery_seconds += _current_delivery_seconds
	_enter_idle()


func _arrive_at_station() -> void:
	if _station == null or _station.station_cat != self:
		_become_upset()
		return
	position = _station.position + station_offset
	_visual.flip_h = true
	_station.cat_arrived = true
	_station_idle_timer = 0.0
	_state = State.STATIONED


## While stationed, wander to a different unstaffed matching station once
## this one has had nothing to do for station_wander_delay seconds — but
## only if that other station actually has work waiting; a cat never
## trades one idle station for another equally idle one, and never
## abandons a station that's just waiting for its output to be
## collected (has_pending_work() counts that as work).
func _tend_station(delta: float) -> void:
	if _station.has_pending_work():
		_station_idle_timer = 0.0
		return
	_station_idle_timer += delta
	if _station_idle_timer < station_wander_delay:
		return
	_station_idle_timer = 0.0
	var better: ProcessingBuilding = _find_nearest_unstaffed_station(true)
	if better == null:
		return
	_station.station_cat = null
	_station.cat_arrived = false
	_station = better
	better.station_cat = self
	_begin_path_to_station(better)
	_state = State.TO_STATION


## Sets off toward a random nearby point (see _pick_wander_cell()) so idle
## cats aren't left standing in one spot, potentially blocking a doorway.
## A no-op (stays IDLE, tries again next cycle) if the picked spot turns
## out to basically be where the cat already is.
func _begin_wander() -> void:
	_wander_timer = randf_range(wander_delay_min, wander_delay_max)
	var target_point: Vector3 = grid_manager.grid_to_world(_pick_wander_cell())
	if target_point.distance_to(position) < grid_manager.cell_size:
		return
	_path = grid_manager.find_path_to_point(position, target_point)
	_path_index = 0
	_state = State.WANDER


## While wandering, still polls for real work exactly like IDLE does — a
## cat that stumbles into wander distance of a job/station breaks off to
## do it immediately rather than finishing its stroll first.
func _tend_wander(delta: float) -> void:
	_poll_timer -= delta
	if _poll_timer <= 0.0:
		_poll_timer = idle_poll_interval
		if role == Role.DELIVERY:
			_look_for_delivery_job()
		else:
			_look_for_station()
		if _state != State.WANDER:
			return
	if _follow_path(delta):
		_state = State.IDLE
		_wander_timer = randf_range(wander_delay_min, wander_delay_max)


## A random in-bounds, unoccupied cell within wander_radius of the idle
## anchor (not the cat's current position — see _idle_anchor). Retries a
## few times against occupied/out-of-bounds cells before giving up and
## returning the anchor cell itself (making _begin_wander() a harmless
## no-op for that cycle) rather than looping until it finds one.
func _pick_wander_cell() -> Vector2i:
	var anchor_cell: Vector2i = grid_manager.world_to_grid(_idle_anchor)
	var radius_cells: int = maxi(1, int(wander_radius / grid_manager.cell_size))
	for attempt: int in 8:
		var offset := Vector2i(
			randi_range(-radius_cells, radius_cells), randi_range(-radius_cells, radius_cells)
		)
		var candidate: Vector2i = anchor_cell + offset
		if grid_manager.is_in_bounds(candidate) and not grid_manager.is_cell_occupied(candidate):
			return candidate
	return anchor_cell


func _begin_path_to(building: Building) -> void:
	_path = grid_manager.find_approach_path(position, building)
	_path_index = 0


## Same as _begin_path_to(), but for TO_STATION specifically: appends the
## exact parked spot (station.position + station_offset) as one more
## waypoint past the building-approach leg, so the cat walks all the way
## there instead of stopping near the building's center and having
## _arrive_at_station() teleport it the rest of the way. That teleport
## could be over a meter (station_offset's own length, up to
## interaction_distance more slack on top) in whatever direction the cat
## happened to approach from — visible as overshooting the station, then
## snapping back to the parked spot. Walking the real distance removes
## the snap; _arrive_at_station() still force-sets position on arrival,
## now just as a sub-tolerance correction rather than a real jump.
func _begin_path_to_station(station: ProcessingBuilding) -> void:
	_begin_path_to(station)
	_path.append(station.position + station_offset)


## Walks the cached path leg by leg; true once the final waypoint
## (the target building itself) is reached within interaction_distance.
func _follow_path(delta: float) -> bool:
	if _path.is_empty():
		return true
	var is_last: bool = _path_index == _path.size() - 1
	var target: Vector3 = _path[_path_index]
	target.y = position.y
	var previous_position: Vector3 = position
	position = position.move_toward(target, move_speed * delta)
	total_distance_meters += previous_position.distance_to(position)
	_update_facing(position.x - previous_position.x)
	var tolerance: float = interaction_distance if is_last else waypoint_tolerance
	if position.distance_to(target) > tolerance:
		return false
	if is_last:
		return true
	_path_index += 1
	return false


## The sprite art faces left by default; flip it to face right while
## actually moving rightward so the cat doesn't walk backwards on
## screen. Holds the last facing when movement is purely along Z (no
## meaningful X change) instead of flickering back to the default.
## CarriedItem is deliberately NOT flipped along with it — item icons
## have readable text baked in (e.g. "FLOUR"), and mirroring that text
## would make it backwards exactly when the cat walks right.
func _update_facing(delta_x: float) -> void:
	if absf(delta_x) < 0.001:
		return
	_visual.flip_h = delta_x > 0.0


func _become_upset() -> void:
	_upset_timer = upset_duration
	_state = State.UPSET


func _shake(delta: float) -> void:
	_upset_timer -= delta
	_visual.position.x = sin(_upset_timer * 45.0) * 0.07
	if _upset_timer > 0.0:
		return
	_visual.position.x = 0.0
	if _carried_item.visible:
		_drop_item_on_ground()
	_job = null
	_enter_idle()


## Leaves the carried item's sprite on the floor, fading away.
func _drop_item_on_ground() -> void:
	var dropped := Sprite3D.new()
	dropped.texture = _carried_item.texture
	dropped.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	dropped.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	dropped.pixel_size = _carried_item.pixel_size
	get_parent().add_child(dropped)
	dropped.global_position = global_position + Vector3(0.4, 0.35, 0.4)
	var tween: Tween = dropped.create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(dropped, "modulate:a", 0.0, 1.5)
	tween.tween_callback(dropped.queue_free)
	_carried_item.visible = false


func _show_carried_item(item: StringName) -> void:
	var texture_path: String = "res://assets/sprites/items/%s.png" % item
	if ResourceLoader.exists(texture_path):
		_carried_item.texture = load(texture_path)
		_carried_item.pixel_size = _CARRIED_ITEM_BASE_PIXEL_SIZE * ItemVisuals.scale_for(item)
		# offset is in raw texture pixels, scaled by pixel_size like
		# everything else here — dividing the constant *world* hand
		# height by this item's own (possibly ItemVisuals-shrunk)
		# pixel_size cancels that scale back out, so every item's
		# center still lands at the same real-world hand height instead
		# of drooping toward the ground the smaller its own correction is.
		_carried_item.offset = Vector2(0, _CARRIED_ITEM_HAND_HEIGHT_METERS / _carried_item.pixel_size)
		_carried_item.visible = true
	else:
		push_warning("No item sprite for '%s'." % item)


func _update_name_label() -> void:
	_name_label.text = "%s\n(%s)" % [cat_name, Role.keys()[role].capitalize()]
