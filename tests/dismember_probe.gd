extends Node3D
## Dev probe: spawns an android on a lit floor, damages it past its health
## thresholds, and screenshots mid-degradation to confirm panels shed without
## errors. Run windowed:
##   godot --path . res://tests/dismember_probe.tscn

var _bot: Node3D

func _ready() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.6, 4.2)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.11, 0.13)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 1.0
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.15, 0.15, 0.17)
	floor_mi.material_override = fm
	add_child(floor_mi)
	_run.call_deferred()

func _run() -> void:
	var ps: PackedScene = load("res://scenes/enemies/android.tscn")
	_bot = ps.instantiate()
	add_child(_bot)
	_bot.global_position = Vector3(0, 0, 0)
	_bot.rotation.y = PI
	if _bot.has_method("set_physics_process"):
		_bot.set_physics_process(false) # no AI; we just want the damage reactions
	await _wait(0.4)
	var hp = _bot.get_node_or_null("Damageable")
	# Three bites: should cross 0.66 and 0.33 thresholds -> two panels shed.
	for i in 3:
		if hp:
			hp.apply_damage(28.0, null)
		await _wait(0.5)
		await _save("dismember_%d" % i)
	get_tree().quit()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/%s.png" % name)
	print("SAVED ", name)
