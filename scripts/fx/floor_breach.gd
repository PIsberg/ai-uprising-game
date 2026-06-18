class_name FloorBreach
extends Node3D
## The floor erupting: chunky concrete slabs are blasted up and out, dust billows,
## a hot under-glow flares from the breach, and a cracked scorch crater is left
## behind. Fully code-built (no art assets). Used for the TERMINATOR's "burst up
## through the floor" entrance. Self-frees once the rubble has settled.

@export var radius: float = 2.8
@export var chunk_count: int = 16

var _chunks: Array = []   # [{node: MeshInstance3D, vel: Vector3, spin: Vector3}]
var _light: OmniLight3D
var _age: float = 0.0

func _ready() -> void:
	_spawn_chunks()
	_spawn_dust()
	_spawn_crater()
	_spawn_flash()
	var tw := create_tween()
	tw.tween_interval(4.5)
	tw.tween_callback(queue_free)

## Angular concrete slabs flung up and outward, tumbling.
func _spawn_chunks() -> void:
	for i in chunk_count:
		var ang := TAU * float(i) / float(chunk_count) + randf_range(-0.25, 0.25)
		var r := randf_range(0.15, radius)
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz := randf_range(0.35, 0.95)
		bm.size = Vector3(sz, randf_range(0.12, 0.3), sz * randf_range(0.7, 1.25))
		var mat := StandardMaterial3D.new()
		var shade := randf_range(0.11, 0.19)
		mat.albedo_color = Color(shade, shade, shade + 0.02)
		mat.roughness = 0.96
		# Some slabs glow molten on the torn underside.
		if randf() < 0.45:
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.38, 0.1)
			mat.emission_energy_multiplier = randf_range(0.6, 1.8)
		bm.material = mat
		slab.mesh = bm
		slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slab.position = Vector3(cos(ang) * r, 0.05, sin(ang) * r)
		slab.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(slab)
		var up := randf_range(6.5, 12.0)
		var outv := randf_range(2.0, 5.5) * (r / radius + 0.3)
		_chunks.append({
			"node": slab,
			"vel": Vector3(cos(ang) * outv, up, sin(ang) * outv),
			"spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)),
		})

## A billowing dust cloud kicked up from the breach.
func _spawn_dust() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 40
	p.lifetime = 1.3
	p.explosiveness = 0.8
	p.direction = Vector3(0, 1, 0)
	p.spread = 75.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.1
	# Grow a touch then fade out so it dissipates like dust instead of popping.
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.5)); sc.add_point(Vector2(0.35, 1.0)); sc.add_point(Vector2(1.0, 0.85))
	p.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.55, 0.5, 0.55))
	ramp.set_color(1, Color(0.5, 0.46, 0.42, 0.0))
	p.color_ramp = ramp
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.85)
	q.material = m
	p.mesh = q
	add_child(p)

## A lingering cracked scorch crater on the deck.
func _spawn_crater() -> void:
	var s := ScorchMark.new()
	s.radius = radius * 1.05
	s.hold = 30.0
	s.fade = 6.0
	add_child(s)

## A hot orange flash welling up from below, snapping out fast.
func _spawn_flash() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.15)
	_light.light_energy = 7.0
	_light.omni_range = radius * 3.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.6, 0)
	add_child(_light)

func _process(delta: float) -> void:
	_age += delta
	if _light:
		_light.light_energy = maxf(0.0, 7.0 * (1.0 - _age / 0.9))
	for c in _chunks:
		var node: Node3D = c["node"]
		if not is_instance_valid(node):
			continue
		var v: Vector3 = c["vel"]
		if node.position.y > 0.02 or v.y > 0.0:
			v.y -= 28.0 * delta
			node.position += v * delta
			node.rotation += c["spin"] * delta
			if node.position.y <= 0.02 and v.y < 0.0:
				node.position.y = 0.02
				v = Vector3.ZERO
				c["spin"] = Vector3.ZERO
			c["vel"] = v
