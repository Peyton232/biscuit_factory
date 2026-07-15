extends Node
## Autoload (registered in project.godot as "SaveManager") owning
## save-slot files and which-slot-is-active session state — nothing
## about gameplay itself. FactoryWorld owns the actual capture/restore
## logic (it's the one that knows about Economy/TierManager/Buildings/
## Cats); this class only knows how to get a FactorySaveData to and from
## disk, and which slot the current session belongs to.
##
## **Deliberately no `class_name`** — this script is only ever meant to
## be reached through its autoload global name ("SaveManager"), never as
## a type. Godot resolves a bare `class_name` matching an autoload's own
## name as the *class* (requiring static calls), not the live singleton
## instance, which broke plain calls like `SaveManager.foo()`; the
## template's own autoloads sidestep this the same way — `AppConfig`'s
## script has no class_name at all, and `SceneLoader`'s uses a
## deliberately different class_name (`SceneLoaderClass`) than its
## autoload key. See decisions.md.
##
## Also the single place the OS window-close button (X / Alt+F4) is
## intercepted — nothing else in this project (or the template it's
## built on) hooks NOTIFICATION_WM_CLOSE_REQUEST, so without this an OS
## close always skipped straight past any chance to autosave.

const SLOT_COUNT: int = 3

## Which slot the current play session belongs to; -1 means none chosen
## yet (e.g. the game scene was opened directly, without going through
## the main menu's slot picker).
var current_slot: int = -1

## Set by begin_load_game(), consumed once by FactoryWorld._ready() via
## take_pending_save_data(). Null means "start fresh" — either a brand
## new game, or no slot was ever chosen.
var _pending_save_data: FactorySaveData = null


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave_if_in_game()
		get_tree().quit()


func slot_path(slot: int) -> String:
	return "user://save_slot_%d.tres" % slot


func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


## Loads and returns a slot's save data without consuming or clearing
## anything — used by the slot-picker UI to preview money/tier/last-
## saved time before the player commits to a choice. Null if the slot
## is empty.
func peek_slot(slot: int) -> FactorySaveData:
	if not slot_exists(slot):
		return null
	return ResourceLoader.load(slot_path(slot), "", ResourceLoader.CACHE_MODE_IGNORE) as FactorySaveData


## Starts a brand-new game in the given slot. The slot's file isn't
## touched until the next real save (autosave on exit, or a manual Save
## Game) — starting a new game into an occupied slot only warns the
## player it WILL be overwritten (see SaveSlotMenu), it doesn't clobber
## the old file the instant they pick the slot.
func begin_new_game(slot: int) -> void:
	current_slot = slot
	_pending_save_data = null


## Marks the given slot to be restored once factory_world.tscn starts.
func begin_load_game(slot: int) -> void:
	current_slot = slot
	_pending_save_data = peek_slot(slot)


## Consumed once by FactoryWorld._ready(). Null means "start fresh."
func take_pending_save_data() -> FactorySaveData:
	var data: FactorySaveData = _pending_save_data
	_pending_save_data = null
	return data


## Writes the given data to the currently active slot. No-ops if no
## slot is active (e.g. this fires from the OS close button while still
## sitting at the main menu).
func save_current_game(data: FactorySaveData) -> void:
	if current_slot == -1:
		return
	data.saved_at_unix_time = int(Time.get_unix_time_from_system())
	ResourceSaver.save(data, slot_path(current_slot))


## Resets session state — called once control returns to the main menu,
## so a later OS-close from the menu itself doesn't try to resave a
## slot that's no longer the active game.
func clear_active_slot() -> void:
	current_slot = -1
	_pending_save_data = null


func _autosave_if_in_game() -> void:
	var scene: Node = get_tree().current_scene
	if scene is FactoryWorld:
		save_current_game((scene as FactoryWorld).capture_save_data())
