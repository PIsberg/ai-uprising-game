extends Node3D
## Windowed visual check for the ATTENTION HEAD: its searchlight sweep, then its
## gaze locked (red) on a stand-in player, from the side so the cone reads.
## Headless gives black frames.
##   godot --path . res://tests/attention_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://attention_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.25
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
	cam.global_position = Vector3(9.0, 2.2, 7.0)
	cam.look_at(Vector3(0, 1.6, 4.0), Vector3.UP)
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
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.height = 1.8
	body.mesh = cm
	body.position.y = 0.9
	player.add_child(body)
	add_child(player)
	player.global_position = Vector3(0, 0, 9)
	var head: EnemyAttention = (load("res://scenes/enemies/attention.tscn") as PackedScene).instantiate()
	add_child(head)
	head.set_physics_process(false) # posed
	head.global_position = Vector3(0, 3.6, -2)
	head.look_at(Vector3(0, 3.6, 9), Vector3.UP)
	for i in 30:
		head.gaze_tick(1.0 / 30.0)
		await get_tree().process_frame
	await _snap(out_dir, "attention_0_sweep")
	head.target = player
	head.set_state(EnemyBase.State.ATTACK)
	for i in 120:
		head.gaze_tick(1.0 / 60.0)
		await get_tree().process_frame
	await _snap(out_dir, "attention_1_locked")
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
