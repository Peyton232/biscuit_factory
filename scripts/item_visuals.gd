class_name ItemVisuals
extends RefCounted
## Per-item display-scale correction for the shared item-icon pipeline.
## Every consumer of assets/sprites/items/<id>.png (Cat's CarriedItem,
## BuildingItemDisplay, IngredientSourceStack) renders that PNG at one
## shared pixel_size, so an item whose hand-drawn art happens to occupy
## more of its native canvas than its neighbors renders visibly larger
## in-world for no gameplay reason -- there's no per-item size gameplay
## should express. scale_for() multiplies into whatever pixel_size a
## call site already uses; unlisted items (or items with no size issue)
## get 1.0, i.e. unchanged.
##
## Values were derived from each PNG's native pixel height (checked
## directly, not eyeballed) against a ~26px target -- cake_layer's own
## height, chosen as the anchor because the cake/batter/pie/egg/butter
## art was confirmed correctly sized as-is (2026-07-13). Items at or
## below that target keep the default 1.0 rather than getting scaled up.
## Follow-up same day: `biscuit`/`cream_bun`/`frosted_cake` got a further
## (milder) trim after actually seeing them in the live factory rather
## than just the static showcase grid -- `cake_layer` itself (the anchor)
## stays untouched.

const _SCALE_OVERRIDES: Dictionary[StringName, float] = {
	&"whipped_cream": 0.52,
	&"meringue": 0.57,
	&"frosting": 0.54,
	&"milk": 0.6,
	&"sweet_dough": 0.58,
	&"rich_dough": 0.67,
	&"basic_dough": 0.68,
	&"buttered_toast": 0.62,
	&"french_toast": 0.62,
	&"sliced_bread": 0.62,
	&"toast": 0.62,
	&"cookie_cutout": 0.63,
	&"frosted_sugar_cookie": 0.63,
	&"sugar_cookie": 0.63,
	&"bread_roll": 0.68,
	&"butter_roll": 0.65,
	&"frosted_sweet_roll": 0.72,
	&"sweet_roll": 0.72,
	&"biscuit": 0.75,
	&"danish": 0.81,
	&"sugar": 0.76,
	&"flour": 0.87,
	&"bread": 0.96,
	&"cream_bun": 0.82,
	&"frosted_cake": 0.82,
}


static func scale_for(item: StringName) -> float:
	return _SCALE_OVERRIDES.get(item, 1.0)
