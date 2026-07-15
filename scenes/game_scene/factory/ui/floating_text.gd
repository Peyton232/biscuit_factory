class_name FloatingText
extends Label3D
## A short-lived world-space label that rises and fades out, used for
## feedback like "+$5" over the shipping bin or "+dough" over a mixer.
## Spawn with the static helper; the node frees itself.

@export var rise_speed: float = 1.1
@export var lifetime: float = 1.3

var _age: float = 0.0


static func spawn(parent: Node, world_position: Vector3, message: String,
		color: Color = Color.WHITE) -> void:
	var label := FloatingText.new()
	label.text = message
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.008
	label.font_size = 44
	label.outline_size = 14
	parent.add_child(label)
	label.global_position = world_position


func _process(delta: float) -> void:
	_age += delta
	position += Vector3.UP * rise_speed * delta
	# Hold full opacity briefly, then fade out.
	modulate.a = clampf(2.0 * (1.0 - _age / lifetime), 0.0, 1.0)
	if _age >= lifetime:
		queue_free()
