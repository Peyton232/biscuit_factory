class_name BuildingDefinition
extends Resource
## Data defining a placeable building type. All balance and identity data
## lives here (as .tres files in resources/buildings/); building scenes
## stay behavior-only. The placer works entirely off these definitions.

@export var display_name: String = ""
## One short sentence for the Building Book's card — what this building
## actually does, not its stats (those are their own fields/read
## straight off the card by BuildingCard). Empty on nothing; every
## definition should have one.
@export_multiline var description: String = ""
## Icon for build UI buttons. The labeled crate sprite doubles as one.
@export var icon: Texture2D
## World meters per icon pixel, i.e. the Sprite3D.pixel_size every real
## placed building of this type renders its Visual at (see
## architecture.md's Sprite3D conventions — target sprite width ≈ the
## 2 m cell size). Each building scene's own Visual node still hardcodes
## its own matching value directly (so this isn't the actual live source
## of truth for a *placed* building's size) — this export exists so
## BuildingGhost, which is a single node reused across every building
## type with no per-type scene knowledge, can size its preview to match
## instead of assuming one fixed value for every building. Defaults to
## 0.075, matching every placeholder crate sprite (~20-30 px) baked
## before real per-building art existed; a building with real,
## higher-resolution art (see Oven) sets its own smaller value here to
## match its own Visual.
@export var icon_pixel_size: float = 0.075
## Footprint in grid cells.
@export var size: Vector2i = Vector2i.ONE
## Purchase cost. Unused until the economy exists.
@export var cost: int = 0
## Item ids this building consumes (see .context/recipes.md). Unused by
## ProcessingBuilding (Mixer/Oven/etc.), which instead reads inputs from
## its assigned Recipe, and unused by ShippingBin, which instead derives
## its (per-instance, player-configurable) accepted items from
## sell_prices — leave empty on those definitions.
@export var inputs: Array[StringName] = []
## Item ids this building produces. Same ProcessingBuilding exception as
## inputs above.
@export var outputs: Array[StringName] = []
## Inventory capacities. 0 disables that side (e.g. sources take no
## inputs, shipping bins emit no outputs). For a ProcessingBuilding, size
## input_capacity for its largest available recipe.
@export var input_capacity: int = 4
@export var output_capacity: int = 4
## Seconds a processing building takes to turn inputs into an output.
## Unused by ProcessingBuilding — each Recipe carries its own
## processing_time instead.
@export var processing_time: float = 3.0
## Scene instanced on placement. Its root must extend Building.
@export var scene: PackedScene
