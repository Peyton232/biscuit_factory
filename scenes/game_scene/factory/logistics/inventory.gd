class_name Inventory
extends RefCounted
## Item storage with reservation support for the delivery system.
## Counts are per item id (StringName, see .context/recipes.md).
##
## Reservations let delivery jobs promise items/space without moving
## anything yet, so no two jobs claim the same item or slot:
## - outgoing: an item in storage is claimed for a future pickup
## - incoming: a free slot is claimed for a future delivery
##
## Capacity 0 disables the inventory (e.g. a source's input side).

signal changed

var capacity: int = 0

var _items: Dictionary[StringName, int] = {}
var _reserved_incoming: Dictionary[StringName, int] = {}
var _reserved_outgoing: Dictionary[StringName, int] = {}


func _init(initial_capacity: int = 0) -> void:
	capacity = initial_capacity


func count(item: StringName) -> int:
	return _items.get(item, 0)


func total_count() -> int:
	var total: int = 0
	for amount: int in _items.values():
		total += amount
	return total


## Free slots, minus slots promised to inbound deliveries.
func space_left() -> int:
	var reserved: int = 0
	for amount: int in _reserved_incoming.values():
		reserved += amount
	return capacity - total_count() - reserved


## Slots promised to inbound deliveries of one specific item.
func reserved_incoming(item: StringName) -> int:
	return _reserved_incoming.get(item, 0)


## Items present and not already claimed by a pickup reservation.
func available_for_pickup(item: StringName) -> int:
	return count(item) - _reserved_outgoing.get(item, 0)


## Direct add (production). Fails when full; reserved slots stay safe.
func add(item: StringName, amount: int = 1) -> bool:
	if amount > space_left():
		return false
	_items[item] = count(item) + amount
	changed.emit()
	return true


## Direct remove (consumption). Never touches reserved items.
func remove(item: StringName, amount: int = 1) -> bool:
	if amount > available_for_pickup(item):
		return false
	_items[item] = count(item) - amount
	changed.emit()
	return true


func reserve_outgoing(item: StringName) -> bool:
	if available_for_pickup(item) < 1:
		return false
	_reserved_outgoing[item] = _reserved_outgoing.get(item, 0) + 1
	return true


func release_outgoing(item: StringName) -> void:
	assert(_reserved_outgoing.get(item, 0) > 0, "No outgoing reservation to release.")
	_reserved_outgoing[item] = _reserved_outgoing[item] - 1


## Removes a previously reserved item (a pickup happening).
func take_reserved(item: StringName) -> void:
	release_outgoing(item)
	_items[item] = count(item) - 1
	changed.emit()


func reserve_incoming(item: StringName) -> bool:
	if space_left() < 1:
		return false
	_reserved_incoming[item] = reserved_incoming(item) + 1
	return true


func release_incoming(item: StringName) -> void:
	assert(reserved_incoming(item) > 0, "No incoming reservation to release.")
	_reserved_incoming[item] = _reserved_incoming[item] - 1


## Adds an item into a previously reserved slot (a delivery arriving).
func deposit_reserved(item: StringName) -> void:
	release_incoming(item)
	_items[item] = count(item) + 1
	changed.emit()


## Drops all stored items (reservations are untouched). Used when a
## station's recipe is reassigned and its held ingredients no longer
## apply to anything.
func clear() -> void:
	_items.clear()
	changed.emit()


## Snapshot of stored (non-reserved) counts, for save/load. Reservations
## are deliberately excluded — they're tied to live DeliveryJobs, which
## don't survive a save/load round-trip (see FactorySaveData's class doc).
func save_items() -> Dictionary[StringName, int]:
	return _items.duplicate()


## Restores stored counts directly, bypassing capacity/reservation
## checks — used only during save/load reconstruction, before any
## DeliveryJob has had a chance to reserve anything against this
## inventory yet.
func load_items(items: Dictionary[StringName, int]) -> void:
	_items = items.duplicate()
	changed.emit()
