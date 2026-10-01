class_name AchievementDefinition
extends Resource
## One achievement's identity and unlock condition data. All balance and
## copy lives here (as .tres files in `resources/achievements/`), same
## split as BuildingDefinition/Recipe: the tracker reads these, it never
## hardcodes a threshold.
##
## **Designed for Steam from the start, without depending on Steam.**
## Steam achievements are identified by a per-app "API Name" string and
## are stored **per account, not per save file**. Two consequences shape
## everything here:
## - `id` is the stable key for both local storage and the Steam API
##   name (see `steam_api_name()`), so it must never change once shipped
##   — renaming one silently orphans every player's unlock, locally and
##   on Steam. The display name and description are free to change.
## - Unlock state is stored account-wide in `PlayerConfig`, NOT in the
##   save slot (see Achievements), matching Steam's own semantics so the
##   two can't disagree once Steam is wired up.
##
## Wiring Steam later should need no changes in this file or the
## tracker: `Achievements.achievement_unlocked` is a single chokepoint a
## future Steam layer subscribes to and forwards as
## `Steam.setAchievement(definition.steam_api_name())`.

## How a progress number should be written out. NONE means this
## achievement has no meaningful running count (it's an event: "finished
## the game"), so no progress is shown and none is published.
enum ProgressFormat {
	NONE,
	COUNT,
	MONEY,
	TIME,
}

enum Category {
	PROGRESSION,
	CATS,
	PRODUCTION,
	CHALLENGE,
}

## Stable identifier. Lower_snake_case; never change it after release
## (see the class doc). Also the basis of the Steam API name.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.PROGRESSION
## Art comes later — every definition ships with this null for now, and
## the toast/list fall back to a category-tinted placeholder rather than
## drawing nothing. Dropping a texture in here is the whole of the art
## hand-off; no code changes needed.
@export var icon: Texture2D
## Hidden achievements show as "???" in the list until unlocked (the
## toast always shows the real name — by then it's been earned).
## **Nothing ships hidden**: the achievements list exists so players can
## "see what achievements there are and how to get each", and a "???"
## row is the one thing on that page that answers neither. The mechanism
## stays supported and tested, so flipping this on a future surprise
## achievement is a one-field edit.
@export var hidden: bool = false
## Sort position inside its category, low first. Stops the list order
## depending on file names or disk order.
@export var sort_order: int = 0

@export_group("Condition")
## The number the tracker compares against: cats adopted, items shipped,
## dollars earned, seconds played. Meaning is per-achievement and lives
## in AchievementTracker; this is only the number, so tuning never needs
## a code edit. Zero for achievements that are a pure event ("finished
## the game") with nothing to count.
@export var target: int = 0
## For per-item shipping achievements: which item id to count. Empty for
## everything else.
@export var item: StringName = &""
## How the list renders this achievement's progress ("12 / 25",
## "$34,600 / $50,000", "1h 12m / 5h"). NONE hides it.
##
## **This is also the switch that decides whether reaching `target`
## auto-unlocks.** AchievementTracker only publishes progress for
## achievements whose condition genuinely is "reach this number", and
## `Achievements.set_progress()` unlocks on that. Two achievements
## deliberately have a `target` but stay NONE: Speed Baker (its target is
## a *limit* you want to stay under, so counting up to it would be
## backwards) and Crazy Cat Lady Bakery (its target is only half the
## condition — the cats-per-station ratio is the other half, so a lone
## number would both mislead the player and unlock too early).
@export var progress_format: ProgressFormat = ProgressFormat.NONE

## Optional override for the Steam API Name, for the case where the
## Steamworks entry was already created under a different string. Leave
## empty and it derives from `id`.
@export var steam_api_name_override: String = ""


## The Steam API Name this achievement maps to. Derived rather than
## hand-entered per definition so the two can't drift: `adopt_10_cats`
## becomes `ACH_ADOPT_10_CATS`, which is the convention Steamworks' own
## examples use. Whatever this returns is what has to be typed into the
## Steamworks achievement config.
func steam_api_name() -> String:
	if not steam_api_name_override.is_empty():
		return steam_api_name_override
	return "ACH_" + String(id).to_upper()
