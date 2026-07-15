class_name Building
extends Node3D
## Base class for all placeable factory buildings. A building covers the
## footprint given by its definition and registers those cells with the
## GridManager while in the tree.
##
## Call setup() before adding to the tree. Visuals live on child nodes
## (placeholder sprites now, final pixel art later) — never in this class.

var grid_manager: GridManager
var definition: BuildingDefinition
## Anchor cell: the footprint's lowest x/y corner.
var cell: Vector2i
## Items waiting to be processed / picked up. The delivery system reads
## and reserves these; buildings never push items anywhere themselves.
var input_inventory: Inventory
var output_inventory: Inventory


## Assigns grid position and definition. Must be called before add_child().
func setup(manager: GridManager, anchor_cell: Vector2i, building_definition: BuildingDefinition) -> void:
	grid_manager = manager
	definition = building_definition
	cell = anchor_cell
	position = manager.region_to_world(anchor_cell, building_definition.size)
	input_inventory = Inventory.new(building_definition.input_capacity)
	output_inventory = Inventory.new(building_definition.output_capacity)


func accepts_item(item: StringName) -> bool:
	return current_inputs().has(item)


## Whether a delivery of this item should be scheduled. Caps each input
## item at 1 on hand/incoming (counting in-flight deliveries) — a recipe
## never consumes more than one of a given input per batch (see
## ProcessingBuilding._try_start()), so holding extra is pure clutter,
## and it's what stops one ingredient from flooding a multi-input
## building and starving the others. (This used to divide
## input_capacity across current_inputs().size() instead, sized for the
## station's *largest* available recipe — which badly over-allocated
## for any recipe with fewer inputs than that, e.g. a 1-input recipe on
## a Mixer whose capacity is sized for Batter's three.)
func wants_item(item: StringName) -> bool:
	if not accepts_item(item) or input_inventory.space_left() < 1:
		return false
	var claimed: int = input_inventory.count(item) + input_inventory.reserved_incoming(item)
	return claimed < 1


func produces_item(item: StringName) -> bool:
	return current_outputs().has(item)


## Item ids this building currently accepts. Defaults to the definition's
## static list; ProcessingBuilding overrides this to reflect its assigned
## Recipe instead, since that can change at runtime.
func current_inputs() -> Array[StringName]:
	return definition.inputs


## Item ids this building currently produces. See current_inputs().
func current_outputs() -> Array[StringName]:
	return definition.outputs


## 0 when idle; otherwise 0..1 progress toward whatever this building is
## currently working on. Base implementation never progresses (e.g.
## ShippingBin has no timed production). Overridden by ProcessingBuilding
## (recipe batches) and IngredientSource (production timer) so
## BuildingProgressBar can read it uniformly regardless of building type.
func progress() -> float:
	return 0.0


func _ready() -> void:
	assert(grid_manager != null and definition != null,
			"Call setup() before adding a Building to the tree.")
	_set_footprint_occupied(true)
	# The placeholder crate sprite doubles as the definition's icon, so
	# one scene can serve several definitions (e.g. flour/butter sources).
	var visual: Sprite3D = get_node_or_null("Visual") as Sprite3D
	if visual != null and definition.icon != null:
		visual.texture = definition.icon


func _exit_tree() -> void:
	if grid_manager != null and definition != null:
		_set_footprint_occupied(false)


## Captures this building's common save-relevant state (identity,
## position, inventory contents). Subclasses with extra per-instance
## state (ProcessingBuilding's recipe, ShippingBin's accepted items)
## override and extend via super() — see decisions.md.
func save_entry() -> BuildingSaveEntry:
	var entry := BuildingSaveEntry.new()
	entry.definition_path = definition.resource_path
	entry.cell = cell
	var inputs: Dictionary[StringName, int] = input_inventory.save_items()
	for item: StringName in inputs:
		entry.input_items[String(item)] = inputs[item]
	var outputs: Dictionary[StringName, int] = output_inventory.save_items()
	for item: StringName in outputs:
		entry.output_items[String(item)] = outputs[item]
	return entry


## Restores this building's common state from a save entry. Must be
## called AFTER add_child() (setup() has already run by then, so
## input_inventory/output_inventory exist) — see FactoryWorld.
func load_entry(entry: BuildingSaveEntry) -> void:
	var inputs: Dictionary[StringName, int] = {}
	for item: String in entry.input_items:
		inputs[StringName(item)] = entry.input_items[item]
	input_inventory.load_items(inputs)
	var outputs: Dictionary[StringName, int] = {}
	for item: String in entry.output_items:
		outputs[StringName(item)] = entry.output_items[item]
	output_inventory.load_items(outputs)


func footprint_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in definition.size.x:
		for y: int in definition.size.y:
			cells.append(cell + Vector2i(x, y))
	return cells


func _set_footprint_occupied(occupied: bool) -> void:
	for footprint_cell: Vector2i in footprint_cells():
		if occupied:
			grid_manager.set_cell_occupant(footprint_cell, self)
		else:
			grid_manager.clear_cell(footprint_cell)
