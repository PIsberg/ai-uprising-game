extends Node3D
## Lines up the new robots, renders one frame, screenshots it, and quits.
## Run (with a window): godot --path . tools/preview_robots.tscn

const ROBOTS := ["vacuum", "reaper", "hunter", "sentinel", "mauler"]


func _ready() -> void:
	# Camera.
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.2, 13), Vector3(0, 1.0, 0), Vector3.UP)
	cam.make_current()

	# Lighting + sky.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.4
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.18)
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	# Ground.
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 0.22, 0.25)
	pm.material = gmat
	ground.mesh = pm
	add_child(ground)

	# Robots in a row, facing the camera.
	var xs := [-6.0, -3.0, 0.0, 3.0, 6.0]
	for i in ROBOTS.size():
		var bot: Node3D = load("res://scenes/enemies/%s.tscn" % ROBOTS[i]).instantiate()
		add_child(bot)
		bot.global_position = Vector3(xs[i], 0, 0)
		bot.rotation.y = PI                 # face the camera
		if bot.has_method("set_physics_process"):
			bot.set_physics_process(false)  # freeze AI; keep model
		# Show the custodian fully risen so its legs are visible.
		if ROBOTS[i] == "vacuum" and bot.has_method("_apply_rise"):
			bot._apply_rise(1.0)
		# A 2 m reference pole beside each robot (red top mark at 2 m).
		var pole := MeshInstance3D.new()
		var pmm := BoxMesh.new()
		pmm.size = Vector3(0.08, 2.0, 0.08)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.9, 0.9, 0.95)
		pmm.material = pmat
		pole.mesh = pmm
		pole.position = Vector3(xs[i] - 1.1, 1.0, 0.4)
		add_child(pole)

	# Render a few frames, then capture.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/preview.png")
	print("PREVIEW SAVED")
	get_tree().quit()
