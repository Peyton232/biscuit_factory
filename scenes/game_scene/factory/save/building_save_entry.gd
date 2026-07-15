class_name BuildingSaveEntry
extends Resource
## One placed building's save-relevant state, as a plain data record —
## no Node/Building reference (buildings don't survive a scene reload,
## so there's nothing here but data). `definition_path` is the building
## type's `.tres` resource_path (e.g. "res://resources/buildings/
## mixer.tres") — a stable, always-present identifier, unlike `uid://`
## which some building resources lack (confirmed by inspection) — see
## Building.save_entry()/load_entry().
##
## `recipe_path` and `accepted_items` are only ever populated for the
## building types that have them (ProcessingBuilding, ShippingBin
## respectively) — empty/unused otherwise. Dictionary keys are plain
## String, not StringName, purely because Resource export typing
## doesn't cover StringName-keyed dictionaries as cleanly; callers
## convert at the read/write boundary (see Building.save_entry()).

@export var definition_path: String = ""
@export var cell: Vector2i = Vector2i.ZERO
## ProcessingBuilding only; empty string means no recipe assigned.
@export var recipe_path: String = ""
@export var input_items: Dictionary[String, int] = {}
@export var output_items: Dictionary[String, int] = {}
## ShippingBin only; empty for every other building type.
@export var accepted_items: Dictionary[String, bool] = {}
