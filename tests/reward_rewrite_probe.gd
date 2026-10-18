extends Node
## Dev probe: REWARD REWRITE consoles (RewardRewriter, def key `rewriters`).
## (1) standing at the console shows the reward line; interact cycles the three
##     lines and restarts the upload; stepping off lets the upload drain;
## (2) "shots": every robot in RADIUS stands still and fires into the sky (rounds
##     counted, nobody walks toward the player), a robot past RADIUS and a boss are
##     untouched; the console reads PATCHED and cannot be used again;
## (3) "huddle": three robots 16 m apart pack within 3 m of their centroid;
## (4) "kills": robots turn on each other and their fire lands while the player
##     stands far off;
## (5) the rewrite ends after REWRITE_TIME and every robot is itself again;
## (6) the builder places the authored consoles on SUBLEVEL and WATER WORLD.
##   godot --headless --path . --audio-driver Dummy res://tests/reward_rewrite_probe.tscn

const ENEMY := "res://scenes/enemies/android.tscn"

var _fails := 0

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _wait(seconds: float) -> void:
	for i in int(ceil(seconds / 0.25)): # short waits: one long timer stalls autoload ticking headless
		await get_tree().create_timer(0.25, true, true).timeout

func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)

func _floor() -> NavigationRegion3D:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 160)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(160, 1, 160)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	return nav

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = load(ENEMY).instantiate()
	add_child(e)
	e.global_position = pos
	return e

func _console(pos: Vector3) -> Node3D:
	var c: Node3D = (load("res://scripts/systems/reward_rewriter.gd") as GDScript).new()
	add_child(c)
	c.global_position = pos
	return c

## Stand the player in the console until it uploads `kind`.
func _upload(c: Node3D, player: Node3D, kind: String) -> void:
	player.global_position = c.global_position + Vector3(0, 0.1, 0.6)
	await _frames(4)
	while c.current() != kind:
		await _tap("interact")
	await _wait(float(c.UPLOAD_TIME) + 0.5)
	player.global_position = Vector3(70, 0.1, 70) # walk away: robots are on their own

func _run() -> void:
	var script: Script = load("res://scripts/systems/reward_rewriter.gd")
	_check(script != null, "RewardRewriter script exists")
	if script == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	_floor()
	await _frames(10)
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 30)
	player.get("hp").invulnerable = true

	# 1. Cycle + upload progress.
	var c1 := _console(Vector3(0, 0, 0))
	player.global_position = Vector3(0, 0.1, 0.6)
	await _frames(6)
	var first: String = c1.current()
	await _tap("interact")
	_check(c1.current() != first, "interact cycles the reward line (%s -> %s)" % [first, c1.current()])
	_check(String(c1._screen.text).contains(String(c1.LINES[c1.current()])), "screen shows the selected line")
	await _wait(1.0)
	player.global_position = Vector3(0, 0.1, 30)
	await _wait(1.5)
	_check(not c1.used and float(c1._t) < 1.0, "stepping off drains the upload (t=%.2f)" % float(c1._t))

	# 2. shots.
	var a := _robot(Vector3(8, 0, 0))
	var b := _robot(Vector3(-8, 0, 4))
	var far := _robot(Vector3(0, 0, -40))
	var boss := _robot(Vector3(6, 0, -6))
	boss.score_value = 1000
	await _frames(6)
	await _upload(c1, player, "shots")
	_check(c1.used, "console used after the upload")
	_check(a.reward_hack == "shots" and b.reward_hack == "shots", "robots in range took the rewrite")
	_check(far.reward_hack == "" and boss.reward_hack == "", "a robot past RADIUS and a boss are untouched")
	var a_at := a.global_position
	await _wait(2.0)
	print("shots: a fired %d, b fired %d, a moved %.2f m" % [a.reward_shots, b.reward_shots, a.global_position.distance_to(a_at)])
	_check(a.reward_shots >= 5 and b.reward_shots >= 5, "rewritten robots empty their guns")
	_check(a.global_position.distance_to(a_at) < 0.5, "a rewritten robot stands still")
	_check(String(c1._screen.text).contains("PATCHED"), "console reads PATCHED")
	player.global_position = c1.global_position + Vector3(0, 0.1, 0.6)
	await _wait(3.0)
	_check(a.reward_hack == "shots", "a used console uploads nothing new")
	player.global_position = Vector3(70, 0.1, 70)

	# 5. ends after REWRITE_TIME.
	await _wait(float(c1.REWRITE_TIME))
	_check(a.reward_hack == "" and b.reward_hack == "", "rewrite wears off after REWRITE_TIME")
	for r in [a, b, far, boss]:
		r.queue_free()
	await _frames(2)

	# 3. huddle.
	var c2 := _console(Vector3(40, 0, 0))
	var h1 := _robot(Vector3(32, 0, 8))
	var h2 := _robot(Vector3(48, 0, 8))
	var h3 := _robot(Vector3(40, 0, -8))
	await _frames(6)
	await _upload(c2, player, "huddle")
	await _wait(5.0)
	var cen: Vector3 = (h1.global_position + h2.global_position + h3.global_position) / 3.0
	var spread := maxf(h1.global_position.distance_to(cen), maxf(h2.global_position.distance_to(cen), h3.global_position.distance_to(cen)))
	print("huddle: max distance to centroid %.2f m" % spread)
	_check(h1.reward_hack == "huddle", "huddle rewrite took")
	_check(spread < 3.0, "the squad packs into one knot")
	for r in [h1, h2, h3]:
		r.queue_free()
	await _frames(2)

	# 4. kills.
	var c3 := _console(Vector3(-40, 0, 0))
	var k1 := _robot(Vector3(-44, 0, 0))
	var k2 := _robot(Vector3(-36, 0, 0))
	await _frames(6)
	await _upload(c3, player, "kills")
	_check(k1.mislabeled_t > 0.0 and k2.mislabeled_t > 0.0, "kill-count rewrite mislabels the squad")
	await _wait(5.0)
	var dmg1: float = k1.hp.max_health - k1.hp.current_health
	var dmg2: float = k2.hp.max_health - k2.hp.current_health
	print("kills: k1 took %.0f, k2 took %.0f, k1 target %s" % [dmg1, dmg2, k1.target])
	_check(dmg1 + dmg2 > 0.0 or not is_instance_valid(k1) or not is_instance_valid(k2), "robots damage each other")
	_check(is_instance_valid(k1) and k1.target is EnemyBase or not is_instance_valid(k1), "a rewritten robot targets a robot")
	await _wait(float(c3.REWRITE_TIME))
	if is_instance_valid(k1) and k1.hp.is_alive():
		_check(k1.mislabeled_t <= 0.0 and k1.collision_layer == 4, "kill-count rewrite wears off")

	# 6. Authored, built, on clear floor in the real levels.
	for n in get_children():
		if n != self:
			n.queue_free()
	await _frames(3)
	for id in ["sublevel", "water_world"]:
		var n: int = LevelDefs.get_def(id).get("rewriters", []).size()
		_check(n >= 1, "%s authors %d reward console(s)" % [id, n])
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		await _frames(3)
		var built := get_tree().get_nodes_in_group("rewriter")
		_check(built.size() == n, "%s builds %d of %d" % [id, built.size(), n])
		var space := (lvl as Node3D).get_world_3d().direct_space_state
		for con in built:
			var p := (con as Node3D).global_position
			var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.6, 1)
			_check(not space.intersect_ray(down).is_empty(), "%s console at %s is on the floor" % [id, p])
			var box := BoxShape3D.new()
			box.size = Vector3(0.9, 1.4, 0.9)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.collision_mask = 1
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.85)
			var hits := space.intersect_shape(q, 4)
			_check(hits.is_empty(), "%s console at %s has clear room %s" % [id, p,
					str(hits.map(func(h: Dictionary) -> String: return str(h.collider.name)))])
		lvl.queue_free()
		await _frames(3)

	print("RESULT %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
