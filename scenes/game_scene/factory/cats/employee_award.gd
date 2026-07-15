class_name EmployeeAward
extends RefCounted
## One computed Employee Award result — see EmployeeAwards.compute().
## Plain data, no logic; EmployeeAwardsDialog just formats these three
## strings into a display row.

var title: String
var cat_name: String
var value_text: String


func _init(award_title: String, winner_cat_name: String, winner_value_text: String) -> void:
	title = award_title
	cat_name = winner_cat_name
	value_text = winner_value_text
