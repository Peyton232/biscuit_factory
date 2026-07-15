class_name Recipe
extends Resource
## Data for one production recipe a ProcessingBuilding can run: the items
## it consumes, the item it produces, and how long a batch takes. Recipes
## live as .tres files in resources/recipes/ so new recipes (and rebalancing
## existing ones) never touch station code — see ProcessingBuilding.

@export var display_name: String = ""
## Item ids consumed per batch (see .context/recipes.md).
@export var inputs: Array[StringName] = []
## Item id produced per batch.
@export var output: StringName = &""
## Seconds a station takes to turn the inputs into the output.
@export var processing_time: float = 3.0
## Which building type runs this recipe ("Mixer"/"Oven"/"Cutting Station"/
## "Assembly Table") — purely display metadata now (RecipeCard shows
## "Made at: <name>"). Recipe visibility itself is gated by
## TierManager.recipe_tiers, keyed on the Recipe resource directly, not
## by this string — see progression.md. Kept as a plain String rather
## than a direct BuildingDefinition reference: mixer.tscn's
## available_recipes already references this Recipe, and mixer.tres (the
## BuildingDefinition) references mixer.tscn — a Recipe holding its own
## direct reference back to mixer.tres would be a resource load cycle
## (mixer.tres -> mixer.tscn -> this Recipe -> mixer.tres). Must match a
## BuildingDefinition.display_name exactly; nothing enforces this
## automatically, so keep them in sync by hand.
@export var station_name: String = ""
