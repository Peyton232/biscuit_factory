class_name TutorialManager
extends Node
## Drives the interactive first-time tutorial: making and selling one
## batch of Whipped Cream (Milk -> Mixer -> Shipping Bin), the game's
## simplest possible production loop. A linear sequence of TutorialStep
## entries, each shown via TutorialOverlay (instruction text + a
## highlight rect over the relevant button) and advanced either
## automatically — once its is_complete Callable polls true, checked
## every frame — or manually via the overlay's Next button, which always
## works as an escape hatch regardless of real game state. Skippable at
## any time via the overlay's Skip button, which ends the tutorial for
## the rest of this session.
##
## Runs unconditionally on every load of factory_world.tscn — there's no
## save/settings system yet (see architecture.md) to remember "already
## seen", so this is a known, accepted gap until one exists (see
## decisions.md).
##
## With only one starting cat (Newby, role DELIVERY — see decisions.md
## for why the game starts with just one cat instead of the previous
## three), completing the loop actually requires reassigning Newby's
## role TWICE: to MIXER to whip the cream, then back to DELIVERY to ship
## it — the tutorial's steps walk through both, deliberately teaching
## the role-reassignment feature rather than working around the
## single-cat constraint with new mechanics.
##
## **Buildings start with no recipe selected** (see ProcessingBuilding's
## class doc) — a dedicated step teaches picking Whipped Cream on the
## Mixer via BuildingInspectorPanel, right after it's placed.
##
## **The base chapter's final step teaches cat adoption**, timed around
## $10 — the exact price of the second cat (see progression.md's cat
## adoption cost table) — rather than waiting for Tier 1: with only one
## cat, the player must keep manually toggling Newby between Mixer and
## Delivery to keep production going, so a second cat (one parked on the
## Mixer, one on delivery duty) is the natural next step the moment it's
## affordable.
##
## **A second, short chapter fires once Tier 1 unlocks** (see
## `_on_tier_advanced()`), teaching that most recipes now cost money to
## buy via the Recipe Book — the base chapter above never needs to touch
## money (Whipped Cream is free), so without this the player's first
## encounter with a locked recipe would have no guidance at all. It walks
## the player through buying the Bread recipe specifically (not just any
## recipe) and placing an Oven to actually bake it — `TierManager` grants
## a one-time $100 bonus on this same transition (see its own class doc)
## since Mixer/Oven plus a first recipe purchase adds up fast right after
## Tier 0 already spent the player down close to zero.

@export var overlay: TutorialOverlay
@export var factory_hud: FactoryHud
@export var buildings_root: Node3D
@export var cats_root: Node3D
@export var economy: Economy
@export var recipe_shop: RecipeShop
@export var tier_manager: TierManager

## One tutorial step: instructional text, an optional Callable returning
## the Control to highlight right now (or null / an invalid Callable for
## no highlight), and an optional Callable returning whether the step's
## real-world objective is already satisfied (checked every frame; an
## invalid Callable means the step only ever advances via Next).
class TutorialStep:
	var text: String
	var get_highlight: Callable
	var is_complete: Callable

	func _init(p_text: String, p_get_highlight: Callable = Callable(), p_is_complete: Callable = Callable()) -> void:
		text = p_text
		get_highlight = p_get_highlight
		is_complete = p_is_complete

var _steps: Array[TutorialStep] = []
var _step_index: int = 0
var _active: bool = true
var _money_at_step_start: int = 0
var _shown_tier1_chapter: bool = false
## Shown by _finish() — set fresh at the start of whichever chapter is
## currently running (_build_steps() / _on_tier_advanced()), since each
## chapter needs its own closing message, not one shared string.
var _finish_message: String = ""

var _milk_def: BuildingDefinition = preload("res://resources/buildings/milk_source.tres")
var _mixer_def: BuildingDefinition = preload("res://resources/buildings/mixer.tres")
var _bin_def: BuildingDefinition = preload("res://resources/buildings/shipping_bin.tres")
var _oven_def: BuildingDefinition = preload("res://resources/buildings/oven.tres")
var _whipped_cream_recipe: Recipe = preload("res://resources/recipes/whipped_cream.tres")
var _bread_recipe: Recipe = preload("res://resources/recipes/bread.tres")


func _ready() -> void:
	_build_steps()
	overlay.next_pressed.connect(_advance)
	overlay.skip_pressed.connect(_on_skip_pressed)
	_show_step(0)
	if tier_manager != null:
		tier_manager.tier_advanced.connect(_on_tier_advanced)


func _process(_delta: float) -> void:
	if not _active:
		return
	var step: TutorialStep = _steps[_step_index]
	overlay.set_highlight(step.get_highlight.call() if step.get_highlight.is_valid() else null)
	if step.is_complete.is_valid() and step.is_complete.call():
		_advance()


func _advance() -> void:
	if not _active:
		return
	_step_index += 1
	if _step_index >= _steps.size():
		_finish()
		return
	_show_step(_step_index)


func _show_step(index: int) -> void:
	_money_at_step_start = economy.money
	overlay.show_step(_steps[index].text, index + 1, _steps.size())


func _finish() -> void:
	_active = false
	overlay.show_finished(_finish_message)


func _on_skip_pressed() -> void:
	_active = false
	overlay.hide()


## Disables the tutorial without showing anything — called when
## restoring a loaded save (see FactoryWorld.apply_save_data()), since a
## returning player has already been through this. Never called for a
## brand-new game in an empty slot, which still runs the tutorial
## normally. Runs during the same _ready() cascade as _show_step(0)
## above (both are children of FactoryWorld, whose own _ready() runs
## last), so the first step never actually gets drawn.
func skip_silently() -> void:
	_active = false
	overlay.hide()


## Starts a short second chapter the first time Tier 1 unlocks, teaching
## that recipes generally cost money now (Whipped Cream was free, so the
## base chapter above never had to explain this) and that a bought
## recipe still needs the right station built to actually run. Only ever
## fires once; later tiers don't repeat it since both mechanics are
## already learned by then. TierManager grants a $100 bonus on this same
## transition (see its class doc) — this chapter spends it back down
## again (Bread recipe $10 + Oven $60), which is the intended point.
func _on_tier_advanced(new_tier: int) -> void:
	if new_tier != 1 or _shown_tier1_chapter:
		return
	_shown_tier1_chapter = true
	_finish_message = "Explore the Recipe Book and Build menu to keep growing your factory."
	_steps = [
		TutorialStep.new(
			"Tier 1 unlocked! Here's a $100 bonus to help you get going — new buildings are available to build, and most new recipes cost money to unlock (unlike Whipped Cream, which was free). Click Next to see where."),
		TutorialStep.new(
			"Open the Recipe Book and unlock the Bread recipe for $10.",
			func() -> Control: return factory_hud.recipes_button(),
			func() -> bool: return recipe_shop.is_unlocked(_bread_recipe)),
		TutorialStep.new(
			"Bread bakes in an Oven, not the Mixer — place one so you can actually make it.",
			func() -> Control: return _build_target(_oven_def),
			func() -> bool: return _has_building(func(b: Node) -> bool: return b is Oven)),
		TutorialStep.new(
			"Don't like where you placed something? Select Demolish (or press X) to remove it and get most of its cost back. One thing to keep in mind: some products — like Basic Dough or Toast — get reused in more advanced recipes later on, so think twice before tearing out an entire early production line. Click Next to continue.",
			func() -> Control: return factory_hud.demolish_button()),
		TutorialStep.new(
			"One more thing: each Shipping Bin lets you choose exactly which items it accepts. Click a bin and use its checklist if you'd rather route an item to another station instead of selling it."),
	]
	_step_index = 0
	_active = true
	_show_step(0)


## Highlight helper shared by every "place building X" step: the Build
## button itself while the flyout is closed, or that building's own
## option button once the flyout is open and showing it.
func _build_target(definition: BuildingDefinition) -> Control:
	if factory_hud.is_build_flyout_open():
		return factory_hud.build_option_button(definition)
	return factory_hud.build_button()


## Highlight helper shared by every "set a cat's role" step: only
## meaningful once a cat is actually selected (CatInspectorPanel visible)
## — otherwise there's nothing to point at yet, so no highlight at all.
func _role_target(role: Cat.Role) -> Control:
	var panel: CatInspectorPanel = factory_hud.cat_inspector_panel()
	if not panel.visible:
		return null
	return panel.role_button(role)


## Highlight helper for "pick this recipe on a station": only meaningful
## once a building is selected and its inspector panel is showing (the
## player must click the building first) — same spirit as _role_target().
func _recipe_target(recipe: Recipe) -> Control:
	var panel: BuildingInspectorPanel = factory_hud.building_inspector_panel()
	if not panel.visible:
		return null
	return panel.recipe_button(recipe)


func _has_building(check: Callable) -> bool:
	for building: Node in buildings_root.get_children():
		if check.call(building):
			return true
	return false


func _has_cat_with_role(role: Cat.Role) -> bool:
	for cat: Node in cats_root.get_children():
		if cat is Cat and (cat as Cat).role == role:
			return true
	return false


func _has_more_than_one_cat() -> bool:
	return cats_root.get_child_count() > 1


func _build_steps() -> void:
	_finish_message = "Nice work — you made and sold your first batch of Whipped Cream and adopted a second cat! Explore the Build menu and Recipe Book to keep growing your factory."
	_steps = [
		TutorialStep.new(
			"Welcome to your factory! Let's make and sell your first product: Whipped Cream. Click Next to begin."),
		TutorialStep.new(
			"Open the Build menu and place a Milk Source anywhere on the grid. (Right-click cancels whatever you're currently placing, if you change your mind.)",
			func() -> Control: return _build_target(_milk_def),
			func() -> bool: return _has_building(func(b: Node) -> bool: return b is Building and (b as Building).definition == _milk_def)),
		TutorialStep.new(
			"Now place a Mixer next to it.",
			func() -> Control: return _build_target(_mixer_def),
			func() -> bool: return _has_building(func(b: Node) -> bool: return b is Mixer)),
		TutorialStep.new(
			"Buildings start with no recipe selected. Click on your Mixer to select it, then choose Whipped Cream from its recipe list.",
			func() -> Control: return _recipe_target(_whipped_cream_recipe),
			func() -> bool: return _has_building(func(b: Node) -> bool: return b is Mixer and (b as Mixer).recipe == _whipped_cream_recipe)),
		TutorialStep.new(
			"Place a Shipping Bin too, so you have somewhere to sell the finished cream.",
			func() -> Control: return _build_target(_bin_def),
			func() -> bool: return _has_building(func(b: Node) -> bool: return b is ShippingBin)),
		TutorialStep.new(
			"Click on Newby to select him, then assign him to the Mixer role so he can whip the milk into cream.",
			func() -> Control: return _role_target(Cat.Role.MIXER),
			func() -> bool: return _has_cat_with_role(Cat.Role.MIXER)),
		TutorialStep.new(
			"Once Newby has whipped up some cream, switch him back to Delivery so he can carry it to your Shipping Bin.",
			func() -> Control: return _role_target(Cat.Role.DELIVERY),
			func() -> bool: return _has_cat_with_role(Cat.Role.DELIVERY)),
		TutorialStep.new(
			"Now sit back and watch Newby deliver the cream and get paid!",
			Callable(),
			func() -> bool: return economy.money > _money_at_step_start),
		TutorialStep.new(
			"Once you've saved up $10, click Adopt Cat to bring home a second one — between staffing stations and running deliveries, you'll probably have dozens of these little guys running around your factory before long!",
			func() -> Control: return factory_hud.adopt_cat_button(),
			func() -> bool: return _has_more_than_one_cat()),
	]
