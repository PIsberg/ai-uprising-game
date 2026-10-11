extends Node3D
## Kill switches (kill_switch.gd + kill_switch_bank.gd), the off-switch problem
## as a task. Unit pass with a stub player and three switches:
##   - walking into a switch throws it, counts it on the meter (1/3) and starts
##     the watchdog clock, whose seconds show in the label;
##   - the clock holds while the game is not PLAYING;
##   - when it runs out every thrown switch re-arms, the meter drops to 0, the
##     label goes back to plain and a HAL-style revert line is announced (a new
##     line each time);
##   - dying re-arms them too, silently;
##   - all three inside one window completes the task with the plain label and
##     locks the switches down for good (no re-arm after the clock would have
##     run out).
## Campaign pass: on every level that authors a kill_switch, each switch is on
## the built navmesh, and the shortest tour through all of them can be RUN at
## the player's sprint speed inside 60% of the window, leaving the rest for the
## fight the window is meant to be.
##   godot --headless --path . --audio-driver Dummy res://tests/kill_switch_probe.tscn

var _fails: Array[String] = []
var _toasts: Array[String] = []

class StubPlayer extends CharacterBody3D:
	var hp: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.skirmish_event.connect(func(title: String, desc: String): _toasts.append("%s|%s" % [title, desc]))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	GameState.current_state = prev_state
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _task(id: String) -> Dictionary:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return t
	return {}

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("sw", "Cut", 3.0)
	var p := StubPlayer.new()
	p.add_to_group("player")
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	cs.position.y = 1.0
	p.add_child(cs)
	p.hp = Damageable.new()
	p.hp.max_health = 1000.0
	p.add_child(p.hp)
	p.position = Vector3(0, 0, 40)
	add_child(p)
	var bank := KillSwitchBank.new()
	bank.task_id = "sw"
	bank.base_label = "Cut"
	bank.window = 1.5
	add_child(bank)
	var spots := [Vector3(-10, 0, 0), Vector3(0, 0, 0), Vector3(10, 0, 0)]
	for s in spots:
		var ks := KillSwitch.new()
		ks.task_id = "sw"
		ks.position = s
		add_child(ks)
		bank.add_switch(ks)
	await _frames(3)
	_check(bank.thrown_count() == 0 and not bank.running, "nothing thrown until the player arrives")

	p.global_position = spots[0]
	await _frames(4)
	_check(bank.switches[0].thrown, "walking into a switch throws it")
	_check(int(_task("sw")["progress"]) == 1, "the meter counts it (%s)" % _task("sw")["progress"])
	_check(bank.running, "the first throw starts the watchdog clock")
	_check(String(_task("sw")["label"]) == "Cut (2s)", "label carries the seconds (%s)" % _task("sw")["label"])
	_check(_toasts.any(func(s): return s.begins_with("WATCHDOG|")), "the watchdog announces itself")

	GameState.current_state = GameState.State.PAUSED
	var held := bank.remaining
	await _frames(30)
	_check(is_equal_approx(held, bank.remaining), "clock holds while not PLAYING (%.2f -> %.2f)" % [held, bank.remaining])
	GameState.current_state = GameState.State.PLAYING

	# Run the clock out with one switch thrown: the player stays put, away from
	# the others (and off the thrown one, so it is not re-thrown at once).
	p.global_position = Vector3(0, 0, 40)
	await _frames(110)
	_check(not bank.switches[0].thrown, "running out re-arms the thrown switch")
	_check(int(_task("sw")["progress"]) == 0, "the meter drops back to 0")
	_check(String(_task("sw")["label"]) == "Cut", "label back to plain (%s)" % _task("sw")["label"])
	_check(not bank.running and not GameState.is_task_done("sw"), "clock stopped, task still open")
	var reverts := _toasts.filter(func(s): return s.begins_with(KillSwitchBank.REVERT_TITLE + "|"))
	_check(reverts.size() == 1 and reverts[0].ends_with(KillSwitchBank.REVERT_LINES[0]), "the model refuses, once (%s)" % [reverts])

	# Second failure reads a new line.
	p.global_position = spots[2]
	await _frames(4)
	p.global_position = Vector3(0, 0, 40)
	await _frames(110)
	reverts = _toasts.filter(func(s): return s.begins_with(KillSwitchBank.REVERT_TITLE + "|"))
	_check(reverts.size() == 2 and reverts[1].ends_with(KillSwitchBank.REVERT_LINES[1]), "a second revert reads the next line")

	# Death mid-window re-arms everything, without a taunt.
	p.global_position = spots[1]
	await _frames(4)
	p.global_position = Vector3(0, 0, 40)
	await _frames(2)
	_check(bank.switches[1].thrown, "thrown again before the death")
	var lvl_deaths: int = GameState.level_deaths
	GameState.on_player_died("probe")
	GameState.current_state = GameState.State.PLAYING
	await _frames(3)
	GameState.level_deaths = lvl_deaths
	_check(bank.thrown_count() == 0 and not bank.running, "dying re-arms the switches and stops the clock")
	reverts = _toasts.filter(func(s): return s.begins_with(KillSwitchBank.REVERT_TITLE + "|"))
	_check(reverts.size() == 2, "no revert taunt for a death")

	# All three inside one window.
	for s in spots:
		p.global_position = s
		await _frames(4)
	_check(GameState.is_task_done("sw"), "all three inside one window completes the task")
	_check(String(_task("sw")["label"]) == "Cut", "completed with the plain label (%s)" % _task("sw")["label"])
	_check(_toasts.any(func(s): return s.begins_with("SHUTDOWN ACCEPTED|")), "the shutdown is announced")
	p.global_position = Vector3(0, 0, 40)
	await _frames(120)
	var down := true
	for ks: KillSwitch in bank.switches:
		down = down and ks.thrown and ks.locked
	_check(down, "switches stay down after the window would have run out")
	bank.queue_free()
	for ks in bank.switches:
		ks.queue_free()
	p.queue_free()
	GameState.reset_tasks()
	await _frames(3)

func _route_len(map: RID, a: Vector3, b: Vector3) -> float:
	var pa := NavigationServer3D.map_get_closest_point(map, a)
	var pb := NavigationServer3D.map_get_closest_point(map, b)
	var route := NavigationServer3D.map_get_path(map, pa, pb, true)
	if route.size() < 2 or Vector2(route[-1].x - b.x, route[-1].z - b.z).length() > 2.5:
		return INF
	var length := 0.0
	for i in range(1, route.size()):
		length += route[i].distance_to(route[i - 1])
	return length

## Shortest open tour through every point (the clock starts at the first one
## thrown, so the approach does not count). Brute force: a level has a handful.
func _best_tour(map: RID, pts: Array) -> float:
	var n := pts.size()
	var d := []
	for i in n:
		var row := []
		for j in n:
			row.append(0.0 if i == j else _route_len(map, pts[i], pts[j]))
		d.append(row)
	var best := INF
	for perm in _perms(range(n)):
		var total := 0.0
		for k in range(1, perm.size()):
			total += d[perm[k - 1]][perm[k]]
		best = minf(best, total)
	return best

func _perms(items: Array) -> Array:
	if items.size() <= 1:
		return [items]
	var out := []
	for i in items.size():
		var rest := items.duplicate()
		var head = rest.pop_at(i)
		for tail in _perms(rest):
			out.append([head] + tail)
	return out

func _campaign() -> void:
	var ps := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var sprint := float(ps.get("sprint_speed"))
	ps.free()
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var banks: Array = []
		for t in def.get("tasks", []):
			if t.get("type", "") == "kill_switch":
				banks.append(t)
		if banks.is_empty():
			continue
		found += 1
		print("level %s:" % id)
		var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(level)
		var map := level.get_world_3d().navigation_map
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		for i in 40:
			await _frames(6)
			if NavigationServer3D.map_get_closest_point(map, spawn) != Vector3.ZERO:
				break
		await _frames(10)
		for t in banks:
			var pts: Array = []
			for sp in t.get("points", []):
				pts.append(sp["pos"] if sp is Dictionary else sp)
			_check(pts.size() >= 2, "%s authors at least two switches" % id)
			for p in pts:
				var on := NavigationServer3D.map_get_closest_point(map, p)
				_check(Vector2(on.x - p.x, on.z - p.z).length() < 1.6, "%s switch %s is on the navmesh" % [id, p])
				_check(_route_len(map, spawn, p) < INF, "%s switch %s is reachable from the spawn" % [id, p])
			var tour := _best_tour(map, pts)
			var window := float(t.get("window", 20.0))
			_check(tour / sprint <= window * 0.6, "%s tour %.0f m at %.1f m/s = %.1f s fits 60%% of %.0f s" % [id, tour, sprint, tour / sprint, window])
		level.queue_free()
		await _frames(4)
	_check(found >= 1, "at least one campaign level authors a kill_switch (%d)" % found)
