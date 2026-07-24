class_name CatPortrait
extends TextureRect
## A static portrait of one specific cat (a breed + fur tint combo — see
## Cat.BREEDS/FUR_COLORS), gently bouncing in place. Used by
## EmployeeAwardsDialog to show the actual winning cat next to each
## award, rather than just its name in text.
##
## Reuses Cat's own sprite sheets directly rather than needing separate
## portrait art: each breed sheet is 4 walk-cycle frames side by side
## (`hframes = 4` on Cat's own Visual, confirmed against
## `sprite_sheet.png`'s 12000×3000 dimensions — 3000×3000 per frame,
## every breed shares this exact layout). Frame 0 is Cat's own
## "standing still" pose (`_update_walk_animation()` holds frame 0
## whenever not actively walking), so that's the frame cropped out here
## via an `AtlasTexture` region rather than a full walk-cycle preview.
## The fur tint is a plain `Color` multiply in Cat too (`set_fur_color()`),
## reproduced here via `self_modulate` rather than anything fancier.

## Matches Cat.BREEDS' own per-frame size (3000×3000 — see class doc).
const _FRAME_SIZE: float = 3000.0

## How high the bounce lifts the portrait, in pixels — small and
## subtle ("bouncing up and down a little"), not a big cartoonish hop.
const _BOUNCE_HEIGHT: float = 5.0
## One full up-down cycle roughly every ~2 seconds at this speed.
const _BOUNCE_SPEED: float = 3.0

## Randomized per instance so three portraits shown side by side don't
## bounce in lockstep — same "don't move in sync" reasoning as Cat's own
## wander timer (see Cat._wander_timer's doc comment).
var _bounce_timer: float = randf_range(0.0, TAU)


func _ready() -> void:
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_KEEP_SIZE (the default) makes a TextureRect report its own
	# *texture's* raw pixel size as its minimum size, overriding
	# custom_minimum_size entirely — since the source sprite sheet frame
	# is 3000x3000 (see class doc), that blew this control up to fill
	# (and overflow) the whole screen instead of respecting the small
	# size set below. EXPAND_IGNORE_SIZE is what makes custom_minimum_size
	# actually the size that's used, with stretch_mode above scaling the
	# much-larger source texture down to fit inside it.
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE


func _process(delta: float) -> void:
	_bounce_timer += delta
	position.y = -absf(sin(_bounce_timer * _BOUNCE_SPEED)) * _BOUNCE_HEIGHT


## Sets which cat this portrait shows — see class doc for the frame/tint
## mechanics.
func set_cat(breed_index: int, fur_color_index: int) -> void:
	var sheet: Texture2D = Cat.BREEDS[breed_index % Cat.BREEDS.size()]
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0.0, 0.0, _FRAME_SIZE, _FRAME_SIZE)
	texture = atlas
	self_modulate = Cat.FUR_COLORS[fur_color_index % Cat.FUR_COLORS.size()]
