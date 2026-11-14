extends Node3D
## Windowed shot: one real MAULER through its GROUND POUND, photographed early
## in the windup (the rim on the floor, the disc small, the robot coiled), with
## both fists overhead, late (the disc near the rim, the fists on their way
## down) and just after the fists land (the shockwave). Logic is pinned by
## tests/mauler_pound_probe.
##   godot --path . res://tests/mauler_pound_shot.tscn
## Saves user://mauler_pound_<early|raised|late|slam>.png.

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
	var pm := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	pm.mesh = cm
	pm.position.y = 0.9
	player.add_child(pm)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 100000.0
	player.add_child(hp)
	add_child(player)
	hp.current_health = 100000.0
	var m: EnemyMauler = (load("res://scenes/enemies/mauler.tscn") as PackedScene).instantiate()
	add_child(m)
	m.global_position = Vector3(0, 0.3, 2.4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	m.target = player
	m.set_state(EnemyBase.State.CHASE)
	var shot := {}
	for i in 1200:
		await get_tree().physics_frame
		if not is_instance_valid(m):
			break
		if m.pound == EnemyMauler.Pound.WINDUP:
			if not shot.has("early") and m._pound_t < EnemyMauler.POUND_WINDUP * 0.75:
				await _snap(m, "early")
				shot["early"] = true
			elif not shot.has("raised") and m._pound_t < 0.2:
				await _snap(m, "raised")
				shot["raised"] = true
			elif not shot.has("late") and m._pound_t < EnemyMauler.POUND_WINDUP * 0.12:
				await _snap(m, "late")
				shot["late"] = true
		elif shot.has("late") and not shot.has("slam"):
			for k in 5:
				await get_tree().physics_frame
			await _snap(m, "slam")
			shot["slam"] = true
			break
	print("RESULT %s" % ("PASS" if shot.has("slam") else "FAIL"))
	get_tree().quit(0)

func _snap(s: Node3D, tag: String) -> void:
	get_tree().paused = true
	cam.process_mode = Node.PROCESS_MODE_ALWAYS
	cam.global_position = Vector3(5.5, 4.2, -3.5)
	cam.look_at(Vector3(0, 0.6, 1.0), Vector3.UP)
	cam.make_current()
	for i in 3:
		await RenderingServer.frame_post_draw
	var path := "user://mauler_pound_%s.png" % tag
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))
	get_tree().paused = false
