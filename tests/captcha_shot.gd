extends Node3D
## Windowed visual check for the CAPTCHA gate: an android caught in the gap
## mid-challenge under the "[ ] I'm not a robot" panel, then the panel ticked
## for the player. Headless gives black frames.
##   godot --path . res://tests/captcha_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://captcha_shots")
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
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.22, 0.23, 0.26)
	for x in [-7.5, 7.5]:
		var w := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(9.0, 4.4, 1.0)
		bm.material = wall_mat
		w.mesh = bm
		add_child(w)
		w.position = Vector3(x, 2.2, 0)
	var gate := CaptchaGate.build(self, Vector3.ZERO, Vector3.RIGHT, 6.0, 4.4)
	cam.global_position = Vector3(1.5, 2.0, 9.0)
	cam.look_at(Vector3(0, 2.2, 0), Vector3.UP)
	var a: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(a)
	a.global_position = Vector3(0, 0, 5)
	a.look_at(Vector3(0, 0, 10), Vector3.UP)
	for i in 6:
		await get_tree().create_timer(0.2).timeout
	a.global_position = Vector3(0, 0, 0)
	await _physics(40)
	await _snap(out_dir, "captcha_0_held")
	player.free()
	var p := CharacterBody3D.new()
	p.add_to_group("player")
	p.collision_layer = 2
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	cs.position.y = 1.0
	p.add_child(cs)
	add_child(p)
	p.global_position = Vector3(2, 0, 0)
	await _physics(10)
	await _snap(out_dir, "captcha_1_ticked")
	print("RESULT PASS")
	get_tree().quit()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
