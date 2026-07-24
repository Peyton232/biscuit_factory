class_name EmployeeAwards
extends RefCounted
## Computes the end-of-game Employee Awards for the Bakery Report (see
## gameplay_overview.md's "Ending & replayability" and
## VictorySequence.play(), which calls compute() once, right after the
## Bakery Report is dismissed). Pure computation over the live cat
## roster's lifetime stats (Cat.total_*/station_batches_completed/
## roles_held — see Cat.gd's own doc for what each one tracks and why);
## this class owns no state itself and touches no UI.
##
## Award pool (11 possible entries): Employee of the Month (most jobs
## overall, deliveries + station batches combined), Fastest Delivery Cat
## (lowest average delivery time), Master Baker (most station batches
## overall), Workaholic (most busy time), Professional Napper (most
## idle/wander time), Explorer (most distance walked), Jack of All
## Trades (most distinct roles ever held), and one Most-Jobs award per
## station role (Mixer/Oven/Cutting/Assembly).
##
## **Draws _AWARDS_PER_PLAYTHROUGH at random from whichever pool entries
## actually have an eligible winner** — an award nobody qualifies for
## this run (e.g. no cat ever staffed a Cutting Station) is dropped from
## the pool before drawing, never shown with a hollow/zero winner. Ties
## are broken by whichever cat sorts first in the roster (stable,
## deterministic) — not worth a fancier tiebreaker for a cosmetic
## end-of-game flourish. This is what makes different playthroughs
## surface different cats/awards, per the design brief.

const _AWARDS_PER_PLAYTHROUGH: int = 3
## A station role needs at least this many batches from its single best
## cat before "Most <Role> Jobs" is worth awarding — guards against a
## very short victory-lap crowning a cat that did exactly one batch.
const _MIN_STATION_BATCHES_FOR_AWARD: int = 1
## Jack of All Trades needs at least this many distinct roles ever held —
## 1 just means "never reassigned," which isn't "jack of all trades."
const _MIN_ROLES_FOR_JACK_OF_ALL_TRADES: int = 2


static func compute(cats: Array[Cat]) -> Array[EmployeeAward]:
	var pool: Array[EmployeeAward] = _eligible_pool(cats)
	pool.shuffle()
	return pool.slice(0, mini(_AWARDS_PER_PLAYTHROUGH, pool.size()))


static func _eligible_pool(cats: Array[Cat]) -> Array[EmployeeAward]:
	var pool: Array[EmployeeAward] = []
	_append_if_won(pool, _employee_of_the_month(cats))
	_append_if_won(pool, _fastest_delivery_cat(cats))
	_append_if_won(pool, _master_baker(cats))
	_append_if_won(pool, _workaholic(cats))
	_append_if_won(pool, _professional_napper(cats))
	_append_if_won(pool, _explorer(cats))
	_append_if_won(pool, _jack_of_all_trades(cats))
	for role: Cat.Role in [Cat.Role.MIXER, Cat.Role.OVEN, Cat.Role.CUTTER, Cat.Role.ASSEMBLER]:
		_append_if_won(pool, _most_station_jobs(cats, role))
	return pool


static func _append_if_won(pool: Array[EmployeeAward], award: EmployeeAward) -> void:
	if award != null:
		pool.append(award)


static func _total_jobs(cat: Cat) -> int:
	return cat.total_deliveries_completed + _total_batches(cat)


static func _total_batches(cat: Cat) -> int:
	var total: int = 0
	for count: int in cat.station_batches_completed.values():
		total += count
	return total


static func _employee_of_the_month(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_total: int = 0
	for cat: Cat in cats:
		var total: int = _total_jobs(cat)
		if best == null or total > best_total:
			best = cat
			best_total = total
	if best == null or best_total <= 0:
		return null
	return EmployeeAward.new("Employee of the Month", best.cat_name, "%d jobs completed" % best_total,
			best.breed_index, best.fur_color_index)


static func _fastest_delivery_cat(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_avg: float = INF
	for cat: Cat in cats:
		if cat.total_deliveries_completed < 1:
			continue
		var avg: float = cat.total_delivery_seconds / cat.total_deliveries_completed
		if avg < best_avg:
			best = cat
			best_avg = avg
	if best == null:
		return null
	return EmployeeAward.new("Fastest Delivery Cat", best.cat_name, "%.1fs avg. delivery" % best_avg,
			best.breed_index, best.fur_color_index)


static func _master_baker(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_total: int = 0
	for cat: Cat in cats:
		var total: int = _total_batches(cat)
		if best == null or total > best_total:
			best = cat
			best_total = total
	if best == null or best_total <= 0:
		return null
	return EmployeeAward.new("Master Baker", best.cat_name, "%d items produced" % best_total,
			best.breed_index, best.fur_color_index)


static func _workaholic(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_seconds: float = 0.0
	for cat: Cat in cats:
		if best == null or cat.total_busy_seconds > best_seconds:
			best = cat
			best_seconds = cat.total_busy_seconds
	if best == null or best_seconds <= 0.0:
		return null
	return EmployeeAward.new(
			"Workaholic", best.cat_name, "%s spent working" % LifetimeStats.format_playtime(best_seconds),
			best.breed_index, best.fur_color_index)


static func _professional_napper(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_seconds: float = 0.0
	for cat: Cat in cats:
		if best == null or cat.total_idle_seconds > best_seconds:
			best = cat
			best_seconds = cat.total_idle_seconds
	if best == null or best_seconds <= 0.0:
		return null
	return EmployeeAward.new(
			"Professional Napper", best.cat_name, "%s spent napping" % LifetimeStats.format_playtime(best_seconds),
			best.breed_index, best.fur_color_index)


static func _explorer(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_distance: float = 0.0
	for cat: Cat in cats:
		if best == null or cat.total_distance_meters > best_distance:
			best = cat
			best_distance = cat.total_distance_meters
	if best == null or best_distance <= 0.0:
		return null
	return EmployeeAward.new("Explorer", best.cat_name, "%d m walked" % roundi(best_distance),
			best.breed_index, best.fur_color_index)


static func _jack_of_all_trades(cats: Array[Cat]) -> EmployeeAward:
	var best: Cat = null
	var best_count: int = 0
	for cat: Cat in cats:
		var count: int = cat.roles_held.size()
		if best == null or count > best_count:
			best = cat
			best_count = count
	if best == null or best_count < _MIN_ROLES_FOR_JACK_OF_ALL_TRADES:
		return null
	return EmployeeAward.new("Jack of All Trades", best.cat_name, "%d roles held" % best_count,
			best.breed_index, best.fur_color_index)


static func _most_station_jobs(cats: Array[Cat], role: Cat.Role) -> EmployeeAward:
	var best: Cat = null
	var best_count: int = 0
	for cat: Cat in cats:
		var count: int = cat.station_batches_completed.get(role, 0)
		if best == null or count > best_count:
			best = cat
			best_count = count
	if best == null or best_count < _MIN_STATION_BATCHES_FOR_AWARD:
		return null
	return EmployeeAward.new("Most %s Jobs" % _role_label(role), best.cat_name, "%d batches" % best_count,
			best.breed_index, best.fur_color_index)


static func _role_label(role: Cat.Role) -> String:
	match role:
		Cat.Role.MIXER:
			return "Mixer"
		Cat.Role.OVEN:
			return "Oven"
		Cat.Role.CUTTER:
			return "Cutting Station"
		Cat.Role.ASSEMBLER:
			return "Assembly Table"
		_:
			return "Unknown"
