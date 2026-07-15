class_name DecoratingTable
extends ProcessingBuilding
## Finishes baked goods into sellable desserts (cake layer + whipped
## cream -> cream cake, etc, per its BuildingDefinition). A Decorator Cat
## staffs it.
##
## Same three-sprite animated-swap idiom PrepTable uses (see its class
## doc, including why `_set_visual_texture()` recomputes `Visual.offset`
## on every swap, not just `.texture`): definition.icon is the resting
## "idle" sprite; texture_active_1/texture_active_2 alternate at
## anim_frame_seconds while a batch is actively _processing (a rolling
## pin working), back to idle the instant processing stops.

@export var texture_active_1: Texture2D
@export var texture_active_2: Texture2D
## Seconds each active frame holds before swapping to the other.
@export var anim_frame_seconds: float = 0.5

@onready var _visual: Sprite3D = $Visual

var _anim_timer: float = 0.0
var _anim_showing_1: bool = true


func _process(delta: float) -> void:
	var was_processing: bool = _processing
	super._process(delta)
	if not _processing:
		if was_processing:
			_set_visual_texture(definition.icon)
		return
	if not was_processing:
		_anim_timer = 0.0
		_anim_showing_1 = true
		_set_visual_texture(texture_active_1)
		return
	_anim_timer += delta
	if _anim_timer < anim_frame_seconds:
		return
	_anim_timer -= anim_frame_seconds
	_anim_showing_1 = not _anim_showing_1
	_set_visual_texture(texture_active_1 if _anim_showing_1 else texture_active_2)


func _set_visual_texture(texture: Texture2D) -> void:
	_visual.texture = texture
	_visual.offset = Vector2(0, texture.get_height() / 2.0)
