class_name BuildingCard
extends PanelContainer
## A single building type's info as a card: icon, display name,
## placement cost, and a short blurb explaining what it actually does
## (`BuildingDefinition.description`). Purely a view, populated via
## set_definition(); used by BuildingBook. Buildings have no money-unlock
## step anymore (see progression.md) — a building's only lock is its
## tier, which BuildingBook enforces by hiding the whole card, not by
## disabling a button on it — so this card has no lock affordance at
## all, unlike RecipeCard (recipes still cost money once their tier
## unlocks).
##
## **Reuses `RecipeCard`'s own card background art (✅ 2026-07-14)** —
## same `resources/themes/recipe_card_normal.tres` StyleBoxTexture, same
## 550px width and dark-brown text color, so the Building Book and
## Recipe Book read as one consistent style rather than two different
## pause-menu looks. Laid out as an icon-left/text-right row (unlike
## RecipeCard's stacked-and-centered layout) since a building card has
## less content (no input/output item chips) and a wide card with
## everything centered in a single column would look sparse.

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _cost_label: Label = %CostLabel
@onready var _description_label: Label = %DescriptionLabel


func set_definition(definition: BuildingDefinition) -> void:
	_icon.texture = definition.icon
	_name_label.text = definition.display_name
	_cost_label.text = "Cost: $%d" % definition.cost
	_description_label.text = definition.description
