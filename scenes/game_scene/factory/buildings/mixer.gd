class_name Mixer
extends ProcessingBuilding
## Combines ingredients into intermediate products (flour + butter ->
## dough, per its BuildingDefinition). A Mixer Cat will staff it later.
##
## Five hand-drawn sprites: definition.icon (set on Visual by
## Building._ready()) is the resting "idle" sprite (arm raised), matching
## every other building; progress_textures (4 frames, a kneading motion)
## loop continuously — not just alternate, unlike PrepTable/
## DecoratingTable's simpler two-frame swap — at anim_frame_seconds per
## frame while a batch is actively _processing, wrapping back to frame 0
## after the last frame; swaps back to definition.icon the instant
## processing stops. Same previous-frame-state comparison Oven/PrepTable/
## DecoratingTable all use.
##
## Each frame's own pixel height can differ from the resting sprite (the
## idle pose has the arm lifted, taller than the lowered mixing pose), so
## every texture swap routes through `_set_visual_texture()`, which
## recomputes `Visual.offset.y` (half the new texture's own native pixel
## height) each time — same bottom-edge-anchor idiom every other
## building with animated real art already uses.

## The 4-frame kneading loop, played in order while _processing.
@export var progress_textures: Array[Texture2D] = []
## Seconds each frame holds before advancing to the next.
@export var anim_frame_seconds: float = 0.25

@onready var _visual: Sprite3D = $Visual

var _anim_timer: float = 0.0
var _anim_frame_index: int = 0


func _process(delta: float) -> void:
	var was_processing: bool = _processing
	super._process(delta)
	if not _processing:
		if was_processing:
			_set_visual_texture(definition.icon)
		return
	if not was_processing:
		# Just started: show the first loop frame immediately rather than
		# waiting a full anim_frame_seconds on the resting sprite.
		_anim_timer = 0.0
		_anim_frame_index = 0
		_set_visual_texture(progress_textures[_anim_frame_index])
		return
	_anim_timer += delta
	if _anim_timer < anim_frame_seconds:
		return
	_anim_timer -= anim_frame_seconds
	_anim_frame_index = (_anim_frame_index + 1) % progress_textures.size()
	_set_visual_texture(progress_textures[_anim_frame_index])


func _set_visual_texture(texture: Texture2D) -> void:
	_visual.texture = texture
	_visual.offset = Vector2(0, texture.get_height() / 2.0)
