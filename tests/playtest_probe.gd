extends Node3D
## Live "playthrough" probe: drop the new enemies into an arena with a player and
## let the REAL AI run — so we can SEE skitters hop, the Ravager leap+slam, and the
## Warmech lob salvos, and confirm facing/scale/tint/projectiles in motion.
## Run windowed: godot --path . res://tests/playtest_probe.tscn
## Captures shots to user://pt_*.png and prints behaviour telemetry.

var _player: CharacterBody3D
var _enemies: Array = []
var _warmech: Node = null
var _ravager: Node = null
var _skitters: Array = []
var _saw_ravager_leap := false
var _saw_skitter_leap := false
var _warmech_shells := 0
var _cam: Camera3D

func _ready() -> void:
	# Lighting + sky.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, 35, 0); sun.light_energy = 1.4
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.45, 0.5, 0.58)
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.09, 0.1, 0.14)
	add_child(we)
	# Floor (+ a navmesh so the base chase AI can path; leaps move on their own).
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.16, 0.17, 0.2)
	floor_mi.material_override = fmat
	nav.add_child(floor_mi)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.6; nm.cell_size = 0.3
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	await get_tree().create_timer(0.4).timeout

	# Player stand-in (group "player" + Damageable + body on layer 2 for shells).
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2; _player.collision_mask = 1
	var pcs := CollisionShape3D.new(); var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4; pcap.height = 1.7; pcs.shape = pcap; pcs.position = Vector3(0, 0.9, 0)
	_player.add_child(pcs)
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 500.0
	_player.add_child(pdmg)
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, 14)

	# Spawn the new content in striking range so the AI engages immediately.
	_warmech = _spawn("res://scenes/enemies/warmech.tscn", Vector3(0, 0.5, -18))
	_ravager = _spawn("res://scenes/enemies/ravager.tscn", Vector3(8, 0.5, 2))
	for i in 6:
		var a := TAU * float(i) / 6.0
		_skitters.append(_spawn("res://scenes/enemies/skitter.tscn", Vector3(cos(a) * 5.0, 0.5, 6.0 + sin(a) * 3.0)))

	_cam = Camera3D.new(); add_child(_cam)
	_cam.global_position = Vector3(15, 9, 16)
	_cam.look_at(Vector3(0, 1.5, -2), Vector3.UP)

	# Run the live fight, sampling behaviour + grabbing frames.
	var shots := [1.2, 2.6, 4.0, 5.6, 7.0]
	var elapsed := 0.0
	var shot_i := 0
	while elapsed < 7.4:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_sample()
		if shot_i < shots.size() and elapsed >= shots[shot_i]:
			await _grab("pt_%d" % shot_i)
			shot_i += 1

	var dmg_taken: float = 500.0 - (_player.get_node("Damageable") as Damageable).current_health
	print("PLAYTEST  warmech_shells=%d  ravager_leapt=%s  skitter_hopped=%s  player_dmg=%.0f" % [
		_warmech_shells, _saw_ravager_leap, _saw_skitter_leap, dmg_taken])
	print("PLAYTEST ", "OK" if (_warmech_shells > 0 and _saw_ravager_leap and _saw_skitter_leap) else "PARTIAL")
	get_tree().quit()

func _spawn(path: String, pos: Vector3) -> Node:
	var e: Node3D = (load(path) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	_enemies.append(e)
	return e

func _sample() -> void:
	_warmech_shells = maxi(_warmech_shells, _count_shells())  # peak shells in flight ≥1 ⇒ it fired
	if _ravager and is_instance_valid(_ravager) and "_leaping" in _ravager and _ravager._leaping:
		_saw_ravager_leap = true
	for s in _skitters:
		if is_instance_valid(s) and "_leaping" in s and s._leaping:
			_saw_skitter_leap = true

func _grab(name: String) -> void:
	# Track warmech shells live (count projectiles it has spawned this frame window).
	if _warmech and is_instance_valid(_warmech):
		_warmech_shells = _count_shells()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/" + name + ".png")
	print("  shot ", name, "  shells_in_air=", _count_shells())

func _count_shells() -> int:
	var n := 0
	for c in get_children():
		if c is Projectile:
			n += 1
	return n
