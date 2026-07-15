extends Node
## Sets Fredoka as the engine-wide fallback font — the one thing
## `gui/theme/custom` (see resources/themes/fredoka_theme.tres) doesn't
## cover. `Label3D` nodes (cat name tags, BuildingInventoryLabel,
## FloatingText) don't participate in the Control theme system at all;
## they use their own `font` export if set, or `ThemeDB.fallback_font`
## otherwise — none of this project's Label3D nodes set one, so this is
## the single place that makes Fredoka apply to literally all text in
## the game, not just 2D UI.
##
## Done here, at runtime, rather than via the `gui/theme/default_font`
## project setting (the setting that actually seeds `ThemeDB.
## fallback_font` on boot) — that setting is resolved extremely early
## during ProjectSettings parsing, before this specific font's dynamic-
## font loader was reliably available, and broke project.godot parsing
## entirely when tried directly. Setting it here, once the engine has
## already fully booted and autoloads are initializing, avoids that
## ordering problem. See decisions.md.


func _ready() -> void:
	ThemeDB.fallback_font = load("res://assets/fonts/fredoka/Fredoka-Variable.ttf")
