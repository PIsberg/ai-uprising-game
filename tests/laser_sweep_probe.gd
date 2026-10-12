extends Node3D
## Probe: LaserSweep, the rotating laser fence ("laser_sweeps" def key).
## A player standing still 4 m from the emitter, over one full revolution:
## (1) standing, a high beam (1.35 m) hits them; crouched (1.0 m tall) it
##     passes over;
## (2) on the floor a low beam (0.45 m) hits them; with their feet 0.6 m up
##     (mid-jump) it passes under;
## (3) a wall between the emitter and the player stops the beam (no hit, and
##     the beam is drawn no longer than the wall's distance);
## (4) a sweep that `stops_on` a task goes dark once that task is done;
## (5) GROK's mainframe sweeps: a sweep on the core, woken by the HVT kill
##     and stopped by the core's destruction;
## (7) it reads: a low beam is amber with a JUMP tag over it, a high one red
##     with a DUCK tag under it; every hit is preceded by a warning blip at
##     least 0.3 s ahead, none fires for a player out of reach, and walking
##     up to a fence teaches the rule once;
## (6) the CLAUDE vault's decryption is held under a sweep: centred on the
##     decrypt zone, reaching past its edge, woken by the keycard and stopped
##     by the decryption.
##   godot --headless --path . --audio-driver Dummy res://tests/laser_sweep_probe.tscn

var ok := true
var _player: CharacterBody3D
var _hits := 0
var _clock := 0.0
var _hit_at: Array[float] = []
var _warn_at: Array[float] = []
var _taught: Array[String] = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	add_child(body)
	body.global_position = pos
	return body

## Hits taken over one full revolution of `sweep` with the player at `at`.
func _revolution(sweep: LaserSweep, at: Vector3, crouched: bool) -> int:
	_player.global_position = at
	_player.set("_is_crouching", crouched)
	_hits = 0
	_hit_at.clear()
	_warn_at.clear()
	var t := 0.0
	var turn := 360.0 / sweep.speed_deg + 0.3
	while t < turn:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_clock += get_physics_process_delta_time()
	return _hits

func _sweep(beams: Array) -> LaserSweep:
	var s := LaserSweep.new()
	s.radius = 8.0
	s.speed_deg = 120.0
	s.beams = beams
	add_child(s)
	s.global_position = Vector3.ZERO
	return s

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(4, 0, 0)
	_player.set_physics_process(false) # held where the probe puts it
	await get_tree().physics_frame
	var php: Node = _player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	php.damaged.connect(func(_a: float, src) -> void:
		if src is LaserSweep:
			_hits += 1
			_hit_at.append(_clock))
	GameState.teach_hint.connect(func(text: String) -> void: _taught.append(text))

	var high := _sweep([{"height": 1.35, "angle": 0.0}])
	var stand := await _revolution(high, Vector3(4, 0, 0), false)
	var duck := await _revolution(high, Vector3(4, 0, 0), true)
	_check("high beam hits a standing player", stand >= 1, "(%d)" % stand)
	_check("high beam passes over a crouch", duck == 0, "(%d)" % duck)
	high.queue_free()

	var low := _sweep([{"height": 0.45, "angle": 0.0}])
	var floor_hits := await _revolution(low, Vector3(4, 0, 0), false)
	var jump_hits := await _revolution(low, Vector3(4, 0.6, 0), false)
	_check("low beam hits a player on the floor", floor_hits >= 1, "(%d)" % floor_hits)
	_check("low beam passes under a jump", jump_hits == 0, "(%d)" % jump_hits)

	# A wall at 2.5 m along +x shields a player at 4 m behind it.
	var wall := _box(Vector3(2.5, 1, 0), Vector3(0.4, 2, 3))
	var shielded := await _revolution(low, Vector3(4, 0, 0), false)
	_check("a wall stops the beam", shielded == 0, "(%d)" % shielded)
	var drawn := 99.0
	var t := 0.0
	while t < 360.0 / low.speed_deg:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var d: Vector3 = low.beam_direction(0)
		if d.x > 0.995:
			drawn = minf(drawn, low.beam_length(0))
	_check("the beam is drawn up to the wall", drawn < 2.5, "(%.2f m)" % drawn)
	wall.queue_free()
	low.queue_free()

	# It reads: colour, tag and a warning ahead of every hit. The player
	# starts 90 degrees ahead of the low beam, as if walking up to it.
	var pair := _sweep([{"height": 0.45, "angle": 0.0}, {"height": 1.35, "angle": 180.0}])
	pair.warned.connect(func(_i: int) -> void: _warn_at.append(_clock))
	_check("low beam is a jump beam", pair.beam_action(0) == "jump" and pair.beam_cue(0).text == "JUMP")
	_check("high beam is a duck beam", pair.beam_action(1) == "duck" and pair.beam_cue(1).text == "DUCK")
	_check("jump and duck beams differ in colour", pair.beam_color(0) != pair.beam_color(1),
		"(%s vs %s)" % [pair.beam_color(0), pair.beam_color(1)])
	var pair_hits := await _revolution(pair, Vector3(0, 0, 4), false)
	var leads: Array[float] = []
	for h in _hit_at:
		var lead := INF
		for w in _warn_at:
			if w <= h:
				lead = h - w
		leads.append(lead)
	var all_warned := pair_hits >= 2
	for l in leads:
		all_warned = all_warned and l >= 0.3 and l <= LaserSweep.WARN_LEAD + 0.2
	_check("every hit is warned 0.3 s or more ahead", all_warned, "(%d hits, leads %s)" % [pair_hits, leads])
	_check("the tags ride above the jump beam and below the duck beam",
		pair.beam_cue(0).position.y > 0.45 and pair.beam_cue(1).position.y < 1.35,
		"(%.2f, %.2f)" % [pair.beam_cue(0).position.y, pair.beam_cue(1).position.y])
	_check("walking up to a fence teaches the rule, once", _taught.count(LaserSweep.TEACH_TEXT) == 1, "(%s)" % [_taught])
	await _revolution(pair, Vector3(30, 0, 0), false)
	_check("no warning out of reach", _warn_at.is_empty(), "(%d)" % _warn_at.size())
	pair.queue_free()


	# stops_on: dark once the task is done.
	GameState.level_tasks = [{"id": "core", "label": "Core", "done": false, "progress": 0.0, "target": 1.0}]
	var guarded := _sweep([{"height": 0.45, "angle": 0.0}])
	guarded.stops_on = "core"
	var before := await _revolution(guarded, Vector3(4, 0, 0), false)
	GameState.level_tasks[0]["done"] = true
	GameState.tasks_changed.emit()
	var after := await _revolution(guarded, Vector3(4, 0, 0), false)
	_check("hits while the core stands", before >= 1, "(%d)" % before)
	_check("dark once the core is destroyed", after == 0 and not guarded.active, "(%d hits)" % after)
	guarded.queue_free()
	GameState.level_tasks = []

	var def := LevelDefs.get_def("grok")
	var sweeps: Array = def.get("laser_sweeps", [])
	_check("grok has a laser sweep", sweeps.size() >= 1, "(%d)" % sweeps.size())
	var core := Vector3.INF
	for task in def.get("tasks", []):
		if String(task.get("type", "")) == "destroy_core":
			core = task["pos"]
	for s in sweeps:
		var p: Vector3 = s["pos"]
		_check("sweep on the GROK mainframe", Vector2(p.x - core.x, p.z - core.z).length() < 0.5, "(%s vs %s)" % [p, core])
		_check("woken by the HVT kill", String(s.get("wakes_on", "")) == "hvt")
		_check("stopped by the core", String(s.get("stops_on", "")) == "core")
	var vault := LevelDefs.get_def("claude")
	var vs: Array = vault.get("laser_sweeps", [])
	_check("claude has a laser sweep", vs.size() >= 1, "(%d)" % vs.size())
	for task in vault.get("tasks", []):
		if String(task.get("id", "")) != "decrypt":
			continue
		var zp: Vector3 = task["pos"]
		var zr: float = float(task.get("radius", 4.0))
		for s in vs:
			var p: Vector3 = s["pos"]
			_check("vault sweep centred on the decrypt zone", Vector2(p.x - zp.x, p.z - zp.z).length() < 0.5, "(%s vs %s)" % [p, zp])
			_check("vault beams reach past the zone", float(s.get("radius", 8.0)) >= zr + 1.0, "(%.1f vs zone %.1f)" % [float(s.get("radius", 8.0)), zr])
			_check("woken by the keycard", String(s.get("wakes_on", "")) == "key")
			_check("stopped by the decryption", String(s.get("stops_on", "")) == "decrypt")
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
