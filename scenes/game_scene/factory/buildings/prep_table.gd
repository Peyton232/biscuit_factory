class_name PrepTable
extends ProcessingBuilding
## Shapes/cuts intermediate goods ahead of baking (dough -> cut biscuits,
## dough + butter -> croissant dough, etc, per its BuildingDefinition).
## A Prep Cat staffs it.
##
## Three hand-drawn sprites: definition.icon (set on Visual by
## Building._ready()) is the resting "waiting" sprite, matching every
## other building; texture_active_up/texture_active_down alternate at
## anim_frame_seconds while a batch is actively _processing (a knife
## chopping up/down), swapping back to the resting sprite the instant
## processing stops. Same "check once per frame against the previous
## frame's state" idiom Oven already uses for its own on/off swap, plus
## an accumulating timer for the two-frame alternation specifically.
##
## **Each frame's own pixel height can differ slightly** (a knife raised
## mid-chop extends the drawn art's bounding box taller than at rest), so
## `_set_visual_texture()` recomputes `Visual.offset.y` — half the new
## texture's own native pixel height, the bottom-edge-anchor convention
## every building's Visual already follows — on every swap, not just
## `.texture` itself; leaving `offset` fixed while height changes would
## make the sprite appear to float or sink as it animates.

## "Knife up" mid-chop sprite, shown alternating with texture_active_down
## while a batch is processing.
@export var texture_active_up: Texture2D
## "Knife down" mid-chop sprite.
@export var texture_active_down: Texture2D
## Seconds each active frame holds before swapping to the other — a
## deliberately slow chop, not a fast flicker.
@export var anim_frame_seconds: float = 0.5

@onready var _visual: Sprite3D = $Visual

var _anim_timer: float = 0.0
var _anim_showing_up: bool = true


func _process(delta: float) -> void:
	var was_processing: bool = _processing
	super._process(delta)
	if not _processing:
		if was_processing:
			_set_visual_texture(definition.icon)
		return
	if not was_processing:
		# Just started: show the first active frame immediately rather
		# than waiting a full anim_frame_seconds on the resting sprite.
		_anim_timer = 0.0
		_anim_showing_up = true
		_set_visual_texture(texture_active_up)
		return
	_anim_timer += delta
	if _anim_timer < anim_frame_seconds:
		return
	_anim_timer -= anim_frame_seconds
	_anim_showing_up = not _anim_showing_up
	_set_visual_texture(texture_active_up if _anim_showing_up else texture_active_down)


func _set_visual_texture(texture: Texture2D) -> void:
	_visual.texture = texture
	_visual.offset = Vector2(0, texture.get_height() / 2.0)
