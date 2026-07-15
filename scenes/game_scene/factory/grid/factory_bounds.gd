class_name FactoryBounds
extends Node
## Tracks how much of GridManager's full grid is actually buildable right
## now — "add walls to the factory... have those walls expand the space
## they have, make it expensive" playtest feedback. The full grid
## (100x100 cells) has always existed for pathfinding/camera-pan
## headroom, but nothing previously stopped a building from being placed
## anywhere in it; this adds a smaller, centered "unlocked" rectangle
## that starts modest and grows only when the player pays to expand it.
##
## Also blocks pathfinding outside the unlocked area (✅ 2026-07-13 — cats
## could walk straight through the wall visuals otherwise, since they're
## purely decorative meshes with no grid presence of their own):
## _update_pathfinding_blocking() marks every cell outside the current
## rectangle solid on GridManager's AStarGrid2D via a dedicated
## set_point_blocked() (NOT set_cell_occupant()/clear_cell() — those also
## touch the occupied-cell map that BuildingSelector/demolish read, and
## there's no Building on a wall cell to report). Re-run in full
## (iterates the whole grid; cheap enough since this only ever happens on
## _ready()/an expansion/a save load, never per-frame) rather than
## incrementally, so it can't drift out of sync with unlocked_size.
## BuildingPlacer and BuildingMover separately consult
## is_region_within_bounds() alongside their existing
## grid_manager.is_region_available() check, for the placement gate.
##
## Cost grows exponentially per expansion (`base_cost * growth ^ count`,
## rounded to the nearest 10) — this is a new mechanic with no GDD
## reference table, unlike the rest of this game's economy; the curve is
## a first-pass eyeballed judgment call sized to land in the
## hundreds-to-low-thousands range across a handful of expansions,
## matching progression.md's "Estimated Money Growth per Tier" reference
## curve loosely rather than exactly. Tune here if playtesting shows it's
## off.

signal expanded

@export var grid_manager: GridManager
@export var economy: Economy
## Cells buildable along each axis at the start of a new game.
@export var starting_size: Vector2i = Vector2i(12, 12)
## Cells added along each axis per successful expansion.
@export var expand_step: Vector2i = Vector2i(4, 4)
@export var base_cost: int = 200
@export var cost_growth: float = 1.6

var unlocked_size: Vector2i
var _expansion_count: int = 0


func _ready() -> void:
	unlocked_size = starting_size
	_update_pathfinding_blocking()


func is_region_within_bounds(cell: Vector2i, size: Vector2i) -> bool:
	var origin: Vector2i = _origin()
	var far_corner: Vector2i = origin + unlocked_size
	return cell.x >= origin.x and cell.y >= origin.y \
			and cell.x + size.x <= far_corner.x and cell.y + size.y <= far_corner.y


## World-space corner/size of the currently unlocked rectangle, for
## visuals (floor/wall sizing) — same "corner + size" shape
## GridManager.region_to_world() uses for a building footprint.
func unlocked_world_corner() -> Vector3:
	return grid_manager.world_corner() + Vector3(
		_origin().x * grid_manager.cell_size, 0.0, _origin().y * grid_manager.cell_size)


func unlocked_world_size() -> Vector2:
	return Vector2(unlocked_size.x, unlocked_size.y) * grid_manager.cell_size


func current_cost() -> int:
	return int(roundf(base_cost * pow(cost_growth, _expansion_count) / 10.0)) * 10


## Whether expanding further is even geometrically possible — stops the
## unlocked area from trying to outgrow the full grid it lives inside.
func can_expand_further() -> bool:
	var next_size: Vector2i = unlocked_size + expand_step
	return next_size.x <= grid_manager.grid_size.x and next_size.y <= grid_manager.grid_size.y


func try_expand() -> bool:
	if not can_expand_further():
		return false
	if not economy.try_spend(current_cost()):
		return false
	unlocked_size += expand_step
	_expansion_count += 1
	_update_pathfinding_blocking()
	expanded.emit()
	return true


func save_state(out: FactorySaveData) -> void:
	out.factory_unlocked_size = unlocked_size
	out.factory_expansion_count = _expansion_count


func load_state(data: FactorySaveData) -> void:
	if data.factory_unlocked_size != Vector2i.ZERO:
		unlocked_size = data.factory_unlocked_size
	_expansion_count = data.factory_expansion_count
	_update_pathfinding_blocking()
	# Restoring unlocked_size here is a plain field assignment, not a
	# player try_expand() — but FactoryBoundsVisual (walls/floor) and
	# FactoryHud (Expand Factory button cost) both only ever refresh
	# themselves on THIS signal, built once at _ready() and never
	# otherwise re-checked. Without also emitting it here, a loaded
	# save's restored unlocked_size is correct internally (placement
	# already respects it) but the walls/floor visually stay stuck at
	# whatever size they were built at _ready() time — before this same
	# load_state() call ran, since children ready before FactoryWorld's
	# own _ready() calls apply_save_data(). Reported as "expanding the
	# factory doesn't save" — it did; only the visual didn't know.
	expanded.emit()


func _origin() -> Vector2i:
	return (grid_manager.grid_size - unlocked_size) / 2


func _update_pathfinding_blocking() -> void:
	for x: int in grid_manager.grid_size.x:
		for y: int in grid_manager.grid_size.y:
			var cell := Vector2i(x, y)
			grid_manager.set_point_blocked(cell, not is_region_within_bounds(cell, Vector2i.ONE))
