class_name GridManager
extends Node3D
## Owns the factory grid: dimensions, cell size, and conversions between
## world space and grid coordinates. Future placement systems build on this.
##
## Cells are addressed with Vector2i coordinates on the X/Z plane, from
## (0, 0) to (grid_size - Vector2i.ONE). The grid is axis-aligned and
## centered on the world origin, so the factory can grow evenly in every
## direction from the starting camera position.

## Number of cells along X and Z.
@export var grid_size: Vector2i = Vector2i(100, 100)
## Side length of one square cell, in meters.
@export var cell_size: float = 2.0

## Maps occupied cells to the node occupying them (e.g. a Building).
## Buildings register themselves; only in-bounds cells should be marked.
var _occupied_cells: Dictionary[Vector2i, Node] = {}

## Kept in sync with _occupied_cells (solid = occupied) so path requests
## never need to rescan the whole grid.
var _astar := AStarGrid2D.new()

const _NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0),
]

## Extra AStarGrid2D weight_scale per occupied neighbor a free cell borders
## (see _refresh_weight_scale()) — a *soft* nudge, not a hard block
## (buildings are already solid, so a cat can never actually enter one);
## this only makes the pathfinder prefer a route with more clearance when
## one exists, without forbidding the tight aisle when it's the only
## option ("cats walk through buildings a lot... on a tight factory may be
## unavoidable" — player's own framing). Deliberately modest — a single
## real extra step of detour (cost ~1.0, since `_astar.cell_size` is
## `Vector2.ONE`) should usually still beat hugging one building-adjacent
## cell, same "nudge, not dominate" spirit as DeliveryManager's own
## cat_proximity_weight.
const _NEAR_BUILDING_WEIGHT_PER_NEIGHBOR: float = 0.6


func _ready() -> void:
	_astar.region = Rect2i(Vector2i.ZERO, grid_size)
	_astar.cell_size = Vector2.ONE
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()


## World position of the grid's corner cell (0, 0) edge, at y = 0.
func world_corner() -> Vector3:
	return Vector3(-grid_size.x * cell_size * 0.5, 0.0, -grid_size.y * cell_size * 0.5)


## The cell containing the given world position. May be out of bounds;
## check with is_in_bounds().
func world_to_grid(world_position: Vector3) -> Vector2i:
	var local: Vector3 = world_position - world_corner()
	return Vector2i(floori(local.x / cell_size), floori(local.z / cell_size))


## World position of the center of the given cell, at y = 0.
func grid_to_world(cell: Vector2i) -> Vector3:
	var corner: Vector3 = world_corner()
	return corner + Vector3((cell.x + 0.5) * cell_size, 0.0, (cell.y + 0.5) * cell_size)


## Snaps a world position to the center of the cell containing it.
func snap_to_grid(world_position: Vector3) -> Vector3:
	return grid_to_world(world_to_grid(world_position))


## World position of the center of a rectangular cell region, at y = 0.
## `cell` is the region's lowest x/y corner.
func region_to_world(cell: Vector2i, size: Vector2i) -> Vector3:
	var corner: Vector3 = world_corner()
	return corner + Vector3(
		(cell.x + size.x * 0.5) * cell_size,
		0.0,
		(cell.y + size.y * 0.5) * cell_size
	)


## True when every cell of the region is in bounds and unoccupied.
func is_region_available(cell: Vector2i, size: Vector2i) -> bool:
	for x: int in size.x:
		for y: int in size.y:
			var checked: Vector2i = cell + Vector2i(x, y)
			if not is_in_bounds(checked) or is_cell_occupied(checked):
				return false
	return true


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func is_cell_occupied(cell: Vector2i) -> bool:
	return _occupied_cells.has(cell)


## True for a building-occupied cell OR a cell FactoryBounds has marked
## impassable outside the currently-unlocked area (see set_point_blocked())
## — everything the pathfinding AStarGrid2D itself treats as solid. Callers
## picking an arbitrary destination (not tied to an existing Building, which
## can never be placed outside the unlocked area in the first place) should
## check this, not just is_cell_occupied(), or they can hand
## find_path_to_point() a target the AStar grid can never actually route
## into.
func is_point_blocked(cell: Vector2i) -> bool:
	return _astar.is_point_solid(cell)


## The node occupying the cell, or null when free.
func get_cell_occupant(cell: Vector2i) -> Node:
	return _occupied_cells.get(cell)


func set_cell_occupant(cell: Vector2i, occupant: Node) -> void:
	_occupied_cells[cell] = occupant
	_astar.set_point_solid(cell, true)
	_refresh_neighbor_weight_scales(cell)


func clear_cell(cell: Vector2i) -> void:
	_occupied_cells.erase(cell)
	_astar.set_point_solid(cell, false)
	_refresh_weight_scale(cell)
	_refresh_neighbor_weight_scales(cell)


## Recomputes `cell`'s own AStarGrid2D weight_scale from its CURRENT
## occupied-neighbor count — a plain O(4) rescan rather than incrementally
## tracked, so it can't drift stale from occupancy changes that happened
## nearby while this specific cell itself was solid (and so skipped by
## _refresh_neighbor_weight_scales() below) — cheap enough to just always
## recompute fresh (only called on a placement/demolish, never per-frame).
## No-op for a currently-occupied cell: weight_scale is meaningless for a
## solid cell, AStarGrid2D never routes through it regardless.
func _refresh_weight_scale(cell: Vector2i) -> void:
	if is_cell_occupied(cell):
		return
	var occupied_neighbors: int = 0
	for offset: Vector2i in _NEIGHBOR_OFFSETS:
		if is_cell_occupied(cell + offset):
			occupied_neighbors += 1
	_astar.set_point_weight_scale(cell, 1.0 + occupied_neighbors * _NEAR_BUILDING_WEIGHT_PER_NEIGHBOR)


## Refreshes every in-bounds neighbor of `cell` (a cell whose own occupancy
## just changed) — each neighbor's own occupied-neighbor count just
## changed along with it.
func _refresh_neighbor_weight_scales(cell: Vector2i) -> void:
	for offset: Vector2i in _NEIGHBOR_OFFSETS:
		var neighbor: Vector2i = cell + offset
		if is_in_bounds(neighbor):
			_refresh_weight_scale(neighbor)


## Marks a cell impassable for pathfinding ONLY — unlike
## set_cell_occupant()/clear_cell(), this never touches _occupied_cells,
## so it can't be mistaken for "a Building occupies this cell" by
## get_cell_occupant()/is_cell_occupied() (BuildingSelector, demolish
## mode, etc.). Used by FactoryBounds to keep cats from pathing through
## the walls outside the currently-unlocked area — those cells have no
## Building on them, they're just off-limits.
func set_point_blocked(cell: Vector2i, blocked: bool) -> void:
	if is_in_bounds(cell):
		_astar.set_point_solid(cell, blocked)


## A walkable path from a world position to just outside the given
## building's footprint, ending with the building's own position as a
## final short approach leg. Cells occupied by buildings are obstacles;
## falls back to a direct single-leg path if no route exists (e.g. the
## building is fully boxed in) so callers never get stuck with nothing.
func find_approach_path(from_world: Vector3, target: Building) -> Array[Vector3]:
	var start_cell: Vector2i = world_to_grid(from_world)
	var approach_cell: Vector2i = _find_adjacent_free_cell(target)
	var waypoints: Array[Vector3] = []
	if is_in_bounds(start_cell) and start_cell != approach_cell:
		for cell: Vector2i in _astar.get_id_path(start_cell, approach_cell):
			waypoints.append(grid_to_world(cell))
	if waypoints.is_empty():
		waypoints.append(grid_to_world(approach_cell))
	waypoints.append(target.position)
	return waypoints


## A walkable path from a world position to another arbitrary world point
## (not tied to a Building) — used for cat wandering. Falls back to a
## direct route if no path exists, same fallback spirit as
## find_approach_path() above. **Assumes to_world is itself a reachable
## (in-bounds, unblocked) point** — the "no path found" fallback exists for
## a start point temporarily boxed in, not to excuse an unreachable target;
## a blocked to_world (e.g. outside FactoryBounds' unlocked area) makes the
## fallback walk straight through whatever's blocking it instead. Callers
## picking their own target (Cat._pick_wander_cell()) must check
## is_point_blocked() themselves before calling this.
func find_path_to_point(from_world: Vector3, to_world: Vector3) -> Array[Vector3]:
	var start_cell: Vector2i = world_to_grid(from_world)
	var end_cell: Vector2i = world_to_grid(to_world)
	var waypoints: Array[Vector3] = []
	if is_in_bounds(start_cell) and start_cell != end_cell:
		for cell: Vector2i in _astar.get_id_path(start_cell, end_cell):
			waypoints.append(grid_to_world(cell))
	if waypoints.is_empty():
		waypoints.append(to_world)
	return waypoints


## The nearest free cell orthogonally adjacent to the building's
## footprint. Falls back to the building's own anchor cell if somehow
## fully boxed in (shouldn't normally happen).
func _find_adjacent_free_cell(target: Building) -> Vector2i:
	for footprint_cell: Vector2i in target.footprint_cells():
		for offset: Vector2i in _NEIGHBOR_OFFSETS:
			var neighbor: Vector2i = footprint_cell + offset
			if is_in_bounds(neighbor) and not is_cell_occupied(neighbor):
				return neighbor
	return target.cell
