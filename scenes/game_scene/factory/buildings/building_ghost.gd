class_name BuildingGhost
extends Node3D
## Half-opacity preview of the building about to be placed: shows the
## selected BuildingDefinition's icon at the hovered cell, at that
## building's own footprint anchor, while BuildingPlacer has a definition
## selected. Purely cosmetic feedback, same spirit as GridCursor's
## highlight quad below it — just at the building's own icon instead of
## a flat colored quad. Reuses grid_cursor.validity_check (already wired
## to BuildingPlacer's own placement rules) to tint invalid positions,
## instead of duplicating that logic here.

@export var grid_manager: GridManager
@export var grid_cursor: GridCursor
@export var placer: BuildingPlacer
## Optional: when set and a move is pending, the ghost also previews the
## building being relocated (falls back to placer's own selection when
## no move is active) — see BuildingMover.
@export var mover: BuildingMover

const _VALID_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.5)
const _INVALID_MODULATE: Color = Color(1.0, 0.55, 0.5, 0.5)

var _sprite: Sprite3D


func _ready() -> void:
	# Same Sprite3D settings every building scene's own Visual uses (see
	# architecture.md's Sprite3D conventions), except alpha_cut is left at
	# its default (disabled) instead of "discard" — a ghost needs real
	# partial transparency, not a hard cutoff. pixel_size/offset are set
	# per-frame in _process() instead of here, since this one Sprite3D is
	# reused across every building type and each type can have a
	# different native icon resolution (see BuildingDefinition.icon_pixel_size).
	_sprite = Sprite3D.new()
	_sprite.name = "Ghost"
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.visible = false
	add_child(_sprite)


func _process(_delta: float) -> void:
	var definition: BuildingDefinition = placer.selected_definition()
	if definition == null and mover != null and mover.is_moving():
		definition = mover.moving_definition()
	if definition == null or not grid_cursor.has_hover:
		_sprite.visible = false
		return
	_sprite.texture = definition.icon
	_sprite.pixel_size = definition.icon_pixel_size
	# Bottom-edge anchor: offset.y = half the icon's own native pixel
	# height, same convention every building's real Visual node uses (see
	# architecture.md) — derived from the texture itself rather than a
	# fixed guess, so the ghost lines up correctly regardless of which
	# building's icon (placeholder crate or real art, any resolution) is
	# currently selected.
	_sprite.offset = Vector2(0, definition.icon.get_height() / 2.0)
	_sprite.position = grid_manager.region_to_world(grid_cursor.hovered_cell, definition.size) \
			+ Vector3(0, 0.05, 0)
	var valid: bool = true
	if grid_cursor.validity_check.is_valid():
		valid = grid_cursor.validity_check.call(grid_cursor.hovered_cell)
	_sprite.modulate = _VALID_MODULATE if valid else _INVALID_MODULATE
	_sprite.visible = true
