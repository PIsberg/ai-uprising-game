extends Node3D
## Dev probe: fires several enemy bolts and one player tracer across the view,
## captures user://tracer_screenshot.png mid-flight. Run windowed:
##   godot --path . res://tests/tracer_screenshot.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 6)
	add_child(cam)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_hdr_threshold = 1.1
	env.environment = e
	add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.18, 0.19, 0.22)
	floor_mi.material_override = fmat
	add_child(floor_mi)
	await get_tree().create_timer(0.3).timeout
	var red: PackedScene = load("res://scenes/fx/tracer_red.tscn")
	# Three enemy bolts at staggered ages so the frame shows them mid-flight.
	for it in [[Vector3(-9, 1.8, -12), Vector3(2, 1.4, 5), 0.0],
			[Vector3(8, 2.2, -14), Vector3(-1, 1.5, 5), 0.12],
			[Vector3(0, 3.0, -18), Vector3(0.5, 1.5, 6), 0.24]]:
		if float(it[2]) > 0.0:
			await get_tree().create_timer(it[2]).timeout
		var t := red.instantiate()
		add_child(t)
		t.setup(it[0], it[1])
	# One player tracer for contrast (instant warm line).
	var ply := (load("res://scenes/fx/tracer.tscn") as PackedScene).instantiate()
	add_child(ply)
	ply.setup(Vector3(0.4, 1.4, 5.5), Vector3(-6, 1.6, -14))
	await get_tree().create_timer(0.03).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/tracer_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/tracer_screenshot.png")
	get_tree().quit()
