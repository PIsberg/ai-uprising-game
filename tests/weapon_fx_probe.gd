extends Node3D
## Dev probe for the new weapon FX. Left: a continuous laser beam burning into a
## wall (hot core + muzzle/impact flares + scorch). Right: a rocket in flight
## (smoke trail + thruster exhaust) that slams a wall and throws the heavy
## detonation FX. Captures two frames — mid-flight and post-detonation — to
## user://weapon_fx_*.png, then quits. Run windowed:
##   godot --path . res://tests/weapon_fx_probe.tscn

var _beam: ElectricBeam
var _beam_from := Vector3(-3.0, 1.0, 0.0)
var _beam_to := Vector3(-3.0, 1.0, -6.0)

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 6.5)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 0.5
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.3, 0.32, 0.38)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.9
	env.environment = e
	add_child(env)
	# A dark floor + two target walls.
	_add_box(Vector3(0, -0.05, -3), Vector3(20, 0.1, 20), Color(0.1, 0.11, 0.13))
	_add_box(_beam_to + Vector3(0, 0, -0.2), Vector3(2, 3, 0.3), Color(0.18, 0.19, 0.22))
	# Right wall is solid (collision on the world layer) so the rocket detonates.
	_add_box(Vector3(3.0, 1.0, -6.2), Vector3(2, 3, 0.3), Color(0.18, 0.19, 0.22), true)

	# Laser beam burning into the left wall.
	_beam = ElectricBeam.new()
	_beam.set_color(Color(0.45, 0.85, 1.0))
	add_child(_beam)

	# Rocket flying toward the right wall.
	var ps: PackedScene = load("res://scenes/weapons/projectile_rocket.tscn")
	var rocket := ps.instantiate()
	add_child(rocket)
	rocket.global_position = Vector3(3.0, 1.0, 1.5)
	if rocket.has_method("launch"):
		rocket.launch(Vector3(0, 0, -7.0), self, 80.0, 5.0, 160.0)

	_run()

func _process(_dt: float) -> void:
	if _beam:
		_beam.update_beam(_beam_from, _beam_to, true)

func _add_box(pos: Vector3, size: Vector3, col: Color, solid: bool = false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1 # world layer the rocket's mask (0b11) includes
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		body.position = pos
		add_child(body)

func _run() -> void:
	# Real-time waits: particle lifetimes + tweens run in seconds, and the rocket
	# (7 m/s over ~7.7 m) reaches the wall at ~1.1 s.
	await get_tree().create_timer(0.45).timeout
	_save("weapon_fx_flight")
	await get_tree().create_timer(1.05).timeout
	_save("weapon_fx_detonation")
	get_tree().quit()

func _save(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_user_data_dir() + "/%s.png" % name
	img.save_png(path)
	print("SAVED ", path)
