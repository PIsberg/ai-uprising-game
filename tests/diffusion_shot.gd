extends Node3D
## Windowed visual check for the DIFFUSION robot: a formed one beside one that
## diffuses, caught three times: half noised out, as the static cloud on its
## way across, and half denoised at the far spot. Headless gives black frames.
##   godot --path . res://tests/diffusion_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://diffusion_shots")
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
	var formed: EnemyDiffusion = (load("res://scenes/enemies/diffusion.tscn") as PackedScene).instantiate()
	add_child(formed)
	formed.global_position = Vector3(-3.5, 0, 0)
	formed.look_at(Vector3(-3.5, 0, 10), Vector3.UP)
	var d: EnemyDiffusion = (load("res://scenes/enemies/diffusion.tscn") as PackedScene).instantiate()
	add_child(d)
	d.global_position = Vector3(0.5, 0, 0)
	d.look_at(Vector3(0.5, 0, 10), Vector3.UP)
	for i in 6:
		await get_tree().create_timer(0.2).timeout
	d.diffuse_to(Vector3(4.0, 0, 1.0))
	await _physics(int(EnemyDiffusion.NOISE_TIME * 60.0 * 0.55))
	await _snap(out_dir, "diffusion_0_noising")
	await _physics(int(EnemyDiffusion.NOISE_TIME * 60.0 * 0.45) + int(EnemyDiffusion.CLOUD_TIME * 60.0 * 0.5))
	await _snap(out_dir, "diffusion_1_cloud")
	await _physics(int(EnemyDiffusion.CLOUD_TIME * 60.0 * 0.5) + int(EnemyDiffusion.DENOISE_TIME * 60.0 * 0.45))
	await _snap(out_dir, "diffusion_2_denoising")
	print("RESULT PASS")
	get_tree().quit()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
