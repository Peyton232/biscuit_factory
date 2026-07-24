class_name CatSaveEntry
extends Resource
## One cat's save-relevant state — see Cat.save_entry() and
## CatShop.restore_cat(). `role` is Cat.Role's int value rather than the
## enum type itself, since a plain int is simpler to round-trip through
## a Resource export and every caller already converts back via
## `as Cat.Role` (matching how CatNamingDialog/CatBatchAdoptDialog pass
## roles around elsewhere in this codebase).
##
## The `total_*`/`roles_held`/`station_batches_completed` fields below
## are Cat's lifetime Employee Awards stats (see Cat.gd's own doc) —
## persisted so a save/load mid-playthrough doesn't reset a cat's
## progress toward Workaholic/Master Baker/etc. `roles_held` and
## `station_batches_completed` use plain `int` keys (Cat.Role's int
## value), same "Resource export typing doesn't cover enum/StringName
## keys as cleanly" reasoning BuildingSaveEntry's own dictionaries
## already document — Cat.save_entry()/load_lifetime_stats() convert at
## the read/write boundary.

@export var cat_name: String = ""
@export var role: int = 0
@export var position: Vector3 = Vector3.ZERO
## Index into Cat.FUR_COLORS — see Cat.set_fur_color()/fur_color_index.
@export var fur_color_index: int = 0
## Index into Cat.BREEDS — see Cat.set_breed()/breed_index.
@export var breed_index: int = 0
@export var total_deliveries_completed: int = 0
@export var total_delivery_seconds: float = 0.0
@export var total_busy_seconds: float = 0.0
@export var total_idle_seconds: float = 0.0
@export var total_distance_meters: float = 0.0
## Every distinct Cat.Role int this cat has ever held.
@export var roles_held: Array[int] = []
## Cat.Role int -> completed batch count at that role.
@export var station_batches_completed: Dictionary[int, int] = {}
