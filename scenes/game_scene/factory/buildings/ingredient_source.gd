class_name IngredientSource
extends Building
## Produces its definition's first output item into its output inventory
## on a timer. Production pauses while the output is full; delivery cats
## drain it. Starts with one item already produced so a freshly-placed
## source isn't sitting empty for a full production_interval.

## Seconds between produced items.
@export var production_interval: float = 4.0

var _timer: float = 0.0


func _ready() -> void:
	super._ready()
	if not definition.outputs.is_empty():
		output_inventory.add(definition.outputs[0])


## 0..1 progress toward the next item; pinned at 1.0 (matches
## BuildingProgressBar's "blocked" color) while production is paused
## because the output is full.
func progress() -> float:
	if definition.outputs.is_empty():
		return 0.0
	return clampf(_timer / production_interval, 0.0, 1.0)


func _process(delta: float) -> void:
	if definition.outputs.is_empty():
		return
	_timer += delta
	if _timer < production_interval:
		return
	# Keep accumulated time when full so production resumes immediately
	# after a pickup frees a slot.
	if output_inventory.add(definition.outputs[0]):
		_timer = 0.0
		FloatingText.spawn(self, global_position + Vector3.UP * 2.1,
				"+%s" % definition.outputs[0])
