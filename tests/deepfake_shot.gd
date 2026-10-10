extends Node3D
## Windowed visual check for the DEEPFAKE: the robot projects its two copies
## facing the camera; frames saved over 2 s so at least one copy's glitch lands
## in a frame. Headless gives black frames.
##   godot --path . res://tests/deepfake_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://deepfake_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.19)
	pm.material = fmat
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.global_position = Vector3(0, 1.7, 9.0)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(0, 0, 9)
	var e: EnemyDeepfake = (load("res://scenes/enemies/deepfake.tscn") as PackedScene).instantiate()
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.look_at(Vector3(0, 0, 9), Vector3.UP) # enemies face -Z, as look_at points it
	for i in 8:
		await get_tree().create_timer(0.2).timeout
	await _snap(out_dir, "deepfake_0_alone")
	e.target = target
	e.project()
	for d in e.decoys:
		d.rotation.y = e.rotation.y
	for i in 10:
		await get_tree().create_timer(0.2).timeout
		await _snap(out_dir, "deepfake_%d" % (i + 1))
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
