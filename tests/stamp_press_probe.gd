extends Node3D
## Probe: StampPress, the hydraulic stamping press hazard ("presses" def key).
## (1) a player standing under a press is hit once per slam (not on every
##     frame the head is down) and shoved out of the footprint;
## (2) robots are never hurt, under it or 1 m outside (traps are for the player);
## (3) every slam is telegraphed: the press is `telegraphing` for at least
##     0.5 s before the head comes down, and the head's underside drops from
##     its full clearance to within 0.3 m of the floor at the slam;
## (4) two presses half a period out of phase slam half a period apart;
## (5) Assembly lays its presses where the def says, and the bulkhead press
##     spans the east gap: a run to the dock has to pass under it.
##   godot --headless --path . --audio-driver Dummy res://tests/stamp_press_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _robot(pos: Vector3) -> Node3D:
	var e: Node3D = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	# Frozen where it stands (a live robot steps and is knocked about), but
	# kept in the physics world: the press finds bodies through an Area3D, and
	# a disabled body is otherwise removed from it (a vacuous pass).
	(e as CollisionObject3D).disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return e

func _phys(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.set_physics_process(false) # stand still; the shove is read off velocity
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0
	var hits := []
	# Only the press's hits: the test robots shoot back.
	php.damaged.connect(func(a: float, src): if src is StampPress: hits.append(a))

	var press := StampPress.new()
	press.size = Vector2(4.0, 4.0)
	press.period = 3.0
	press.phase = 0.0
	add_child(press)
	press.global_position = Vector3.ZERO
	var inside := _robot(Vector3(1.0, 0.0, 1.2))
	var outside := _robot(Vector3(3.0, 0.0, 0.0)) # footprint edge at x=2, robot radius < 1
	var top := press.head_bottom()
	_check("head starts up at its clearance", top > 3.0, "(%.2f m)" % top)

	# Watch two full cycles: slam times, telegraph lead, lowest head point.
	# Lambdas capture locals by value: shared state lives in arrays.
	var slams: Array[float] = []
	var tele_lead: Array[float] = []
	var low := 99.0
	var tele_since := [-1.0]
	var was_tele := false
	var t := [0.0]
	var shoves: Array[Vector3] = []
	press.slammed.connect(func() -> void:
		slams.append(t[0])
		tele_lead.append(t[0] - float(tele_since[0]) if float(tele_since[0]) >= 0.0 else 0.0)
		shoves.append(player.velocity)
		player.velocity = Vector3.ZERO)
	while t[0] < 6.4:
		await get_tree().physics_frame
		t[0] += get_physics_process_delta_time()
		low = minf(low, press.head_bottom())
		if press.telegraphing and not was_tele:
			tele_since[0] = t[0]
		was_tele = press.telegraphing
	_check("two slams in two periods", slams.size() == 2, str(slams))
	_check("player hit once per slam", hits.size() == slams.size() and slams.size() > 0, "(%d hits, %s)" % [hits.size(), str(hits)])
	if not hits.is_empty():
		_check("a slam hurts", hits[0] >= 30.0, "(%.0f)" % hits[0])
	for sv in shoves:
		_check("player shoved out of the footprint", Vector2(sv.x, sv.z).length() >= 5.0, "(%s)" % sv)
	for l in tele_lead:
		_check("slam telegraphed", l >= 0.5, "(%.2f s)" % l)
	_check("head comes down to the floor", low < 0.3, "(%.2f m)" % low)
	_check("robot under the press is not hurt", is_instance_valid(inside) and (inside.get("hp") as Node).get("current_health") == (inside.get("hp") as Node).get("max_health"))
	_check("robot 1 m outside untouched", is_instance_valid(outside) and (outside.get("hp") as Node).get("current_health") == (outside.get("hp") as Node).get("max_health"))
	press.queue_free()
	player.queue_free()
	await get_tree().physics_frame

	# Phase: two presses half a period apart.
	var a := StampPress.new()
	a.period = 2.0
	a.phase = 0.0
	var b := StampPress.new()
	b.period = 2.0
	b.phase = 0.5
	add_child(a)
	add_child(b)
	a.global_position = Vector3(20, 0, 0)
	b.global_position = Vector3(30, 0, 0)
	var ta := []
	var tb := []
	var t2 := [0.0]
	a.slammed.connect(func() -> void: ta.append(t2[0]))
	b.slammed.connect(func() -> void: tb.append(t2[0]))
	while t2[0] < 4.2:
		await get_tree().physics_frame
		t2[0] += get_physics_process_delta_time()
	if ta.size() >= 1 and tb.size() >= 1:
		var gap := absf(float(tb[0]) - float(ta[0]))
		_check("presses half a period out of phase", absf(gap - 1.0) < 0.1, "(%.2f s apart)" % gap)
	else:
		_check("presses half a period out of phase", false, "(no slams %s %s)" % [ta, tb])

	# Assembly: presses where the def puts them, one across the east bulkhead gap.
	var def := LevelDefs.get_def("assembly")
	var presses: Array = def.get("presses", [])
	_check("assembly has presses", presses.size() >= 3, "(%d)" % presses.size())
	var spans_gap := false
	for g in def.get("gates", []):
		if String(g.get("axis", "")) != "x":
			continue
		var gx: float = float(g["at"])
		var gz: float = float(g["gap_pos"])
		var gw: float = float(g["gap"])
		for p in presses:
			var pp: Vector3 = p["pos"]
			var ps: Vector2 = p.get("size", Vector2(4, 4))
			# Covers the gap's whole width and straddles the bulkhead line.
			if absf(pp.x - gx) < ps.x * 0.5 and pp.z - ps.y * 0.5 <= gz - gw * 0.5 + 0.01 \
					and pp.z + ps.y * 0.5 >= gz + gw * 0.5 - 0.01:
				spans_gap = true
	_check("a press spans the east bulkhead gap", spans_gap)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
