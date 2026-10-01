class_name AchievementToast
extends CanvasLayer
## Steam-style unlock popup: slides in from the bottom-right, holds, then
## slides out. Lives inside the `Achievements` autoload scene so it works
## anywhere — in the factory, in a menu, over the credits — rather than
## being a child of FactoryHud, which only exists during gameplay.
##
## **Queued, not concurrent.** Several achievements really can unlock on
## the same frame: shipping one item can complete a per-item goal, the
## 1,000-total goal and a money goal at once. Showing three overlapping
## toasts (or worse, one replacing another mid-animation) is exactly the
## kind of thing that reads as broken, so unlocks are appended to
## `_queue` and shown strictly one at a time.
##
## Drawn on a high `layer` so it sits over the pause menu and every HUD
## panel, and with `process_mode = ALWAYS` so the animation still runs
## while the tree is paused — an achievement can unlock from an action
## taken just before opening the pause menu.

## How long the panel holds at full visibility, between the slide in and
## the slide out.
const _HOLD_SECONDS: float = 3.4
const _SLIDE_SECONDS: float = 0.45
## How far right of its resting place the panel starts and ends, in
## pixels. Sized to comfortably clear the panel's own width so it is
## fully off-screen at rest.
const _SLIDE_DISTANCE: float = 460.0

## Category tint for the placeholder icon block, used until real
## achievement art exists (every definition ships with `icon = null`).
## Deliberately not RoleColors: these are UI categories, not cat roles,
## and coupling them would make a palette change in one drag the other.
const _CATEGORY_COLORS: Dictionary[int, Color] = {
	AchievementDefinition.Category.PROGRESSION: Color(0.42, 0.62, 0.86),
	AchievementDefinition.Category.CATS: Color(0.91, 0.48, 0.64),
	AchievementDefinition.Category.PRODUCTION: Color(0.55, 0.72, 0.42),
	AchievementDefinition.Category.CHALLENGE: Color(0.85, 0.66, 0.30),
}

@onready var _panel: PanelContainer = %ToastPanel
@onready var _title_label: Label = %TitleLabel
@onready var _name_label: Label = %NameLabel
@onready var _description_label: Label = %DescriptionLabel
@onready var _icon: TextureRect = %IconRect

var _queue: Array[AchievementDefinition] = []
var _showing: bool = false
## The panel's authored resting offsets, captured before anything slides
## it. Sliding moves BOTH by the same delta rather than recomputing the
## right edge from `size.x` — size isn't valid until the first layout
## pass, so a size-derived park() at _ready() collapsed the panel's width
## to zero and left the min-size system to fight it back open.
var _rest_left: float = 0.0
var _rest_right: float = 0.0


func _ready() -> void:
	_rest_left = _panel.offset_left
	_rest_right = _panel.offset_right
	_park()
	Achievements.achievement_unlocked.connect(show_achievement)


## Public rather than private: the debug showcase drives it directly, and
## a future Steam reconcile may want to replay an unlock earned on
## another machine.
func show_achievement(definition: AchievementDefinition) -> void:
	_queue.append(definition)
	if not _showing:
		_play_next()


func _park() -> void:
	_set_slide(_SLIDE_DISTANCE)
	_panel.hide()


func _play_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var definition: AchievementDefinition = _queue.pop_front()
	_name_label.text = definition.display_name
	_description_label.text = definition.description
	_title_label.text = "Achievement Unlocked"
	if definition.icon != null:
		_icon.texture = definition.icon
		_icon.modulate = Color.WHITE
	else:
		# Placeholder until art lands: a flat category-tinted block, so
		# the layout is already the real layout and dropping textures in
		# later changes nothing but the pixels.
		_icon.texture = _placeholder_texture()
		_icon.modulate = _CATEGORY_COLORS.get(definition.category, Color.WHITE)
	_panel.show()

	var tween: Tween = create_tween()
	tween.tween_method(_set_slide, _SLIDE_DISTANCE, 0.0, _SLIDE_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(_HOLD_SECONDS)
	tween.tween_method(_set_slide, 0.0, _SLIDE_DISTANCE, _SLIDE_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		_panel.hide()
		_play_next())


func _set_slide(amount: float) -> void:
	_panel.offset_left = _rest_left + amount
	_panel.offset_right = _rest_right + amount


## One shared 1x1 white pixel, tinted per category by `modulate` — the
## same "one texture, modulate for colour" idiom the cats' collar and
## FactoryHud's generated icons already use, rather than shipping 17
## placeholder PNGs that all have to be deleted later.
static var _placeholder: Texture2D = null

static func _placeholder_texture() -> Texture2D:
	if _placeholder == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_placeholder = ImageTexture.create_from_image(image)
	return _placeholder
