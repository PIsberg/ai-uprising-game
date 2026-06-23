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
	var dart := BoxMesh.new()
	dart.size = Vector3(0.012, 0.012, 0.07) # stretched, reads as a streak
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	m.emission_energy_multiplier = 7.0
	dart.material = m

	var gs := get_node_or_null("/root/GraphicsSettings")
	var use_gpu: bool = gs == null or bool(gs.get("gpu_particles_enabled"))
	if use_gpu:
		# GPU path showcases 4.7's scale-over-velocity: the spark is a long hot
		# streak while it's screaming out of the bore, shrinking to a tumbling
		# ember as it slows — instead of a uniform dash.
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = true
		p.amount = 12
		p.lifetime = 0.22
		p.explosiveness = 1.0
		p.draw_pass_1 = dart
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, -1) # out of the bore
		pm.spread = 13.0
		pm.initial_velocity_min = 7.0
		pm.initial_velocity_max = 16.0
		pm.gravity = Vector3(0, -14.0, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.0
		pm.scale_over_velocity_min = 5.0
		pm.scale_over_velocity_max = 16.0
		var sv := Curve.new()
		sv.add_point(Vector2(0.0, 0.45)) # slow -> short ember
		sv.add_point(Vector2(1.0, 2.4))  # fast -> long streak
		var svt := CurveTexture.new(); svt.curve = sv
		pm.scale_over_velocity_curve = svt
		# Tumble the dying embers.
		pm.angle_min = -180.0; pm.angle_max = 180.0
		pm.angular_velocity_min = -600.0; pm.angular_velocity_max = 600.0
		p.process_material = pm
		add_child(p)
	else:
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
		p.angle_min = -180.0; p.angle_max = 180.0
		p.angular_velocity_min = -600.0; p.angular_velocity_max = 600.0
		p.mesh = dart
		add_child(p)
