extends Node3D
## Windowed visual check for the ROLLBACK robot: it watches an android die,
## then is caught mid-rewind (beam, VHS column, timecode running back) and
## again with the android half rebuilt from the feet up. Headless gives black
## frames.
##   godot --path . res://tests/rollback_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://rollback_shots")
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
	cam.global_position = Vector3(0, 2.4, 10.0)
	cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)
	cam.current = true
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 80) # far out of sight: no AI
	var rb: EnemyRollback = (load("res://scenes/enemies/rollback.tscn") as PackedScene).instantiate()
	add_child(rb)
	rb.global_position = Vector3(-3.5, 0, -2.0)
	var a: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(a)
	a.global_position = Vector3(2.0, 0, 0.5)
	a.set_physics_process(false)
	for i in 6:
		await get_tree().create_timer(0.2).timeout
	a.hp.apply_damage(99999.0, null)
	while not rb.channeling:
		await get_tree().physics_frame
	await _physics(int(EnemyRollback.CHANNEL_TIME * 60.0 * 0.6))
	await _snap(out_dir, "rollback_0_rewinding")
	await _physics(int(EnemyRollback.CHANNEL_TIME * 60.0 * 0.4) + int(EnemyRollback.REBUILD_TIME * 60.0 * 0.5))
	await _snap(out_dir, "rollback_1_rebuilding")
	await _physics(int(EnemyRollback.REBUILD_TIME * 60.0 * 0.5) + 20)
	await _snap(out_dir, "rollback_2_restored")
	print("RESULT PASS")
	get_tree().quit()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
