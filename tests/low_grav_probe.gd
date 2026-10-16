extends Node3D
## Low-gravity fields (LowGravField, def key `low_grav`). Unit pass on a flat
## floor with the REAL player scene and a real android:
##   - a jump outside the field peaks at the normal ~1.2 m; the same jump
##     inside peaks at least JUMP_LIFT times higher;
##   - a robot dropped inside falls at least 1.5x slower than one outside;
##   - stepping out restores full gravity at once;
##   - a jump-pad style launch inside the field keeps its solved arc (the field
##     does not bend launches);
##   - walking up teaches the rule once.
## Campaign pass: on every level with a field that names a `ledge`, a jump
## from the field's floor clears the ledge's height and the ledge is within
## reach of the field's edge.
##   godot --headless --path . --audio-driver Dummy res://tests/low_grav_probe.tscn

const JUMP_LIFT := 2.5

var _fails: Array[String] = []
var _hints: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
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

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = at
	add_child(sb)
	return sb

## Peak height above the start of a jump fired from the floor at `at`.
func _apex(p: CharacterBody3D, at: Vector3) -> float:
	p.global_position = at
	p.velocity = Vector3.ZERO
	await _frames(20)
	var y0 := p.global_position.y
	p.velocity.y = p.jump_velocity
	var top := y0
	for i in 400:
		await get_tree().physics_frame
		top = maxf(top, p.global_position.y)
		if i > 5 and p.is_on_floor():
			break
	return top - y0

## Seconds a robot takes to fall `h` m onto the floor from `at`.
func _fall_time(r: EnemyBase, at: Vector3) -> float:
	r.global_position = at
	r.velocity = Vector3.ZERO
	var t := 0.0
	for i in 600:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if i > 2 and r.is_on_floor():
			break
	return t

func _unit() -> void:
	print("unit:")
	var floor_body := _box(Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	var field := LowGravField.new()
	field.radius = 5.0
	field.height = 10.0
	field.position = Vector3.ZERO
	add_child(field)
	var p: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.position = Vector3(20, 0.1, 0)
	add_child(p)
	await _frames(20)
	_hints.clear()

	var out := await _apex(p, Vector3(20, 0.1, 0))
	var inside := await _apex(p, Vector3(0, 0.1, 0))
	_check(out > 0.8 and out < 1.6, "outside, a jump peaks normally (%.2f m)" % out)
	_check(inside >= out * JUMP_LIFT, "inside, the same jump peaks %.1fx higher (%.2f m)" % [inside / maxf(out, 0.01), inside])
	_check(_hints.size() == 1 and _hints[0] == LowGravField.TEACH_TEXT, "walking in teaches the rule once (%d)" % _hints.size())

	p.global_position = Vector3(20, 0.1, 0)
	await _frames(4)
	_check(is_equal_approx(p.gravity_scale, 1.0), "stepping out restores full gravity (%.2f)" % p.gravity_scale)

	# A launch inside the field keeps its arc: fly the same launch in and out.
	p.global_position = Vector3(20, 0.1, 0)
	await _frames(10)
	p.launch(Vector3(0, 8, 0), 2.0)
	var top_out := p.global_position.y
	for i in 120:
		await get_tree().physics_frame
		top_out = maxf(top_out, p.global_position.y)
	p.global_position = Vector3(0, 0.1, 0)
	await _frames(10)
	p.launch(Vector3(0, 8, 0), 2.0)
	var top_in := p.global_position.y
	for i in 120:
		await get_tree().physics_frame
		top_in = maxf(top_in, p.global_position.y)
	_check(absf(top_in - top_out) < 0.3, "a launch keeps its arc inside the field (%.2f vs %.2f m)" % [top_in, top_out])
	p.queue_free()
	await _frames(4)

	var r_out: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
	r_out.position = Vector3(20, 4.0, 10)
	add_child(r_out)
	var r_in: EnemyBase = LevelBuilder.enemy_scene("android").instantiate()
	r_in.position = Vector3(0, 4.0, 1)
	add_child(r_in)
	await _frames(30)
	var t_out := await _fall_time(r_out, Vector3(20, 4.0, 10))
	var t_in := await _fall_time(r_in, Vector3(0, 4.0, 1))
	_check(t_in >= t_out * 1.5, "a robot falls slower inside (%.2f s vs %.2f s)" % [t_in, t_out])
	r_out.queue_free()
	r_in.queue_free()
	field.queue_free()
	floor_body.queue_free()
	await _frames(4)

func _campaign() -> void:
	var found := 0
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var jv: float = ((load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Node).get("jump_velocity")
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for e in def.get("low_grav", []):
			found += 1
			if not e.has("ledge"):
				continue
			var at: Vector3 = e["pos"]
			var ledge: Vector3 = e["ledge"]
			var sc: float = float(e.get("scale", LowGravField.DEFAULT_SCALE))
			var apex := jv * jv / (2.0 * g * sc)
			_check(apex >= ledge.y - at.y + 0.4, "%s field at %s: a jump peaks %.1f m, the ledge is %.1f m up" % [id, at, apex, ledge.y - at.y])
			var r: float = float(e.get("radius", 4.0))
			var gap := Vector2(ledge.x - at.x, ledge.z - at.z).length() - r
			_check(gap <= 2.5, "%s ledge at %s is %.1f m past the field's edge (<= 2.5)" % [id, ledge, gap])
	_check(found >= 1, "at least one campaign level authors a low-gravity field (%d)" % found)
	# Built levels: the field's floor and the ledge are where the def says.
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("low_grav", []).is_empty():
			continue
		var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(level)
		await _frames(20)
		var space := level.get_world_3d().direct_space_state
		for e in def["low_grav"]:
			var at: Vector3 = e["pos"]
			var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.5, at + Vector3.DOWN * 1.0, 1)
			var hit := space.intersect_ray(q)
			_check(not hit.is_empty() and absf((hit.position as Vector3).y - at.y) < 0.2, "%s field floor at %s is open ground" % [id, at])
			if e.has("ledge"):
				var ledge: Vector3 = e["ledge"]
				var q2 := PhysicsRayQueryParameters3D.create(ledge + Vector3.UP * 2.0, ledge + Vector3.DOWN * 1.0, 1)
				var h2 := space.intersect_ray(q2)
				_check(not h2.is_empty() and absf((h2.position as Vector3).y - ledge.y) < 0.3,
					"%s ledge at %s is a deck top (hit %s)" % [id, ledge, h2.get("position", "nothing")])
		level.queue_free()
		await _frames(4)
