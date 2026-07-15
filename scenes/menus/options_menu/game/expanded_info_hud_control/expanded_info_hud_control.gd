extends HBoxContainer
## Settings > Game checkbox for the in-game HUD's top-left panel: off by
## default (just Money/Tool — what a normal player actually needs), on
## shows the debug-oriented FPS/Jobs readouts too (see
## FactoryHud.EXPANDED_INFO_HUD_SECTION/_KEY, which this reads/writes —
## a single canonical section/key, not a second copy that could drift).
## Persisted via PlayerConfig directly (not AppSettings, which is part of
## the vendored addon and doesn't have a helper for this project-specific
## setting) — the same underlying config file every other options tab
## already saves into.

@onready var _checkbox: CheckBox = %Checkbox


func _ready() -> void:
	_checkbox.button_pressed = PlayerConfig.get_config(
			FactoryHud.EXPANDED_INFO_HUD_SECTION, FactoryHud.EXPANDED_INFO_HUD_KEY, false)
	_checkbox.toggled.connect(_on_toggled)


func _on_toggled(enabled: bool) -> void:
	PlayerConfig.set_config(FactoryHud.EXPANDED_INFO_HUD_SECTION, FactoryHud.EXPANDED_INFO_HUD_KEY, enabled)
