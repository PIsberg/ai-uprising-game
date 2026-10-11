extends Node3D
## Windowed visual check for night vision: a dark room (its one lamp shot out)
## with three robots, through the player's camera, goggles off and then on.
## Headless gives black frames.
##   godot --path . res://tests/night_vision_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://night_vision_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.015)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.32, 0.4)
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_box(Vector3(40, 1, 40), Vector3(0, -0.5, 0), Color(0.18, 0.19, 0.2))
	_box(Vector3(40, 6, 1), Vector3(0, 3, -14), Color(0.22, 0.23, 0.26))
	_box(Vector3(1, 6, 40), Vector3(-10, 3, 0), Color(0.22, 0.23, 0.26))
	_box(Vector3(2, 2, 2), Vector3(3, 1, -6), Color(0.3, 0.3, 0.32))
	# The room's lamp, already shot out.
	var lamp_light := OmniLight3D.new()
	lamp_light.light_energy = 2.4
	lamp_light.omni_range = 16.0
	add_child(lamp_light)
	lamp_light.global_position = Vector3(0, 5.0, -4)
	lamp_light.add_to_group("level_light")
	var lamp := ShootableLight.build(self, lamp_light, Color(1, 0.95, 0.85), 6.0)
	GameState.has_night_vision = true
	var p: Node3D = load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	p.global_position = Vector3(0, 0.2, 6)
	var bots: Array = []
	for spot in [Vector3(-4, 0, -6), Vector3(1, 0, -9), Vector3(6, 0, -5)]:
		var e: EnemyBase = (load("res://scenes/enemies/gunner.tscn") as PackedScene).instantiate()
		add_child(e)
		e.global_position = spot
		bots.append(e)
	await _physics(40)
	for e in bots:
		e.set_physics_process(false)
		e.look_at(Vector3(0, e.global_position.y, 6), Vector3.UP)
	(lamp.get_node("Damageable") as Damageable).apply_damage(500.0, p)
	await _physics(40)
	await _snap(out_dir, "nv_0_off")
	p.call("toggle_night_vision")
	await _physics(40)
	await _snap(out_dir, "nv_1_on")
	print("RESULT PASS")
	get_tree().quit()

func _box(size: Vector3, pos: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	b.add_child(mi)
	add_child(b)
	b.global_position = pos

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
