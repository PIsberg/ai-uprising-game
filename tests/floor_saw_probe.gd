extends Node3D
## Probe: FloorSaw, the blade that runs a striped floor slot ("saws" def key).
## A 10 m slot along +x at the origin, over a round trip:
## (1) the blade runs end to end and back, pausing at each end;
## (2) a player standing in the lane mid-slot is cut as the blade passes
##     each way, and every cut is warned 0.5 s or more ahead (`warned`);
## (3) a player in the lane with their feet 1.0 m up (mid-jump) is never cut;
##     one standing just outside the stripes is never cut nor warned;
## (4) a cut throws the player out of the lane, to their side;
## (5) a robot in the lane is cut, one 2 m off is not;
## (6) walking up to a saw teaches the rule, once;
## (7) the Assembly's north gap is guarded by two slots, either side of the
##     bulkhead, each blade reaching to within a body's width of both edges
##     of the (scaled) gap, running opposite ways.
##   godot --headless --path . --audio-driver Dummy res://tests/floor_saw_probe.tscn

var ok := true
var _clock := 0.0
var _hits: Array[float] = []
var _warns: Array[float] = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	e.set("move_speed", 0.0)
	# The base stat too: EnemyBase's deferred _sync_stats rescales health from it.
	e.max_health = 1000000.0
	e.hp.max_health = 1000000.0
	e.hp.current_health = 1000000.0
	return e

func _phys(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		_clock += get_physics_process_delta_time()

## Cuts and warnings over one round trip with the player held at `at`.
func _trip(saw: FloorSaw, player: CharacterBody3D, at: Vector3) -> void:
	player.global_position = at
	player.velocity = Vector3.ZERO
	_hits.clear()
	_warns.clear()
	var t := 0.0
	while t < saw.round_trip() + 0.2:
		await _phys(0.05)
		t += 0.05
		player.global_position = at # held: a cut sets velocity, the probe reads it

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_floor()
	var taught: Array[String] = []
	GameState.teach_hint.connect(func(text: String) -> void: taught.append(text))
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(5, 0, 20)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	php.damaged.connect(func(_a: float, src: Node) -> void:
		if src is FloorSaw:
			_hits.append(_clock))

	var saw := FloorSaw.new()
	saw.span = Vector3(10, 0, 0)
	add_child(saw)
	saw.global_position = Vector3.ZERO
	saw.warned.connect(func() -> void: _warns.append(_clock))

	# (1) travel: out, pause, back, pause.
	var samples := {}
	var t := 0.0
	var max_off := 0.0
	var paused_far := 0.0
	while t < saw.round_trip():
		await _phys(0.05)
		t += 0.05
		max_off = maxf(max_off, saw.blade_offset())
		if saw.heading() == 0.0 and saw.blade_offset() > 9.9:
			paused_far += 0.05
		samples[snappedf(t, 0.05)] = saw.blade_offset()
	_check("the blade runs to the far end", max_off > 9.95, "(%.2f)" % max_off)
	_check("it pauses there", paused_far >= saw.pause - 0.1, "(%.2f s)" % paused_far)
	_check("and comes back", saw.blade_offset() < 0.3, "(%.2f)" % saw.blade_offset())
	_check("nothing taught from 20 m off", taught.is_empty(), "(%s)" % [taught])

	# (2) standing in the lane at 5 m: cut both ways, each warned ahead.
	await _trip(saw, player, Vector3(5, 0, 0.1))
	_check("a player in the lane is cut each pass", _hits.size() == 2, "(%d)" % _hits.size())
	var leads: Array[float] = []
	for h in _hits:
		var lead := INF
		for w in _warns:
			if w <= h:
				lead = h - w
		leads.append(lead)
	var warned := not _hits.is_empty()
	for l in leads:
		warned = warned and l >= 0.5 and l <= FloorSaw.WARN_LEAD + 0.2
	_check("every cut is warned 0.5 s or more ahead", warned, "(leads %s)" % [leads])
	_check("walking up to a saw teaches the rule, once", taught.count(FloorSaw.TEACH_TEXT) == 1, "(%s)" % [taught])

	# (4) a cut throws them out of the lane, to their side (+z here).
	player.global_position = Vector3(saw.blade_offset(), 0, 0.2)
	player.velocity = Vector3.ZERO
	(saw.get("_cool") as Dictionary).clear()
	await _phys(0.05)
	_check("a cut throws the player out to their side", player.velocity.z > 4.0, "(%s)" % player.velocity)

	# (3) mid-jump over it, and just outside the stripes.
	await _trip(saw, player, Vector3(5, 1.0, 0.0))
	_check("a jump clears the blade", _hits.is_empty(), "(%d cuts)" % _hits.size())
	await _trip(saw, player, Vector3(5, 0, FloorSaw.LANE_HALF + 0.35))
	_check("outside the stripes: never cut", _hits.is_empty(), "(%d)" % _hits.size())
	_check("outside the stripes: never warned", _warns.is_empty(), "(%d)" % _warns.size())

	# (5) robots.
	player.global_position = Vector3(5, 0, 30)
	var in_lane := _robot(Vector3(3, 0, 0.0))
	var off_lane := _robot(Vector3(7, 0, 2.0))
	var robot_cuts := {in_lane: 0, off_lane: 0}
	for b in [in_lane, off_lane]:
		var bot: EnemyBase = b
		bot.hp.damaged.connect(func(_a: float, src: Node) -> void:
			if src is FloorSaw:
				robot_cuts[bot] += 1)
	await _phys(saw.round_trip() + 0.2)
	_check("a robot in the lane is cut", robot_cuts[in_lane] >= 2, "(%d)" % robot_cuts[in_lane])
	_check("a robot 2 m off is not", robot_cuts[off_lane] == 0, "(%d)" % robot_cuts[off_lane])
	saw.queue_free()

	_assembly()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _assembly() -> void:
	var def := LevelDefs.get_def("assembly")
	var saws: Array = def.get("saws", [])
	_check("assembly has floor saws", saws.size() >= 2, "(%d)" % saws.size())
	var gate: Dictionary = {}
	for g in def.get("gates", []):
		if String(g["axis"]) == "z":
			gate = g
	var at := float(gate.get("at", 0.0))
	var lo := float(gate.get("gap_pos", 0.0)) - float(gate.get("gap", 0.0)) * 0.5
	var hi := float(gate.get("gap_pos", 0.0)) + float(gate.get("gap", 0.0)) * 0.5
	var sides := {}
	var dirs: Array[float] = []
	for s in saws:
		var a: Vector3 = s["a"]
		var b: Vector3 = s["b"]
		if absf(a.z - b.z) > 0.01 or absf(a.z - at) > 3.0:
			continue
		sides[signf(a.z - at)] = true
		var reach_lo := minf(a.x, b.x) - FloorSaw.RADIUS
		var reach_hi := maxf(a.x, b.x) + FloorSaw.RADIUS
		_check("the slot at z=%.1f covers the gap to under a body's width" % a.z,
			reach_lo - lo < 0.7 and hi - reach_hi < 0.7 and reach_lo >= lo - 0.01 and reach_hi <= hi + 0.01,
			"(reach %.2f..%.2f, gap %.2f..%.2f)" % [reach_lo, reach_hi, lo, hi])
		dirs.append(float(s.get("phase", 0.0)))
	_check("slots on both sides of the bulkhead", sides.size() == 2, "(%s)" % [sides.keys()])
	_check("the two blades run opposite ways", dirs.size() == 2 and is_equal_approx(absf(dirs[0] - dirs[1]), 0.5), "(%s)" % [dirs])
