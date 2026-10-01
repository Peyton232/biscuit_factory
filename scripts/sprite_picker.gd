class_name SpritePicker
extends RefCounted
## Screen-space hit testing against billboarded `Sprite3D`s — "is the
## mouse over the thing the player can actually see?"
##
## **Why this exists rather than the ground-plane math the rest of the
## factory's picking uses** (`GridCursor.world_point`, i.e. where the
## mouse ray meets y = 0): that math is correct for anything whose
## clickable extent *is* its footprint on the floor — grid cells,
## buildings, placement previews. It is wrong for a billboard sprite,
## which is drawn standing *up* out of its footprint. The mouse pixel
## over a cat's head projects to a ground point roughly a metre BEHIND
## the cat, so head clicks either miss entirely or land on whatever is
## behind it. Reported as cats only being selectable by their body, and
## worst exactly where it matters most — a cat parked at a Mixer, whose
## body is hidden behind the station and whose head is the only part
## left to click. See decisions.md.
##
## The quad's on-screen rectangle is derived from the sprite's own
## texture/frame size and `pixel_size`, so nothing here needs tuning
## when the art changes.

## Returned by frame_uv() when the point misses. Negative on both axes,
## which a real UV never is, so `uv.x < 0.0` is the miss test.
const MISS: Vector2 = Vector2(-1.0, -1.0)

## Alpha above which is_opaque_at() calls a pixel solid.
const ALPHA_THRESHOLD: float = 0.1

## Ceiling on the texture size is_opaque_at() will keep a decompressed
## `Image` of. A texture past it is treated as solid across its whole
## quad instead. Not arbitrary: this project's building art is small
## pixel art (a Mixer is 89x123), but the cat walk-cycle sheet is
## 12000x3000 — an `Image` of that is ~144 MB of RAM to answer a
## mouse-over question, which is why cats are hit-tested by quad and
## only their *occluders* are alpha-tested (see CatSelector).
const MAX_ALPHA_TEXTURE_PIXELS: int = 4_000_000

## texture -> its decompressed Image, or null for "too big, don't ask
## again". Static: shared by every caller, built at most once per
## texture for the life of the process.
static var _alpha_images: Dictionary[Texture2D, Image] = {}


## Whether screen_point lands anywhere on the sprite's drawn quad.
static func hits(sprite: Sprite3D, camera: Camera3D, screen_point: Vector2) -> bool:
	return frame_uv(sprite, camera, screen_point).x >= 0.0


## Whether screen_point lands on a part of the sprite that is actually
## painted (alpha above ALPHA_THRESHOLD) rather than its transparent
## padding. Falls back to hits() for a texture too large to sample.
static func is_opaque_at(sprite: Sprite3D, camera: Camera3D, screen_point: Vector2) -> bool:
	var uv: Vector2 = frame_uv(sprite, camera, screen_point)
	if uv.x < 0.0:
		return false
	var image: Image = _alpha_image(sprite.texture)
	if image == null:
		return true
	# Sample in NORMALIZED texture space, then scale by the Image's own
	# size — `Texture2D.get_image()` does not always hand back an image
	# at the texture's nominal dimensions (a headless run returns a much
	# smaller one: 23x32 for an 89x123 Mixer). Converting frame pixels
	# straight into image pixels silently clamped every sample into the
	# image's bottom-right corner, which read as transparent and made
	# every station look see-through.
	var frame_size: Vector2 = _frame_size_px(sprite)
	var origin: Vector2 = _frame_origin_px(sprite, frame_size)
	var texture_size := Vector2(sprite.texture.get_width(), sprite.texture.get_height())
	var normalized: Vector2 = (origin + uv * frame_size) / texture_size
	var x: int = clampi(int(normalized.x * image.get_width()), 0, image.get_width() - 1)
	var y: int = clampi(int(normalized.y * image.get_height()), 0, image.get_height() - 1)
	return image.get_pixel(x, y).a > ALPHA_THRESHOLD


## UV within the sprite's currently displayed frame at screen_point, or
## MISS if the point is off the quad.
##
## **The quad's axes are the CAMERA's right/up, not the sprite node's
## own basis** — that's what billboarding does, and using the node's
## basis would be wrong for exactly the sprites this is meant for. Both
## axes are unprojected and solved as a 2x2 system rather than assuming
## the quad lands screen-axis-aligned, so a rolled camera stays correct
## for free.
static func frame_uv(sprite: Sprite3D, camera: Camera3D, screen_point: Vector2) -> Vector2:
	if sprite == null or camera == null or sprite.texture == null:
		return MISS
	if not sprite.is_visible_in_tree():
		return MISS
	var half_extent: Vector2 = _frame_size_px(sprite) * sprite.pixel_size * 0.5
	var basis: Basis = camera.global_transform.basis
	var right: Vector3 = basis.x
	var up: Vector3 = basis.y
	# offset is in texture pixels, like pixel_size's own unit.
	var center: Vector3 = sprite.global_position \
			+ right * (sprite.offset.x * sprite.pixel_size) \
			+ up * (sprite.offset.y * sprite.pixel_size)
	if camera.is_position_behind(center):
		return MISS
	var center_screen: Vector2 = camera.unproject_position(center)
	var right_screen: Vector2 = camera.unproject_position(center + right * half_extent.x) - center_screen
	var up_screen: Vector2 = camera.unproject_position(center + up * half_extent.y) - center_screen
	var det: float = right_screen.x * up_screen.y - right_screen.y * up_screen.x
	if is_zero_approx(det):
		return MISS
	var delta: Vector2 = screen_point - center_screen
	var u: float = (delta.x * up_screen.y - delta.y * up_screen.x) / det
	var v: float = (right_screen.x * delta.y - right_screen.y * delta.x) / det
	if absf(u) > 1.0 or absf(v) > 1.0:
		return MISS
	# u/v run -1..1 from the quad's center, with +v up; UV runs 0..1 from
	# the frame's top-left.
	var uv := Vector2((u + 1.0) * 0.5, (1.0 - v) * 0.5)
	if sprite.flip_h:
		uv.x = 1.0 - uv.x
	if sprite.flip_v:
		uv.y = 1.0 - uv.y
	return uv


static func _frame_size_px(sprite: Sprite3D) -> Vector2:
	if sprite.region_enabled:
		return sprite.region_rect.size
	return Vector2(
			sprite.texture.get_width() / float(maxi(1, sprite.hframes)),
			sprite.texture.get_height() / float(maxi(1, sprite.vframes)))


## Top-left corner of the displayed frame within the whole texture.
static func _frame_origin_px(sprite: Sprite3D, frame_size: Vector2) -> Vector2:
	if sprite.region_enabled:
		return sprite.region_rect.position
	var hframes: int = maxi(1, sprite.hframes)
	return Vector2(sprite.frame % hframes, sprite.frame / hframes) * frame_size


## Null for a texture past MAX_ALPHA_TEXTURE_PIXELS (or one that won't
## decompress) — cached either way, so the decision is made once.
static func _alpha_image(texture: Texture2D) -> Image:
	if _alpha_images.has(texture):
		return _alpha_images[texture]
	var image: Image = null
	if texture.get_width() * texture.get_height() <= MAX_ALPHA_TEXTURE_PIXELS:
		image = texture.get_image()
		if image != null and image.is_compressed() and image.decompress() != OK:
			image = null
	_alpha_images[texture] = image
	return image
