extends Node3D
## Signal hunt (task "trace_signal", SignalTransmitter). Unit, on a flat floor
## with a stand-in player:
##   - the SIGNAL bars rise as the player closes in (0 beyond 60 m, 5 within 8);
##   - hidden, it is no objective (no waypoint, no radar) and the task label
##     carries the meter; it pings faster up close; the first ping in range
##     teaches the rule;
##   - within REVEAL_RANGE with line of sight it reveals: objective, toast,
##     `revealed`, plain label; behind a wall at the same range it stays hidden;
##   - a shot from afar reveals it too; destroyed, it completes its task.
## Campaign (the Hollow): the emitter is built hidden, the beacon task waits
## on it, it stands clear of geometry, out of every hazard bed, reachable and
## well away from spawn; revealing it brings its alarm squad; destroying it
## puts the beacon up.
##   godot --headless --path . --audio-driver Dummy res://tests/signal_hunt_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []
var _toasts: Array[String] = []
var _player: CharacterBody3D

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	GameState.skirmish_event.connect(func(t: String, _d: String) -> void: _toasts.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	await _campaign()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))

func _label(id: String) -> String:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return String(t["label"])
	return ""

func _unit() -> void:
	print("unit:")
	_check(SignalTransmitter.bars_for(70.0) == 0 and SignalTransmitter.bars_for(50.0) == 1 and SignalTransmitter.bars_for(20.0) == 3
		and SignalTransmitter.bars_for(5.0) == 5, "the bars rise as you close in (70 m 0, 50 m 1, 20 m 3, 5 m 5)")
	var root := Node3D.new()
	add_child(root)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(300, 1, 300)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	root.add_child(sb)
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2
	_player.position = Vector3(0, 0.05, 50)
	root.add_child(_player)
	GameState.level_tasks.clear()
	GameState.register_task("signal", "Trace and destroy the hidden transmitter")
	var st := SignalTransmitter.new()
	st.task_id = "signal"
	var got := {"revealed": 0}
	st.revealed.connect(func() -> void: got["revealed"] += 1)
	root.add_child(st)
	_hints.clear()
	await _seconds(6.0)
	var far := st.pings
	_check(st.hidden and not st.is_in_group("objective"), "hidden it is no objective: no waypoint, no radar")
	_check(_label("signal").ends_with("■□□□□"), "the task label carries the meter at 50 m (%s)" % _label("signal"))
	_check(_hints.has(SignalTransmitter.TEACH_TEXT), "the first ping in range teaches the rule")
	_player.global_position = Vector3(0, 0.05, 9)
	await _seconds(6.0)
	var near := st.pings - far
	_check(near >= far * 2 and _label("signal").ends_with("■■■■□"), "it pings faster up close (%d in 6 s at 50 m, %d at 9 m; %s)" % [far, near, _label("signal")])
	# A wall between: hidden at reveal range.
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(6, 4, 0.4)
	wcs.shape = wbs
	wall.add_child(wcs)
	wall.position = Vector3(0, 2, 2.5)
	root.add_child(wall)
	_player.global_position = Vector3(0, 0.05, 5)
	await _seconds(0.5)
	_check(st.hidden, "behind a wall at %.0f m it stays hidden" % 5.0)
	wall.queue_free()
	_toasts.clear()
	await _seconds(0.3)
	_check(not st.hidden and st.is_in_group("objective") and got["revealed"] == 1 and _toasts.has("TRANSMITTER FOUND"),
		"in sight within %.0f m it reveals: waypoint, toast, alarm signal" % SignalTransmitter.REVEAL_RANGE)
	_check(_label("signal") == "Trace and destroy the hidden transmitter", "and the label drops the meter")
	# Revealed by a shot from afar.
	_player.global_position = Vector3(0, 0.05, 45)
	var st2 := SignalTransmitter.new()
	st2.task_id = "signal2"
	st2.position = Vector3(10, 0, 0)
	root.add_child(st2)
	await _frames(3)
	st2.hp.apply_damage(10.0, _player)
	await _frames(2)
	_check(not st2.hidden, "a shot from %.0f m reveals it too" % _player.global_position.distance_to(st2.global_position))
	st.hp.apply_damage(SignalTransmitter.HEALTH + 1.0, _player)
	await _frames(3)
	_check(GameState.is_task_done("signal") and not is_instance_valid(st), "destroyed, it completes its task")
	root.queue_free()
	GameState.level_tasks.clear()
	await _frames(4)

func _in_bed(at: Vector3, beds: Array) -> bool:
	for b in beds:
		var c: Vector3 = b.get("pos", Vector3.ZERO)
		var sz: Vector2 = b.get("size", Vector2.ZERO)
		if absf(at.x - c.x) < sz.x * 0.5 + 0.8 and absf(at.z - c.z) < sz.y * 0.5 + 0.8:
			return true
	return false

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var task: Dictionary = {}
		for t in def.get("tasks", []):
			if t.get("type", "") == "trace_signal":
				task = t
		if task.is_empty():
			continue
		print("level %s:" % id)
		var beds: Array = def.get("lava", []).duplicate()
		for t in def.get("tasks", []):
			beds.append_array((t as Dictionary).get("flood", {}).get("beds", []))
			for w in (t as Dictionary).get("waves", []):
				beds.append_array((w as Dictionary).get("flood", {}).get("beds", []))
		var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(level)
		var map := level.get_world_3d().navigation_map
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		for i in 40:
			await _frames(6)
			if NavigationServer3D.map_get_closest_point(map, spawn) != Vector3.ZERO:
				break
		await _frames(10)
		var sts := level.find_children("*", "SignalTransmitter", true, false)
		_check(sts.size() == 1, "%s builds its transmitter" % id)
		if sts.is_empty():
			level.queue_free()
			continue
		found += 1
		var st := sts[0] as SignalTransmitter
		st.set_physics_process(false) # the probe's own player must not reveal it
		var at := st.global_position
		_check(st.hidden and not st.is_in_group("objective"), "%s: it starts hidden, no waypoint" % id)
		var dependents: Array[String] = []
		for t in GameState.level_tasks:
			if t.get("staged", false):
				dependents.append(String(t["id"]))
		_check(not dependents.is_empty(), "%s: a later stage waits on it (%s)" % [id, dependents])
		var space := level.get_world_3d().direct_space_state
		var box := BoxShape3D.new()
		box.size = Vector3(1.4, 1.4, 1.4)
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = box
		sq.transform = Transform3D(Basis(), at + Vector3.UP * 0.9)
		sq.collision_mask = 1
		sq.exclude = [st.get_rid()]
		_check(space.intersect_shape(sq, 1).is_empty(), "%s: it stands clear of geometry at %s" % [id, at])
		_check(not _in_bed(at, beds), "%s: it is out of every hazard bed" % id)
		var near := NavigationServer3D.map_get_closest_point(map, at)
		var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, spawn), near, true)
		_check(path.size() > 1 and path[-1].distance_to(near) < 0.6 and Vector2(near.x - at.x, near.z - at.z).length() < 2.0,
			"%s: it can be reached from spawn" % id)
		_check(Vector2(at.x - spawn.x, at.z - spawn.z).length() > 50.0, "%s: it is a hunt, %.0f m from spawn" % [id, Vector2(at.x - spawn.x, at.z - spawn.z).length()])
		var before := get_tree().get_nodes_in_group("enemy").size()
		var alarm := 0
		for a in task.get("alarm", []):
			alarm += int(a.get("count", 1))
		st.reveal()
		await _seconds(0.5 + 0.35 * alarm + 2.0)
		var after := get_tree().get_nodes_in_group("enemy").size()
		_check(after - before >= alarm, "%s: revealing it brings its alarm squad (+%d robots, %d authored)" % [id, after - before, alarm])
		st.hp.apply_damage(SignalTransmitter.HEALTH + 1.0, null)
		await _seconds(0.5)
		_check(not level.find_children("*", "ObjectiveCore", true, false).is_empty(), "%s: destroying it puts the next stage up" % id)
		level.queue_free()
		await _frames(4)
	_check(found >= 1, "at least one campaign level hunts a signal (%d)" % found)
