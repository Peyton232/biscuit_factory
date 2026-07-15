class_name SaveSlotMenu
extends Control
## Shared 3-slot picker for both "New Game" and "Load Game", opened by
## MainMenu via _open_sub_menu() (same pattern as the existing Level
## Select flow) — one scene rather than two nearly-identical ones, since
## the only real difference between the two is which slots are
## clickable and whether an occupied slot needs an overwrite warning.
##
## Set mode via set_mode() (not the plain `mode` export) right after
## instantiation — it refreshes the slot labels/enabled-state
## immediately, rather than relying on _ready() having already run by
## the time the caller sets it.

enum Mode { NEW_GAME, LOAD_GAME }

signal slot_chosen(slot: int)

const _SLOT_COUNT: int = 3

var mode: Mode = Mode.NEW_GAME

@onready var _slot_buttons: Array[Button] = [%Slot1Button, %Slot2Button, %Slot3Button]
@onready var _delete_buttons: Array[Button] = [%Slot1DeleteButton, %Slot2DeleteButton, %Slot3DeleteButton]
@onready var _overwrite_confirmation: ConfirmationOverlaidWindow = %OverwriteConfirmation
@onready var _delete_confirmation: ConfirmationOverlaidWindow = %DeleteConfirmation

## Set right before showing the overwrite confirmation, so its
## "confirmed" handler knows which slot to actually commit to.
var _pending_overwrite_slot: int = -1
## Same idea as _pending_overwrite_slot, for the delete confirmation.
var _pending_delete_slot: int = -1


func _ready() -> void:
	_refresh()


func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	_refresh()


func _refresh() -> void:
	for i: int in _SLOT_COUNT:
		var data: FactorySaveData = SaveManager.peek_slot(i)
		_slot_buttons[i].text = _slot_label(i, data)
		# Load Game can't do anything useful with an empty slot; New Game
		# can (it just starts fresh there), so only Load Game disables it.
		if mode == Mode.LOAD_GAME:
			_slot_buttons[i].disabled = data == null
		else:
			_slot_buttons[i].disabled = false
		# Nothing to delete on an already-empty slot, in either mode.
		_delete_buttons[i].visible = data != null


func _slot_label(slot: int, data: FactorySaveData) -> String:
	if data == null:
		return "Slot %d\nEmpty" % (slot + 1)
	var when: String = Time.get_datetime_string_from_unix_time(data.saved_at_unix_time, true)
	var playtime: String = LifetimeStats.format_playtime(data.playtime_seconds)
	# "★ " prefix marks a slot that has ever reached Tier Winner — a plain
	# text glyph rather than a new icon asset, matching this menu's
	# existing text-only slot labels (see FactorySaveData.completed).
	var star: String = "★ " if data.completed else ""
	return "%sSlot %d\nTier %d — $%d — %s played\nSaved %s" % [star, slot + 1, data.current_tier, data.money, playtime, when]


func _on_slot_button_pressed(slot: int) -> void:
	if mode == Mode.LOAD_GAME:
		if not SaveManager.slot_exists(slot):
			return
		SaveManager.begin_load_game(slot)
		slot_chosen.emit(slot)
		return
	# New Game: an occupied slot needs a warning first; an empty one
	# commits immediately.
	if SaveManager.slot_exists(slot):
		_pending_overwrite_slot = slot
		_overwrite_confirmation.show()
		return
	SaveManager.begin_new_game(slot)
	slot_chosen.emit(slot)


func _on_overwrite_confirmed() -> void:
	SaveManager.begin_new_game(_pending_overwrite_slot)
	slot_chosen.emit(_pending_overwrite_slot)


## The delete "✕" sits on top of the slot's own big pick button (see
## save_slot_menu.tscn) — Godot delivers a click to that topmost child
## first, so this fires instead of _on_slot_button_pressed for the same
## click, not in addition to it.
func _on_delete_button_pressed(slot: int) -> void:
	_pending_delete_slot = slot
	_delete_confirmation.show()


func _on_delete_confirmed() -> void:
	SaveManager.delete_slot(_pending_delete_slot)
	_pending_delete_slot = -1
	_refresh()


func _on_back_button_pressed() -> void:
	# Emits `hidden`, which MainMenu._open_sub_menu() already connected
	# to _close_sub_menu() (CONNECT_ONE_SHOT) — same pattern the Level
	# Select flow relies on. ui_cancel/ESC works too, unrelated to this
	# button, since MainMenu._input() checks `if sub_menu:` directly.
	hide()
