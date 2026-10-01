class_name AchievementsPage
extends Control
## The achievement list: every achievement in the game, grouped by
## category, showing what it is, how to earn it, and whether it's done.
##
## **One scene, opened from both menus.** The pause menu and the main
## menu wrap it in their own window shells
## (`pause_menu_achievements_window.tscn` /
## `main_menu_achievements_window.tscn`), but the page itself is shared —
## a second copy would be two places to fix a layout bug.
##
## **This works in the main menu because it reads only the `Achievements`
## autoload**, which is account-wide and always present. That is the
## payoff of keeping unlock state out of the save file: unlike StatsPage
## — which has to find LifetimeStats via a group lookup and shows nothing
## outside a running game — this page needs no gameplay scene at all.
##
## Populated once in `_ready()` rather than live-updating, same as
## RecipeBook/BuildingBook/StatsPage: both menus instantiate it fresh
## every time they open it, and nothing here can change while it's on
## screen (the pause menu pauses the tree; the main menu has no game
## running).
##
## **Progress ("12 / 25") is read back from the autoload, never computed
## here.** AchievementTracker publishes it; this page only formats it.
## That is the whole reason the page can show a number without owning a
## second copy of the condition table — and because
## `Achievements.set_progress()` is also what unlocks on reaching the
## total, the number shown here is literally the number that decides the
## unlock. They cannot disagree.
##
## Progress only exists while a game is running, so from the main menu
## rows show just Locked/Unlocked. That is deliberate: progress belongs
## to one save and there are three slots, so a persisted "last known"
## number would be from whichever save was played most recently. See
## AchievementsManager._progress.

const _TEXT_COLOR: Color = Color(0.18, 0.13, 0.09, 1)
## Locked rows are dimmed rather than hidden — the point of the page is
## seeing what there is to go after.
const _LOCKED_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.45)
## Slightly lighter than the body text so the count reads as secondary to
## the description that explains it.
const _PROGRESS_COLOR: Color = Color(0.45, 0.33, 0.22, 1)

const _CATEGORY_NAMES: Dictionary[int, String] = {
	AchievementDefinition.Category.PROGRESSION: "Progression",
	AchievementDefinition.Category.CATS: "Cats",
	AchievementDefinition.Category.PRODUCTION: "Production",
	AchievementDefinition.Category.CHALLENGE: "Challenge",
}

## Matches AchievementToast's own category tints so an achievement looks
## the same here as it did in the popup that announced it.
const _CATEGORY_COLORS: Dictionary[int, Color] = {
	AchievementDefinition.Category.PROGRESSION: Color(0.42, 0.62, 0.86),
	AchievementDefinition.Category.CATS: Color(0.91, 0.48, 0.64),
	AchievementDefinition.Category.PRODUCTION: Color(0.55, 0.72, 0.42),
	AchievementDefinition.Category.CHALLENGE: Color(0.85, 0.66, 0.30),
}

@onready var _summary_label: Label = %SummaryLabel
@onready var _list: VBoxContainer = %List

static var _placeholder: Texture2D = null


func _ready() -> void:
	_summary_label.text = "%d of %d unlocked" % [
		Achievements.unlocked_count(), Achievements.DEFINITIONS.size()]
	var last_category: int = -1
	for definition: AchievementDefinition in Achievements.all_sorted():
		if definition.category != last_category:
			last_category = definition.category
			_list.add_child(_make_category_header(definition.category))
		_list.add_child(_make_row(definition))


func _make_category_header(category: int) -> Control:
	var label := Label.new()
	label.text = _CATEGORY_NAMES.get(category, "Other")
	label.add_theme_color_override("font_color", _TEXT_COLOR)
	label.add_theme_font_size_override("font_size", 20)
	# Breathing room above every group but the first.
	if _list.get_child_count() > 0:
		label.add_theme_constant_override("line_spacing", 10)
	return label


func _make_row(definition: AchievementDefinition) -> Control:
	var unlocked: bool = Achievements.is_unlocked(definition.id)
	# A hidden achievement keeps its secret until earned. Nothing ships
	# hidden today (the player asked to be able to see how to get each
	# one), but the mechanism stays supported so flipping one `hidden` in
	# a .tres is all it takes.
	var secret: bool = definition.hidden and not unlocked

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if not unlocked:
		row.modulate = _LOCKED_MODULATE

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if definition.icon != null and not secret:
		icon.texture = definition.icon
	else:
		icon.texture = _placeholder_texture()
		icon.modulate = _CATEGORY_COLORS.get(definition.category, Color.WHITE)
	row.add_child(icon)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = "???" if secret else definition.display_name
	name_label.add_theme_color_override("font_color", _TEXT_COLOR)
	name_label.add_theme_font_size_override("font_size", 17)
	text.add_child(name_label)
	var description_label := Label.new()
	description_label.text = "Hidden achievement." if secret else definition.description
	description_label.add_theme_color_override("font_color", _TEXT_COLOR)
	description_label.add_theme_font_size_override("font_size", 13)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size = Vector2(340, 0)
	text.add_child(description_label)
	row.add_child(text)

	# Progress under the description, for countable achievements that
	# aren't already done.
	if not unlocked and not secret \
			and definition.progress_format != AchievementDefinition.ProgressFormat.NONE \
			and Achievements.has_progress(definition.id):
		var progress_label := Label.new()
		progress_label.text = _format_progress(definition)
		progress_label.add_theme_color_override("font_color", _PROGRESS_COLOR)
		progress_label.add_theme_font_size_override("font_size", 13)
		text.add_child(progress_label)

	var status := Label.new()
	status.text = "Unlocked" if unlocked else "Locked"
	status.add_theme_color_override("font_color", _TEXT_COLOR)
	status.add_theme_font_size_override("font_size", 13)
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status)
	return row


## "12 / 25", "$34,600 / $50,000", "1h 12m / 5h" — the unit comes from
## the definition rather than from guessing at the id, so a new countable
## achievement only has to set `progress_format`.
func _format_progress(definition: AchievementDefinition) -> String:
	var values: Vector2i = Achievements.progress(definition.id)
	match definition.progress_format:
		AchievementDefinition.ProgressFormat.MONEY:
			return "$%s / $%s" % [_thousands(values.x), _thousands(values.y)]
		AchievementDefinition.ProgressFormat.TIME:
			return "%s / %s" % [LifetimeStats.format_playtime(values.x),
					LifetimeStats.format_playtime(values.y)]
		_:
			return "%s / %s" % [_thousands(values.x), _thousands(values.y)]


## 1000 -> "1,000". Godot has no built-in thousands separator, and
## "$50000 / $50000" is genuinely hard to read at a glance.
static func _thousands(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


## Shared 1x1 white pixel tinted per category, the same stand-in
## AchievementToast uses while achievement art doesn't exist yet.
static func _placeholder_texture() -> Texture2D:
	if _placeholder == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_placeholder = ImageTexture.create_from_image(image)
	return _placeholder
