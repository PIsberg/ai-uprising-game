extends Node3D
## Probe: LadleCrane, the foundry's hunting overhead crane ("ladle_crane" def key).
## (1) the crane hunts: within 8 s its ladle hangs within 1.5 m (on the
##     ground plane) of a player standing inside its coverage;
## (2) every pour is telegraphed: `aiming` for at least 1.0 s before it pours;
## (3) the pour lands where it aimed, on the player, and the molten pool hurts
##     them, but not a robot standing in it;
## (4) the pool cools away: gone within pool_time + 1.5 s;
## (5) a player outside the coverage is never poured on;
## (6) The Crucible's crane covers the second forge ring and the pour-gate
##     escape, and its ladle stays at least 2 m clear of both towers.
##   godot --headless --path . --audio-driver Dummy res://tests/ladle_crane_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(6, 0.1, 4)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	var burns := []
	php.damaged.connect(func(a: float, src) -> void:
		if src is LavaHazard:
			burns.append(a))

	var crane := LadleCrane.new()
	crane.span_x = Vector2(-10, 10)
	crane.span_z = Vector2(-10, 10)
	crane.first_pour = 1.0
	add_child(crane)
	var pours := []
	var aim_since := [-1.0]
	var leads := []
	var t := [0.0]
	crane.poured.connect(func(at: Vector3) -> void:
		pours.append(at)
		leads.append(t[0] - float(aim_since[0])))
	var near_t := -1.0
	var was_aiming := false
	while t[0] < 8.0 and pours.is_empty():
		await get_tree().physics_frame
		t[0] += get_physics_process_delta_time()
		var l: Vector3 = crane.ladle_position()
		if near_t < 0.0 and Vector2(l.x - 6.0, l.z - 4.0).length() < 1.5:
			near_t = t[0]
		if crane.aiming and not was_aiming:
			aim_since[0] = t[0]
		was_aiming = crane.aiming
	_check("crane hunts the player", near_t >= 0.0, "(ladle over them after %.1f s)" % near_t)
	_check("it pours", pours.size() == 1, "(%d)" % pours.size())
	if not pours.is_empty():
		_check("pour telegraphed 1.0+ s", float(leads[0]) >= 1.0, "(%.2f s)" % leads[0])
		var at: Vector3 = pours[0]
		_check("pour lands on the player", Vector2(at.x - 6.0, at.z - 4.0).length() < 1.5, "(%s)" % at)
		var w := 0.0
		while w < 1.0 and burns.is_empty():
			await get_tree().physics_frame
			w += get_physics_process_delta_time()
		_check("the pool burns the player", not burns.is_empty(), "(%s)" % str(burns))
		# A robot standing in the same pool is not burned (traps are for the player).
		var bot: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
		add_child(bot)
		bot.global_position = at + Vector3(0.6, 0.0, 0.0)
		# Kept in the physics world while frozen: the pool finds bodies through
		# its Area3D, and a disabled body is otherwise removed (a vacuous pass).
		bot.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		bot.process_mode = Node.PROCESS_MODE_DISABLED
		var bot_burns := [0]
		bot.hp.damaged.connect(func(_a: float, src) -> void:
			if src is LavaHazard:
				bot_burns[0] += 1)
		w = 0.0
		while w < 1.5:
			await get_tree().physics_frame
			w += get_physics_process_delta_time()
		_check("a robot in the pool is not burned", bot_burns[0] == 0, "(%d)" % bot_burns[0])
		bot.queue_free()
		w = 0.0
		var gone := false
		while w < crane.pool_time + 1.5 and not gone:
			await get_tree().physics_frame
			w += get_physics_process_delta_time()
			gone = get_tree().get_nodes_in_group("ladle_pool").is_empty()
		_check("the pool cools away", gone, "(after %.1f s)" % w)

	# Out of its reach: never poured on.
	player.global_position = Vector3(30, 0.1, 30)
	var outside := pours.size()
	t[0] = 0.0
	while t[0] < 12.0:
		await get_tree().physics_frame
		t[0] += get_physics_process_delta_time()
	_check("no pour on a player outside its coverage", pours.size() == outside, "(%d more)" % (pours.size() - outside))
	crane.queue_free()

	# The Crucible: covers ring2 and the escape, clear of the towers.
	var def := LevelDefs.get_def("crucible")
	var c: Dictionary = def.get("ladle_crane", {})
	_check("crucible has a ladle crane", not c.is_empty())
	if not c.is_empty():
		var sx: Vector2 = c["span_x"]
		var sz: Vector2 = c["span_z"]
		var inside := func(p: Vector3) -> bool:
			return p.x >= sx.x and p.x <= sx.y and p.z >= sz.x and p.z <= sz.y
		for task in def.get("tasks", []):
			if String(task.get("id", "")) in ["ring2", "meltdown"]:
				_check("crane covers %s" % task["id"], inside.call(task["pos"]), "(%s)" % task["pos"])
		for tw in def.get("towers", []):
			var p: Vector3 = tw["pos"]
			var r: float = float(tw.get("radius", 3.0))
			var dx := maxf(maxf(sx.x - p.x, p.x - sx.y), 0.0)
			var dz := maxf(maxf(sz.x - p.z, p.z - sz.y), 0.0)
			var gap := Vector2(dx, dz).length() - r - LadleCrane.LADLE_RADIUS
			_check("ladle clear of the tower at %s" % p, gap >= 2.0, "(%.1f m)" % gap)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
