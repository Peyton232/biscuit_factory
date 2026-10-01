class_name FactoryWorld
extends Node3D
## Root of the playable factory scene. Owns save/load: capture_save_data()
## walks the live gameplay nodes into a fresh FactorySaveData;
## apply_save_data() does the reverse, called from _ready() when
## SaveManager has a pending loaded save. SaveManager (autoload) only
## knows about slot files and session state — it has no idea what an
## Economy or a Building even is; this class is the one place that
## bridges "a save file" and "an actual running game."
##
## Restoring a save deliberately drops everything transient/
## reconstructible (in-flight DeliveryJobs, cat paths/station claims,
## in-progress processing batches) — see FactorySaveData's class doc.
## Every restored cat comes back IDLE and every restored building comes
## back unstaffed; the existing dispatch/station-polling systems
## reconstruct real activity within moments on their own.
##
## Also owns the one-time "you finished the game" sequence: the moment
## `tier_manager` advances into Tier Winner (its last tier), this shows
## `FactoryHud`'s `%GameCompleteDialog` ("You've done it!"), waits for the
## player to click Continue, saves the game (marking `completed = true`,
## which is what earns the save slot its gold star — see
## `FactorySaveData.completed` and `SaveSlotMenu`), shows a brief
## "Congratulations!" beat, then (✅ 2026-07-13, replacing the old
## `SceneLoader.load_scene(AppConfig.ending_scene_path)` full-scene swap
## to the template's `end_credits.tscn`) awaits `victory_sequence.play()`
## — a cinematic camera pan over this *same still-running* factory with
## credits rolling over it and a Bakery Report/Rank at the end, per
## gameplay_overview.md's "Ending & replayability". Only Employee Awards
## (a separate, not-yet-built backlog item) is missing from that
## sequence; play() otherwise hands control straight back to the player —
## this class is the natural home for the sequence since it already owns
## both capture_save_data()/SaveManager and is the one scene this all
## happens inside of; FactoryHud only owns the dialog as a view (see its
## class doc).
##
## Also owns the one-time "opening cutscene": for a genuinely new game
## (no pending save data to restore — see _ready()), fires
## `opening_sequence.play()` (fire-and-forget, same as
## `_run_game_complete_sequence()`'s own callers — nothing here needs to
## block on it) before the player ever sees the factory. A loaded/
## continued game never sees it, same treatment `tutorial_manager`
## already gives its own first step.
##
## Also decides *when* `tier_music_controller` actually starts playing,
## rather than letting it default to "the instant the scene loads" (see
## TierMusicController's own class doc for why `_ready()` only builds the
## stream and tracks the current tier — it never starts playback itself):
## immediately for a loaded save (already at the correct tier the moment
## the factory appears), but only once `opening_sequence.message_dismissed`
## fires for a brand new game — starting music under a still-empty,
## cat-less factory during the opening's walk-in would undercut that beat.

@export var economy: Economy
@export var tier_manager: TierManager
@export var recipe_shop: RecipeShop
@export var lifetime_stats: LifetimeStats
@export var buildings_root: Node3D
@export var cats_root: Node3D
@export var grid_manager: GridManager
@export var factory_bounds: FactoryBounds
@export var building_placer: BuildingPlacer
@export var cat_shop: CatShop
@export var tutorial_manager: TutorialManager
@export var factory_hud: FactoryHud
@export var victory_sequence: VictorySequence
@export var opening_sequence: OpeningSequence
@export var tier_music_controller: TierMusicController

## How long the "Congratulations!" beat sits on screen before the credits
## scene loads — long enough to read, short enough not to feel stuck.
const _CONGRATULATIONS_DISPLAY_SECONDS: float = 2.5
## Played once the "Congratulations!" beat shows, right before the
## credits (victory_sequence.play()) roll — see class doc.
const _ENDING_SOUND: AudioStream = preload("res://assets/sounds/effects/ending.wav")
## How long the tier music takes to duck down before _ENDING_SOUND plays,
## and to swell back up once it finishes — see _play_ending_sound().
## Reported as "ending.wav gets buried under the still-playing tier
## music"; same duration used for both directions.
const _ENDING_DUCK_SECONDS: float = 3.0
## How far the tier music ducks while _ENDING_SOUND plays, as a fraction
## of its own current volume — halved rather than silenced so the loop
## doesn't feel like it stopped, just steps back for the sting.
const _ENDING_DUCK_VOLUME: float = 0.5

## True once Tier Winner has ever been reached this session or restored
## from a loaded save — see class doc and FactorySaveData.completed.
var _completed: bool = false


func _ready() -> void:
	var data: FactorySaveData = SaveManager.take_pending_save_data()
	if data != null:
		apply_save_data(data)
		_start_tier_music()
	elif opening_sequence != null:
		if tier_music_controller != null:
			opening_sequence.message_dismissed.connect(
					tier_music_controller.start_playback, CONNECT_ONE_SHOT)
		opening_sequence.play()
	else:
		_start_tier_music()
	if tier_manager != null:
		tier_manager.tier_advanced.connect(_on_tier_advanced)


func _start_tier_music() -> void:
	if tier_music_controller != null:
		tier_music_controller.start_playback()


## Builds a fresh snapshot of the current game state.
func capture_save_data() -> FactorySaveData:
	var data := FactorySaveData.new()
	data.money = economy.money
	data.completed = _completed
	tier_manager.save_state(data)
	recipe_shop.save_state(data)
	lifetime_stats.save_state(data)
	if factory_bounds != null:
		factory_bounds.save_state(data)
	for building: Node in buildings_root.get_children():
		if building is Building:
			data.buildings.append((building as Building).save_entry())
	for cat: Node in cats_root.get_children():
		if cat is Cat:
			data.cats.append((cat as Cat).save_entry())
	return data


## Restores a previously-captured snapshot. Called once, from _ready(),
## before any frame renders — every child's own _ready() (Economy
## seeding starting_money, ShippingBin seeding its default accepted
## items, TutorialManager showing step 1, etc.) has already run by this
## point, since Godot calls children's _ready() before the parent's own;
## this simply overwrites that fresh-game default state with the saved
## one.
func apply_save_data(data: FactorySaveData) -> void:
	economy.set_money(data.money)
	_completed = data.completed
	tier_manager.load_state(data)
	recipe_shop.load_state(data)
	lifetime_stats.load_state(data)
	if factory_bounds != null:
		factory_bounds.load_state(data)
	cat_shop.restore_adopted_count(lifetime_stats.cats_adopted_count)

	# factory_world.tscn bakes a starter cat ("Newby") directly under
	# Cats, and Buildings starts empty — both must be cleared before
	# reconstructing from the save, or a loaded game would end up with
	# Newby duplicated alongside the restored roster instead of replaced
	# by it. free() (not queue_free()) so they're actually gone before
	# anything else queries these roots this same frame.
	for cat: Node in cats_root.get_children():
		cat.free()
	for building: Node in buildings_root.get_children():
		building.free()

	for entry: BuildingSaveEntry in data.buildings:
		_restore_building(entry)
	for entry: CatSaveEntry in data.cats:
		cat_shop.restore_cat(entry)

	if tutorial_manager != null:
		tutorial_manager.skip_silently()


func _restore_building(entry: BuildingSaveEntry) -> void:
	var definition: BuildingDefinition = load(entry.definition_path) as BuildingDefinition
	if definition == null:
		return
	var building: Building = definition.scene.instantiate() as Building
	building.setup(grid_manager, entry.cell, definition)
	building_placer.inject_dependencies(building)
	buildings_root.add_child(building)
	building.load_entry(entry)


## Fires on every tier advancement, not just Winner — cheap to check and
## keeps this the single place that reacts to the signal for
## FactoryWorld's own concerns (FactoryHud has its own separate
## connection for its build-grid refresh).
func _on_tier_advanced(new_tier: int) -> void:
	if new_tier == TierManager.TIER_NAMES.size() - 1:
		_run_game_complete_sequence()


## See class doc. Only ever runs once per save's lifetime in practice —
## reaching Tier Winner a second time isn't possible (advance_tier() has
## nowhere further to go from it) — but is harmless to re-enter since
## nothing here is destructive.
func _run_game_complete_sequence() -> void:
	_completed = true
	if factory_hud == null:
		return
	var dialog: GameCompleteDialog = factory_hud.game_complete_dialog()
	dialog.show_message("You've done it! You've completed all the tiers!")
	await dialog.continue_pressed

	SaveManager.save_current_game(capture_save_data())

	dialog.show_message_no_button("Congratulations!")
	# Fire-and-forget, same idiom as opening_sequence.play() above — the
	# beat's own timer below isn't tied to this, so a missing
	# tier_music_controller still just plays the sound with no ducking.
	_play_ending_sound()
	await get_tree().create_timer(_CONGRATULATIONS_DISPLAY_SECONDS).timeout
	# VictorySequence only hides/shows factory_hud as a whole (a CanvasLayer)
	# around its own cinematic — it has no idea this dialog exists, so
	# without explicitly hiding it here, it stays internally visible=true
	# and pops right back into view the instant factory_hud.show() restores
	# the HUD at the end of the sequence. Reported as "the congratulations
	# textbox does not go away." See decisions.md.
	dialog.hide()

	if victory_sequence != null:
		await victory_sequence.play()


## Ducks tier_music_controller down to _ENDING_DUCK_VOLUME, plays
## _ENDING_SOUND once that fade completes, then swells the music back up
## to full once the sound itself finishes — see class doc and the
## _ENDING_DUCK_* consts. unduck() is deliberately not awaited: the swell
## is meant to keep going underneath (bleeding into) the start of
## victory_sequence's credits, not block anything further.
func _play_ending_sound() -> void:
	if tier_music_controller == null:
		Sfx.spawn(self, _ENDING_SOUND)
		return
	await tier_music_controller.duck(_ENDING_DUCK_VOLUME, _ENDING_DUCK_SECONDS)
	var ending_player: AudioStreamPlayer = Sfx.spawn(self, _ENDING_SOUND)
	await ending_player.finished
	tier_music_controller.unduck(_ENDING_DUCK_SECONDS)
