class_name EmployeeAward
extends RefCounted
## One computed Employee Award result — see EmployeeAwards.compute().
## Plain data, no logic; EmployeeAwardsDialog formats/displays these.
##
## Carries the winning cat's `breed_index`/`fur_color_index` (not a live
## `Cat` reference) so the dialog can render an actual portrait of the
## winner via `CatPortrait` — plain ints, same "decoupled from the live
## node" convention `CatSaveEntry` already uses for the same two fields,
## rather than holding a `Cat` in this otherwise-plain data/RefCounted
## class.

var title: String
var cat_name: String
var value_text: String
var breed_index: int
var fur_color_index: int


func _init(award_title: String, winner_cat_name: String, winner_value_text: String,
		winner_breed_index: int, winner_fur_color_index: int) -> void:
	title = award_title
	cat_name = winner_cat_name
	value_text = winner_value_text
	breed_index = winner_breed_index
	fur_color_index = winner_fur_color_index
