extends Node3D
## Haul payload (haul_payload.gd): walking into the core shoulders it and sets
## GameState.carrying; the real player.gd then holds a heavy walk with sprint
## ignored and refuses to dash (each checked against the uncarried control, so
## a no-op check cannot pass); hits under drop_damage keep it, crossing it
## knocks the core loose behind the player and clears the flag; it can be
## picked back up; dying drops it; carrying it into the ring completes the
## task. Then on every campaign level that authors a "haul" task, the core and
## its uplink ring both sit on walkable ground joined by a route on the built
## navmesh.
##   godot --headless --path . --audio-driver Dummy res://tests/haul_probe.tscn

var _fails: Array[String] = []

class StubPlayer extends CharacterBody3D:
	var hp: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10) # let autoload boot settle before touching GameState
	_player_rules()
	await _dash_rule()
	await _unit()
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## The movement rules live in player.gd, so test the real script.
func _player_rules() -> void:
	print("player rules:")
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	GameState.carrying = false
	var walk: float = p._current_speed()
	Input.action_press("sprint")
	var sprint_free: float = p._current_speed()
	GameState.carrying = true
	var sprint_loaded: float = p._current_speed()
	Input.action_release("sprint")
	var walk_loaded: float = p._current_speed()
	_check(sprint_free > walk, "control: sprint is faster than a walk when free (%.2f > %.2f)" % [sprint_free, walk])
	_check(is_equal_approx(sprint_loaded, walk_loaded), "carrying ignores sprint (%.2f vs %.2f)" % [sprint_loaded, walk_loaded])
	_check(walk_loaded < walk * 0.8, "carrying is a heavy walk (%.2f < 0.8 x %.2f)" % [walk_loaded, walk])
	GameState.carrying = false
	p.free()

## Dash needs a live player (input is read in its physics tick), on a floor.
## The free control proves the input path starts a dash at all.
func _dash_rule() -> void:
	var floor := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs
	floor.add_child(fcs)
	floor.position = Vector3(0, -0.5, -200)
	add_child(floor)
	var p = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.position = Vector3(0, 0.2, -200)
	add_child(p)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _frames(20)
	var dashed := {}
	for loaded in [false, true]:
		GameState.carrying = loaded
		p._dash_cd = 0.0
		await _frames(2)
		var ev := InputEventAction.new()
		ev.action = "dash"
		ev.pressed = true
		Input.parse_input_event(ev)
		await _frames(3)
		dashed[loaded] = p._dash_cd > 0.0
		var up := InputEventAction.new()
		up.action = "dash"
		up.pressed = false
		Input.parse_input_event(up)
		await _frames(30)
	_check(dashed[false], "control: the dash input starts a dash when free")
	_check(not dashed[true], "carrying refuses the dash")
	GameState.carrying = false
	GameState.current_state = prev_state
	p.queue_free()
	floor.queue_free()
	await _frames(3)

func _stub(at: Vector3) -> StubPlayer:
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
	p.position = at # BEFORE add_child: never overlap the core for a frame by accident
	add_child(p)
	return p

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("haul_t", "Haul", 0.0)
	var p := _stub(Vector3(-12, 0, 0))
	var h := HaulPayload.new()
	h.task_id = "haul_t"
	h.base_label = "Haul"
	h.deliver_pos = Vector3(30, 0, 0)
	h.deliver_radius = 3.0
	h.drop_damage = 30.0
	add_child(h)
	await _frames(6)
	_check(not h.carried and not GameState.carrying, "core waits on the ground")
	p.global_position = Vector3(0, 0, 0)
	await _frames(4)
	_check(h.carried and GameState.carrying, "walking into the core shoulders it")
	p.hp.apply_damage(20.0, null)
	await _frames(2)
	_check(h.carried, "a 20 HP hit does not knock it loose")
	p.hp.apply_damage(15.0, null)
	await _frames(2)
	_check(not h.carried and not GameState.carrying and h.drops == 1, "crossing 30 HP knocks it loose and clears the flag")
	var gap := Vector2(h.global_position.x - p.global_position.x, h.global_position.z - p.global_position.z).length()
	_check(gap > 1.5, "the dropped core lands away from the player (%.1f m)" % gap)
	await _frames(50) # past the pickup cooldown
	p.global_position = h.global_position
	await _frames(4)
	_check(h.carried, "the dropped core can be picked back up")
	# Death drops it where the player fell.
	GameState.on_player_died("probe")
	GameState.current_state = GameState.State.PLAYING
	await _frames(2)
	_check(not h.carried and not GameState.carrying and h.drops == 2, "dying drops the core")
	await _frames(50)
	p.global_position = Vector3(5, 0, 5)
	await _frames(3)
	p.global_position = h.global_position
	await _frames(4)
	_check(h.carried, "picked up again after the death drop")
	p.global_position = Vector3(30, 0, 1)
	await _frames(4)
	_check(h.delivered and GameState.is_task_done("haul_t"), "carrying it into the ring completes the task")
	_check(not GameState.carrying, "delivery clears the carrying flag")
	h.queue_free()
	p.queue_free()
	GameState.reset_tasks()
	await _frames(3)

func _campaign() -> void:
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var hauls: Array = []
		for t in def.get("tasks", []):
			if t.get("type", "") == "haul":
				hauls.append(t)
		if hauls.is_empty():
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
		for t in hauls:
			var from: Vector3 = t.get("pos", Vector3.ZERO)
			var to: Vector3 = t.get("to", Vector3.ZERO)
			var a := NavigationServer3D.map_get_closest_point(map, from)
			var b := NavigationServer3D.map_get_closest_point(map, to)
			_check(Vector2(a.x - from.x, a.z - from.z).length() < 2.0, "%s haul core at %s is on walkable ground" % [id, from])
			_check(Vector2(b.x - to.x, b.z - to.z).length() < 2.0, "%s uplink ring at %s is on walkable ground" % [id, to])
			var route := NavigationServer3D.map_get_path(map, a, b, true)
			var ends := route.size() > 1 and Vector2(route[-1].x - to.x, route[-1].z - to.z).length() < 2.5
			var length := 0.0
			for i in range(1, route.size()):
				length += route[i].distance_to(route[i - 1])
			_check(ends, "%s core reaches the uplink on the navmesh (%.0f m)" % [id, length])
		level.queue_free()
		await _frames(4)
