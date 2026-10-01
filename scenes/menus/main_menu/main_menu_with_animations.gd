extends MainMenu
## Main menu extension that adds options and animates the title and menu fading in.
## The scene adds a 'Continue' button if a game is in progress.
## The animation can be skipped by the player with any input.
##
## **Applies the game's custom cursor here, not via project.godot's
## mouse_cursor/custom_image (✅ 2026-07-15)** — that setting applies the
## cursor from the very first frame, including over the studio-logo
## `opening.tscn` splash before this menu ever loads; requested to only
## show once the actual title screen appears. FactoryHud's own
## `_CURSOR_NORMAL`/`_CURSOR_NORMAL_HOTSPOT` (used to restore the normal
## cursor after the pinch-cursor swap while carrying a cat/building)
## duplicate this same texture+hotspot — see its own doc comment.

const _CURSOR: Texture2D = preload("res://assets/UI/cursor.png")
## Scaled by the same 36/50 factor as FactoryHud's own copy of this
## hotspot — see its own doc comment (cursor.png shrunk 2026-07-15).
const _CURSOR_HOTSPOT := Vector2(1, 0)

## Optional scene to open when the player clicks a 'Level Select' button.
@export var level_select_packed_scene: PackedScene
## If true, have the player confirm before starting a new game if a game is in progress.
@export var confirm_new_game : bool = true
## Opened by both New Game and Load Game (see SaveSlotMenu) — one
## shared 3-slot picker rather than two separate scenes.
@export var save_slot_menu_packed_scene: PackedScene
## The achievement list, reachable without starting a game. Wraps the
## same `achievements_page.tscn` the pause menu's own window does — the
## page reads only the account-wide `Achievements` autoload, so it needs
## no running factory to show anything. See AchievementsPage.
@export var achievements_packed_scene: PackedScene

var animation_state_machine : AnimationNodeStateMachinePlayback

@onready var continue_game_button = %ContinueGameButton
@onready var level_select_button = %LevelSelectButton
@onready var new_game_confirmation = %NewGameConfirmation
@onready var achievements_button = %AchievementsButton

## Stops the title screen music here rather than in each button handler
## below — every path into a running game (New Game, Load Game, Continue,
## Level Select) funnels through this one override, so this is the single
## point that's "leaving the menu for gameplay," instead of one more
## thing each `_on_..._pressed()` has to remember to do.
##
## **`stop()` alone isn't enough — it only silences the player for the
## instant this line runs.** `ProjectMusicController` doesn't just play a
## stream, it *keeps its tracked player alive across a scene swap*:
## when the menu's `BackgroundMusicPlayer` node actually exits the tree a
## moment later (during the real scene transition below), its own
## `_on_removed_music_player()` unconditionally reparents that node onto
## itself and **restarts playback** (`_clone_music_player()`/
## `_reparent_music_player()` both end in `play.call_deferred(...)`,
## regardless of the earlier `.stop()` call) — deliberate behavior for
## smoothly continuing/crossfading music into a next scene's own player,
## not something that magically stays stopped. Reported as "music starts
## playing immediately on New Game, then a second copy after the opening's
## first prompt" — the *first* copy was this exact revival (the menu's
## own track coming back from the dead moments after being stopped), the
## second was the factory's own `TierMusicController` starting on
## schedule as designed. Setting `music_stream_player = null` right after
## `stop()` is what actually prevents the revival: `_on_removed_music_
## player()` only reparents/replays if `music_stream_player == node`,
## which is false once this line runs, so the exiting node is just freed
## normally with the rest of the old menu scene instead.
func load_game_scene() -> void:
	ProjectMusicController.stop()
	ProjectMusicController.music_stream_player = null
	GameState.start_game()
	super.load_game_scene()

## Opens the shared save-slot picker instead of loading immediately — the
## player explicitly chooses which of the 3 slots a fresh game starts in
## (see SaveSlotMenu). Old confirm_new_game/new_game_confirmation are
## left in place but unused (see decisions.md) — the slot picker's own
## overwrite-confirmation dialog replaces that role, scoped per-slot.
func new_game() -> void:
	var menu: SaveSlotMenu = _open_sub_menu(save_slot_menu_packed_scene) as SaveSlotMenu
	menu.set_mode(SaveSlotMenu.Mode.NEW_GAME)
	menu.slot_chosen.connect(_on_new_game_slot_chosen)


func _on_load_game_button_pressed() -> void:
	var menu: SaveSlotMenu = _open_sub_menu(save_slot_menu_packed_scene) as SaveSlotMenu
	menu.set_mode(SaveSlotMenu.Mode.LOAD_GAME)
	menu.slot_chosen.connect(_on_load_game_slot_chosen)


func _on_new_game_slot_chosen(_slot: int) -> void:
	GameState.reset()
	load_game_scene()


func _on_load_game_slot_chosen(_slot: int) -> void:
	load_game_scene()

func intro_done() -> void:
	animation_state_machine.travel("OpenMainMenu")

func _is_in_intro() -> bool:
	return animation_state_machine.get_current_node() == "Intro"

func _event_skips_intro(event : InputEvent) -> bool:
	return event.is_action_released("ui_accept") or \
		event.is_action_released("ui_select") or \
		event.is_action_released("ui_cancel") or \
		_event_is_mouse_button_released(event)

func _open_sub_menu(menu : PackedScene) -> Node:
	animation_state_machine.travel("OpenSubMenu")
	return super._open_sub_menu(menu)

func _close_sub_menu() -> void:
	super._close_sub_menu()
	animation_state_machine.travel("OpenMainMenu")

func _input(event : InputEvent) -> void:
	if _is_in_intro() and _event_skips_intro(event):
		intro_done()
		return
	super._input(event)

func _show_level_select_if_set() -> void: 
	if level_select_packed_scene == null: return
	if GameState.get_levels_reached() <= 1 : return
	level_select_button.show()

func _show_continue_if_set() -> void:
	if GameState.get_current_level_path().is_empty(): return
	continue_game_button.show()

func _ready() -> void:
	super._ready()
	Input.set_custom_mouse_cursor(_CURSOR, Input.CURSOR_ARROW, _CURSOR_HOTSPOT)
	_show_level_select_if_set()
	_show_continue_if_set()
	achievements_button.pressed.connect(_on_achievements_button_pressed)
	animation_state_machine = $MenuAnimationTree.get("parameters/playback")

func _on_achievements_button_pressed() -> void:
	_open_sub_menu(achievements_packed_scene)


func _on_continue_game_button_pressed() -> void:
	GameState.continue_game()
	load_game_scene()

func _on_level_select_button_pressed() -> void:
	var level_select_scene := _open_sub_menu(level_select_packed_scene)
	if level_select_scene.has_signal("level_selected"):
		level_select_scene.connect("level_selected", load_game_scene)

func _on_new_game_confirmation_confirmed() -> void:
	GameState.reset()
	load_game_scene()
