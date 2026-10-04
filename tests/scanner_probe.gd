extends Node3D
## Vision scanners (vision_scanner.gd): a player in the cone with a clear line
## of sight raises the alarm after detect_time and calls the reinforcement hook
## with the authored squad; out of the cone, or behind a wall, nothing happens;
## the alarm respects max_alarms; a shot-out head never detects again. Then on
## every campaign level that authors "scanners", each alarm squad spawns on the
## built navmesh with a walking route to the player spawn.
##   godot --headless --path . --audio-driver Dummy res://tests/scanner_probe.tscn

var _fails: Array[String] = []
var _calls: Array = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _unit()
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _on_alarm(specs: Array) -> void:
	_calls.append(specs)

## A stand-in player: only the "player" group and a position matter here.
func _make_player(at: Vector3) -> Node3D:
	var p := Node3D.new()
	p.add_to_group("player")
	add_child(p)
	p.global_position = at
	return p

func _scanner(at: Vector3) -> VisionScanner:
	var s := VisionScanner.new()
	s.sweep_deg = 0.0 # stares straight down -Z
	s.tilt_deg = 20.0
	s.reach = 20.0
	s.detect_time = 0.5
	s.cooldown = 1.0
	s.track_time = 0.5
	s.max_alarms = 2
	s.alarm_specs = [{"type": "drone", "pos": Vector3(0, 0, 0)}]
	s.alarm = _on_alarm
	s.position = at
	add_child(s)
	return s

func _unit() -> void:
	print("unit:")
	var s := _scanner(Vector3(0, 4.0, 0))
	await _frames(5)
	# Where the cone centre meets chest height (1.1 m): 2.9 m drop at 20 degrees.
	var hit_d := (4.0 - 1.1) / tan(deg_to_rad(20.0))
	var p := _make_player(Vector3(40, 0, 40)) # far outside
	await _frames(60)
	_check(_calls.is_empty(), "no alarm while the player is out of the cone")
	p.global_position = Vector3(0, 0, -hit_d)
	await _frames(20) # 0.33 s < detect_time
	_check(_calls.is_empty() and s.exposure > 0.0, "exposure builds before the alarm (%.2f)" % s.exposure)
	await _frames(30)
	_check(_calls.size() == 1, "held in the cone past detect_time raises the alarm (%d)" % _calls.size())
	_check(_calls.size() > 0 and (_calls[0] as Array).size() == 1, "alarm hands over the authored squad")
	_check(s.mode == VisionScanner.Mode.TRACK, "scanner locks on after the alarm")

	# Cooldown then a second detection; then max_alarms caps it.
	await _frames(120)
	_check(_calls.size() == 2, "second detection after cooldown alarms again (%d)" % _calls.size())
	await _frames(240)
	_check(_calls.size() == 2, "max_alarms caps the alarms (%d)" % _calls.size())
	s.queue_free()
	p.queue_free()
	await _frames(3)

	# Line of sight: a wall between lens and player blocks detection.
	_calls.clear()
	var s2 := _scanner(Vector3(30, 4.0, 0))
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(6, 6, 0.5)
	wcs.shape = wbs
	wall.add_child(wcs)
	add_child(wall)
	wall.global_position = Vector3(30, 3, -hit_d * 0.5)
	var p2 := _make_player(Vector3(30, 0, -hit_d))
	await _frames(90)
	_check(_calls.is_empty(), "a wall between lens and player blocks detection")
	wall.queue_free()
	p2.queue_free()
	s2.queue_free()
	await _frames(3)

	# Shot out: never detects again.
	_calls.clear()
	var s3 := _scanner(Vector3(60, 4.0, 0))
	await _frames(3)
	var d := s3.find_child("Damageable", true, false) as Damageable
	d.apply_damage(999.0, null)
	var p3 := _make_player(Vector3(60, 0, -hit_d))
	await _frames(90)
	_check(s3.mode == VisionScanner.Mode.DEAD and _calls.is_empty(), "a shot-out scanner is blind")
	p3.queue_free()
	s3.queue_free()
	await _frames(3)

func _campaign() -> void:
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("scanners", []).is_empty():
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
		var built := get_tree().get_nodes_in_group("scanner").size()
		_check(built == def["scanners"].size(), "%s builds all %d scanners (%d)" % [id, def["scanners"].size(), built])
		var k := 0
		for sc in def["scanners"]:
			for e in sc.get("alarm", []):
				var at: Vector3 = e.get("pos", Vector3.ZERO)
				var near := NavigationServer3D.map_get_closest_point(map, at)
				var on := Vector2(near.x - at.x, near.z - at.z).length() < 2.0
				var route := NavigationServer3D.map_get_path(map, near, NavigationServer3D.map_get_closest_point(map, spawn), true)
				var ends := route.size() > 1 and Vector2(route[-1].x - spawn.x, route[-1].z - spawn.z).length() < 3.0
				var flyer: bool = String(e.get("type", "")) in ["drone", "seeker", "raptor", "whirlwind"]
				_check(flyer or (on and ends), "%s scanner %d alarm %s at %s spawns on walkable ground with a route" % [id, k, e.get("type", ""), at])
			k += 1
		level.queue_free()
		await _frames(4)