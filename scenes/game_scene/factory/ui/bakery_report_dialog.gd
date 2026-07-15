class_name BakeryReportDialog
extends PanelContainer
## The Bakery Report — shown once, right after Victory Sequence's
## credits finish scrolling (see VictorySequence.play()), celebrating
## the player's own factory rather than a plain "You Win." Purely a
## view, same split as GameCompleteDialog/CatNamingDialog/
## CatBatchAdoptDialog: VictorySequence gathers the actual stats
## (LifetimeStats/RecipeShop/FactoryBounds) and calls show_report(),
## this just formats and displays them and emits continue_pressed.
##
## Bakery Rank itself is computed by VictorySequence._compute_bakery_rank()
## (see its own doc for the rank list/thresholds), not here — show_report()
## just takes the resulting rank as a plain string, so the formula can
## keep changing at the call site without ever touching this view.

signal continue_pressed

@onready var _completion_time_label: Label = %CompletionTimeLabel
@onready var _rank_label: Label = %RankLabel
@onready var _money_label: Label = %MoneyLabel
@onready var _cats_label: Label = %CatsLabel
@onready var _goods_label: Label = %GoodsLabel
@onready var _recipes_label: Label = %RecipesLabel
@onready var _deliveries_label: Label = %DeliveriesLabel
@onready var _factory_size_label: Label = %FactorySizeLabel
@onready var _continue_button: Button = %ContinueButton


func _ready() -> void:
	hide()
	_continue_button.pressed.connect(func() -> void: continue_pressed.emit())


func show_report(
		completion_time_seconds: float,
		rank: String,
		money_earned: int,
		cats_adopted: int,
		goods_produced: int,
		recipes_unlocked: int,
		deliveries: int,
		factory_size: Vector2i) -> void:
	_completion_time_label.text = "Completion Time: %s" % LifetimeStats.format_playtime(completion_time_seconds)
	_rank_label.text = "Bakery Rank: %s" % rank
	_money_label.text = "Total Money Earned: $%d" % money_earned
	_cats_label.text = "Total Cats Adopted: %d" % cats_adopted
	_goods_label.text = "Total Goods Produced: %d" % goods_produced
	_recipes_label.text = "Total Recipes Unlocked: %d" % recipes_unlocked
	_deliveries_label.text = "Total Deliveries: %d" % deliveries
	_factory_size_label.text = "Factory Size: %d × %d" % [factory_size.x, factory_size.y]
	show()
