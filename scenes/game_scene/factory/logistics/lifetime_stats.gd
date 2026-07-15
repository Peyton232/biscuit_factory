class_name LifetimeStats
extends Node
## All-time totals for the current save — never reset, regardless of
## tier or anything else. Feeds the pause-menu Stats page (see
## `ui/stats_page.gd`) and, later, TierManager's per-tier goal progress
## via a baseline snapshot of shipped_count() (see progression.md/
## roadmap.md's GDD Alignment section) — TierManager doesn't reset this,
## it just remembers where each count stood when its tier began.
##
## Registers itself in the "lifetime_stats" group in _ready() so
## StatsPage — instantiated fresh each time via the pause menu's generic
## window loader, with no export wiring to gameplay nodes — can still
## find it, same pattern RecipeShop uses for RecipeBook.

signal item_shipped(item: StringName)
signal cat_adopted

## Item id -> lifetime units shipped. Recorded regardless of sale price
## (a $0 item would still count as "shipped"), since ShippingBin's own
## concept is shipping, not strictly selling.
var items_shipped: Dictionary[StringName, int] = {}
var cats_adopted_count: int = 0
## Lifetime money earned from shipped sales specifically — NOT the same
## as Economy.money (current balance, which also moves on spending and
## demolish refunds). Deliberately scoped to sales income only, so a
## demolish-and-rebuild spree doesn't inflate "money earned."
var money_earned_total: int = 0
## Total seconds this save has spent actively playing. Accumulated via
## _process(delta) rather than wall-clock timestamps, so it naturally
## stops counting while the pause menu is open — Node._process() is
## skipped tree-wide once get_tree().paused is true (the pause menu sets
## this), and this node doesn't opt out via PROCESS_MODE_ALWAYS, so no
## extra pause-checking code is needed here.
var playtime_seconds: float = 0.0
## Lifetime count of completed DeliveryJobs — every cat trip a job
## represents (ingredient hauls between buildings, not just final
## shipments), recorded by DeliveryManager.complete_job(). Deliberately
## a different number from items_shipped's total: this counts overall
## factory/logistics activity, items_shipped counts finished goods that
## actually reached a ShippingBin.
var total_deliveries_completed: int = 0


func _ready() -> void:
	add_to_group("lifetime_stats")


func _process(delta: float) -> void:
	playtime_seconds += delta


func record_shipped(item: StringName, price: int) -> void:
	items_shipped[item] = items_shipped.get(item, 0) + 1
	money_earned_total += price
	item_shipped.emit(item)


func record_cat_adopted() -> void:
	cats_adopted_count += 1
	cat_adopted.emit()


func record_delivery_completed() -> void:
	total_deliveries_completed += 1


func shipped_count(item: StringName) -> int:
	return items_shipped.get(item, 0)


## Total finished-goods units shipped across every item, lifetime — the
## Bakery Report's "Total Goods Produced" figure (see VictorySequence/
## BakeryReportDialog).
func total_items_shipped() -> int:
	var total: int = 0
	for item: StringName in items_shipped:
		total += items_shipped[item]
	return total


## "3h 42m" / "42m" — shared by StatsPage and SaveSlotMenu's per-slot
## preview so both read the same format. Static since it's a pure
## formatting helper, not tied to any one instance's state.
static func format_playtime(seconds: float) -> String:
	var total_minutes: int = int(seconds) / 60
	var hours: int = total_minutes / 60
	var minutes: int = total_minutes % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes


func save_state(out: FactorySaveData) -> void:
	for item: StringName in items_shipped:
		out.items_shipped[String(item)] = items_shipped[item]
	out.cats_adopted_count = cats_adopted_count
	out.money_earned_total = money_earned_total
	out.playtime_seconds = playtime_seconds
	out.total_deliveries_completed = total_deliveries_completed


func load_state(data: FactorySaveData) -> void:
	items_shipped.clear()
	for item: String in data.items_shipped:
		items_shipped[StringName(item)] = data.items_shipped[item]
	cats_adopted_count = data.cats_adopted_count
	money_earned_total = data.money_earned_total
	playtime_seconds = data.playtime_seconds
	total_deliveries_completed = data.total_deliveries_completed
