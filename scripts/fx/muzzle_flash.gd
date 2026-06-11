extends Node3D

@export var lifetime: float = 0.06
var _age: float = 0.0
var _size: float = 1.0

func _ready() -> void:
	# No two flashes alike: random roll around the bore + per-shot size jitter.
	rotation.z = randf() * TAU
	_size = randf_range(0.8, 1.35)

func _process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		queue_free()
		return
	var s := 1.0 - (_age / lifetime)
	scale = Vector3.ONE * (0.6 + s * 0.6) * _size
	for c in get_children():
		if c is OmniLight3D:
			# Bright flicker that briefly throws light across the room each shot.
			(c as OmniLight3D).light_energy = 6.5 * s * _size
