extends Node3D
## Windowed visual check for DataBleed: binary spraying out of rifle hits on a
## robot (one crit), then the death fountain off a second one. Headless gives
## black frames.
##   godot --path . res://tests/data_bleed_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://data_bleed_shots")
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
	cam.global_position = Vector3(3.5, 1.9, 5.5)
	cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	cam.current = true
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 1.5, 9.5)
	var rifle: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(rifle)
	rifle._active_shooter = player
	var bots: Array[EnemyBase] = []
	for x in [-1.8, 1.8]:
		var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
		e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE # stays shootable
		e.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(e)
		e.global_position = Vector3(x, 0, 0)
		e.look_at(Vector3(x, 0, 10), Vector3.UP)
		e.hp.max_health = 100000.0
		e.hp.current_health = 100000.0
		bots.append(e)
	for i in 6:
		await get_tree().create_timer(0.2).timeout
	for k in 4:
		var y := 0.7 + k * 0.25
		rifle._do_hitscan(Vector3(-1.8, y, 9.5), Vector3(0, 0, -1))
		await _physics(4)
	await _physics(6)
	await _snap(out_dir, "data_bleed_0_hits")
	bots[1].hp.apply_damage(1000000.0, player, false, bots[1].global_position + Vector3.UP)
	await _physics(16)
	await _snap(out_dir, "data_bleed_1_death")
	print("RESULT PASS")
	get_tree().quit()

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
