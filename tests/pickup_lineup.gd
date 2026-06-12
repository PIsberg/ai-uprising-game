extends Node3D
## Dev probe: renders the pickups (health, ammo, weapon) side by side and
## saves user://pickup_lineup.png, then quits. Run windowed:
##   godot --path . res://tests/pickup_lineup.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.1, 3.2)
	cam.rotation_degrees = Vector3(-8, 0, 0)
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.15, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_hdr_threshold = 1.2
	env.environment = e
	add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.22, 0.23, 0.26)
	fmat.roughness = 0.6
	floor_mi.material_override = fmat
	add_child(floor_mi)
	for it in [["res://scenes/pickups/health_pack.tscn", -2.1],
			["res://scenes/pickups/ammo_box.tscn", -0.7],
			["res://scenes/pickups/overclock.tscn", 0.7],
			["res://scenes/pickups/weapon_pickup.tscn", 2.1]]:
		var inst := (load(it[0]) as PackedScene).instantiate() as Node3D
		inst.position = Vector3(it[1], 0, 0)
		add_child(inst)
	_capture()

func _capture() -> void:
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/pickup_lineup.png")
	print("SAVED ", OS.get_user_data_dir() + "/pickup_lineup.png")
	get_tree().quit()
