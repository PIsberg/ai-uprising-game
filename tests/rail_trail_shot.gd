extends Node3D
## Windowed visual check for the railgun's ionization trail: three gauss trails
## fired 0.5 s apart seen side-on (fresh, half-life, nearly gone), then the
## view down the barrel of a fresh one. Headless gives black frames.
##   godot --path . res://tests/rail_trail_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://rail_trail_shots")
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
	player.queue_free()
	var col := Color(0.6, 0.9, 1.0)
	for i in 3:
		RailTrail.spawn(self, Vector3(-14, 1.0 + i * 0.9, -3), Vector3(14, 1.0 + i * 0.9, -6), col)
		await _physics(30)
	await _snap(out_dir, "rail_0_side")
	await _physics(int(RailTrail.LIFE * 60.0) + 5)
	cam.global_position = Vector3(0.3, 1.75, 6.0)
	cam.look_at(Vector3(0, 1.4, -40), Vector3.UP)
	RailTrail.spawn(self, Vector3(0.25, 1.55, 5.3), Vector3(0, 1.3, -40), col)
	await _physics(8)
	await _snap(out_dir, "rail_1_barrel")
	print("RESULT PASS")
	get_tree().quit()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
