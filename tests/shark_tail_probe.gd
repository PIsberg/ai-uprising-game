extends Node3D
## Probe: RAZORFIN swims with its tail. robot_shark.glb is cut offline into
## Body and Tail (hinged at the caudal peduncle); EnemyShark._tick_tail sweeps
## it. The tail tip (the rear of the Tail's bounds on the midline) is measured
## once at rest in the part's own frame and followed through its transform,
## read in the `Model/Mesh` node's frame and put back through the fitted base
## so the flyer's bank and the breach's pitch are taken out.
## (1) the Tail and Body parts are there and the hinge sits at the peduncle
##     (60-80% of the way from the nose to the tail tip, at the Tail's front);
## (2) holding station the tail only sways lazily (tip under 0.12 m aside);
## (3) swimming toward the player at speed the tip swings 0.2+ m to each
##     side and reverses 3+ times in a second;
## (4) in the first half of a breach it beats harder (0.3+ m aside) and
##     faster (3+ reversals in 0.6 s); in the dive it straightens (under 0.1 m)
## (5) nothing else swings: the Body's nose stays within 0.03 m.
##   godot --headless --path . --audio-driver Dummy res://tests/shark_tail_probe.tscn

var ok := true
var _e: CharacterBody3D
var _tail: MeshInstance3D
var _body: MeshInstance3D
var _tip_local := Vector3.ZERO
var _nose_local := Vector3.ZERO

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _box(mi: MeshInstance3D) -> AABB:
	return _e.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())

## A part-local point in the body frame with the chassis bank and the
## breach's pitch taken out.
func _read(mi: MeshInstance3D, local: Vector3) -> Vector3:
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * local))

func _tip() -> Vector3:
	return _read(_tail, _tip_local)

## Sample the tip's sideways offset for `seconds`: [max |x|, reversals].
func _sample(seconds: float) -> Array:
	var worst := 0.0
	var reversals := 0
	var prev := _tip().x
	var dir := 0
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var x := _tip().x
		worst = maxf(worst, absf(x))
		var d := signf(x - prev)
		if d != 0.0 and absf(x - prev) > 0.004:
			if dir != 0 and int(d) != dir:
				reversals += 1
			dir = int(d)
		prev = x
	return [worst, reversals]

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -6.5, 0)
	floor_body.add_child(cs)
	add_child(floor_body)
	_e = (load("res://scenes/enemies/shark.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, -1.7, 0)
	var t := 0.0
	while t < 2.0 and not bool(_e.get("_tail_tried")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_tail = _e.find_child("Tail", true, false) as MeshInstance3D
	_body = _e.find_child("Body", true, false) as MeshInstance3D
	var rigged: bool = _tail != null and _body != null and not (_e.get("_tail_e") as Array).is_empty()
	_check("tail and body parts found and rigged", rigged, "(tried %s)" % _e.get("_tail_tried"))
	if not rigged:
		print("RESULT FAIL")
		get_tree().quit()
		return
	var pivot: Vector3 = _e.get("_tail_pivot")
	var tb := _box(_tail)
	var bb0 := _box(_body)
	# The peduncle: about three quarters of the way from the nose to the tail tip.
	var along: float = (pivot.z - bb0.position.z) / (tb.end.z - bb0.position.z)
	_check("hinge sits at the peduncle", along > 0.6 and along < 0.8 and absf(pivot.x) < 0.01 and absf(pivot.z - tb.position.z) < 0.05, "(%s, %.0f%% of the length)" % [pivot, along * 100.0])
	_tip_local = _tail.global_transform.affine_inverse() * (_e.global_transform * Vector3(0, tb.get_center().y, tb.end.z))
	var bb := _box(_body)
	_nose_local = _body.global_transform.affine_inverse() * (_e.global_transform * Vector3(0, bb.get_center().y, bb.position.z))
	var nose_rest := _read(_body, _nose_local)
	print("  tip at rest %s, nose %s" % [_tip(), nose_rest])

	# (2) Holding station: no target, no movement.
	_e.set("move_speed", 0.0)
	var s := await _sample(1.0)
	_check("holding station the tail only sways", float(s[0]) < 0.12, "(%.3f m, %d reversals)" % [s[0], s[1]])

	# (3) Swimming: a player well past the preferred range, breach parked.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -30)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0
	_e.set("move_speed", 7.0)
	_e.set("target", player)
	_e.set("_breach_cd", 999.0)
	_e.call("set_state", 3) # CHASE: cruises toward it
	await _sample(0.4) # up to speed
	s = await _sample(1.0)
	var speed := Vector2(_e.velocity.x, _e.velocity.z).length()
	_check("it actually swims", speed > 3.0, "(%.1f m/s)" % speed)
	_check("swimming, the tail swings wide", float(s[0]) >= 0.2, "(%.3f m)" % s[0])
	_check("swimming, the tail beats", int(s[1]) >= 3, "(%d reversals in 1 s)" % s[1])
	var nose := _read(_body, _nose_local)
	_check("the body itself does not swing", nose.distance_to(nose_rest) < 0.03, "(%.3f m)" % nose.distance_to(nose_rest))

	# (4) A breach: thrust beats on the climb, straight on the dive.
	player.global_position = _e.global_position + (-_e.global_transform.basis.z) * 6.0 + Vector3(0, 1.8, 0)
	_e.call("set_state", 4) # ATTACK
	_e.call("_start_breach")
	s = await _sample(0.6)
	_check("the breach's climb beats the tail hard", float(s[0]) >= 0.3, "(%.3f m)" % s[0])
	_check("and fast", int(s[1]) >= 3, "(%d reversals in 0.6 s)" % s[1])
	t = 0.0
	while t < 0.45:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	s = await _sample(0.2)
	_check("the dive trails the tail straight", float(s[0]) < 0.1, "(%.3f m)" % s[0])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
