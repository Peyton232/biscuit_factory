class_name RecipeCard
extends PanelContainer
## A single recipe's info card: display name, which station it's made at
## (`recipe.station_name`), input items -> output item
## (icon + label per item, reusing the same assets/sprites/items/<id>.png
## lookup Cat._show_carried_item() uses), and processing time. Purely a
## view, populated via set_recipe(); used by RecipeBook. Recipe details
## are always shown in full even while locked (a locked recipe is a
## shop preview, not a mystery) — set_lock_state() adds a button on top:
## a clickable "Unlock for $N" for a directly-purchasable recipe, or a
## disabled "Unlocks with <Recipe>" for an intermediate that only
## unlocks as a side effect of buying that other recipe (see RecipeShop's
## INTERNALLY_UNLOCKS).

signal unlock_pressed(recipe: Recipe)

## Same dark-brown FactoryHud's own labels use for legibility against a
## light/busy background — recipecard.jpeg's card art (✅ 2026-07-14) is
## a light cream fill, so every label drawn directly on it needs an
## explicit override (the theme's project-wide default is a light color,
## tuned for the dark backdrops this game otherwise uses). Deliberately
## set individually per-label rather than once on the root: %UnlockButton
## sits on this same card but keeps its own default (light-on-dark)
## Button styling, so a single blanket override risked also darkening
## its text against its own unrelated dark background. Set here (not
## just in the .tscn) since _make_item_chip()'s item-name labels and
## set_recipe()'s "+" separators are both built at runtime.
const _CARD_TEXT_COLOR: Color = Color(0.18, 0.13, 0.09, 1)

@onready var _name_label: Label = %NameLabel
@onready var _station_icon: TextureRect = %StationIcon
@onready var _station_label: Label = %StationLabel
@onready var _inputs_row: HBoxContainer = %InputsRow
@onready var _output_row: HBoxContainer = %OutputRow
@onready var _time_label: Label = %TimeLabel
@onready var _unlock_button: Button = %UnlockButton

var _recipe: Recipe = null
## Same "recipe_shop" group lookup other freshly-instantiated pause-menu
## windows use to find their gameplay-scene reference (see StatsPage) —
## used by _make_item_chip() below so an input/output item's chip label
## reflects a display-only rename (e.g. "danish" -> "Egg Danish")
## instead of a stale capitalized id.
var _recipe_shop: RecipeShop = null

## recipe.station_name (e.g. "Oven") -> that station's own
## BuildingDefinition icon — "make recipe cards more clear, show the
## building as well" (the station name was already shown as text; this
## adds the icon players actually recognize from the Build menu). Built
## once, shared across every card instance, by scanning
## resources/buildings/*.tres for a display_name match — same
## discover-from-disk pattern StationItemShowcase already uses, so a
## future station type picks up an icon with no lookup table to
## hand-maintain.
static var _station_icons: Dictionary[String, Texture2D] = {}
static var _station_icons_built: bool = false


func _ready() -> void:
	_unlock_button.hide()
	_unlock_button.pressed.connect(func() -> void: unlock_pressed.emit(_recipe))
	_recipe_shop = get_tree().get_first_node_in_group("recipe_shop") as RecipeShop
	_build_station_icons()


static func _build_station_icons() -> void:
	if _station_icons_built:
		return
	_station_icons_built = true
	var dir: DirAccess = DirAccess.open("res://resources/buildings/")
	for file_name: String in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var definition: BuildingDefinition = load("res://resources/buildings/" + file_name) as BuildingDefinition
		if definition != null and definition.icon != null:
			_station_icons[definition.display_name] = definition.icon


func set_recipe(recipe: Recipe) -> void:
	_recipe = recipe
	_name_label.text = recipe.display_name
	_station_label.text = "Made at: %s" % recipe.station_name
	_station_icon.texture = _station_icons.get(recipe.station_name)
	for child: Node in _inputs_row.get_children():
		child.queue_free()
	for i: int in recipe.inputs.size():
		if i > 0:
			var plus := Label.new()
			plus.text = "+"
			plus.add_theme_color_override("font_color", _CARD_TEXT_COLOR)
			_inputs_row.add_child(plus)
		_inputs_row.add_child(_make_item_chip(recipe.inputs[i]))
	for child: Node in _output_row.get_children():
		child.queue_free()
	_output_row.add_child(_make_item_chip(recipe.output))
	_time_label.text = "%.1fs" % recipe.processing_time


## Shows/updates the lock button for a gated recipe; call after
## set_recipe(). Pass unlocked=true (once bought/bundled-in) to hide it
## again. Recipes outside both the shop and INTERNALLY_UNLOCKS (just
## Whipped Cream) never call this, so they never show a lock affordance
## at all.
##
## purchasable=true (the default): a directly-buyable recipe, shows a
## clickable "Unlock for $N" (unlock_pressed fires on click).
## purchasable=false: an intermediate that only unlocks by buying
## bundled_with (its display name) — shows a disabled, non-interactive
## "Unlocks with <bundled_with>" instead, since there's nothing to
## purchase here directly.
func set_lock_state(price: int, unlocked: bool, purchasable: bool = true, bundled_with: String = "") -> void:
	if purchasable:
		_unlock_button.text = "Unlock for $%d" % price
		_unlock_button.disabled = false
	else:
		_unlock_button.text = "Unlocks with %s" % bundled_with
		_unlock_button.disabled = true
	_unlock_button.visible = not unlocked


func _make_item_chip(item: StringName) -> VBoxContainer:
	var chip := VBoxContainer.new()
	chip.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(28, 28)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var texture_path: String = "res://assets/sprites/items/%s.png" % item
	if ResourceLoader.exists(texture_path):
		icon.texture = load(texture_path)
	chip.add_child(icon)

	var label := Label.new()
	label.text = _recipe_shop.display_name_for_item(item) if _recipe_shop != null else String(item).capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", _CARD_TEXT_COLOR)
	chip.add_child(label)
	return chip
