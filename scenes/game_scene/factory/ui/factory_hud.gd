class_name FactoryHud
extends CanvasLayer
## In-game HUD: money/tool/FPS/jobs/tier readouts (top-left), pause and
## settings buttons (top-right), a bottom bar (Build/Recipes/Demolish/
## Adopt Cat) plus a Build flyout populated automatically from the
## placer's building definitions, the cat inspector panel (shown while
## CatSelector has a cat selected), and the building inspector panel
## (shown while BuildingSelector has any building selected — recipe
## assignment for a Mixer/Oven, production rate for a Source, sell prices
## for the ShippingBin). The two panels are mutually exclusive —
## selecting one hides the other. Also owns the cat-naming popup shown
## before a new cat is adopted, where the player also picks its starting
## role.
##
## **Recipes button opens the same Recipe Book window the pause menu's
## own Recipes button opens** — a second entry point, not a replacement;
## `%RecipeBookWindow` is a permanently-embedded hidden instance of
## `pause_menu_recipe_book_window.tscn`, shown/hidden the same way
## `%SettingsWindow` already is (plain `.show()`, self-closes via its own
## Close/"Back" button).
##
## **Build menu is a toggleable flyout, not a persistent scrolling bar**
## (that used to be a horizontally-scrolling HBoxContainer — clunky to
## navigate once there were more than a few building types). Clicking
## the "Build" button in the bottom bar shows/hides `%BuildFlyout`, a
## `GridContainer` of one button per tier-unlocked `placer.definitions()`
## entry (wraps to rows instead of scrolling); picking a building selects
## it and closes the flyout again. `_on_tool_changed()` also closes the
## flyout on any tool change (selecting a building, demolish, or
## ESC-cancel all emit `tool_changed`), so it never lingers open after
## the player has already acted on it.
##
## **Buildings have no money-unlock step anymore** (see progression.md)
## — a definition whose tier hasn't unlocked simply has no button in the
## flyout at all (`_rebuild_build_grid()` skips it), rather than showing
## disabled with an unlock price the old BuildingShop model used to.
## `_rebuild_build_grid()` reruns whenever `tier_manager.tier_advanced`
## fires (an in-session tier advance), AND right before the flyout is
## actually shown (`_on_build_button_pressed()`) — the latter is what
## keeps a **loaded** save correct, since restoring a tier via
## `TierManager.load_state()` never fires `tier_advanced` at all; without
## it the flyout would permanently show whatever was unlocked at the
## fresh-game default the HUD was first built against. See decisions.md.
##
## **Tier readout + manual advancement**: `%TierLabel` shows the current
## tier and goal progress (polled in `_process()`, same convention as
## `%JobsLabel`); `%TierCompleteButton` is hidden until
## `tier_manager.can_advance()`, and calls `tier_manager.advance_tier()`
## when pressed — advancing is a deliberate player action, never
## automatic (see progression.md). `TierCompleteConfetti.spawn()` fires
## the instant the button *appears* (the false→true edge of
## `can_advance()`, detected in `_update_tier_readout()`), not when it's
## clicked — see that function's own comment for why, and
## `_tier_readout_primed` for why the very first readout tick never
## fires it (would otherwise misfire on a loaded save whose tier was
## already completable at save time).
##
## **`%GameCompleteDialog`** is a permanently-embedded hidden view (same
## pattern as `%CatNamingDialog`) for the one-time "you finished the
## game" moment reaching Tier Winner triggers. This class only exposes it
## (`game_complete_dialog()`); FactoryWorld is the one driving what
## happens around it (save the game, roll credits, return to menu) since
## it already owns that machinery — see FactoryWorld's class doc.

@export var placer: BuildingPlacer
@export var economy: Economy
@export var delivery_manager: DeliveryManager
@export var cat_shop: CatShop
@export var cat_placer: CatPlacer
@export var cat_selector: CatSelector
@export var building_selector: BuildingSelector
@export var building_mover: BuildingMover
## Optional: null just means no "Expand Factory" button (graceful
## fallback, same convention tier_manager/recipe_shop use elsewhere).
@export var factory_bounds: FactoryBounds
@export var recipe_shop: RecipeShop
@export var tier_manager: TierManager
## The template's pause menu controller node; its pause() opens the menu.
@export var pause_controller: Node

## Icon art for the bottom bar's Build/Recipes/Demolish buttons — real
## hand-drawn pixel art (✅ 2026-07-14) replacing plain text buttons.
## JPEG, not PNG: source files as delivered, no alpha channel needed
## since each icon is already a fully opaque square (see decisions.md).
const _BUILD_ICON: Texture2D = preload("res://assets/UI/buildicon.jpeg")
const _RECIPES_ICON: Texture2D = preload("res://assets/UI/recipeicon.jpeg")
const _DEMOLISH_ICON: Texture2D = preload("res://assets/UI/demolishicon.jpeg")
## Pause/Settings top-right icon buttons — PNG, not JPEG (real alpha
## backgrounds, unlike the square opaque bottom-bar icons above), built
## the same way via _make_icon_button() (see _populate_top_right()).
const _PAUSE_ICON: Texture2D = preload("res://assets/UI/Pause.png")
const _SETTINGS_ICON: Texture2D = preload("res://assets/UI/Settings.png")

const _TIER_COMPLETE_SOUND: AudioStream = preload("res://assets/sounds/effects/tier_complete.wav")
const _EXPANSION_SOUND: AudioStream = preload("res://assets/sounds/effects/factory_expansion.wav")

## PlayerConfig section/key backing the Settings > Game tab's "Expanded
## Info HUD" checkbox (see menus/options_menu/game/expanded_info_hud_control/) —
## public so that control reads/writes the exact same section/key
## FactoryHud itself polls below, rather than a second copy of the same
## two strings risking drift. Section reuses AppSettings.GAME_SECTION (the
## template's own convention for this kind of setting) rather than
## inventing a project-specific one.
const EXPANDED_INFO_HUD_SECTION: StringName = AppSettings.GAME_SECTION
const EXPANDED_INFO_HUD_KEY: StringName = &"ExpandedInfoHud"

## Shared pill-button art (see UiButtonStyle) for the bottom bar's
## remaining dynamic-text buttons (Adopt Cat/Adopt Multiple/Expand
## Factory). See _make_pill_button().

@onready var _money_label: Label = %MoneyLabel
@onready var _tool_label: Label = %ToolLabel
@onready var _fps_label: Label = %FpsLabel
@onready var _jobs_label: Label = %JobsLabel
@onready var _tier_label: Label = %TierLabel
@onready var _tier_complete_button: Button = %TierCompleteButton
@onready var _bottom_bar: HBoxContainer = %BottomBar
@onready var _build_flyout: PanelContainer = %BuildFlyout
@onready var _build_grid: GridContainer = %BuildGrid
@onready var _build_back_button: Button = %BackButton
@onready var _top_right: HBoxContainer = %TopRight
@onready var _settings_window: Control = %SettingsWindow
@onready var _recipe_book_window: Control = %RecipeBookWindow
@onready var _cat_panel: CatInspectorPanel = %CatInspectorPanel
@onready var _building_panel: BuildingInspectorPanel = %BuildingInspectorPanel
@onready var _cat_naming_dialog: CatNamingDialog = %CatNamingDialog
@onready var _cat_batch_dialog: CatBatchAdoptDialog = %CatBatchAdoptDialog
@onready var _game_complete_dialog: GameCompleteDialog = %GameCompleteDialog

var _selected_cat: Cat = null
var _selected_building: Building = null
## Cached PlayerConfig read, so _process() only touches FpsLabel/JobsLabel
## visibility on an actual change instead of every frame — see
## _apply_expanded_info_hud(). Polled rather than event-driven since the
## Settings window that owns this checkbox lives in a completely separate
## scene instanced fresh each time (no signal to connect to from here).
var _expanded_info_hud: bool = false
## True once _update_tier_readout() has run at least once — guards the
## confetti trigger below from firing on the very first frame, which
## would otherwise misfire on a loaded save whose tier goal was already
## satisfied at save time (TierManager's restored state isn't applied
## until FactoryWorld._ready(), which — children ready before parents —
## runs after this class's own _ready(), so it's only guaranteed visible
## by the first _process() tick, not any earlier).
var _tier_readout_primed: bool = false
var _cat_shop_button: Button
var _demolish_button: TextureButton
var _expand_button: Button
var _build_button: TextureButton
var _recipes_button: TextureButton
var _pause_button: TextureButton
var _settings_button: TextureButton
var _build_buttons: Dictionary[BuildingDefinition, Button] = {}


func _ready() -> void:
	_building_panel.recipe_shop = recipe_shop
	_building_panel.tier_manager = tier_manager
	economy.money_changed.connect(_on_money_changed)
	placer.tool_changed.connect(_on_tool_changed)
	cat_selector.selection_changed.connect(_on_cat_selection_changed)
	building_selector.selection_changed.connect(_on_building_selection_changed)
	cat_shop.cost_changed.connect(_on_cat_shop_cost_changed)
	_cat_panel.name_changed.connect(_on_cat_name_changed)
	_cat_panel.role_selected.connect(_on_cat_role_selected)
	_cat_panel.pick_up_pressed.connect(_on_cat_pick_up_pressed)
	_building_panel.recipe_selected.connect(_on_building_recipe_selected)
	_building_panel.bin_item_toggled.connect(_on_bin_item_toggled)
	_building_panel.bin_all_toggled.connect(_on_bin_all_toggled)
	_building_panel.move_pressed.connect(_on_building_move_pressed)
	_cat_naming_dialog.name_confirmed.connect(_on_cat_name_confirmed)
	_cat_batch_dialog.batch_confirmed.connect(_on_cat_batch_confirmed)
	if cat_placer != null:
		cat_placer.placing_changed.connect(_on_cat_placing_changed)
	if building_mover != null:
		building_mover.moving_changed.connect(_on_building_moving_changed)
	_build_back_button.pressed.connect(_build_flyout.hide)
	_tier_complete_button.pressed.connect(_on_tier_complete_pressed)
	if tier_manager != null:
		tier_manager.tier_advanced.connect(_on_tier_advanced)
	_on_money_changed(economy.money)
	_on_tool_changed()
	_populate_top_right()
	_populate_build_menu()
	_rebuild_build_grid()
	_apply_expanded_info_hud(_read_expanded_info_hud_setting())


func _process(_delta: float) -> void:
	var expanded: bool = _read_expanded_info_hud_setting()
	if expanded != _expanded_info_hud:
		_apply_expanded_info_hud(expanded)
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Debug readout: how many jobs exist vs. how many are still waiting
	# for a cat. If "waiting" stays high and non-zero, cats are the
	# bottleneck (too few, too slow, or genuinely stuck) rather than
	# production or dispatch.
	var active: int = delivery_manager.active_jobs().size()
	var waiting: int = delivery_manager.available_jobs().size()
	_jobs_label.text = "Jobs: %d active, %d waiting" % [active, waiting]
	_update_tier_readout()


func _read_expanded_info_hud_setting() -> bool:
	return PlayerConfig.get_config(EXPANDED_INFO_HUD_SECTION, EXPANDED_INFO_HUD_KEY, false)


## Shows/hides the debug-oriented FPS/Jobs readouts — the default
## top-left panel only shows Money/Tool (the two lines a normal player
## actually needs); the extra two are opt-in via Settings > Game.
## %TopLeft has no fixed height forcing extra room for them (see its
## .tscn) — a PanelContainer/VBoxContainer already auto-sizes to fit only
## its VISIBLE children, so toggling these two labels' visibility grows
## or shrinks the whole panel with no manual resize code needed here.
func _apply_expanded_info_hud(enabled: bool) -> void:
	_expanded_info_hud = enabled
	_fps_label.visible = enabled
	_jobs_label.visible = enabled


func _update_tier_readout() -> void:
	if tier_manager == null:
		_tier_label.hide()
		_tier_complete_button.hide()
		return
	var goal: Dictionary = tier_manager.goal_requirements()
	if goal.is_empty():
		_tier_label.text = tier_manager.tier_name()
	else:
		var parts: Array[String] = []
		for item: StringName in goal:
			var item_name: String = recipe_shop.display_name_for_item(item) if recipe_shop != null else String(item).capitalize()
			parts.append("%s %d/%d" % [item_name, tier_manager.goal_progress(item), goal[item]])
		_tier_label.text = "%s — %s" % [tier_manager.tier_name(), ", ".join(parts)]
	# Confetti fires the moment the button *appears* (the player just
	# completed the tier's goal), not when they click it — "tier complete
	# isn't obvious enough" playtest feedback, same motivation the button
	# itself exists for; celebrating on click only rewards a player who
	# already noticed the button was there.
	var can_advance: bool = tier_manager.can_advance()
	if _tier_readout_primed and can_advance and not _tier_complete_button.visible:
		TierCompleteConfetti.spawn(self)
	_tier_complete_button.visible = can_advance
	_tier_readout_primed = true


func _on_tier_complete_pressed() -> void:
	if tier_manager != null and tier_manager.can_advance():
		tier_manager.advance_tier()
		Sfx.spawn(self, _TIER_COMPLETE_SOUND)


func _on_tier_advanced(_new_tier: int) -> void:
	_rebuild_build_grid()


## Builds a TextureButton from a single square icon (no separate hover/
## pressed/disabled art was provided) — a modulate shift on hover/press
## stands in for the missing state art, so it still reads as clickable
## instead of a flat, unresponsive image. texture_filter is forced to
## NEAREST here rather than relying on a project-wide default (there
## isn't one — every crisp Sprite3D in this project sets its own filter
## per-node too, see architecture.md's Sprite3D conventions) so the
## pixel art stays sharp instead of Control's default linear blur.
## tooltip_text carries the label the icon itself no longer spells out.
func _make_icon_button(icon: Texture2D, tooltip: String) -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = icon
	button.tooltip_text = tooltip
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.mouse_entered.connect(func() -> void: button.modulate = Color(1.15, 1.15, 1.15))
	button.mouse_exited.connect(func() -> void: button.modulate = Color.WHITE)
	button.button_down.connect(func() -> void: button.modulate = Color(0.8, 0.8, 0.8))
	button.button_up.connect(func() -> void: button.modulate = Color.WHITE)
	return button


## Builds a themed Button with the shared pill background (UiButtonStyle
## — same art main-menu/Pause/Settings buttons use) instead of Godot's
## flat default style. Unlike _make_icon_button()'s TextureButtons, these
## three (Adopt Cat/Adopt Multiple/Expand Factory) carry dynamic,
## unbounded text — a price that only grows over a long playthrough (e.g.
## "Expand Factory  $1511160") — so no custom_minimum_size is forced
## here; the button sizes to its own text as it always has, and the pill
## StyleBoxTextures' texture_margin_* (9-slice) keeps the border/corner
## art fixed-size regardless of how wide that ends up being, instead of
## stretching (and distorting) the whole image uniformly.
func _make_pill_button() -> Button:
	return UiButtonStyle.make()


func _populate_top_right() -> void:
	_pause_button = _make_icon_button(_PAUSE_ICON, "Pause")
	_pause_button.pressed.connect(_on_pause_pressed)
	_top_right.add_child(_pause_button)

	_settings_button = _make_icon_button(_SETTINGS_ICON, "Settings")
	_settings_button.pressed.connect(_on_settings_pressed)
	_top_right.add_child(_settings_button)


func _populate_build_menu() -> void:
	_build_button = _make_icon_button(_BUILD_ICON, "Build")
	_build_button.pressed.connect(_on_build_button_pressed)
	_bottom_bar.add_child(_build_button)

	_recipes_button = _make_icon_button(_RECIPES_ICON, "Recipes")
	_recipes_button.pressed.connect(_on_recipes_button_pressed)
	_bottom_bar.add_child(_recipes_button)

	_demolish_button = _make_icon_button(_DEMOLISH_ICON, "Demolish (X)")
	_demolish_button.pressed.connect(placer.select_demolish)
	_bottom_bar.add_child(_demolish_button)

	_cat_shop_button = _make_pill_button()
	_cat_shop_button.pressed.connect(_on_buy_cat_pressed)
	_bottom_bar.add_child(_cat_shop_button)
	_update_cat_shop_button()

	var batch_button := _make_pill_button()
	batch_button.text = "Adopt Multiple"
	batch_button.pressed.connect(_on_adopt_multiple_pressed)
	_bottom_bar.add_child(batch_button)

	if factory_bounds != null:
		_expand_button = _make_pill_button()
		_expand_button.pressed.connect(_on_expand_pressed)
		_bottom_bar.add_child(_expand_button)
		factory_bounds.expanded.connect(_update_expand_button)
		_update_expand_button()


## Clears and repopulates the build flyout from placer.definitions(),
## skipping any definition whose tier hasn't unlocked yet — a tier-locked
## building has no button at all (not a disabled one), per progression.md.
## Called once in _ready() and again whenever tier_manager.tier_advanced
## fires, since that's the only thing that changes which buildings are
## even visible.
func _rebuild_build_grid() -> void:
	for child: Node in _build_grid.get_children():
		child.queue_free()
	_build_buttons.clear()
	for definition: BuildingDefinition in placer.definitions():
		if tier_manager != null and not tier_manager.is_building_unlocked(definition):
			continue
		var button := _make_pill_button()
		button.pressed.connect(_on_build_option_pressed.bind(definition))
		button.text = "%s  $%d" % [definition.display_name, definition.cost]
		button.icon = _scaled_build_icon(definition.icon)
		_build_grid.add_child(button)
		_build_buttons[definition] = button


## A plain Button.icon renders at the texture's own native pixel size —
## fine for the tiny (~20-30px) placeholder crates, but a building with
## real, higher-resolution art (see Oven, 90x86px) would visibly dwarf
## every other button's icon. **This used to cap it via `expand_icon` +
## an `icon_max_width` theme constant override instead** — found (via a
## real rendered screenshot, not just reading the code) to render
## inconsistently: some buttons' icons simply failed to draw at all,
## seemingly depending on unrelated layout details like how many other
## controls shared a container, not on anything about the icon itself.
## Pre-scaling the actual pixel data into a small `ImageTexture` up
## front sidesteps that flakiness entirely — a `Button.icon` at or under
## _BUILD_ICON_MAX_SIZE natively needs no per-frame scaling decision by
## Button's own layout code at all, which is exactly how every
## placeholder crate's icon already rendered correctly for as long as
## this project has had a build flyout. See decisions.md.
##
## **Always scaled onto a fixed _BUILD_ICON_MAX_SIZE-square canvas, not
## left at native size when already small enough (✅ fixed 2026-07-14)**
## — the original version returned small icons untouched, which meant
## every building's icon rendered at a *different* footprint (whatever
## its own art happened to be natively sized at) rather than a
## consistent one, reported as "some icons too big, take up more space
## than other buttons." Every icon is now scaled to fit within (not
## upscaled to fill/distort) the square canvas via nearest-neighbor —
## safe for pixel art even when upscaling a small icon, since NEAREST
## blocks pixels up cleanly rather than blurring the way linear
## filtering would — then centered on a transparent
## `_BUILD_ICON_MAX_SIZE`×`_BUILD_ICON_MAX_SIZE` `Image`, so the
## resulting `Button.icon` is always exactly the same pixel dimensions
## no matter the source art's own resolution or aspect ratio.
const _BUILD_ICON_MAX_SIZE: int = 32


func _scaled_build_icon(texture: Texture2D) -> Texture2D:
	# Named icon_scale/canvas_offset, not scale/offset — FactoryHud
	# extends CanvasLayer, which has its own scale/offset properties;
	# the obvious local names silently shadowed them (caught as a real
	# runtime warning, not just style noise).
	var icon_scale: float = float(_BUILD_ICON_MAX_SIZE) / maxf(texture.get_width(), texture.get_height())
	var scaled_width: int = maxi(1, roundi(texture.get_width() * icon_scale))
	var scaled_height: int = maxi(1, roundi(texture.get_height() * icon_scale))
	var image: Image = texture.get_image()
	# Some building icons import with VRAM compression (format varies by
	# .import settings) — Image.resize()/blit_rect() both require an
	# uncompressed image, and blit_rect() further requires the source and
	# destination to share the exact same format. decompress() + convert()
	# normalize any source texture to one resize()/blit_rect()-safe format
	# before doing anything else with it; skipped for the already-common
	# case (is_compressed() false, format already RGBA8) since both are
	# no-ops there anyway.
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	image.resize(scaled_width, scaled_height, Image.INTERPOLATE_NEAREST)
	var canvas := Image.create(_BUILD_ICON_MAX_SIZE, _BUILD_ICON_MAX_SIZE, false, Image.FORMAT_RGBA8)
	@warning_ignore("integer_division")
	var canvas_offset := Vector2i((_BUILD_ICON_MAX_SIZE - scaled_width) / 2, (_BUILD_ICON_MAX_SIZE - scaled_height) / 2)
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, Vector2i(scaled_width, scaled_height)), canvas_offset)
	return ImageTexture.create_from_image(canvas)


## Rebuilds right before the flyout actually becomes visible (on top of
## the existing tier_advanced-triggered rebuild), not just when toggling
## it closed — a loaded save restores TierManager.current_tier directly
## (TierManager.load_state(), not advance_tier()), which never fires
## tier_advanced, so without this the flyout permanently shows whatever
## was unlocked at the fresh-game default (Tier 0) it was first built
## against, regardless of which tier the loaded save actually reached.
## Same root cause and same fix shape as RecipeBook's analogous bug —
## see decisions.md.
func _on_build_button_pressed() -> void:
	_build_flyout.visible = not _build_flyout.visible
	if _build_flyout.visible:
		_rebuild_build_grid()


func _on_build_option_pressed(definition: BuildingDefinition) -> void:
	placer.select_definition(definition)


## Opens the same Recipe Book window the pause menu's "Recipes" button
## opens (scenes/windows/pause_menu_recipe_book_window.tscn) — this is a
## second, independent entry point, not a replacement; both stay wired.
## Embedded as a permanent hidden child (%RecipeBookWindow), same as
## %SettingsWindow above, rather than instantiated/freed on demand like
## PauseMenu._load_and_show_menu() does — FactoryHud has no equivalent of
## PauseMenu's %MenuButtons focus-disable dance to coordinate with, so
## there's nothing the transient-instance approach buys here; the window
## closes itself via its own built-in Close/"Back" button
## (WindowContainer.close(), unrelated to this class).
func _on_recipes_button_pressed() -> void:
	_build_flyout.hide()
	_recipe_book_window.show()


func _on_money_changed(money: int) -> void:
	_money_label.text = "$ %d" % money


## Fires from picking/clearing a building tool. Also cancels an active
## cat placement and an active building move — the three modes are all
## mutually exclusive — but this can't loop back on itself:
## CatPlacer.begin_placing() and BuildingMover.begin_move() both call
## placer.clear_tool() *before* marking themselves active, so at the
## moment that clear_tool() reaches here, is_placing()/is_moving() are
## still false and this is a no-op for whichever mode is actually
## starting.
func _on_tool_changed() -> void:
	if cat_placer != null and cat_placer.is_placing():
		cat_placer.cancel_placing()
	if building_mover != null and building_mover.is_moving():
		building_mover.cancel_move()
	_refresh_tool_label()
	_build_flyout.hide()


func _on_cat_placing_changed() -> void:
	_refresh_tool_label()


func _on_building_move_pressed(building: Building) -> void:
	building_mover.begin_move(building)
	_building_panel.hide()


func _on_building_moving_changed() -> void:
	_refresh_tool_label()


func _refresh_tool_label() -> void:
	if cat_placer != null and cat_placer.is_placing():
		_tool_label.text = "Tool: %s" % cat_placer.tool_label()
	elif building_mover != null and building_mover.is_moving():
		_tool_label.text = "Tool: %s" % building_mover.tool_label()
	else:
		_tool_label.text = "Tool: %s" % placer.tool_label()


func _on_pause_pressed() -> void:
	pause_controller.pause()


func _on_settings_pressed() -> void:
	_settings_window.show()


## Opens the naming popup rather than adopting immediately — the actual
## purchase/spawn happens once the player places the cat (see
## _on_cat_name_confirmed() and CatPlacer), so a cancelled popup never
## charges the player. Guarded against a placement already pending, so
## the player can't stack a second naming flow on top of one whose cat
## hasn't been placed yet and silently lose the first.
func _on_buy_cat_pressed() -> void:
	if cat_placer != null and cat_placer.is_placing():
		return
	_build_flyout.hide()
	_cat_naming_dialog.open(cat_shop.current_cost(), cat_shop.next_suggested_name())


func _on_cat_name_confirmed(cat_name: String, role: Cat.Role) -> void:
	if cat_placer != null:
		cat_placer.begin_placing(cat_name, role)
	else:
		cat_shop.buy_cat(cat_name, role)


## Opens the batch-adopt dialog, guarded the same way single adoption is
## — can't stack a batch purchase on top of a placement that hasn't
## resolved yet.
func _on_adopt_multiple_pressed() -> void:
	if cat_placer != null and cat_placer.is_placing():
		return
	_build_flyout.hide()
	_cat_batch_dialog.open(cat_shop)


## Buys up to `quantity` cats of the chosen role back-to-back, each with
## its own generated name from CatShop's shared pool. Stops early
## (partial fill) if funds run out mid-batch rather than requiring
## all-or-nothing — buy_cat() already returns false without spending
## anything once the player can't afford the next one.
func _on_cat_batch_confirmed(quantity: int, role: Cat.Role) -> void:
	for i: int in quantity:
		if not cat_shop.buy_cat(cat_shop.next_suggested_name(), role):
			break


func _on_cat_shop_cost_changed(_cost: int) -> void:
	_update_cat_shop_button()


func _update_cat_shop_button() -> void:
	_cat_shop_button.text = "Adopt Cat  $%d" % cat_shop.current_cost()


func _on_expand_pressed() -> void:
	if factory_bounds.try_expand():
		Sfx.spawn(self, _EXPANSION_SOUND)
	_update_expand_button()


func _update_expand_button() -> void:
	if not factory_bounds.can_expand_further():
		_expand_button.text = "Factory Fully Expanded"
		_expand_button.disabled = true
		return
	_expand_button.text = "Expand Factory  $%d" % factory_bounds.current_cost()


func _on_cat_selection_changed(cat: Cat) -> void:
	_selected_cat = cat
	if cat != null:
		_building_panel.hide()
		_cat_panel.show_for_cat(cat)
	else:
		_cat_panel.hide()


func _on_cat_name_changed(new_name: String) -> void:
	if _selected_cat != null:
		_selected_cat.set_cat_name(new_name)


func _on_cat_role_selected(role: Cat.Role) -> void:
	if _selected_cat != null:
		_selected_cat.set_role(role)
		_cat_panel.show_for_cat(_selected_cat)


func _on_cat_pick_up_pressed() -> void:
	cat_selector.begin_hold()


func _on_building_selection_changed(building: Building) -> void:
	_selected_building = building
	if building != null:
		_cat_panel.hide()
		_building_panel.show_for_building(building)
	else:
		_building_panel.hide()


func _on_building_recipe_selected(recipe: Recipe) -> void:
	var processing: ProcessingBuilding = _selected_building as ProcessingBuilding
	if processing != null:
		processing.assign_recipe(recipe)
		_building_panel.show_for_building(processing)


func _on_bin_item_toggled(item: StringName, enabled: bool) -> void:
	var bin: ShippingBin = _selected_building as ShippingBin
	if bin != null:
		bin.set_accepted(item, enabled)


func _on_bin_all_toggled(enabled: bool) -> void:
	var bin: ShippingBin = _selected_building as ShippingBin
	if bin != null:
		bin.set_all_accepted(enabled)
		_building_panel.show_for_building(bin)


## --- Read-only accessors for TutorialManager ---
## The tutorial lives in a separate scene (factory_world.tscn, not a
## descendant of factory_hud.tscn), so it can't reach %UniqueName nodes
## here directly — these are the small, purpose-built public surface it
## highlights against instead of reaching into private HUD internals.

func build_button() -> TextureButton:
	return _build_button


func is_build_flyout_open() -> bool:
	return _build_flyout.visible


## The build flyout's button for a specific definition, or null if that
## definition isn't in the hotbar (or hasn't unlocked by tier yet, or the
## flyout hasn't been populated — shouldn't happen post-_ready()).
func build_option_button(definition: BuildingDefinition) -> Button:
	return _build_buttons.get(definition)


func cat_inspector_panel() -> CatInspectorPanel:
	return _cat_panel


func building_inspector_panel() -> BuildingInspectorPanel:
	return _building_panel


func recipes_button() -> TextureButton:
	return _recipes_button


func adopt_cat_button() -> Button:
	return _cat_shop_button


func demolish_button() -> TextureButton:
	return _demolish_button


## Read by FactoryWorld to drive the one-time win sequence — see its
## class doc. Same "view owned here, orchestrated there" split as the
## panels above; FactoryWorld is the one that already owns
## capture_save_data()/scene loading, so it's the natural place to
## sequence the save + credits roll around this dialog's two beats.
func game_complete_dialog() -> GameCompleteDialog:
	return _game_complete_dialog
