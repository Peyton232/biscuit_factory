class_name ShippingBin
extends Building
## Ships out delivered items on a timer, paying the player per item.
## Prices live here for now; they move to proper item data once items
## need more than a price (icons, names, unlock state).
##
## **Which items this specific bin instance accepts is player-configurable
## at runtime**, via BuildingInspectorPanel's per-item toggle (click the
## bin to select it, then check/uncheck items) — see set_accepted().
## Defaults to every *currently tier-unlocked* item in sell_prices (not
## the full menu — a bin only ever offers items whose own tier has been
## reached, per progression.md; `tier_manager` is injected by
## BuildingPlacer, same as `economy`/`lifetime_stats`). As new tiers
## unlock, `_on_tier_advanced()` adds each newly-available item to
## already-placed bins too, defaulting it to accepted — existing
## toggles on already-unlocked items are left untouched. Turning an item
## off doesn't just stop it from selling —
## current_inputs() (which DeliveryManager's dispatch scan reads via
## wants_item()) excludes it too, so deliveries route to a *different*
## accepting building instead once this bin stops accepting something —
## useful once an item is both sellable AND a recipe ingredient elsewhere
## (e.g. Whipped Cream: sell it here, or turn it off on this bin so it
## all goes to a Decorating Table for Cream Cake/Pavlova/Cream Pie).

## Seconds between shipped items.
@export var ship_interval: float = 2.0
## Payout per item id. Items missing from this table ship for free.
## Also the full set of items this bin type is ever able to accept —
## _accepted (below) is a per-instance subset of these keys.
@export var sell_prices: Dictionary[StringName, int] = {&"biscuit": 5}
## "Lid open" sprite, shown briefly (_OPEN_DURATION) each time an item
## ships, then swapped back to the resting definition.icon ("closed") —
## same "swap Visual.texture, revert on a condition" idiom Oven/PrepTable/
## DecoratingTable all use, just timer-driven instead of state-driven
## since a single shipment is instantaneous, not a duration to track.
@export var texture_open: Texture2D

## Injected by the BuildingPlacer when the bin is placed.
var economy: Economy
## Injected by the BuildingPlacer alongside economy, above.
var lifetime_stats: LifetimeStats
## Injected by the BuildingPlacer alongside economy, above.
var tier_manager: TierManager

## item -> whether THIS bin instance currently accepts it. Defaults to
## true for every currently tier-unlocked sell_prices key in _ready(),
## then grows (new keys default true) as tiers unlock — see
## _on_tier_advanced().
var _accepted: Dictionary[StringName, bool] = {}

var _timer: float = 0.0
## Counts down while the "open" sprite is showing; reverts to closed at 0.
var _open_timer: float = 0.0

const _MONEY_COLOR := Color(1.0, 0.84, 0.35)
const _OPEN_DURATION: float = 0.2
const _SELL_SOUND: AudioStream = preload("res://assets/sounds/effects/sell.wav")

@onready var _visual: Sprite3D = $Visual


func _ready() -> void:
	super._ready()
	for item: StringName in sell_prices:
		if tier_manager == null or tier_manager.is_item_unlocked(item):
			_accepted[item] = true
	if tier_manager != null:
		tier_manager.tier_advanced.connect(_on_tier_advanced)


## Items this bin type can sell that have unlocked by tier so far —
## the actual menu shown to the player (BuildingInspectorPanel), as
## opposed to sell_prices, which is the type's full possible menu across
## every tier.
func unlocked_items() -> Array[StringName]:
	var items: Array[StringName] = []
	for item: StringName in sell_prices:
		if tier_manager == null or tier_manager.is_item_unlocked(item):
			items.append(item)
	return items


## Adds any newly-unlocked sell_prices item to this already-placed bin,
## defaulting it to accepted — items already present (and however the
## player has toggled them) are left untouched.
func _on_tier_advanced(_new_tier: int) -> void:
	for item: StringName in sell_prices:
		if not _accepted.has(item) and tier_manager.is_item_unlocked(item):
			_accepted[item] = true


## Items this bin instance currently accepts (a runtime-configurable
## subset of sell_prices' keys) — overrides Building.current_inputs(),
## which would otherwise read the static definition.inputs list.
func current_inputs() -> Array[StringName]:
	var accepted: Array[StringName] = []
	for item: StringName in sell_prices:
		if _accepted.get(item, false):
			accepted.append(item)
	return accepted


func is_accepted(item: StringName) -> bool:
	return _accepted.get(item, false)


## Toggles whether this bin instance accepts the given item. No-op for an
## item outside sell_prices — there's nothing to toggle for an item this
## bin type could never sell in the first place.
func set_accepted(item: StringName, enabled: bool) -> void:
	if not sell_prices.has(item):
		return
	_accepted[item] = enabled


## Select All / Deselect All QOL shortcut for BuildingInspectorPanel —
## sets every currently tier-unlocked item to the same accepted state in
## one call, rather than the player toggling each checkbox individually.
func set_all_accepted(enabled: bool) -> void:
	for item: StringName in unlocked_items():
		_accepted[item] = enabled


## Adds this bin instance's per-item accepted overrides on top of
## Building's common save entry.
func save_entry() -> BuildingSaveEntry:
	var entry: BuildingSaveEntry = super.save_entry()
	for item: StringName in _accepted:
		entry.accepted_items[String(item)] = _accepted[item]
	return entry


## Restores accepted-item overrides, fully replacing whatever _ready()
## already seeded from the current tier's defaults (this runs after
## add_child(), so _ready() has already populated _accepted once).
func load_entry(entry: BuildingSaveEntry) -> void:
	super.load_entry(entry)
	_accepted.clear()
	for item: String in entry.accepted_items:
		_accepted[StringName(item)] = entry.accepted_items[item]


func _process(delta: float) -> void:
	if _open_timer > 0.0:
		_open_timer -= delta
		if _open_timer <= 0.0:
			_set_visual_texture(definition.icon)
	_timer += delta
	if _timer < ship_interval:
		return
	# **Only ships currently-accepted items (✅ fixed — reported as "a
	# player deselected Whipped Cream but it still got shipped")** — used
	# to scan every sell_prices item regardless of _accepted, so it could
	# still sell an item the player had just unchecked, either because it
	# was already sitting in the inventory before the toggle or because a
	# delivery already in flight at toggle time (wants_item() caps each
	# input at 1, so this is at most a single stray unit — see Building.
	# wants_item()) landed moments later. That old behavior was meant to
	# avoid stranding pre-existing stock, but "the checkbox says off and
	# it sold anyway" reads as broken to a player, not as a kindness — an
	# already-there deselected item now just waits, unshipped, until
	# re-accepted (or Select All).
	for item: StringName in sell_prices:
		if not is_accepted(item):
			continue
		if input_inventory.remove(item):
			_ship(item)
			_timer = 0.0
			return
	# Nothing to ship; stay primed so the next arrival leaves promptly.
	_timer = ship_interval


func _ship(item: StringName) -> void:
	_set_visual_texture(texture_open)
	_open_timer = _OPEN_DURATION
	Sfx.spawn(self, _SELL_SOUND)
	var price: int = sell_prices.get(item, 0)
	if lifetime_stats != null:
		lifetime_stats.record_shipped(item, price)
	if economy != null and price > 0:
		economy.earn(price)
		FloatingText.spawn(self, global_position + Vector3.UP * 2.1,
				"+$%d" % price, _MONEY_COLOR)
	else:
		FloatingText.spawn(self, global_position + Vector3.UP * 2.1, "shipped")


## Sets Visual's texture and recomputes offset.y (half the new texture's
## own native pixel height, the bottom-edge-anchor convention every
## building's Visual follows) — open/closed art aren't the same pixel
## height, so leaving offset fixed across the swap would make the sprite
## appear to float or sink.
func _set_visual_texture(texture: Texture2D) -> void:
	_visual.texture = texture
	_visual.offset = Vector2(0, texture.get_height() / 2.0)
