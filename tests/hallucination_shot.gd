extends Node3D
## Windowed visual check for MODEL HALLUCINATION: two hallucinated humans
## (PlayerPhantom) 6 m and 10 m out, with an android between them that has
## turned on the nearer one. Headless gives black frames.
##   godot --path . res://tests/hallucination_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://hallucination_shots")
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
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 4)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.7, 4)
	cam.look_at(Vector3(0, 1.2, -8), Vector3.UP)
	cam.current = true
	var a := PlayerPhantom.new()
	add_child(a)
	a.global_position = Vector3(-2.5, 0, -2)
	var b := PlayerPhantom.new()
	add_child(b)
	b.global_position = Vector3(3.5, 0, -6)
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = Vector3(-1.0, 0, -9)
	GameState.current_state = GameState.State.PLAYING
	for i in 8:
		await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("hallucination.png"))
	print("RESULT PASS")
	get_tree().quit()
