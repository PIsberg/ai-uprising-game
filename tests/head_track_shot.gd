extends Node3D
## Windowed visual check for head tracking (HeadTrackModifier): five rig
## families facing the viewer, shot at rest and then tracking a "player" on a
## ledge up and to the right. Headless gives black frames.
##   godot --path . res://tests/head_track_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://head_track_shots")
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
	# The camera stands on a ledge up and to the right, like a player above them.
	cam.global_position = Vector3(4.0, 4.6, 11.5)
	cam.look_at(Vector3(0, 1.4, 0), Vector3.UP)
	var bots: Array = []
	var paths := ["gunner", "sentinel", "rollback", "quantizer", "alien"]
	for i in paths.size():
		var e: EnemyBase = (load("res://scenes/enemies/%s.tscn" % paths[i]) as PackedScene).instantiate()
		add_child(e)
		var x := -6.4 + i * 3.2
		var fly: bool = paths[i] in ["quantizer", "alien"]
		e.global_position = Vector3(x, 1.6 if fly else 0.0, 0)
		e.look_at(Vector3(x, e.global_position.y, 10), Vector3.UP) # facing the viewer
		bots.append(e)
	await _physics(45)
	for e in bots:
		e.set_physics_process(false)
		e.target = null
		e.state = EnemyBase.State.IDLE
	await _physics(90)
	await _snap(out_dir, "head_track_0_rest")
	# The "player" stands on the ledge: robots look up at it.
	player.global_position = cam.global_position - Vector3.UP * 1.5
	for e in bots:
		e.target = player
		e.state = EnemyBase.State.ATTACK
	await _physics(90)
	await _snap(out_dir, "head_track_1_tracking")
	print("RESULT PASS")
	get_tree().quit()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
