extends Node3D
## Probe: LaserGate, the laser hurdle gate ("laser_gates" def key).
## A 6 m gate along x at the origin (period 3.2 s), over two periods:
## (1) the knee and chest beams take turns, each live half a period, and the
##     next one flickers WARN_TIME (0.7 s) or more before it lights;
## (2) only the live beam carries its tag (JUMP over the knee beam, DUCK
##     under the chest beam);
## (3) a player standing in the doorway is hit by both; crouched, only while
##     the knee beam is live; with their feet 0.6 m up (mid-jump), only while
##     the chest beam is live; past a post, never;
## (4) walking up to it teaches the rule, once;
## (5) both of Skybridge Uplink's blast doors carry a gate centred in the
##     (scaled) gap and spanning it, half a period apart.
##   godot --headless --path . --audio-driver Dummy res://tests/laser_gate_probe.tscn

var ok := true
var _clock := 0.0
var _hit_live: Array[int] = []

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

func _phys(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		_clock += get_physics_process_delta_time()

## Which live beams hit a player held at `at` over two periods.
func _periods(gate: LaserGate, player: CharacterBody3D, at: Vector3, crouched: bool) -> Dictionary:
	player.global_position = at
	player.set("_is_crouching", crouched)
	_hit_live.clear()
	await _phys(gate.period * 2.0)
	var seen := {}
	for l in _hit_live:
		seen[l] = true
	return seen

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_floor()
	var taught: Array[String] = []
	GameState.teach_hint.connect(func(text: String) -> void: taught.append(text))
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0, 30)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0

	var gate := LaserGate.new()
	gate.width = 6.0
	gate.period = 3.2
	add_child(gate)
	gate.global_position = Vector3.ZERO
	php.damaged.connect(func(_a: float, src: Node) -> void:
		if src is LaserGate:
			_hit_live.append(gate.live_beam()))
	var lit_at: Array[float] = []
	var lit_beam: Array[int] = []
	gate.switched.connect(func(l: int) -> void:
		lit_at.append(_clock)
		lit_beam.append(l))

	# (1)+(2) two periods from 30 m off, sampling the look.
	var flick_start := {}
	var leads: Array[float] = []
	var tags_ok := true
	var t := 0.0
	while t < gate.period * 2.0:
		await _phys(0.05)
		t += 0.05
		var f := gate.flickering()
		if f != -1 and not flick_start.has(f):
			flick_start[f] = _clock
		var live := gate.live_beam()
		if flick_start.has(live):
			leads.append(_clock - float(flick_start[live]))
			flick_start.erase(live)
		tags_ok = tags_ok and gate.beam_cue(live).visible and not gate.beam_cue(1 - live).visible \
			and gate.beam_shown(live)
	_check("beams take turns, two swaps a period", lit_beam.size() >= 4, "(%s)" % [lit_beam])
	var alternate := true
	for i in range(1, lit_beam.size()):
		alternate = alternate and lit_beam[i] != lit_beam[i - 1]
	_check("they alternate", alternate)
	var lead_ok := leads.size() >= 3
	for l in leads:
		lead_ok = lead_ok and l >= LaserGate.WARN_TIME - 0.06
	_check("each beam flickers 0.7 s before it lights", lead_ok, "(leads %s)" % [leads])
	_check("only the live beam is tagged and drawn solid", tags_ok)
	_check("the knee beam is tagged JUMP, the chest beam DUCK",
		gate.beam_cue(0).text == "JUMP" and gate.beam_cue(1).text == "DUCK"
		and gate.beam_cue(0).position.y > 0.45 and gate.beam_cue(1).position.y < 1.35)
	_check("nothing taught from 30 m off", taught.is_empty(), "(%s)" % [taught])

	# (3) in the doorway.
	var stand := await _periods(gate, player, Vector3(1.0, 0, 0.1), false)
	_check("standing: both beams hit", stand.has(0) and stand.has(1), "(%s)" % [stand.keys()])
	_check("walking up to it teaches the rule, once", taught.count(LaserGate.TEACH_TEXT) == 1, "(%s)" % [taught])
	var duck := await _periods(gate, player, Vector3(1.0, 0, 0.1), true)
	_check("crouched: only the knee beam hits", duck.has(0) and not duck.has(1), "(%s)" % [duck.keys()])
	var jump := await _periods(gate, player, Vector3(1.0, 0.6, 0.1), false)
	_check("mid-jump: only the chest beam hits", jump.has(1) and not jump.has(0), "(%s)" % [jump.keys()])
	var past := await _periods(gate, player, Vector3(3.0 + 0.6, 0, 0), false)
	_check("past a post: never hit", past.is_empty(), "(%s)" % [past.keys()])
	gate.queue_free()

	_uplink()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _uplink() -> void:
	var def := LevelDefs.get_def("uplink")
	var gates: Array = def.get("laser_gates", [])
	_check("uplink has laser gates", gates.size() >= 2, "(%d)" % gates.size())
	var phases: Array[float] = []
	for door in def.get("gates", []):
		if String(door["axis"]) != "z" or absf(absf(float(door["at"])) - 16.0 * LevelDefs.WORLD_SCALE) > 0.1:
			continue
		var c := Vector3(float(door["gap_pos"]), 0.0, float(door["at"]))
		var found := false
		for g in gates:
			var p: Vector3 = g["pos"]
			if Vector2(p.x - c.x, p.z - c.z).length() < 0.3:
				found = true
				phases.append(float(g.get("phase", 0.0)))
				_check("the gate at %s spans its door" % c, float(g["width"]) >= float(door["gap"]) - 0.01
					and String(g.get("axis", "x")) == "x", "(%.1f vs gap %.1f)" % [float(g["width"]), float(door["gap"])])
		_check("a gate in the blast door at %s" % c, found)
	_check("the two doors are half a period apart", phases.size() == 2 and is_equal_approx(absf(phases[0] - phases[1]), 0.5), "(%s)" % [phases])
