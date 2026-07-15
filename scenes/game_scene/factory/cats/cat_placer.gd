class_name CatPlacer
extends Node3D
## Lets the player choose where a newly adopted cat spawns by clicking a
## spot on the ground, mirroring BuildingPlacer's click-to-place flow
## (ghost preview, click commits and spends, right-click/ESC cancels) —
## player-requested, since adoption used to always spawn a cat at one
## fixed CatShop.spawn_position regardless of where the player actually
## wanted it. Cats aren't grid-cell locked (no footprint/occupancy the
## way buildings are), so any ground point GridCursor is hovering is a
## valid placement target — no validity_check callback needed, unlike
## BuildingPlacer.
##
## Reuses the existing place_building/cancel_placement input actions
## rather than adding cat-specific ones — the two placement modes are
## mutually exclusive (begin_placing() cancels any active building tool
## first, and FactoryHud cancels an active cat placement if the player
## picks a building tool instead) and mean the same thing either way:
## left click confirms, right click/ESC cancels.
##
## Batch adoption (CatBatchAdoptDialog) deliberately does NOT go through
## this — it spawns at CatShop's fixed spawn_position instead, since
## requiring N placement clicks in a row for "buy several at once,
## quickly" would defeat the point of that tool.

signal placing_changed

@export var grid_cursor: GridCursor
@export var cat_shop: CatShop
@export var building_placer: BuildingPlacer

const _GHOST_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.5)

var _pending_name: String = ""
var _pending_role: Cat.Role = Cat.Role.DELIVERY
var _has_pending: bool = false

var _ghost: Sprite3D


func _ready() -> void:
	# Reuses the same sprite sheet/settings as Cat's own Visual node (see
	# architecture.md's Sprite3D conventions) so the ghost actually looks
	# like a cat, at half opacity — no validity tinting needed, since
	# unlike a building's footprint, any ground point is a valid spot.
	_ghost = Sprite3D.new()
	_ghost.name = "Ghost"
	_ghost.texture = preload("res://assets/sprites/cats/sprite_sheet.png")
	_ghost.hframes = 4
	_ghost.frame = 0
	_ghost.offset = Vector2(0, 1500)
	_ghost.pixel_size = 0.00054
	_ghost.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ghost.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_ghost.modulate = _GHOST_MODULATE
	_ghost.visible = false
	add_child(_ghost)


func is_placing() -> bool:
	return _has_pending


## Human-readable label for FactoryHud's tool readout while placing.
func tool_label() -> String:
	return "Placing %s (click to confirm)" % _pending_name


func _process(_delta: float) -> void:
	if not _has_pending or not grid_cursor.has_hover:
		_ghost.visible = false
		return
	_ghost.position = grid_cursor.world_point + Vector3(0, 0.05, 0)
	_ghost.visible = true


## Starts placement mode for a newly-named, not-yet-spent adoption.
## Cancels any active building tool first (before _has_pending is set),
## so the two placement modes never compete for the same click and
## clearing the building tool here can't loop back and cancel the cat
## placement we're about to start.
func begin_placing(cat_name: String, role: Cat.Role) -> void:
	building_placer.clear_tool()
	_pending_name = cat_name
	_pending_role = role
	_has_pending = true
	placing_changed.emit()


func cancel_placing() -> void:
	if not _has_pending:
		return
	_has_pending = false
	placing_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _has_pending:
		return
	if event.is_action_pressed("cancel_placement"):
		cancel_placing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("place_building"):
		# Consume every click while placement is pending — even ones that
		# miss the grid — so it never falls through and starts a camera
		# drag, same reasoning as BuildingPlacer's own place_building
		# handling.
		if grid_cursor.has_hover:
			if cat_shop.adopt_cat_at(_pending_name, _pending_role, grid_cursor.world_point):
				_has_pending = false
				placing_changed.emit()
		get_viewport().set_input_as_handled()
