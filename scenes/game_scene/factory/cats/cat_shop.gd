class_name CatShop
extends Node
## Lets the player adopt new cats, priced per the GDD's explicit cat-cost
## table (progression.md) — a flat per-cat schedule for cats 2-10, then
## flat per-band pricing above that; NOT a linear formula (the increments
## between cats 2-10 vary: +2, +3, +3, +2, +3, +2, +3, +2, +3 — no clean
## `base + n*increment` reproduces this). Pricing is based on how many
## cats have been adopted through this shop — NOT on how many cats exist
## in the world — so the free starting cat (Newby, cat #1, placed
## directly in the scene rather than bought here) doesn't inflate the
## first shop adoption's price. Each adopted cat also gets a random fur
## tint from Cat.FUR_COLORS, purely cosmetic.
##
## **Owns the shared random-name pool** (`NAME_BANK`, `next_suggested_name()`)
## used by both single adoption (`CatNamingDialog` previews one name,
## discarded if the player types over it or cancels) and batch adoption
## (`CatBatchAdoptDialog`, one name consumed per cat bought) — see those
## classes and decisions.md for why this lives here rather than on
## either dialog: it's shared, shop-wide adoption state, not a concern of
## either individual view.
##
## **Two spawn paths**: `adopt_cat_at(name, role, position)` spawns at an
## exact world position — used for single adoption, where the player
## clicks to place the cat (see `CatPlacer`). `buy_cat(name, role)` still
## spawns at the fixed `spawn_position` export (with a small random
## jitter so a run of them doesn't stack exactly on top of each other) —
## used for batch adoption, where requiring N placement clicks in a row
## would defeat the point of a "buy several at once, fast" tool. Both
## funnel through `_spawn_cat()`.

signal cost_changed(cost: int)

## 500 popular cat names, none describing a coat color/pattern — fur
## tint is assigned independently at random (see set_fur_color() below),
## so a color-coded suggestion (Ginger, Oreo, Smokey, ...) could easily
## land on a mismatched cat. Grown from the original 100 after playtest
## feedback asked for a bigger pool; same exclusion rule applied to every
## addition (also screened out food names with a strong coat-color
## association — Snickers, Tootsie, Truffle, etc. — for the same reason).
const NAME_BANK: Array[String] = [
	"Luna", "Bella", "Charlie", "Lucy", "Max", "Milo", "Leo", "Oliver",
	"Simba", "Loki", "Jack", "Chloe", "Lily", "Oscar", "Jasper", "Salem",
	"Gizmo", "Felix", "Nala", "Zoe", "Missy", "Buddy", "Sam", "Sammy",
	"Jasmine", "Tom", "Ziggy", "Cleo", "Rocky", "Molly", "Winston", "Toby",
	"Kiki", "Sasha", "Bailey", "Daisy", "Rosie", "Sophie", "Maggie", "Angel",
	"Baby", "Princess", "Duchess", "Queenie", "Duke", "Prince", "King",
	"Captain", "Admiral", "Zeus", "Apollo", "Athena", "Freya", "Odin",
	"Thor", "Hera", "Artemis", "Poseidon", "Atlas", "Phoenix", "Nova",
	"Stella", "Willow", "Ivy", "Meadow", "Aurora", "Skye", "Winter",
	"Sierra", "Aspen", "Juniper", "Aria", "Echo", "Comet", "Sadie",
	"Ellie", "Piper", "Hannah", "Emma", "Ava", "Mia", "Zara", "Layla",
	"Nora", "Ada", "Iris", "Vera", "Mabel", "Juno", "Boo", "Nibbles",
	"Pixel", "Widget", "Noodle", "Pretzel", "Waffles", "Cupcake", "Bean",
	"Puddles", "Bubbles",
	"Alice", "Alex", "Anna", "Abby", "Amelia", "Adam", "Ben", "Beth",
	"Bob", "Carl", "Cathy", "Chris", "Clara", "Cody", "Cora", "Diana",
	"Dylan", "Ella", "Emily", "Ethan", "Eva", "Evan", "Faith", "Finn",
	"Fiona", "Frank", "Gabby", "Gary", "Gemma", "George", "Grace", "Hank",
	"Henry", "Holly", "Hope", "Ian", "Jake", "Jane", "Janet", "Jenny",
	"Joey", "Jordan", "Josie", "Julia", "June", "Kai", "Kate", "Katie",
	"Kevin", "Kyle", "Lea", "Leah", "Leon", "Levi", "Liam", "Lila",
	"Liz", "Lola", "Louie", "Louis", "Mac", "Madge", "Mae", "Mandy",
	"Marco", "Maria", "Marlow", "Matt", "Mavis", "Maya", "Mel", "Millie",
	"Mimi", "Minnie", "Monty", "Nancy", "Nate", "Ned", "Nell", "Nico",
	"Nikki", "Nina", "Norah", "Ollie", "Opie", "Paige", "Pam", "Pat",
	"Paul", "Peggy", "Percy", "Pete", "Phil", "Poppy", "Quinn", "Rachel",
	"Randy", "Ray", "Reggie", "Remy", "Rex", "Riley", "Robbie", "Roger",
	"Rosa", "Roxy", "Rufus", "Ruth", "Sally", "Sara", "Scout", "Sean",
	"Shane", "Sharon", "Sheila", "Sherman", "Sid", "Simon", "Sonny", "Stan",
	"Stevie", "Sue", "Susie", "Sydney", "Tara", "Ted", "Terry", "Theo",
	"Tia", "Tilly", "Timmy", "Tina", "Tommy", "Tony", "Tori", "Trish",
	"Tucker", "Uma", "Val", "Vic", "Vicky", "Vinny", "Vito", "Wade",
	"Wally", "Walt", "Wendy", "Will", "Wyatt", "Zack", "Zeke", "Zia",
	"Ares", "Cupid", "Eros", "Gaia", "Hades", "Helios", "Hercules", "Hestia",
	"Icarus", "Isis", "Janus", "Kronos", "Leda", "Medusa", "Midas", "Minerva",
	"Morpheus", "Nemesis", "Nike", "Nyx", "Orion", "Osiris", "Pan", "Persephone",
	"Rhea", "Selene", "Skadi", "Titan", "Triton", "Ulysses", "Vulcan", "Woden",
	"Xena", "Yara", "Bragi", "Freyr", "Baldur", "Idun", "Tyr", "Frigg",
	"Autumn", "Birch", "Blossom", "Breeze", "Brook", "Canyon", "Cedar", "Clay",
	"Cliff", "Clover", "Coral", "Dawn", "Dune", "Ember", "Fern", "Flint",
	"Flora", "Forest", "Frost", "Glacier", "Glen", "Gale", "Harbor", "Haze",
	"Hollow", "Horizon", "Isle", "Jet", "Lake", "Lark", "Leaf", "Marsh",
	"Meadowlark", "Mesa", "Mist", "Moon", "Moss", "Ocean", "Pebble", "Petal",
	"Pine", "Prairie", "Rain", "Reed", "Ridge", "River", "Robin", "Sage",
	"Sea", "Shell", "Slate", "Sol", "Star", "Stone", "Storm", "Summer",
	"Sunny", "Thistle", "Thunder", "Tide", "Timber", "Torrent", "Vale", "Violet",
	"Wren", "Yarrow", "Bubba", "Bumble", "Button", "Chip", "Chirpy", "Cricket",
	"Dash", "Doodle", "Doogle", "Dumpling", "Fidget", "Figgy", "Fizz", "Fluffball",
	"Gadget", "Giggle", "Goober", "Gremlin", "Grub", "Gus", "Hobbes", "Hopper",
	"Jellybean", "Jiggles", "Jinx", "Jitter", "Kiddo", "Kip", "Kit", "Knick",
	"Knack", "Marbles", "Muffin", "Munchkin", "Nugget", "Nutter", "Peewee", "Pippin",
	"Pogo", "Pom", "Poof", "Popcorn", "Puffball", "Pumpkin", "Quill", "Ribbit",
	"Ripple", "Scamp", "Scooter", "Scribble", "Skipper", "Skittle", "Sniffles", "Snap",
	"Sprocket", "Squeak", "Squiggle", "Squish", "Tater", "Tick", "Tinker", "Tumble",
	"Twinkle", "Twitch", "Wiggle", "Wobble", "Zippy", "Zoom", "Baron", "Baroness",
	"Bishop", "Countess", "Czar", "Earl", "Emperor", "Empress", "General", "Governor",
	"Judge", "Kaiser", "Lady", "Lord", "Madame", "Major", "Marquis", "Monarch",
	"Pharaoh", "Rajah", "Rani", "Regent", "Sheriff", "Sultan", "Viceroy", "Viscount",
	"Colonel", "Commander", "Sergeant", "Basil", "Berry", "Biscotti", "Clementine", "Fennel",
	"Ginseng", "Mango", "Olive", "Papaya", "Pepper", "Plum", "Pumpernickel", "Saffron",
	"Sesame", "Sprout", "Tofu", "Wasabi", "Yam", "Kiwi", "Mint", "Rye",
	"Yuzu", "Astro", "Buzz", "Cosmo", "Cosmos", "Draco", "Eclipse", "Galaxy",
	"Halo", "Jupiter", "Meteor", "Neptune", "Nebula", "Orbit", "Photon", "Pluto",
	"Pulsar", "Quasar", "Rocket", "Saturn", "Rowan", "Wisp", "Nimbus", "Sunday",
]

@export var cat_scene: PackedScene
@export var cats_root: Node3D
@export var economy: Economy
@export var grid_manager: GridManager
@export var delivery_manager: DeliveryManager
@export var lifetime_stats: LifetimeStats

@export var spawn_position: Vector3 = Vector3.ZERO

## Cost for cats #2 through #10 specifically (index 0 = cat #2, ...
## index 8 = cat #10) — the part of the table with no clean per-band
## shortcut. Cats #11+ fall through to flat per-band pricing below.
const _EARLY_COSTS: Array[int] = [10, 12, 15, 18, 20, 23, 25, 28, 30]

var _adopted_count: int = 0
## A shuffled copy of NAME_BANK, drawn from front-to-back so a session
## sees every name once before any repeat — reshuffled only once fully
## exhausted. Built once in _ready(), not at const-eval time, since
## shuffle() depends on the engine's RNG being seeded.
var _name_pool: Array[String] = []
var _name_pool_index: int = 0


func _ready() -> void:
	_reshuffle_name_pool()


## The overall cat number this adoption would be (#1 is the free
## starting cat, never bought here) mapped straight to progression.md's
## table.
func current_cost() -> int:
	return _cost_for_cat_number(_adopted_count + 2)


## Total cost of adopting `quantity` cats back-to-back starting from the
## shop's current state, without actually spending/adopting anything —
## used by CatBatchAdoptDialog to preview a running total as the player
## changes the quantity (prices rise per cat, so this is never just
## quantity * current_cost()).
func cost_for_quantity(quantity: int) -> int:
	var total: int = 0
	for i: int in quantity:
		total += _cost_for_cat_number(_adopted_count + 2 + i)
	return total


func _cost_for_cat_number(cat_number: int) -> int:
	if cat_number <= 10:
		return _EARLY_COSTS[cat_number - 2]
	if cat_number <= 15:
		return 35
	if cat_number <= 20:
		return 40
	if cat_number <= 30:
		return 50
	if cat_number <= 40:
		return 60
	if cat_number <= 50:
		return 75
	return 100


func can_afford() -> bool:
	return economy.can_afford(current_cost())


## The next name to suggest, walking through a shuffled NAME_BANK front
## to back (reshuffling once exhausted) rather than a fresh
## pick_random() per call, which could repeat immediately — see
## decisions.md. Purely a suggestion: nothing is reserved by calling
## this, so previewing one (opening a dialog) and never adopting just
## means that name comes up again sooner next time, which is fine.
func next_suggested_name() -> String:
	if _name_pool_index >= _name_pool.size():
		_reshuffle_name_pool()
	var name_: String = _name_pool[_name_pool_index]
	_name_pool_index += 1
	return name_


func _reshuffle_name_pool() -> void:
	_name_pool = NAME_BANK.duplicate()
	_name_pool.shuffle()
	_name_pool_index = 0


## Adopts and spawns a new cat at an exact world position (the player
## clicked to place it — see CatPlacer) if affordable; returns false
## otherwise.
func adopt_cat_at(cat_name: String, role: Cat.Role, position: Vector3) -> bool:
	return _spawn_cat(cat_name, role, position)


## Adopts and spawns a new cat at the fixed spawn_position (plus a small
## random jitter so a run of batch-adopted cats doesn't stack exactly on
## top of each other) if affordable; returns false otherwise. Used for
## single adoption before CatPlacer existed, and still used today for
## batch adoption, where requiring a placement click per cat would
## defeat the point of buying several at once quickly.
func buy_cat(cat_name: String, role: Cat.Role = Cat.Role.DELIVERY) -> bool:
	var jitter := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	return _spawn_cat(cat_name, role, spawn_position + jitter)


## Common spend-and-spawn path for both adoption entry points above. The
## name/role are set after add_child() since Cat.set_cat_name()/set_role()
## touch onready vars (name label, station-search state) that only exist
## once the cat has entered the tree.
func _spawn_cat(cat_name: String, role: Cat.Role, position: Vector3) -> bool:
	if not economy.try_spend(current_cost()):
		return false
	_adopted_count += 1
	if lifetime_stats != null:
		lifetime_stats.record_cat_adopted()
	var cat: Cat = cat_scene.instantiate() as Cat
	cat.delivery_manager = delivery_manager
	cat.grid_manager = grid_manager
	cat.position = position
	cats_root.add_child(cat)
	cat.set_cat_name(cat_name)
	cat.set_role(role)
	cat.set_fur_color(randi() % Cat.FUR_COLORS.size())
	cost_changed.emit(current_cost())
	return true


## Reconstructs a previously-adopted cat during save/load restore — like
## _spawn_cat() but never spends money or touches _adopted_count/
## lifetime_stats, since this cat was already paid for and counted in
## the session that saved it. Its saved name/role/position/fur tint plus
## Employee Awards lifetime stats (load_lifetime_stats()) need recreating;
## see FactoryWorld.apply_save_data().
func restore_cat(entry: CatSaveEntry) -> void:
	var cat: Cat = cat_scene.instantiate() as Cat
	cat.delivery_manager = delivery_manager
	cat.grid_manager = grid_manager
	cat.position = entry.position
	cats_root.add_child(cat)
	cat.set_cat_name(entry.cat_name)
	cat.set_role(entry.role as Cat.Role)
	cat.set_fur_color(entry.fur_color_index)
	cat.load_lifetime_stats(entry)


## Restores the shop's own adopted-cat counter after a save load, so
## future pricing continues where the previous session left off instead
## of restarting at cat #2's price. _adopted_count and
## LifetimeStats.cats_adopted_count only ever increment together (see
## _spawn_cat() above), so they're always equal — this derives the
## counter from the already-restored LifetimeStats rather than needing a
## redundant saved field.
func restore_adopted_count(count: int) -> void:
	_adopted_count = count
