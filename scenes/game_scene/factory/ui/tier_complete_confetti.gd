class_name TierCompleteConfetti
extends Control
## A short celebratory confetti burst covering the whole screen, shown
## when a tier completes — "tier complete isn't obvious enough" playtest
## feedback. Purely decorative, self-freeing, same "spawn with a static
## helper, the node frees itself" pattern as FloatingText.
##
## Built from plain CPUParticles2D emitters (no texture asset needed —
## an untextured CPUParticles2D still draws as small colored quads) laid
## out along the top edge of the screen, each firing one downward burst.

const _COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.45),
	Color(1.0, 0.85, 0.3),
	Color(0.45, 0.85, 1.0),
	Color(0.6, 1.0, 0.55),
	Color(0.85, 0.55, 1.0),
]

@export var emitter_count: int = 10
@export var burst_lifetime: float = 2.2


static func spawn(parent: Node) -> void:
	var confetti := TierCompleteConfetti.new()
	parent.add_child(confetti)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var viewport_width: float = get_viewport_rect().size.x
	for i: int in range(emitter_count):
		var particles := CPUParticles2D.new()
		particles.position = Vector2(viewport_width * (float(i) + 0.5) / emitter_count, -10.0)
		particles.one_shot = true
		particles.amount = 14
		particles.lifetime = burst_lifetime
		particles.explosiveness = 0.4
		particles.direction = Vector2(0.0, 1.0)
		particles.spread = 50.0
		particles.gravity = Vector2(0.0, 220.0)
		particles.initial_velocity_min = 60.0
		particles.initial_velocity_max = 160.0
		particles.scale_amount_min = 3.0
		particles.scale_amount_max = 6.0
		particles.color = _COLORS[i % _COLORS.size()]
		add_child(particles)
		particles.emitting = true
	await get_tree().create_timer(burst_lifetime + 0.3).timeout
	queue_free()
