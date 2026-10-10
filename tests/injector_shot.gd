extends Node3D
## Windowed visual check for the PROMPT INJECTION terminal: the prompt typing
## out, the injection ring going out, and three androids jailbroken (spinning,
## thinking out loud). Headless gives black frames.
##   godot --path . res://tests/injector_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://injector_shots")
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
	cam.global_position = Vector3(2.5, 2.4, 6.5)
	cam.look_at(Vector3(0, 1.2, -3.0), Vector3.UP)
	cam.current = true
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	add_child(player)
	player.global_position = Vector3(0, 0, 30)
	var inj := PromptInjector.new()
	add_child(inj)
	var bots: Array[EnemyBase] = []
	for x in [-4.0, 0.0, 4.0]:
		var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
		e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		e.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(e)
		e.global_position = Vector3(x, 0, -6)
		e.look_at(Vector3(x, 0, 6), Vector3.UP)
		bots.append(e)
	for i in 6:
		await get_tree().create_timer(0.2).timeout
	player.global_position = Vector3(0.3, 0, 0.3)
	await get_tree().create_timer(0.9).timeout
	await _snap(out_dir, "injector_0_typing")
	for e in bots:
		e.process_mode = Node.PROCESS_MODE_INHERIT
	while not inj.used:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	await _snap(out_dir, "injector_1_ring")
	await get_tree().create_timer(0.9).timeout
	await _snap(out_dir, "injector_2_jailbroken")
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
