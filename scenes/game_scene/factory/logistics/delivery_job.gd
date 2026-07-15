class_name DeliveryJob
extends RefCounted
## One planned movement of a single item from one building's output
## inventory to another building's input inventory. Data plus state
## transitions — created, tracked, and removed by the DeliveryManager.
##
## Reservations are taken when the job is created and resolved as the job
## progresses, so no two jobs ever claim the same item or slot. Cats
## drive the transitions: assign() when a cat takes the job,
## mark_picked_up() at the pickup building, then the manager's
## complete_job() at the destination.

enum Status {
	PENDING,     ## Created, waiting for a cat.
	ASSIGNED,    ## A cat claimed the job and is heading to the pickup.
	IN_TRANSIT,  ## The item is in the cat's paws.
	COMPLETED,   ## Delivered.
	CANCELLED,   ## Abandoned; reservations released.
}

var item: StringName
var pickup: Building
var destination: Building
var assigned_cat: Cat = null
var status: Status = Status.PENDING

# Reservation state: which promises this job currently holds.
var _holds_pickup_reservation: bool = false
var _holds_delivery_reservation: bool = false


func _init(job_item: StringName, pickup_building: Building, destination_building: Building) -> void:
	item = job_item
	pickup = pickup_building
	destination = destination_building


## Claims the item at the pickup and a slot at the destination.
## All-or-nothing; returns false (holding nothing) when either fails.
func reserve() -> bool:
	if not pickup.output_inventory.reserve_outgoing(item):
		return false
	if not destination.input_inventory.reserve_incoming(item):
		pickup.output_inventory.release_outgoing(item)
		return false
	_holds_pickup_reservation = true
	_holds_delivery_reservation = true
	return true


func is_reserved() -> bool:
	return _holds_pickup_reservation or _holds_delivery_reservation


func assign(cat: Cat) -> void:
	assert(status == Status.PENDING, "Only pending jobs can be assigned.")
	assigned_cat = cat
	status = Status.ASSIGNED


## The cat collected the item from the pickup building.
func mark_picked_up() -> void:
	assert(status == Status.ASSIGNED, "Pickup requires an assigned job.")
	pickup.output_inventory.take_reserved(item)
	_holds_pickup_reservation = false
	status = Status.IN_TRANSIT


## The item arrived in the destination's input. Called via the manager.
func complete() -> void:
	assert(status == Status.IN_TRANSIT, "Completion requires a picked-up item.")
	destination.input_inventory.deposit_reserved(item)
	_holds_delivery_reservation = false
	status = Status.COMPLETED


## Releases whatever reservations remain. An item already in transit is
## lost for now (a future feature may drop or return it).
func cancel() -> void:
	assert(status != Status.COMPLETED, "Cannot cancel a completed job.")
	if _holds_pickup_reservation:
		pickup.output_inventory.release_outgoing(item)
		_holds_pickup_reservation = false
	if _holds_delivery_reservation:
		destination.input_inventory.release_incoming(item)
		_holds_delivery_reservation = false
	status = Status.CANCELLED
