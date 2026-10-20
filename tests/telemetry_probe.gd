extends Node3D
## Probe: the playtest TELEMETRY recorder (scripts/autoload/telemetry.gd).
## A session started on a scratch file, a real player on a floor with a wall:
## (1) the player's arrival logs level_start with the level id and mode;
## (2) a hit from a fire vent and a kill credited to the held gun are counted;
## (3) holding forward into the wall for 3 s logs one stuck event at the wall;
## (4) the fire vent's kill logs a death naming FIRE VENT, with the vent in the
##     last-5-s damage list;
## (5) a completed task logs its label and time;
## (6) the level clear logs level_end with result "clear", the grade, the damage
##     taken by source (FIRE VENT) and the kills by weapon;
## (7) every line is one JSON object with an event and a time;
## (8) with no --telemetry flag a headless run records nothing by default.
##   godot --headless --path . --audio-driver Dummy res://tests/telemetry_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
const OUT := "user://telemetry_probe.jsonl"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

func _box(size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = pos

func _events() -> Array:
	var out: Array = []
	var f := FileAccess.open(OUT, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		out.append(JSON.parse_string(line))
	return out

func _of(evs: Array, kind: String) -> Array:
	return evs.filter(func(e): return e is Dictionary and String(e.get("event", "")) == kind)

func _run() -> void:
	_check("headless runs record nothing by default", not Telemetry.enabled_by_default())
	if FileAccess.file_exists(OUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT))
	Telemetry.start_session(OUT)
	_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0))
	_box(Vector3(30, 4, 1), Vector3(0, 2, -4)) # the wall forward runs into
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState.set_state(GameState.State.PLAYING)
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p)
	p.global_position = Vector3(0, 1, 0)
	await _wait_game(0.5)

	# 2. Damage by source, a kill by weapon.
	var vent: Node = (load("res://scripts/systems/fire_vent.gd") as GDScript).new()
	add_child(vent)
	var hp: Damageable = p.get("hp")
	var max_hp := hp.max_health
	hp.apply_damage(10.0, vent, false, null, true)
	GameState.enemy_killed.emit(100, "DRONE")
	# One trigger pull whose 8 pellets all land is one hit, not eight (a shotgun read
	# 157% accuracy in the first bot session).
	var wm: WeaponManager = p.find_children("*", "WeaponManager", true, false)[0]
	wm.current.fired.emit(wm.current)
	for i in 8:
		GameState.player_dealt_damage.emit(5.0, Vector3.ZERO, false, false)

	# 3. Stuck against the wall.
	Input.action_press("move_forward")
	await _wait_game(3.0)
	Input.action_release("move_forward")
	await _wait_game(0.3)

	# 5. A task.
	GameState.task_completed.emit("Destroy the core")
	# 6 (clear) comes after a death and its respawn would end the level, so record
	# the death on a second life: 4. death by the vent.
	hp.apply_damage(99999.0, vent, false, null, true)
	await _wait_game(0.3)
	GameState.level_graded.emit("B", {"time": 42.0})
	GameState.level_completed.emit()
	await _wait_game(0.2)
	# A second life on the same level that dies and is reloaded (TRY AGAIN): the
	# level ends "died", not "left" (the first bot session read "1 left").
	p.queue_free()
	GameState.set_state(GameState.State.PLAYING)
	await _wait_game(0.2)
	var p2: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	add_child(p2)
	p2.global_position = Vector3(0, 1, 0)
	await _wait_game(0.3)
	(p2.get("hp") as Damageable).apply_damage(99999.0, vent, false, null, true)
	await _wait_game(0.2)
	p2.queue_free()
	await _wait_game(0.3)
	Telemetry.end_session()

	var evs := _events()
	print("events: ", evs.map(func(e): return e.get("event", "?") if e is Dictionary else "BAD"))
	_check("every line is a JSON object with an event and a time",
		not evs.is_empty() and evs.all(func(e): return e is Dictionary and e.has("event") and e.has("t")))
	var starts := _of(evs, "level_start")
	_check("level_start names the level and mode (one per life)", starts.size() == 2 and starts[0].get("level") == "gpt" and starts[0].get("mode") == "campaign", str(starts))
	var stuck := _of(evs, "stuck")
	_check("holding forward into a wall logs one stuck event", stuck.size() == 1, str(stuck))
	if stuck.size() >= 1:
		var z := float((stuck[0]["pos"] as Array)[2])
		_check("the stuck event sits at the wall", z < -2.0 and z > -4.0, "z=%.2f" % z)
	var deaths := _of(evs, "death")
	_check("the death names FIRE VENT", deaths.size() == 2 and deaths[0].get("killer") == "FIRE VENT", str(deaths))
	if deaths.size() >= 1:
		_check("the death lists the vent among the last 5 s of hits", (deaths[0].get("recent", []) as Array).any(func(h): return h.get("source") == "FIRE VENT"))
	var tasks := _of(evs, "task")
	_check("the task logs its label", tasks.size() == 1 and tasks[0].get("label") == "Destroy the core", str(tasks))
	var ends := _of(evs, "level_end")
	_check("a death then a reload ends the level as died", ends.size() == 2 and ends[1].get("result") == "died", str(ends.map(func(e): return e.get("result"))))
	_check("level_end: clear with the grade", ends.size() >= 1 and ends[0].get("result") == "clear" and ends[0].get("grade") == "B", str(ends))
	if ends.size() >= 1:
		var hits: Dictionary = ends[0].get("hits_by_weapon", {})
		var shots: Dictionary = ends[0].get("shots_by_weapon", {})
		_check("eight pellets of one shot are one hit", shots.size() == 1 and hits.size() == 1 and int(hits.values()[0]) == 1 and int(shots.values()[0]) == 1, "shots %s hits %s" % [shots, hits])
		var taken: Dictionary = ends[0].get("damage_taken", {})
		# Health lost, not the raw hit: the 99999 finisher counts what the player had left.
		_check("level_end: damage taken by source, as health lost", float(taken.get("FIRE VENT", 0.0)) >= 5.0 and float(taken.get("FIRE VENT", 0.0)) <= max_hp + 10.5, str(taken)) # + the first 10, regen refills between
		var kills: Dictionary = ends[0].get("kills_by_weapon", {})
		_check("level_end: a kill credited to the held gun", kills.size() == 1 and int(kills.values()[0]) == 1, str(kills))
		_check("level_end: one death", int(ends[0].get("deaths", -1)) == 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT))
	GameState.set_state(GameState.State.MENU)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
