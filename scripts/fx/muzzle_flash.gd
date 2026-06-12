extends Node3D

@export var lifetime: float = 0.06
var _age: float = 0.0
var _size: float = 1.0

func _ready() -> void:
	# No two flashes alike: random roll around the bore + per-shot size jitter.
	rotation.z = randf() * TAU
	_size = randf_range(0.8, 1.35)
	for c in get_children():
		if c is MeshInstance3D:
			# A flash is light — it must not draw into shadow maps.
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spawn_sparks()

func _process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		# Flash is spent; go dark but linger so the spark burst can finish.
		for c in get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false
			elif c is OmniLight3D:
				(c as OmniLight3D).light_energy = 0.0
		if _age > 0.45:
			queue_free()
		return
	var s := 1.0 - (_age / lifetime)
	scale = Vector3.ONE * (0.6 + s * 0.6) * _size
	for c in get_children():
		if c is OmniLight3D:
			# Sharp pop (quadratic decay) that briefly throws light around.
			(c as OmniLight3D).light_energy = 9.0 * s * s * _size

## Hot spark darts spat from the bore — the detail that separates a flat
## "flash card" from a gunshot. One burst per shot, dies with the node.
func _spawn_sparks() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 10
	p.lifetime = 0.22
	p.explosiveness = 1.0
	p.direction = Vector3(0, 0, -1) # out of the bore
	p.spread = 13.0
	p.initial_velocity_min = 7.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var dart := BoxMesh.new()
	dart.size = Vector3(0.012, 0.012, 0.07) # stretched, reads as a streak
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	m.emission_energy_multiplier = 7.0
	dart.material = m
	p.mesh = dart
	add_child(p)
