extends MainMenu
## Main menu extension that adds options and animates the title and menu fading in.
## The scene adds a 'Continue' button if a game is in progress.
## The animation can be skipped by the player with any input.

## Optional scene to open when the player clicks a 'Level Select' button.
@export var level_select_packed_scene: PackedScene
## If true, have the player confirm before starting a new game if a game is in progress.
@export var confirm_new_game : bool = true
## Opened by both New Game and Load Game (see SaveSlotMenu) — one
## shared 3-slot picker rather than two separate scenes.
@export var save_slot_menu_packed_scene: PackedScene

var animation_state_machine : AnimationNodeStateMachinePlayback

@onready var continue_game_button = %ContinueGameButton
@onready var level_select_button = %LevelSelectButton
@onready var new_game_confirmation = %NewGameConfirmation

func load_game_scene() -> void:
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
	_show_level_select_if_set()
	_show_continue_if_set()
	animation_state_machine = $MenuAnimationTree.get("parameters/playback")

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
