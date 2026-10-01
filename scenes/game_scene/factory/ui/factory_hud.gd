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
## Swapped in globally (Input.set_custom_mouse_cursor) while the player is
## actively carrying a cat or relocating a building — see _update_cursor().
## _CURSOR_NORMAL/_CURSOR_NORMAL_HOTSPOT duplicate the same texture/hotspot
## MainMenuWithAnimations applies once the title screen first appears (✅
## 2026-07-15 — no longer a project.godot mouse_cursor/custom_image setting,
## see that script's own doc comment for why), since reverting away from a
## custom cursor requires re-setting the original one explicitly (passing
## null clears back to the bare OS pointer, not back to this game's own).
## Both cursor.png/cursor pinch.png were shrunk 50x50 -> 36x36 (✅
## 2026-07-15, "make the cursor a little smaller") — hotspots below are
## scaled by the same 36/50 factor to stay pinned to the same visual
## point on the art (the fingertip/pinch point), not just the top-left.
const _CURSOR_NORMAL: Texture2D = preload("res://assets/UI/cursor.png")
const _CURSOR_NORMAL_HOTSPOT := Vector2(1, 0)
const _CURSOR_PINCH: Texture2D = preload("res://assets/UI/cursor pinch.png")
const _CURSOR_PINCH_HOTSPOT := Vector2(16, 6)
## Pause/Settings top-right icon buttons — PNG, not JPEG (real alpha
## backgrounds, unlike the square opaque bottom-bar icons above), built
## the same way via _make_icon_button() (see _populate_top_right()).
const _PAUSE_ICON: Texture2D = preload("res://assets/UI/Pause.png")
const _SETTINGS_ICON: Texture2D = preload("res://assets/UI/Settings.png")

## How long the insufficient-funds warning sits at full opacity before
## UiFade takes it away — a fade alone starts vanishing immediately,
## which is too quick to read two words and look back at your money.
const _WARNING_HOLD_SECONDS: float = 1.2

const _TIER_COMPLETE_SOUND: AudioStream = preload("res://assets/sounds/effects/tier_complete.wav")
const _EXPANSION_SOUND: AudioStream = preload("res://assets/sounds/effects/factory_expansion.wav")

## PlayerConfig section/key backing the Settings > Game tab's "Expanded
## Info HUD" checkbox (see menus/options_menu/game/expanded_info_hud_control/) —
## public so that control reads/writes the exact same section/key
## FactoryHud itself polls below, rather than a second copy of the same
## two strings risking drift. Section reuses AppSettings.GAME_SECTION (the
## template's own convention for this kind of setting) rather than
## inventing a project-specific one.
## Clear space to leave between the centred tier banner and the cards on
## either side of it — see _fit_tier_banner().
const _TIER_BANNER_GAP_PX: float = 12.0
## Floor on the banner's width, so a very narrow window wraps the goal
## line hard rather than collapsing the banner to nothing.
const _TIER_BANNER_MIN_WIDTH_PX: float = 240.0

const EXPANDED_INFO_HUD_SECTION: StringName = AppSettings.GAME_SECTION
const EXPANDED_INFO_HUD_KEY: StringName = &"ExpandedInfoHud"

## Shared pill-button art (see UiButtonStyle) for the bottom bar's
## remaining dynamic-text buttons (Adopt Cat/Adopt Multiple/Expand
## Factory). See _make_pill_button().

## Last text/width _fit_tier_banner() measured for, so it re-measures on
## change instead of on every frame.
var _fitted_tier_text: String = ""
var _fitted_viewport_width: float = -1.0

@onready var _money_label: Label = %MoneyLabel
@onready var _tool_label: Label = %ToolLabel
@onready var _fps_label: Label = %FpsLabel
@onready var _jobs_label: Label = %JobsLabel
@onready var _tier_label: Label = %TierLabel
@onready var _tier_panel: PanelContainer = %TopCenter
@onready var _top_left: PanelContainer = %TopLeft
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
@onready var _insufficient_funds_label: Label = %InsufficientFundsLabel

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
	cat_selector.held_changed.connect(_on_cat_held_changed)
	building_selector.selection_changed.connect(_on_building_selection_changed)
	cat_shop.cost_changed.connect(_on_cat_shop_cost_changed)
	_cat_panel.name_changed.connect(_on_cat_name_changed)
	_cat_panel.role_selected.connect(_on_cat_role_selected)
	_cat_panel.pick_up_pressed.connect(_on_cat_pick_up_pressed)
	_cat_panel.pet_pressed.connect(_on_cat_pet_pressed)
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
	_build_back_button.pressed.connect(func() -> void: UiFade.out(_build_flyout))
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


## Keeps the tier/goal banner from growing out from under the money card.
##
## `TopCenter` is a content-hugging PanelContainer centred with
## `grow_horizontal = BOTH`, so it widens symmetrically to fit whatever
## `TierLabel` holds. That is fine for "Tier 0", but a Tier 5 goal line
## lists five products with their counts and measures **766 px** at the
## default font — wider than the free gap between the money card and the
## pause buttons, so the banner grew straight underneath both. Reported
## as "tier 5 goals conflicts with money and tool box".
##
## Rather than pin the banner to a fixed width (which would leave "Tier
## 0" rattling around in a wide empty box), the label is switched between
## two modes: hug the text while it fits, wrap inside the available gap
## once it doesn't. `custom_minimum_size.x` is the lever, because an
## autowrapping Label reports a minimum width of roughly one word
## (measured: 33 px), so it is the only thing keeping the panel open.
##
## Recomputed only when the text or the window width actually changes —
## `_update_tier_readout()` runs every frame and re-measuring a string
## against the font 60 times a second for an unchanged answer is waste.
func _fit_tier_banner() -> void:
	var viewport_width: float = get_viewport().get_visible_rect().size.x
	if _tier_label.text == _fitted_tier_text and is_equal_approx(viewport_width, _fitted_viewport_width):
		return
	_fitted_tier_text = _tier_label.text
	_fitted_viewport_width = viewport_width

	# The banner is centred, so whichever side has less room governs both.
	var left_clearance: float = _top_left.position.x + _top_left.size.x
	var right_clearance: float = viewport_width - _top_right.position.x
	var clearance: float = maxf(left_clearance, right_clearance) + _TIER_BANNER_GAP_PX
	var available: float = maxf(_TIER_BANNER_MIN_WIDTH_PX, viewport_width - clearance * 2.0)

	var font: Font = _tier_label.get_theme_font("font")
	var font_size: int = _tier_label.get_theme_font_size("font_size")
	var natural: float = font.get_string_size(_tier_label.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var chrome: float = _tier_banner_chrome_width()
	if natural + chrome <= available:
		_tier_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_tier_label.custom_minimum_size.x = 0.0
	else:
		_tier_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tier_label.custom_minimum_size.x = available - chrome


## Everything eating horizontal space inside the banner before the label
## gets any: the MarginContainer's own constants **and** the panel
## StyleBox's content margins. Measured rather than assumed — the card
## art's margins alone are 48 px here, and leaving them out of the sum
## is what left the banner still overlapping the money card by 12 px on
## the first attempt at this fix.
func _tier_banner_chrome_width() -> float:
	var margin: MarginContainer = _tier_panel.get_node("Margin")
	var style: StyleBox = _tier_panel.get_theme_stylebox("panel")
	return margin.get_theme_constant("margin_left") \
			+ margin.get_theme_constant("margin_right") \
			+ style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)


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
	_fit_tier_banner()
	# Confetti fires the moment the button *appears* (the player just
	# completed the tier's goal), not when they click it — "tier complete
	# isn't obvious enough" playtest feedback, same motivation the button
	# itself exists for; celebrating on click only rewards a player who
	# already noticed the button was there.
	var can_advance: bool = tier_manager.can_advance()
	if _tier_readout_primed and can_advance and not _tier_complete_button.visible:
		TierCompleteConfetti.spawn(self)
		# The sting belongs HERE, with the confetti, not on the button
		# click below (✅ fixed — "I completed tier 0 but did not hear the
		# tier complete noise"). The confetti was already moved to this
		# moment for exactly the reason in the comment above; the sound
		# was left behind on the click, so a player who completed a tier
		# and hadn't yet spotted the button — the case that comment is
		# about — got a silent celebration. Clicking the button still
		# makes the template's ordinary UI click sound.
		Sfx.spawn(self, _TIER_COMPLETE_SOUND)
	_tier_complete_button.visible = can_advance
	_tier_readout_primed = true


func _on_tier_complete_pressed() -> void:
	if tier_manager != null and tier_manager.can_advance():
		tier_manager.advance_tier()


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
	# A fading flyout counts as closed, so clicking Build again mid-fade
	# reopens it rather than reading as "it's still visible, close it".
	if _build_flyout.visible and not UiFade.is_fading(_build_flyout):
		UiFade.out(_build_flyout)
		return
	UiFade.show_now(_build_flyout)
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
	UiFade.out(_build_flyout)
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
	UiFade.out(_build_flyout)


func _on_cat_placing_changed() -> void:
	_refresh_tool_label()


func _on_building_move_pressed(building: Building) -> void:
	building_mover.begin_move(building)
	_building_panel.hide()


func _on_building_moving_changed() -> void:
	_refresh_tool_label()
	_update_cursor()


func _on_cat_held_changed(_cat: Cat) -> void:
	_update_cursor()


## Pinch cursor while the player is actively carrying a cat or relocating
## a building — both are a "you're holding something, click to place it"
## interaction, so they share one cursor rather than each needing its own
## visual language.
func _update_cursor() -> void:
	var pinching: bool = cat_selector.is_holding() \
			or (building_mover != null and building_mover.is_moving())
	if pinching:
		Input.set_custom_mouse_cursor(_CURSOR_PINCH, Input.CURSOR_ARROW, _CURSOR_PINCH_HOTSPOT)
	else:
		Input.set_custom_mouse_cursor(_CURSOR_NORMAL, Input.CURSOR_ARROW, _CURSOR_NORMAL_HOTSPOT)
	# Known Godot engine limitation: set_custom_mouse_cursor() updates
	# immediately internally, but the OS-drawn cursor image itself only
	# redraws on the next mouse motion/window-enter event on several
	# platforms — reported as the pinch cursor sticking around after a
	# building move is confirmed by a click (no mouse motion involved).
	# warp_mouse() to the mouse's own position forces an immediate redraw
	# without actually moving the cursor.
	Input.warp_mouse(get_viewport().get_mouse_position())


## Appends the cancel hint whenever a tool is actually held (✅ — "not
## sure how to make it clear that the player can right click to unselect
## whatever building they are currently placing"). Shown only while
## something is selected, so it reads as an instruction about the thing
## in hand rather than permanent HUD noise; and shown on the Tool line
## itself, which is already the one place the HUD says what you're
## holding, rather than as a new floating element to collide with
## something.
func _refresh_tool_label() -> void:
	var label: String = ""
	if cat_placer != null and cat_placer.is_placing():
		label = cat_placer.tool_label()
	elif building_mover != null and building_mover.is_moving():
		label = building_mover.tool_label()
	else:
		label = placer.tool_label()
	_tool_label.text = "Tool: %s" % label
	if _tool_is_active():
		_tool_label.text += "  (right-click to cancel)"


## Whether the player is currently holding something a right-click would
## put down — a building to place, a cat to position, or a building being
## moved. Mirrors the three modes _on_tool_changed() treats as mutually
## exclusive.
func _tool_is_active() -> bool:
	if cat_placer != null and cat_placer.is_placing():
		return true
	if building_mover != null and building_mover.is_moving():
		return true
	return placer.selected_definition() != null or placer.is_demolish_mode()


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
	# Checked HERE rather than at the end of the flow (✅ fixed — "if you
	# don't have enough for adopt a cat, you still get to the point of
	# being able to place"). Nothing charged the player until placement
	# resolved, so an unaffordable adoption used to walk them through
	# naming a cat, picking its role, and lining up a placement before
	# silently failing — all the work, no cat, no explanation.
	UiFade.out(_build_flyout)
	if not cat_shop.can_afford():
		_flash_insufficient_funds()
		return
	_cat_batch_dialog.hide()
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
	UiFade.out(_build_flyout)
	if not cat_shop.can_afford():
		_flash_insufficient_funds()
		return
	# The two adopt dialogs sit on the same screen rectangle, and nothing
	# used to close one when the other opened — the overlap audit caught
	# them stacked (see decisions.md).
	_cat_naming_dialog.hide()
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


## Brief red warning over the bottom bar, held long enough to read and
## then faded out. A one-line message beats disabling the Adopt Cat
## button outright: a dead button tells the player nothing about *why*,
## and the button's own label already shows the price they're short of.
func _flash_insufficient_funds() -> void:
	_insufficient_funds_label.text = "Insufficient funds"
	UiFade.show_now(_insufficient_funds_label)
	UiFade.out_after(_insufficient_funds_label, _WARNING_HOLD_SECONDS)


func _on_cat_shop_cost_changed(_cost: int) -> void:
	_update_cat_shop_button()


func _update_cat_shop_button() -> void:
	_cat_shop_button.text = "Adopt Cat  $%d" % cat_shop.current_cost()


func _on_expand_pressed() -> void:
	# Same up-front check the adopt buttons do: try_expand() fails
	# silently on an unaffordable expansion (its try_spend() just returns
	# false), which left the player clicking a button that did nothing.
	if factory_bounds.can_expand_further() and not economy.can_afford(factory_bounds.current_cost()):
		_flash_insufficient_funds()
		return
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
		UiFade.cancel(_cat_panel)
		_cat_panel.show_for_cat(cat)
	else:
		_cat_panel.hide()


## Naming and role-picking are both "I'm done with this cat" actions, so
## the panel sees itself out rather than sitting there until the player
## happens to click empty ground or press ESC (✅ — "after they name a cat
## or select a role it should fade"). The cat stays *selected* (its hover
## outline still reads), so clicking it again brings the panel straight
## back; only the panel leaves.
func _on_cat_name_changed(new_name: String) -> void:
	if _selected_cat != null:
		_selected_cat.set_cat_name(new_name)
		UiFade.out(_cat_panel)


func _on_cat_role_selected(role: Cat.Role) -> void:
	if _selected_cat != null:
		_selected_cat.set_role(role)
		# Still refresh first: the panel is visible for the whole fade,
		# so it has to show the role that was just picked rather than
		# fading out still displaying the old one.
		_cat_panel.show_for_cat(_selected_cat)
		UiFade.out(_cat_panel)


## **Deliberately does not fade the panel**, unlike picking a role or
## entering a name. Those are "I'm done with this cat" actions; petting
## is something you do repeatedly, and dismissing the panel after one pet
## would mean re-selecting the cat to do it again. Same reasoning as the
## Shipping Bin checklist keeping its panel open.
func _on_cat_pet_pressed() -> void:
	if _selected_cat != null:
		_selected_cat.pet()


func _on_cat_pick_up_pressed() -> void:
	cat_selector.begin_hold()


func _on_building_selection_changed(building: Building) -> void:
	_selected_building = building
	if building != null:
		_cat_panel.hide()
		UiFade.cancel(_building_panel)
		_building_panel.show_for_building(building)
	else:
		_building_panel.hide()


## Picking a recipe finishes the job this panel was opened for, so it
## fades away like the cat panel does. **Deliberately NOT done for the
## Shipping Bin checklist** (`_on_bin_item_toggled`/`_on_bin_all_toggled`
## below): that list is inherently multi-select — a player routing three
## items away from a bin would have to re-open the panel between every
## checkbox.
func _on_building_recipe_selected(recipe: Recipe) -> void:
	var processing: ProcessingBuilding = _selected_building as ProcessingBuilding
	if processing != null:
		processing.assign_recipe(recipe)
		_building_panel.show_for_building(processing)
		UiFade.out(_building_panel)


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


## The Building the player currently has selected, or null. Unlike the
## panel getters above (which the tutorial highlights *against*), this is
## a state query: the Tier 1 chapter's "click one of your Shipping Bins"
## step completes on it.
func selected_building() -> Building:
	return _selected_building


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
