class_name UiButtonStyle
extends RefCounted
## Shared pill-button styling (resources/themes/pill_button_*.tres, same
## art the main menu/Pause/Settings/bottom-bar buttons already use) for
## Buttons built at runtime rather than declared in a .tscn — used by
## FactoryHud's dynamic bottom-bar buttons and BuildingInspectorPanel's
## dynamic Move/recipe/Select-All buttons, so both stay visually
## consistent with the game's established button art without each
## duplicating the same theme-override block.

const _PILL_NORMAL: StyleBoxTexture = preload("res://resources/themes/pill_button_normal.tres")
const _PILL_HOVER: StyleBoxTexture = preload("res://resources/themes/pill_button_hover.tres")
const _PILL_PRESSED: StyleBoxTexture = preload("res://resources/themes/pill_button_pressed.tres")
## The project's established "readable label over a light/busy
## background" color — see decisions.md.
const TEXT_COLOR: Color = Color(0.18, 0.13, 0.09, 1)


## Applies the pill background + dark-brown text color to an existing
## Button (including toggle-mode buttons and disabled ones — a locked
## recipe button, say — since disabled falls back to the same normal
## art rather than Godot's default greyed-out look).
static func apply(button: Button) -> void:
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	button.add_theme_color_override("font_focus_color", TEXT_COLOR)
	button.add_theme_color_override("font_disabled_color", TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _PILL_NORMAL)
	button.add_theme_stylebox_override("hover", _PILL_HOVER)
	button.add_theme_stylebox_override("pressed", _PILL_PRESSED)
	button.add_theme_stylebox_override("focus", _PILL_NORMAL)
	button.add_theme_stylebox_override("disabled", _PILL_NORMAL)


## A new pill-styled Button, for call sites that don't already have one
## to style in place.
static func make() -> Button:
	var button := Button.new()
	apply(button)
	return button
