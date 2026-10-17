extends Node
## Probe: a killed robot's wreck is a physics body, not a canned topple tween.
## (1) on flat floor it falls over (> 50 deg off upright), away from the
##     shooter, and comes to rest on the floor, not in it;
## (2) killed at the edge of a 3 m catwalk with the shot pushing it off, it
##     goes over the edge and lands on the floor below (the tween toppled it
##     in place on the catwalk), for a skinned rig (GUNNER) and a rigid model
##     (REAPER);
## (3) the wreck and its physics body are gone within 7 s;
## (4) a boss (score >= 1000) keeps the scripted topple its kill-cam frames.
##   godot --headless --path . --audio-driver Dummy res://tests/wreck_physics_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	var n := int(ceil(sec / 0.25))
	for i in n:
		await get_tree().create_timer(0.25).timeout

func _ready() -> void:
	_run.call_deferred()

func _box(size: Vector3, pos: Vector3) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_position = pos

func _spawn(scene: String, pos: Vector3, shooter: Node3D) -> EnemyBase:
	var e := (load("res://scenes/enemies/%s.tscn" % scene) as PackedScene).instantiate() as EnemyBase
	add_child(e)
	e.global_position = pos
	await _wait(0.75)
	e.set_physics_process(false)
	e.velocity = Vector3.ZERO
	e.global_position = pos
	e._last_known_target_pos = shooter.global_position
	e._has_last_known = true
	return e

func _kill(e: EnemyBase, shooter: Node3D) -> void:
	e.hp.apply_damage(99999.0, shooter)

func _tilt_deg(t: Transform3D) -> float:
	return rad_to_deg(t.basis.orthonormalized().y.angle_to(Vector3.UP))

## The wreck's transform when its WreckBody settles (asleep after 1 s, or the
## 2.2 s tumble cap) and freezes, just before the sink. Waited on the physics
## timeline, up to 5 game seconds. Empty if it never settles.
##
## It used to sample the robot every 0.1 s of process time for 3 s and want two
## samples within 1 cm. A wreck still moving at the tumble cap freezes and goes
## straight into the sink (always moving), so it read as "never comes to rest"
## on CI (#302) though the game had settled it like any other.
func _rest(e: EnemyBase) -> Array:
	var got: Array = []
	var wb: WreckBody = null
	var t := 0.0
	while got.is_empty() and t < 5.0:
		if wb == null:
			for b in get_tree().get_nodes_in_group("wreck_bodies"):
				if b is WreckBody and (b as WreckBody).follower == e:
					wb = b
					wb.settled.connect(func() -> void:
						got.append(e.global_transform)
						print("  (settled after %.2f game s, %s)" % [wb._t, "asleep" if wb.sleeping else "tumble cap"]),
						CONNECT_ONE_SHOT)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return got

func _run() -> void:
	_box(Vector3(120, 1, 120), Vector3(0, -0.5, 0)) # floor, top at y = 0
	var shooter := Node3D.new()
	add_child(shooter)

	# 1. Flat floor: falls over, away from the shot, rests on the floor.
	shooter.global_position = Vector3(-30, 1.5, 0)
	var e := await _spawn("gunner", Vector3(-24, 0, 0), shooter)
	var start := e.global_position
	_kill(e, shooter)
	var r := await _rest(e)
	if not r.is_empty():
		var t: Transform3D = r[0]
		var away := (t.origin - start).dot(Vector3.RIGHT)
		_check("flat floor: the wreck falls over", _tilt_deg(t) > 50.0, "tilt %.0f deg" % _tilt_deg(t))
		_check("flat floor: it falls away from the shooter", away > 0.3, "moved %.2f m along the shot" % away)
		_check("flat floor: it rests on the floor, not in it", t.origin.y > -0.6, "origin y %.2f" % t.origin.y)
	else:
		_check("flat floor: the wreck comes to rest", false)

	# 2. Catwalk edge, 3 m up: the shot pushes it over the edge.
	_box(Vector3(6, 0.4, 4), Vector3(-3, 2.8, 12)) # top at y = 3.0, edge at x = 0
	var wrecks: Array = []
	for scene: String in ["gunner", "reaper"]:
		shooter.global_position = Vector3(-8, 4.5, 12)
		var w := await _spawn(scene, Vector3(-0.45, 3.0, 12), shooter)
		_kill(w, shooter)
		var rw := await _rest(w)
		if not rw.is_empty():
			var y: float = (rw[0] as Transform3D).origin.y
			_check("%s goes off the catwalk edge and lands below" % scene, y < 1.5 and y > -0.6,
				"rests at y %.2f (catwalk top 3.0, floor 0)" % y)
		else:
			_check("%s wreck comes to rest" % scene, false)
		wrecks.append(w)
		await _wait(0.5)

	# 3. Cleaned up.
	await _wait(5.0)
	var left := 0
	for w in wrecks + [e]:
		if is_instance_valid(w):
			left += 1
	_check("wrecks are freed within 7 s", left == 0, "%d left" % left)
	_check("no wreck bodies left behind", get_tree().get_nodes_in_group("wreck_bodies").is_empty(),
		"%d left" % get_tree().get_nodes_in_group("wreck_bodies").size())

	# 4. Bosses keep the scripted topple (no wreck body).
	shooter.global_position = Vector3(30, 1.5, -20)
	var boss := await _spawn("smasher", Vector3(20, 0, -20), shooter)
	_kill(boss, shooter)
	await _wait(0.5)
	_check("a boss gets no wreck body", get_tree().get_nodes_in_group("wreck_bodies").is_empty())

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
