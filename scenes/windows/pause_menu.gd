@tool
extends OverlaidWindow

## Same shared pill-button art every other themed button in this project
## uses (see resources/themes/) — applied here in code since
## RecipesButton/BuildingsButton/StatsButton are built at runtime (see
## _make_recipes_button() and its own doc comment for why), unlike the
## rest of %MenuButtons' siblings, which get the identical styling as
## plain .tscn node overrides in pause_menu_layer.tscn instead.
const _PILL_BUTTON_NORMAL: StyleBoxTexture = preload("res://resources/themes/pill_button_normal.tres")
const _PILL_BUTTON_HOVER: StyleBoxTexture = preload("res://resources/themes/pill_button_hover.tres")
const _PILL_BUTTON_PRESSED: StyleBoxTexture = preload("res://resources/themes/pill_button_pressed.tres")
const _PILL_BUTTON_TEXT_COLOR: Color = Color(0.18, 0.13, 0.09, 1)

@export var options_menu_scene : PackedScene
@export var recipe_book_scene : PackedScene
@export var building_book_scene : PackedScene
@export var stats_scene : PackedScene
@export var achievements_scene : PackedScene
## Path to a main menu scene.
## Will attempt to read from AppConfig if left empty.
@export_file("*.tscn") var main_menu_scene_path : String
@export_node_path(&"ConfirmationOverlaidWindow") var restart_confirmation_node_path : NodePath
@export_node_path(&"ConfirmationOverlaidWindow") var main_menu_confirmation_node_path : NodePath
@export_node_path(&"ConfirmationOverlaidWindow") var exit_confirmation_node_path : NodePath
@export var menu_container_node_path : NodePath = ^".."

@onready var restart_confirmation : ConfirmationOverlaidWindow = get_node(restart_confirmation_node_path)
@onready var main_menu_confirmation : ConfirmationOverlaidWindow = get_node(main_menu_confirmation_node_path)
@onready var exit_confirmation : ConfirmationOverlaidWindow = get_node(exit_confirmation_node_path)
@onready var menu_container : Node = get_node(menu_container_node_path)
@onready var options_button = %OptionsButton
@onready var main_menu_button = %MainMenuButton
@onready var exit_button = %ExitButton
@onready var save_game_button : Button = %SaveGameButton
## Built in code rather than hand-added to this inherited scene's node
## overrides (see decisions.md) — %MenuButtons and its five existing
## buttons are all overrides baked into this file by the editor; adding a
## sixth by hand editing the .tscn silently failed to instantiate.
@onready var recipes_button : Button = _make_recipes_button()
@onready var buildings_button : Button = _make_buildings_button()
@onready var stats_button : Button = _make_stats_button()
@onready var achievements_button : Button = _make_achievements_button()

var open_window : Node
var _ignore_first_cancel : bool = false

func get_main_menu_scene_path() -> String:
	if main_menu_scene_path.is_empty():
		return AppConfig.main_menu_scene_path
	return main_menu_scene_path

func close_window() -> void:
	if open_window != null:
		if open_window.has_method("close"):
			open_window.close()
		else:
			open_window.hide()
		open_window = null

## Applies the shared pill-button styling (see class doc) to a
## code-built button — every state (normal/hover/pressed/focus) points
## at the same 3 shared StyleBoxTextures every other themed button in
## this project reuses.
func _style_pill_button(button: Button) -> void:
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_color_override("font_color", _PILL_BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", _PILL_BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", _PILL_BUTTON_TEXT_COLOR)
	button.add_theme_color_override("font_focus_color", _PILL_BUTTON_TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _PILL_BUTTON_NORMAL)
	button.add_theme_stylebox_override("hover", _PILL_BUTTON_HOVER)
	button.add_theme_stylebox_override("pressed", _PILL_BUTTON_PRESSED)
	button.add_theme_stylebox_override("focus", _PILL_BUTTON_NORMAL)


func _make_recipes_button() -> Button:
	# Idempotent: this script is @tool, so _ready() (and this onready init)
	# also runs in-editor whenever the scene is opened/refreshed — reuse
	# an already-created button instead of piling up duplicates.
	var existing: Button = %MenuButtons.get_node_or_null("RecipesButton") as Button
	if existing != null:
		return existing
	var button := Button.new()
	button.name = "RecipesButton"
	button.text = "Recipes"
	_style_pill_button(button)
	button.pressed.connect(_on_recipes_button_pressed)
	%MenuButtons.add_child(button)
	%MenuButtons.move_child(button, options_button.get_index() + 1)
	return button


func _make_buildings_button() -> Button:
	# Same reasoning/idempotency as _make_recipes_button() above.
	var existing: Button = %MenuButtons.get_node_or_null("BuildingsButton") as Button
	if existing != null:
		return existing
	var button := Button.new()
	button.name = "BuildingsButton"
	button.text = "Buildings"
	_style_pill_button(button)
	button.pressed.connect(_on_buildings_button_pressed)
	%MenuButtons.add_child(button)
	%MenuButtons.move_child(button, recipes_button.get_index() + 1)
	return button


func _make_stats_button() -> Button:
	# Same reasoning/idempotency as _make_recipes_button() above.
	var existing: Button = %MenuButtons.get_node_or_null("StatsButton") as Button
	if existing != null:
		return existing
	var button := Button.new()
	button.name = "StatsButton"
	button.text = "Stats"
	_style_pill_button(button)
	button.pressed.connect(_on_stats_button_pressed)
	%MenuButtons.add_child(button)
	%MenuButtons.move_child(button, buildings_button.get_index() + 1)
	return button


func _make_achievements_button() -> Button:
	# Same reasoning/idempotency as _make_recipes_button() above.
	var existing: Button = %MenuButtons.get_node_or_null("AchievementsButton") as Button
	if existing != null:
		return existing
	var button := Button.new()
	button.name = "AchievementsButton"
	button.text = "Achievements"
	_style_pill_button(button)
	button.pressed.connect(_on_achievements_button_pressed)
	%MenuButtons.add_child(button)
	%MenuButtons.move_child(button, stats_button.get_index() + 1)
	return button


func _disable_focus() -> void:
	for child in %MenuButtons.get_children():
		if child is Control:
			child.focus_mode = FOCUS_NONE

func _enable_focus() -> void:
	for child in %MenuButtons.get_children():
		if child is Control:
			child.focus_mode = FOCUS_ALL

func _load_scene(scene_path: String) -> void:
	_scene_tree.paused = false
	SceneLoader.load_scene(scene_path)

func _show_window(window : Control) -> void:
	_disable_focus.call_deferred()
	window.show()
	open_window = window
	await window.hidden
	open_window = null
	_enable_focus.call_deferred()

func _load_and_show_menu(scene : PackedScene) -> void:
	var window_instance : Control = scene.instantiate()
	window_instance.visible = false
	menu_container.add_child.call_deferred(window_instance)
	await _show_window(window_instance)
	window_instance.queue_free()

func _handle_cancel_input() -> void:
	if _ignore_first_cancel:
		_ignore_first_cancel = false
		return
	if open_window != null:
		close_window()
	else:
		super._handle_cancel_input()

func show() -> void:
	super.show()
	if Input.is_action_pressed("ui_cancel"):
		_ignore_first_cancel = true

func _refresh_exit_button() -> void:
	exit_button.visible = !OS.has_feature("web")

func _refresh_options_button() -> void:
	options_button.visible = options_menu_scene != null

func _refresh_recipes_button() -> void:
	recipes_button.visible = recipe_book_scene != null

func _refresh_buildings_button() -> void:
	buildings_button.visible = building_book_scene != null

func _refresh_stats_button() -> void:
	stats_button.visible = stats_scene != null

func _refresh_main_menu_button() -> void:
	main_menu_button.visible = !get_main_menu_scene_path().is_empty()

## Unhides the template's dormant Save Game button — this pause menu
## only ever exists inside factory_world.tscn, so unlike the other
## _refresh_*_button() checks above there's no "is this even wired"
## condition to gate on; it's always relevant here.
func _refresh_save_game_button() -> void:
	save_game_button.visible = true

func _ready() -> void:
	_refresh_exit_button()
	_refresh_options_button()
	_refresh_recipes_button()
	_refresh_buildings_button()
	_refresh_stats_button()
	_refresh_main_menu_button()
	_refresh_save_game_button()
	restart_confirmation.confirmed.connect(_on_restart_confirmation_confirmed)
	main_menu_confirmation.confirmed.connect(_on_main_menu_confirmation_confirmed)
	exit_confirmation.confirmed.connect(_on_exit_confirmation_confirmed)

func _on_restart_button_pressed() -> void:
	_show_window(restart_confirmation)

func _on_options_button_pressed() -> void:
	_load_and_show_menu(options_menu_scene)

func _on_recipes_button_pressed() -> void:
	_load_and_show_menu(recipe_book_scene)

func _on_buildings_button_pressed() -> void:
	_load_and_show_menu(building_book_scene)

func _on_stats_button_pressed() -> void:
	_load_and_show_menu(stats_scene)

func _on_achievements_button_pressed() -> void:
	_load_and_show_menu(achievements_scene)

func _on_main_menu_button_pressed() -> void:
	_show_window(main_menu_confirmation)

func _on_exit_button_pressed() -> void:
	_show_window(exit_confirmation)

## Saves immediately (no confirmation needed — nothing is lost either
## way) and briefly relabels the button for feedback, since there's
## otherwise no visible sign anything happened.
func _on_save_game_button_pressed() -> void:
	_autosave_if_in_game()
	save_game_button.text = "Saved!"
	save_game_button.disabled = true
	await get_tree().create_timer(1.5).timeout
	save_game_button.text = "Save Game"
	save_game_button.disabled = false

## Captures the live game state via FactoryWorld (this pause menu is
## always a direct child of factory_world.tscn's root — see
## PauseMenuController) and writes it to the active save slot. No-ops
## if get_tree().current_scene somehow isn't a FactoryWorld (shouldn't
## happen in practice, since this menu doesn't exist anywhere else).
func _autosave_if_in_game() -> void:
	var scene: Node = get_tree().current_scene
	if scene is FactoryWorld:
		SaveManager.save_current_game((scene as FactoryWorld).capture_save_data())

func _on_restart_confirmation_confirmed() -> void:
	SceneLoader.reload_current_scene()
	close()

func _on_main_menu_confirmation_confirmed():
	_autosave_if_in_game()
	SaveManager.clear_active_slot()
	_load_scene(get_main_menu_scene_path())

func _on_exit_confirmation_confirmed():
	_autosave_if_in_game()
	get_tree().quit()
