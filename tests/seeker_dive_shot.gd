extends Node3D
## Windowed shot: one real SEEKER through its terminal dive, photographed
## closing (amber band blinking), armed (core and band steady white) and spent
## after a dodged dive (dark). Logic is pinned by tests/seeker_dive_probe.
##   godot --path . res://tests/seeker_dive_shot.tscn
## Saves user://seeker_dive_<closing|armed|spent>.png.

var cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.75)
	e.ambient_light_energy = 0.6
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mi.mesh = bm
	sb.add_child(mi)
	sb.position.y = -0.5
	add_child(sb)
	cam = Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 0
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 100000.0
	player.add_child(hp)
	add_child(player)
	hp.current_health = 100000.0
	var s: EnemySeeker = (load("res://scenes/enemies/seeker.tscn") as PackedScene).instantiate()
	add_child(s)
	s.global_position = Vector3(0, 1.5, 22)
	var shot := {}
	for i in 1200:
		await get_tree().physics_frame
		if not is_instance_valid(s):
			break
		var d := s.global_position.distance_to(player.global_position)
		if not shot.has("closing") and d < 14.0 and s._dive == EnemySeeker.Dive.NONE:
			await _snap(s, "closing")
			shot["closing"] = true
		elif not shot.has("armed") and s._dive == EnemySeeker.Dive.ARM and s._dive_t < 0.25:
			await _snap(s, "armed")
			shot["armed"] = true
		elif shot.has("armed") and not shot.has("dodged") and s._dive == EnemySeeker.Dive.DIVE:
			player.global_position += Vector3(7, 0, 0)
			shot["dodged"] = true
		elif not shot.has("spent") and s._dive == EnemySeeker.Dive.RECOVER and s._dive_t < 0.7:
			await _snap(s, "spent")
			shot["spent"] = true
			break
	print("RESULT %s" % ("PASS" if shot.has("spent") else "FAIL"))
	get_tree().quit(0)

func _snap(s: Node3D, tag: String) -> void:
	get_tree().paused = true
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	# The model sits about 1 m above the body's origin.
	cam.global_position = s.global_position + Vector3(1.5, 1.5, -2.4)
	cam.look_at(s.global_position + Vector3(0, 0.85, 0), Vector3.UP)
	cam.make_current()
	for i in 3:
		await RenderingServer.frame_post_draw
	var path := "user://seeker_dive_%s.png" % tag
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
	get_tree().paused = false
