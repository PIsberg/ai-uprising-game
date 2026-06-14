extends Node3D
## Dev probe: stages each boss's new dramatic entrance against a dark floor and
## captures timed frames so they can be eyeballed. Saves user://boss_drop_*.png
## (GOLIATH-IX sky-drop) and user://boss_portal_*.png (OVERSEER gate). Run
## WINDOWED (headless renders black + skips shader/particle work):
##   godot --path . res://tests/boss_entrance_probe.tscn

var _cam: Camera3D

func _ready() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 40, 0)
	key.light_energy = 0.6
	add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.025, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.1, 0.12, 0.16)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.6
	e.glow_bloom = 0.15
	e.glow_hdr_threshold = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.07, 0.08, 0.09)
	fmat.roughness = 0.6
	pm.material = fmat
	floor_mesh.mesh = pm
	# Static floor body so the falling colossus has something to land on.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	body.add_child(floor_mesh)
	add_child(body)
	_cam = Camera3D.new()
	add_child(_cam)

	var player := Node3D.new()
	player.add_to_group("player")
	player.global_position = Vector3(8, 1.6, 18)
	add_child(player)

	await _capture_drop()
	await _capture_portal(player)
	get_tree().quit()

func _frame(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + name)
	print("SAVED ", name)

func _capture_drop() -> void:
	# Far back + elevated so the frame spans sky (the falling boss) to ground
	# (the landing) at once.
	_cam.position = Vector3(4, 8, 44)
	_cam.look_at(Vector3(0, 15, 0), Vector3.UP)
	_cam.fov = 80.0
	var boss := (load("res://scenes/enemies/colossus.tscn") as PackedScene).instantiate() as Node3D
	# Set the spawn mark BEFORE add_child (as EnemySpawner does) so the boss's
	# _ready sky-lift isn't overwritten.
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)
	for shot in [[1.1, "boss_drop_1.png"], [0.5, "boss_drop_2.png"], [0.5, "boss_drop_3.png"], [0.7, "boss_drop_4_land.png"], [0.7, "boss_drop_5_settled.png"]]:
		await get_tree().create_timer(shot[0], true, false, true).timeout
		_frame(shot[1])
	boss.queue_free()
	await get_tree().create_timer(0.2, true, false, true).timeout

func _capture_portal(player: Node3D) -> void:
	player.global_position = Vector3(0, 1.6, 18)
	_cam.position = Vector3(0, 6.5, 20)
	_cam.look_at(Vector3(0, 6.0, 0), Vector3.UP)
	_cam.fov = 60.0
	var boss := (load("res://scenes/enemies/overseer.tscn") as PackedScene).instantiate() as Node3D
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)
	for shot in [[0.3, "boss_portal_1_open.png"], [0.4, "boss_portal_2_emerge.png"], [0.5, "boss_portal_3_out.png"], [0.6, "boss_portal_4_closing.png"], [0.6, "boss_portal_5_done.png"]]:
		await get_tree().create_timer(shot[0], true, false, true).timeout
		_frame(shot[1])
