class_name BuildingInspectorPanel
extends PanelContainer
## Panel shown while a Building is selected. Content depends on what kind
## of building it is — purely a view, FactoryHud wires recipe_selected to
## the selected ProcessingBuilding's assign_recipe():
## - ProcessingBuilding (Mixer/Oven): one toggle button per available
##   recipe, rebuilt each time since different station types offer a
##   different number of recipes. A recipe whose tier hasn't unlocked yet
##   (per tier_manager) is skipped entirely — not shown at all, same
##   "hidden not disabled" rule the Recipe Book uses (see progression.md).
##   A recipe whose tier HAS unlocked but that's still locked (per
##   recipe_shop) shows as a disabled button instead of being selectable
##   — visible so the player knows it exists and where to go rather than
##   the station's menu silently looking shorter than it is. A directly-
##   purchasable recipe shows its price ("locked, $10"); an intermediate
##   with no price of its own (see RecipeShop.INTERNALLY_UNLOCKS) shows
##   which recipe to buy instead ("locked — buy Bread").
## - IngredientSource: its production rate ("flour: 15.0/min").
## - ShippingBin: one checkbox per currently tier-unlocked sell_prices
##   item ("Accept whipped_cream ($5)") — `bin.unlocked_items()`, not the
##   type's full possible menu; a not-yet-unlocked item's checkbox simply
##   doesn't exist yet, same "hidden not disabled" rule as everywhere
##   else tier-gating applies (see progression.md). Toggling a shown
##   checkbox updates that specific bin instance's accepted items live —
##   see ShippingBin.set_accepted(). This is how the player configures
##   what a bin picks up, per the request that motivated it: an item that
##   is both sellable AND a recipe ingredient elsewhere (Whipped Cream)
##   can be routed away from a bin that doesn't need it right now.
##   A "Select All" / "Deselect All" button pair sits above the checkbox
##   list (QOL request — a bin can offer a couple dozen items by Tier 5+,
##   and toggling each one individually to route "everything except this
##   one ingredient" elsewhere was tedious); see bin_all_toggled below.
## Was ProcessingBuilding-only (StationInspectorPanel); broadened once
## Sources/ShippingBin also needed a click-to-inspect panel — see
## decisions.md.

signal recipe_selected(recipe: Recipe)
signal bin_item_toggled(item: StringName, enabled: bool)
signal bin_all_toggled(enabled: bool)
## A "Move" button, shown for every building kind (not just
## ProcessingBuilding), so the player can relocate a placed building
## instead of only demolish-and-rebuild — see BuildingMover.
signal move_pressed(building: Building)

## Set once by FactoryHud in _ready(), not exported — this panel is a
## permanent HUD child (not re-instantiated per-open like the pause
## menu's windows), so a plain code assignment is simpler and avoids the
## node-override fragility documented in decisions.md.
var recipe_shop: RecipeShop = null
## Same "set once by FactoryHud" convention as recipe_shop above.
var tier_manager: TierManager = null

@onready var _title_label: Label = %TitleLabel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _content: VBoxContainer = %Content
@onready var _info_lines: VBoxContainer = %InfoLines
@onready var _recipe_buttons: VBoxContainer = %RecipeButtons

## Recipe -> its toggle button, rebuilt every show_for_building() call
## (the recipe list itself is rebuilt each time too, since different
## stations offer different recipes). Used by recipe_button(), below.
var _recipe_button_map: Dictionary[Recipe, Button] = {}


## Vertical space kept clear below the panel so a long list stops short
## of the bottom toolbar (Build / Adopt Cat / Expand Factory) instead of
## running underneath it or off the bottom of the window.
const _BOTTOM_RESERVED_PX: float = 112.0
## Floor on the scroll viewport, so an unusually short window still shows
## a usable couple of rows rather than collapsing to a sliver.
const _MIN_SCROLL_PX: float = 120.0


func _ready() -> void:
	hide()
	get_viewport().size_changed.connect(_fit_to_screen)


## Populates the panel for the given building and shows it. Called by
## FactoryHud whenever the selection changes or the active recipe changes.
func show_for_building(building: Building) -> void:
	_title_label.text = building.definition.display_name
	_clear(_info_lines)
	_clear(_recipe_buttons)

	var move_button := UiButtonStyle.make()
	move_button.text = "Move"
	move_button.pressed.connect(move_pressed.emit.bind(building))
	_info_lines.add_child(move_button)

	var processing: ProcessingBuilding = building as ProcessingBuilding
	_recipe_button_map.clear()
	if processing != null:
		_recipe_buttons.show()
		for recipe: Recipe in processing.available_recipes:
			if tier_manager != null and not tier_manager.is_recipe_unlocked(recipe):
				continue
			var button := UiButtonStyle.make()
			button.toggle_mode = true
			var locked: bool = recipe_shop != null and not recipe_shop.is_unlocked(recipe)
			if locked:
				if recipe_shop.shop_prices.has(recipe):
					button.text = "%s (locked, $%d)" % [recipe.display_name, recipe_shop.price_for(recipe)]
				else:
					var parent: Recipe = recipe_shop.bundled_parent(recipe)
					button.text = "%s (locked — buy %s)" % [recipe.display_name, parent.display_name] \
							if parent != null else "%s (locked)" % recipe.display_name
				button.disabled = true
			else:
				button.text = recipe.display_name
				button.button_pressed = recipe == processing.recipe
				button.pressed.connect(recipe_selected.emit.bind(recipe))
			_recipe_buttons.add_child(button)
			_recipe_button_map[recipe] = button
	else:
		_recipe_buttons.hide()

	var source: IngredientSource = building as IngredientSource
	if source != null:
		var per_minute: float = 60.0 / source.production_interval
		for item: StringName in source.definition.outputs:
			_add_info_line("%s: %.1f/min" % [item, per_minute])

	var bin: ShippingBin = building as ShippingBin
	if bin != null:
		var select_row := HBoxContainer.new()
		var select_all_button := UiButtonStyle.make()
		select_all_button.text = "Select All"
		select_all_button.pressed.connect(bin_all_toggled.emit.bind(true))
		select_row.add_child(select_all_button)
		var deselect_all_button := UiButtonStyle.make()
		deselect_all_button.text = "Deselect All"
		deselect_all_button.pressed.connect(bin_all_toggled.emit.bind(false))
		select_row.add_child(deselect_all_button)
		_info_lines.add_child(select_row)
		for item: StringName in bin.unlocked_items():
			var check := CheckBox.new()
			check.text = "Accept %s ($%d)" % [item, bin.sell_prices[item]]
			check.button_pressed = bin.is_accepted(item)
			check.toggled.connect(func(enabled: bool) -> void: bin_item_toggled.emit(item, enabled))
			# CheckBox isn't a Button/BaseButton style target the way pill
			# buttons are (its own check-glyph art isn't being reskinned
			# here — no custom checked/unchecked icons exist yet), so just
			# the text color needs fixing for the new light panel
			# background instead of routing through UiButtonStyle.apply().
			check.add_theme_color_override("font_color", UiButtonStyle.TEXT_COLOR)
			check.add_theme_color_override("font_hover_color", UiButtonStyle.TEXT_COLOR)
			check.add_theme_color_override("font_pressed_color", UiButtonStyle.TEXT_COLOR)
			# A CheckBox is a toggle, so a TICKED one that is hovered uses
			# font_hover_pressed_color, and a just-clicked one uses
			# font_focus_color — neither of which the three above cover.
			# Both defaulted to (near-)white, so hovering an accepted item
			# made its label vanish into the light panel. See
			# UiButtonStyle.apply() for the same fix on pill buttons.
			check.add_theme_color_override("font_hover_pressed_color", UiButtonStyle.TEXT_COLOR)
			check.add_theme_color_override("font_focus_color", UiButtonStyle.TEXT_COLOR)
			_info_lines.add_child(check)

	show()
	_fit_to_screen()


## Sizes the scroll viewport to the content, capped at whatever vertical
## space is actually left on screen below the panel.
##
## **Without this the panel simply grew off the bottom of the window.**
## A PanelContainer takes the larger of its authored size and its
## content's minimum size, and by Tier 5 this panel's content is long:
## a Shipping Bin lists a checkbox per sellable item and an Oven lists a
## button per recipe — measured at **572 px** for 18 rows against roughly
## 470 px of usable screen. Everything past the cut was unreachable,
## which is what made French Toast impossible to select and so blocked
## finishing the game (reported: "some textboxes go off screen in tier 5
## ... cant see french toast so cant complete the game").
##
## The title stays outside the ScrollContainer so the player can always
## see which building they are looking at while scrolling its options.
##
## `custom_minimum_size.y` is the lever rather than `size`: a
## ScrollContainer reports a vertical minimum of 0 (it is happy to clip),
## so it contributes nothing to the panel's own minimum height until it
## is given one, and anything written to `size` is overwritten by the
## parent container on the next layout pass.
func _fit_to_screen() -> void:
	if not visible:
		return
	var available: float = get_viewport_rect().size.y - position.y \
			- _BOTTOM_RESERVED_PX - _chrome_height()
	# The floor caps how small the window may squeeze the list, not how
	# small the list itself may be — a two-line panel still renders two
	# lines tall rather than padding itself out to the minimum.
	var cap: float = maxf(_MIN_SCROLL_PX, available)
	_scroll.custom_minimum_size.y = minf(_content.get_combined_minimum_size().y, cap)


## Everything in the panel that is not the scrolling area: the margins
## around the content, the title, and the gap under it. Derived from the
## live theme constants rather than hard-coded, so restyling the panel
## cannot silently desync this from the real layout.
func _chrome_height() -> float:
	var margin: MarginContainer = _scroll.get_parent().get_parent()
	var layout: VBoxContainer = _scroll.get_parent()
	return margin.get_theme_constant("margin_top") \
			+ margin.get_theme_constant("margin_bottom") \
			+ _title_label.get_combined_minimum_size().y \
			+ layout.get_theme_constant("separation")


## The toggle button for a given recipe (only populated for whichever
## building show_for_building() was last called with), or null if that
## recipe isn't offered by the currently-shown building, isn't
## tier-unlocked, or nothing is shown at all. Used by TutorialManager to
## highlight "select this recipe" without reaching into private node
## internals — same pattern as CatInspectorPanel.role_button().
func recipe_button(recipe: Recipe) -> Button:
	return _recipe_button_map.get(recipe)


func _add_info_line(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UiButtonStyle.TEXT_COLOR)
	_info_lines.add_child(label)


func _clear(container: Container) -> void:
	for child: Node in container.get_children():
		child.queue_free()
