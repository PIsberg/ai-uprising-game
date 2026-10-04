extends Node3D
## Escape countdown (escape_zone.gd): the task label carries the remaining
## seconds; once the clock runs out a player outside the ring takes purge
## damage; stepping into the ring completes the task, restores the plain label
## and stops the burn; the clock holds while the game is not PLAYING, and
## dying mid-purge hands the in-place checkpoint respawn a fresh clock. Then on
## every campaign level that authors an "escape" task, the ring is reachable on
## the built navmesh from the prerequisite objective, and that route can be RUN
## (player sprint_speed) inside 60% of the clock, leaving the rest for the
## fight the escape is meant to be.
##   godot --headless --path . --audio-driver Dummy res://tests/escape_probe.tscn

var _fails: Array[String] = []

class StubPlayer extends CharacterBody3D:
	var hp: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	# Let autoload boot settle first: an early state write gets overwritten.
	await _frames(10)
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

func _label(id: String) -> String:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return t["label"]
	return ""

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("esc", "Run", 0.0)
	var p := StubPlayer.new()
	p.add_to_group("player")
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cs.shape = cap
	cs.position.y = 1.0
	p.add_child(cs)
	p.hp = Damageable.new()
	p.hp.max_health = 1000.0
	p.add_child(p.hp)
	# Positioned BEFORE add_child: added at the origin it would overlap the
	# ring for a frame and extract at once.
	p.position = Vector3(30, 0, 0)
	add_child(p)
	var z := EscapeZone.new()
	z.task_id = "esc"
	z.base_label = "Run"
	z.seconds = 1.5
	z.purge_dps = 40.0
	z.radius = 3.0
	add_child(z)
	await _frames(6)
	_check(_label("esc") == "Run (2s)", "label carries the remaining seconds (%s)" % _label("esc"))
	_check(not GameState.is_task_done("esc"), "task open while the player is away")
	_check(z.remaining < 1.5, "the clock is running while PLAYING (%.2f)" % z.remaining)
	# Paused: the clock holds.
	GameState.current_state = GameState.State.PAUSED
	var held := z.remaining
	await _frames(30)
	_check(is_equal_approx(z.remaining, held), "clock holds while not PLAYING (%.2f -> %.2f)" % [held, z.remaining])
	GameState.current_state = GameState.State.PLAYING
	await _frames(110) # past 1.5 s
	_check(z.purging, "the purge starts when the clock runs out")
	var hp0: float = p.hp.current_health
	await _frames(30)
	var lost: float = hp0 - p.hp.current_health
	_check(lost > 10.0 and lost < 30.0, "purge burns a stray player (~20 HP over 0.5 s, got %.1f)" % lost)
	_check(_label("esc").ends_with("PURGE ACTIVE"), "label flags the live purge (%s)" % _label("esc"))
	# Death mid-purge: checkpoint respawn is IN PLACE (no reload), so a clock
	# left at zero would burn the respawned player all the way back from the
	# last objective. Dying must hand them a fresh clock.
	var lvl_deaths: int = GameState.level_deaths
	GameState.on_player_died("probe")
	GameState.current_state = GameState.State.PLAYING
	await _frames(3)
	GameState.level_deaths = lvl_deaths
	_check(not z.purging and z.remaining > 1.3, "dying mid-purge resets the clock for the respawn (purging=%s, %.2f s)" % [z.purging, z.remaining])
	var hp_r: float = p.hp.current_health
	await _frames(20)
	_check(is_equal_approx(hp_r, p.hp.current_health), "no purge burn on the fresh clock")
	p.global_position = Vector3(0, 0, 0)
	await _frames(6)
	_check(GameState.is_task_done("esc"), "stepping into the ring completes the escape")
	_check(_label("esc") == "Run", "label restored on extraction (%s)" % _label("esc"))
	var hp1: float = p.hp.current_health
	await _frames(30)
	_check(is_equal_approx(hp1, p.hp.current_health), "no purge damage after extraction")
	z.queue_free()
	p.queue_free()
	GameState.reset_tasks()
	await _frames(3)

func _campaign() -> void:
	var sprint: float = 9.0
	var ps := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	sprint = float(ps.get("sprint_speed"))
	ps.free()
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var by_id := {}
		var escapes: Array = []
		for t in def.get("tasks", []):
			by_id[String(t.get("id", t.get("type", "")))] = t
			if t.get("type", "") == "escape":
				escapes.append(t)
		if escapes.is_empty():
			continue
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
		for e in escapes:
			var after = e.get("after", "")
			var pre_id: String = after if after is String else String(after[0])
			var from: Vector3 = by_id[pre_id].get("pos", spawn) if by_id.has(pre_id) else spawn
			var to: Vector3 = e.get("pos", Vector3.ZERO)
			var a := NavigationServer3D.map_get_closest_point(map, from)
			var b := NavigationServer3D.map_get_closest_point(map, to)
			var route := NavigationServer3D.map_get_path(map, a, b, true)
			var ends := route.size() > 1 and Vector2(route[-1].x - to.x, route[-1].z - to.z).length() < 2.5
			_check(ends, "%s escape ring at %s is reachable from %s" % [id, to, pre_id])
			var length := 0.0
			for i in range(1, route.size()):
				length += route[i].distance_to(route[i - 1])
			var secs: float = float(e.get("seconds", 45.0))
			_check(length / sprint <= secs * 0.6, "%s escape: %.0f m at %.1f m/s = %.1f s fits 60%% of %.0f s" % [id, length, sprint, length / sprint, secs])
		level.queue_free()
		await _frames(4)
