extends Node3D
## Windowed visual check for the FORK BOMB: one of each generation side by side
## (0, 1, 2), then the moment generation 0 forks. Headless gives black frames.
##   godot --path . res://tests/forkbomb_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://forkbomb_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(80, 1, 80)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.19)
	pm.material = fmat
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 5.5)
	cam.look_at(Vector3(0, 0.4, 0), Vector3.UP)
	cam.current = true
	var bombs: Array[EnemyForkbomb] = []
	for g in 3:
		var e := (load("res://scenes/enemies/forkbomb.tscn") as PackedScene).instantiate() as EnemyForkbomb
		e.generation = g
		e.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(e)
		e.global_position = Vector3(-2.2 + g * 2.2, 0, 0)
		e.look_at(Vector3(e.global_position.x, 0, 6), Vector3.UP)
		bombs.append(e)
	for i in 8:
		await get_tree().create_timer(0.2).timeout
	await _snap(out_dir, "forkbomb_generations")
	bombs[0].process_mode = Node.PROCESS_MODE_INHERIT
	bombs[0].hp.apply_damage(99999.0, null)
	for i in 2:
		await get_tree().create_timer(0.15).timeout
	await _snap(out_dir, "forkbomb_fork")
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(stem + ".png"))
