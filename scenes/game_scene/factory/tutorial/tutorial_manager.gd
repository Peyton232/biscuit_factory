class_name TutorialManager
extends Node
## Drives the interactive first-time tutorial: making and selling one
## batch of Whipped Cream (Milk -> Mixer -> Shipping Bin), the game's
## simplest possible production loop. A linear sequence of TutorialStep
## entries, each shown via TutorialOverlay (instruction text + a
## highlight rect over the relevant button) and advanced **only** by the
## player actually doing what it asks: its is_complete Callable, polled
## every frame against real game state. Skippable at any time via the
## overlay's Skip button, which ends the tutorial for the rest of this
## session.
##
## **There is no Next button** (removed 2026-09-17, by request — see
## decisions.md). Every step therefore needs a real is_complete, since
## Skip is now the only other way forward; _show_step() asserts as much
## rather than letting an is_complete-less step soft-lock the panel.
## Steps that used to be pure exposition ending in "Click Next" are
## either folded into the following step's text or given a small real
## objective of their own (open a bin's checklist, arm Demolish).
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

## Emitted when a chapter finishes by being completed (NOT when it is
## skipped) — the achievement tracker listens for the Tier 1 one. Carries
## which chapter so "completed the tutorial" can mean a specific one
## rather than "some tutorial ended".
signal chapter_completed(chapter: StringName)

const CHAPTER_BASE: StringName = &"base"
const CHAPTER_TIER_1: StringName = &"tier_1"

@export var overlay: TutorialOverlay
@export var factory_hud: FactoryHud
@export var buildings_root: Node3D
@export var cats_root: Node3D
@export var economy: Economy
@export var recipe_shop: RecipeShop
@export var tier_manager: TierManager
## Only used to tell whether Demolish is currently armed — the Tier 1
## chapter's last step asks the player to arm it (see is_demolish_mode()).
@export var building_placer: BuildingPlacer

## One tutorial step: instructional text, an optional Callable returning
## the Control to highlight right now (or null / an invalid Callable for
## no highlight), and a Callable returning whether the step's real-world
## objective is satisfied (checked every frame — required in practice,
## see _show_step()'s assert).
class TutorialStep:
	var text: String
	var get_highlight: Callable
	var is_complete: Callable
	## For the handful of steps whose objective is a *transient UI state*
	## the player might already happen to be in the moment the step
	## appears (a Shipping Bin still selected, Demolish still armed)
	## rather than a durable one (a building exists, a recipe is bought).
	## Such a step would otherwise read complete on its very first frame
	## and flash past unread. When true, a step that starts out already
	## satisfied waits for that state to clear and then happen again, so
	## the player really does perform the action. Left false everywhere
	## else on purpose: for a durable objective, "already done it" should
	## absolutely count — a player who ran ahead and placed the Mixer
	## early shouldn't have to demolish and rebuild it.
	var needs_fresh_action: bool

	func _init(p_text: String, p_get_highlight: Callable = Callable(), p_is_complete: Callable = Callable(), p_needs_fresh_action: bool = false) -> void:
		text = p_text
		get_highlight = p_get_highlight
		is_complete = p_is_complete
		needs_fresh_action = p_needs_fresh_action

var _steps: Array[TutorialStep] = []
var _step_index: int = 0
var _active: bool = true
var _money_at_step_start: int = 0
var _shown_tier1_chapter: bool = false
## Set only by the player pressing Skip Tutorial — NOT by
## skip_silently(). See _on_tier_advanced() for why the two differ.
var _player_skipped: bool = false
## Running count of buildings the player has demolished, and its value
## when the current step began. The demolish step completes on the
## difference, same snapshot idiom as _money_at_step_start.
var _demolitions: int = 0
var _demolitions_at_step_start: int = 0
## Set at _show_step() for a needs_fresh_action step that's already
## satisfied on arrival; cleared by _process() once the state clears.
var _awaiting_fresh_action: bool = false
## Shown by _finish() — set fresh at the start of whichever chapter is
## currently running (_build_steps() / _on_tier_advanced()), since each
## chapter needs its own closing message, not one shared string.
var _finish_message: String = ""
## Which chapter's steps are currently loaded, reported by
## chapter_completed when they run out.
var _chapter: StringName = CHAPTER_BASE

var _milk_def: BuildingDefinition = preload("res://resources/buildings/milk_source.tres")
var _mixer_def: BuildingDefinition = preload("res://resources/buildings/mixer.tres")
var _bin_def: BuildingDefinition = preload("res://resources/buildings/shipping_bin.tres")
var _oven_def: BuildingDefinition = preload("res://resources/buildings/oven.tres")
var _whipped_cream_recipe: Recipe = preload("res://resources/recipes/whipped_cream.tres")
var _bread_recipe: Recipe = preload("res://resources/recipes/bread.tres")


func _ready() -> void:
	_build_steps()
	overlay.skip_pressed.connect(_on_skip_pressed)
	if building_placer != null:
		building_placer.building_demolished.connect(_on_building_demolished)
	_show_step(0)
	if tier_manager != null:
		tier_manager.tier_advanced.connect(_on_tier_advanced)


func _process(_delta: float) -> void:
	if not _active:
		return
	var step: TutorialStep = _steps[_step_index]
	overlay.set_highlight(step.get_highlight.call() if step.get_highlight.is_valid() else null)
	if not step.is_complete.is_valid():
		return
	var complete: bool = step.is_complete.call()
	if _awaiting_fresh_action:
		# Still waiting for the state this step arrived already-satisfied
		# in to clear, so the player's own action is what advances it.
		_awaiting_fresh_action = complete
		return
	if complete:
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
	var step: TutorialStep = _steps[index]
	# With no Next button, a step that can't complete itself would leave
	# Skip as the only way on — a soft-lock, and an easy mistake to make
	# when adding a step. Caught here in debug builds rather than in a
	# playtest. (Stripped from release builds, hence the is_valid() guard
	# below rather than relying on this.)
	assert(step.is_complete.is_valid(),
			"Tutorial step %d has no is_complete, so it could never advance." % index)
	_money_at_step_start = economy.money
	_demolitions_at_step_start = _demolitions
	_awaiting_fresh_action = step.needs_fresh_action \
			and step.is_complete.is_valid() and step.is_complete.call()
	overlay.show_step(step.text, index + 1, _steps.size())


func _finish() -> void:
	_active = false
	overlay.show_finished(_finish_message)
	chapter_completed.emit(_chapter)


## Shows one last summary instead of just vanishing (✅ fixed — reported
## as "tutorial can be skipped then it's confusing," since a player could
## skip before ever seeing the recipe-selection or role-reassignment
## steps and be left with literally zero guidance). Reuses
## overlay.show_finished() — same "Skip becomes Close" mechanic the
## normal completion path already uses — with a generic reminder covering
## the two mechanics every chapter otherwise explains (recipe selection,
## role reassignment), since skip can fire before either was ever shown.
const _SKIP_MESSAGE: String = "Tutorial skipped. Reminders: build from the " \
		+ "Build menu, click a station to pick its recipe, and click a cat " \
		+ "to assign its role so it can staff a station."


## The overlay's Skip/Close button always fires this same signal (see
## TutorialOverlay) — _active distinguishes a genuine mid-tutorial Skip
## (show the reminder once) from the Close click that follows it, or from
## Close after a normal _finish() (both should just hide; _finish() has
## already set _active false and shown its own message by then).
func _on_skip_pressed() -> void:
	if _active:
		_active = false
		# "Skip Tutorial" means the tutorial, not this chapter of it (✅
		# 2026-09-17). Without this flag _on_tier_advanced() would happily
		# re-activate and start the Tier 1 chapter later, ambushing a
		# player who had already said they were done with it.
		_player_skipped = true
		overlay.show_finished(_SKIP_MESSAGE, "Tutorial skipped")
	else:
		overlay.hide()


func _on_building_demolished() -> void:
	_demolitions += 1


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
## already learned by then.
##
## **The chapter's last step waits for a building to actually be
## demolished, not for the tool to be armed** (✅ 2026-09-17 — "the
## demolish tutorial disappears after hitting the demolish in the
## bottom"): arming taught the button but not the click that follows,
## and the panel vanished before the player had done the thing.
## Demolishing refunds the building's FULL cost (decisions.md,
## 2026-07-09), which is what makes it fair to require — and is why the
## step's text no longer says "most of its cost", which was simply
## wrong.
##
## TierManager grants a $100 bonus on this same
## transition (see its class doc) — this chapter spends it back down
## again (Bread recipe $10 + Oven $60), which is the intended point.
## Deliberately gated on _player_skipped but NOT on skip_silently()'s
## own path: a loaded save suppresses the base chapter because that
## player has already seen it, but they may never have seen THIS
## chapter, so it should still fire for them. Only an explicit "Skip
## Tutorial" press means "no more tutorial".
func _on_tier_advanced(new_tier: int) -> void:
	if new_tier != 1 or _shown_tier1_chapter or _player_skipped:
		return
	_shown_tier1_chapter = true
	_chapter = CHAPTER_TIER_1
	_finish_message = "Explore the Recipe Book and Build menu to keep growing your factory."
	_steps = [
		TutorialStep.new(
			"Tier 1 unlocked! Here's a $100 bonus to help you get going. Most new recipes cost money to unlock (unlike Whipped Cream, which was free). Open the Recipe Book and unlock the Bread recipe for $10.",
			func() -> Control: return factory_hud.recipes_button(),
			func() -> bool: return recipe_shop.is_unlocked(_bread_recipe)),
		TutorialStep.new(
			"New buildings are available to build now too, and Bread bakes in an Oven, not the Mixer, so place one to actually make it.",
			func() -> Control: return _build_target(_oven_def),
			func() -> bool: return _has_building(func(b: Node) -> bool: return b is Oven)),
		TutorialStep.new(
			"Each Shipping Bin lets you choose exactly which items it accepts. Click one of your bins to see its checklist. Handy when you'd rather route an item to another station than sell it.",
			Callable(),
			func() -> bool: return _inspecting_shipping_bin(),
			true),
		TutorialStep.new(
			"Last thing: select Demolish (or press X), then click a building to remove it. You get its full cost back, so trying this costs you nothing. (Right-click or Esc puts the tool away without removing anything.) Think twice before tearing out an early production line, though: some products, like Basic Dough or Toast, get reused in later recipes.",
			func() -> Control: return factory_hud.demolish_button(),
			func() -> bool: return _demolitions > _demolitions_at_step_start),
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


## True while the player has one of their Shipping Bins selected, which
## is exactly when its accept-list checklist is on screen.
func _inspecting_shipping_bin() -> bool:
	return factory_hud.selected_building() is ShippingBin


func _build_steps() -> void:
	_chapter = CHAPTER_BASE
	_finish_message = "Nice work! You made and sold your first batch of Whipped Cream and adopted a second cat! Explore the Build menu and Recipe Book to keep growing your factory."
	_steps = [
		TutorialStep.new(
			"Welcome to your factory! Let's make and sell your first product: Whipped Cream. Open the Build menu and place a Milk Source anywhere on the grid. (Right-click cancels whatever you're currently placing, if you change your mind.)",
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
			"Once you've saved up $10, click Adopt Cat to bring home a second one. Between staffing stations and running deliveries, you'll probably have dozens of these little guys running around your factory before long!",
			func() -> Control: return factory_hud.adopt_cat_button(),
			func() -> bool: return _has_more_than_one_cat()),
	]
