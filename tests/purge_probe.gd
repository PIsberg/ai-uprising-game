extends Node3D
## Dev probe for the "survive" wave escalation (SurviveTimer.waves) and GPT
## Foundry's PURGE PROTOCOL climax authored on top of it.
##
## Guards the two ways a wave silently does nothing:
##   1. Authoring drift — a wave whose "at" lands past the hold duration never
##      fires, an unknown enemy type spawns nothing, and a spawn point inside a
##      lava bed drops the wave straight into the fire (enemies are NOT
##      relocated out of hazards, unlike task objects).
##   2. Timer regression — waves must fire once each, in order, and never after
##      the hold completes.
##   godot --headless --path . res://tests/purge_probe.tscn

var _ok := true

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "BAD ", name, detail])
	if not cond:
		_ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var def: Dictionary = LevelDefs.get_def("gpt")
	var survive := {}
	for t in def.get("tasks", []):
		if t.get("type", "") == "survive":
			survive = t
	_check("gpt has a survive climax", not survive.is_empty())
	var waves: Array = survive.get("waves", [])
	var hold: float = float(survive.get("seconds", 0.0))
	_check("purge has waves", waves.size() >= 3, "%d waves over %.0fs" % [waves.size(), hold])

	# 1. Every wave lands inside the hold, ascending, with a label to announce.
	var prev := -1.0
	for w in waves:
		var at: float = float(w.get("at", 0.0))
		_check("wave @%.0fs fires before the hold ends" % at, at < hold, "%.0f < %.0f" % [at, hold])
		_check("wave @%.0fs is ordered" % at, at > prev)
		_check("wave @%.0fs is announced" % at, String(w.get("label", "")) != "")
		prev = at

	# 2. Every wave enemy resolves to a real scene, and none spawn into lava.
	var lava: Array = def.get("lava", [])
	for w in waves:
		for en in w.get("enemies", []):
			var t: String = en.get("type", "")
			_check("wave enemy '%s' resolves" % t, LevelBuilder.ENEMY_SCENES.has(t))
			var p: Vector3 = en.get("pos", Vector3.ZERO)
			if p.y > 1.0:
				continue # airborne (drones) — lava beds don't reach them
			for bed in lava:
				var c: Vector3 = bed["pos"]
				var s: Vector2 = bed["size"]
				# Spawners scatter a clustered "count" up to 2.5 m off `pos`, so
				# require the point to clear the bed by that margin, not just miss it.
				var inside := absf(p.x - c.x) < s.x * 0.5 + 2.5 and absf(p.z - c.z) < s.y * 0.5 + 2.5
				_check("'%s' @%v clears lava %v" % [t, p, c], not inside)

	# 3. The timer fires each wave exactly once, in order, and stops at the goal.
	GameState.reset_tasks()
	GameState.register_task("purge_test", "test", hold)
	GameState.current_state = GameState.State.PLAYING
	var timer := SurviveTimer.new()
	timer.task_id = "purge_test"
	timer.seconds = hold
	# Deliberately shuffled: _ready must sort them back into firing order.
	timer.waves = [waves[2], waves[0], waves[1]]
	var fired: Array[String] = []
	timer.wave_due.connect(func(_e: Array, l: String): fired.append(l))
	add_child(timer)
	await get_tree().process_frame
	# Drive the clock in 1 s steps past the end of the hold.
	for i in int(hold) + 4:
		timer._process(1.0)
	_check("all waves fired once", fired.size() == waves.size(), "%d/%d" % [fired.size(), waves.size()])
	var want: Array[String] = []
	for w in waves:
		want.append(String(w["label"]))
	_check("waves fired in authored order", fired == want, str(fired))
	_check("hold completed", GameState.is_task_done("purge_test"))

	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()
