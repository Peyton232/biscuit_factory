class_name Oven
extends ProcessingBuilding
## Bakes inputs into finished goods (dough -> biscuit, per its
## BuildingDefinition). An Oven Cat will staff it later.
##
## Two hand-drawn sprites, not one: definition.icon (set on Visual by
## Building._ready()) is the resting "off" sprite, matching every other
## building; texture_on is swapped in only while a batch is actively
## _processing, and swapped back the moment it isn't. Checked once per
## frame against the previous frame's state rather than reassigned
## unconditionally, so an idle/stationed oven isn't re-setting the same
## texture every frame for no reason.

## The "door open, glowing" sprite shown while a batch is processing.
@export var texture_on: Texture2D

@onready var _visual: Sprite3D = $Visual


func _process(delta: float) -> void:
	var was_processing: bool = _processing
	super._process(delta)
	if _processing != was_processing:
		_visual.texture = texture_on if _processing else definition.icon
