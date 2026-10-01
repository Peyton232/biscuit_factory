class_name Sfx
extends AudioStreamPlayer
## A one-shot, self-freeing sound effect — mirrors FloatingText's "spawn
## and let it clean itself up" idiom instead of each caller owning a
## persistent AudioStreamPlayer and having to juggle retrigger-cuts-off-
## the-previous-tail behavior by hand. Non-positional (plain
## AudioStreamPlayer, not the 3D variant) — every current one-shot call
## site is a discrete game event (building placed, recipe unlocked, item
## shipped, tier complete, factory expanded, the ending beat) where
## where-in-the-world it happened doesn't matter, unlike the looping
## station ambience (see ui/station_sound.gd), which deliberately does
## use positional/visibility-gated audio to avoid overwhelming the player
## with dozens of simultaneous stations.

const _BUS: StringName = &"SFX"


## Named spawn(), not play() — Sfx extends AudioStreamPlayer, which
## already declares an instance method called play(); a static method
## sharing that name but a different signature is a real parse error
## ("overrides a method from native class"), not just a style choice.
##
## Returns the underlying AudioStreamPlayer (still self-freeing on
## `finished`) so a caller that cares when a specific one-shot ends —
## e.g. FactoryWorld awaiting the ending beat's sound before swelling
## the tier music back up — can await its `finished` signal too;
## every existing call site just ignores the return value.
static func spawn(parent: Node, stream: AudioStream) -> AudioStreamPlayer:
	if stream == null:
		return null
	var player := Sfx.new()
	player.stream = stream
	player.bus = _BUS
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	return player
