extends Node3D
## AEGIS shield drone (EnemyAegis, Damageable.warded_by). On a flat baked
## navmesh with a stand-in player:
##   - with two androids live, it wards the one nearer the player, beaming gold
##     and wrapping it in a bubble;
##   - the warded android takes no damage from the player; the other does;
##   - a boss-class robot is never warded;
##   - killing the AEGIS drops the ward at once: the android takes damage again
##     and its bubble is gone;
##   - shooting a warded robot teaches the rule once.
##   godot --headless --path . --audio-driver Dummy res://tests/aegis_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _run()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _robot(nav: Node, kind: String, at: Vector3) -> EnemyBase:
	var e: EnemyBase = LevelBuilder.enemy_scene(kind).instantiate()
	e.position = at
	nav.add_child(e)
	return e

func _run() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
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
	await _frames(10)

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	player.position = Vector3(0, 0.05, 30)
	add_child(player)

	var near := _robot(nav, "android", Vector3(-3, 0.2, 10))
	var far := _robot(nav, "android", Vector3(3, 0.2, -10))
	for r in [near, far]:
		r.process_mode = Node.PROCESS_MODE_DISABLED # hold still; hp still works
	var aegis := _robot(nav, "aegis", Vector3(0, 3.0, 0))
	await _frames(4)
	for r in [near, far]:
		r.max_health = 5000.0
		r.hp.max_health = 5000.0
		r.hp.current_health = 5000.0
	var warded := false
	for i in 40:
		await _frames(6)
		if near.hp.warded_by == aegis:
			warded = true
			break
	_check(warded, "it wards the android nearer the player")
	_check(far.hp.warded_by == null, "and only that one")
	_check(near.get_node_or_null("AegisBubble") != null, "the warded robot wears a bubble")

	_hints.clear()
	var h0 := near.hp.current_health
	near.hp.apply_damage(200.0, player)
	_check(near.hp.current_health >= h0, "the warded android takes no damage (%.0f)" % near.hp.current_health)
	_check(_hints.has(EnemyAegis.TEACH_TEXT), "shooting it teaches the rule (%d hints)" % _hints.size())
	var f0 := far.hp.current_health
	far.hp.apply_damage(200.0, player)
	_check(far.hp.current_health < f0, "the other android does")

	aegis.hp.apply_damage(1.0e6, player)
	await _frames(4)
	_check(near.hp.warded_by == null, "killing the AEGIS drops the ward")
	_check(near.get_node_or_null("AegisBubble") == null, "and the bubble")
	h0 = near.hp.current_health
	near.hp.apply_damage(200.0, player)
	_check(near.hp.current_health < h0, "the android takes damage again")

	# Registered and placed like every robot.
	_check(LevelBuilder.ENEMY_SCENES.get("aegis", "") == "res://scenes/enemies/aegis.tscn", "the level builder knows the AEGIS")
	_check(EnemyCodex.ENTRIES.has("aegis") and "aegis" in EnemyCodex.ORDER, "it has a codex entry")
	var placed := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for en in def.get("enemies", []):
			if en.get("type", "") == "aegis":
				placed += 1
		for t in def.get("tasks", []):
			for w in t.get("waves", []):
				for en in w.get("enemies", []):
					if en.get("type", "") == "aegis":
						placed += 1
	_check(placed >= 1, "it is placed on a campaign level (%d)" % placed)

	# Never a boss-class robot.
	for r in [near, far]:
		r.queue_free()
	await _frames(2)
	var big := _robot(nav, "brute", Vector3(0, 0.2, 10))
	big.process_mode = Node.PROCESS_MODE_DISABLED
	big._health_mult = 50.0 # past HIJACK_BOSS_HP: boss-class
	var a2 := _robot(nav, "aegis", Vector3(0, 3.0, 0))
	await _frames(60)
	_check(big.hp.warded_by == null, "a boss-class robot is never warded")
	a2.queue_free()
	big.queue_free()
	player.queue_free()
	nav.queue_free()
