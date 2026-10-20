extends Node
## Dev probe: the NEURAL UPLINK (NeuralUplink, scripts/systems/neural_uplink.gd).
## Looking at a robot you have HIJACKED and pressing interact moves your mind
## into it: you drive and fire that chassis while your body stands frozen.
## (1) a hijacked robot in the crosshair becomes the candidate; an unhijacked one does not;
## (2) interact links: body frozen, chassis camera current, weapons off;
## (3) move input drives the CHASSIS forward and leaves the body where it stood;
## (4) fire input lands chassis shots on a hostile robot;
## (5) interact again unlinks: body back in control, the ridden chassis burns out;
## (6) damage to the abandoned body snaps the link ("body");
## (7) the ride clock running out ends it ("time");
## (8) an escort (mission-critical ally) and an unhijacked robot refuse the link;
## (9) a flying chassis climbs on jump;
## (10) signature attacks (#343), each through the uplink's own fire input: a
##      ridden RAPTOR's belly gun strafes a 3-round burst on one pull; a ridden
##      SEEKER dives at the aim point and detonates (the robot there is hurt, the
##      chassis is spent and the ride ends); a ridden GUNNER spins up (its
##      cadence shortens while the trigger is held); a ridden BRUTE's ground
##      pound hits a robot BEHIND it, which the generic frontal slam cannot. (The
##      HOWITZER has 640 HP, over HIJACK_BOSS_HP: it cannot be ridden at all.)
##   godot --headless --path . --audio-driver Dummy res://tests/neural_uplink_probe.tscn

const ENEMY := "res://scenes/enemies/android.tscn"
const DRONE := "res://scenes/enemies/drone.tscn"

var _fails := 0
var _reasons: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)

func _spawn(path: String, pos: Vector3) -> Node3D:
	var e: Node3D = load(path).instantiate()
	get_tree().root.add_child(e)
	e.global_position = pos
	return e

func _run() -> void:
	var script: Script = load("res://scripts/systems/neural_uplink.gd")
	_check(script != null, "NeuralUplink script exists")
	if script == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	get_tree().root.add_child(floor_body)

	var player: Node3D = load("res://scenes/player/player.tscn").instantiate()
	get_tree().root.add_child(player)
	player.global_position = Vector3.ZERO
	player.get("hp").invulnerable = true # robots shooting the frozen body must not skew steps 1-5
	var uplink: Node = player.get_node_or_null("NeuralUplink")
	_check(uplink != null, "player carries a NeuralUplink")
	if uplink == null:
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	uplink.unlinked.connect(func(reason: String): _reasons.append(reason))

	# 1. Candidate: a hijacked robot straight ahead is offered, an unhijacked one is not.
	var a := _spawn(ENEMY, Vector3(0, 0, -6))
	await _frames(10)
	_check(uplink.candidate == null, "unhijacked robot in the crosshair is not a candidate")
	a.hijack(60.0, player)
	await _frames(10)
	_check(uplink.candidate == a, "hijacked robot in the crosshair is the candidate")

	# 2. Link.
	await _tap("interact")
	_check(uplink.robot == a, "interact links to the candidate")
	_check(bool(player.get("linked_out")), "body flagged linked_out")
	_check(a.pilot == player, "chassis knows its pilot")
	_check(get_viewport().get_camera_3d() == uplink.camera, "chassis camera is current")
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	_check(wm.process_mode == Node.PROCESS_MODE_DISABLED, "weapon rack is off while linked")

	# 3. Move: the chassis walks forward, the body stays put.
	var body_at: Vector3 = player.global_position
	var robot_at: Vector3 = a.global_position
	var facing: Vector3 = -a.global_transform.basis.z # the ride starts looking where the chassis faces
	facing.y = 0.0
	facing = facing.normalized()
	Input.action_press("move_forward")
	await _frames(40)
	Input.action_release("move_forward")
	var body_moved := Vector2(player.global_position.x - body_at.x, player.global_position.z - body_at.z).length()
	var robot_fwd := (a.global_position - robot_at).dot(facing)
	print("move: body moved %.2f m, chassis forward %.2f m" % [body_moved, robot_fwd])
	_check(body_moved < 0.05, "body does not move on move input")
	_check(robot_fwd > 1.0, "chassis walks forward on move input")

	# 4. Fire at a hostile straight ahead.
	var b := _spawn(ENEMY, a.global_position + facing * 9.0)
	b.hp.invulnerable = false
	await _frames(4)
	var b_before: float = b.hp.current_health
	Input.action_press("fire")
	await _frames(45)
	Input.action_release("fire")
	print("fire: hostile hp %.0f -> %.0f" % [b_before, b.hp.current_health])
	_check(b.hp.current_health < b_before, "chassis fire damages a hostile robot")
	_check(a.hp.is_alive(), "ridden chassis alive while linked")

	# 5. Unlink by hand: control returns, the chassis burns out.
	await _tap("interact")
	await _frames(2)
	_check(uplink.robot == null, "interact again unlinks")
	_check(not bool(player.get("linked_out")), "body back in control")
	_check(get_viewport().get_camera_3d() == player.get("camera"), "player camera current again")
	_check(wm.process_mode != Node.PROCESS_MODE_DISABLED, "weapon rack back on")
	_check(not a.hp.is_alive(), "ridden chassis burns out on unlink")
	_check(_reasons.back() == "exit", "unlink reason is exit (got %s)" % [_reasons.back()])
	if is_instance_valid(b):
		b.queue_free()

	# 6. Damage to the body snaps the link.
	var c := _spawn(ENEMY, Vector3(30, 0, 0))
	await _frames(2)
	c.hijack(60.0, player)
	_check(uplink.begin(c), "begin() links a hijacked robot")
	var shooter := _spawn(ENEMY, Vector3(-30, 0, 0))
	await _frames(2)
	player.get("hp").invulnerable = false
	player.get("hp").apply_damage(float(uplink.BODY_BREAK) + 1.0, shooter)
	player.get("hp").invulnerable = true
	await _frames(2)
	_check(uplink.robot == null and _reasons.back() == "body", "body damage snaps the link (got %s)" % [_reasons.back()])
	shooter.queue_free()

	# 7. The clock.
	var d := _spawn(ENEMY, Vector3(60, 0, 0))
	await _frames(2)
	d.hijack(60.0, player)
	uplink.begin(d)
	uplink.time_left = 0.2
	await _frames(30)
	_check(uplink.robot == null and _reasons.back() == "time", "ride clock ends the link (got %s)" % [_reasons.back()])
	_check(not d.hp.is_alive(), "timed-out chassis burns out")

	# 8. Refusals.
	var e := _spawn(ENEMY, Vector3(90, 0, 0))
	await _frames(2)
	_check(not uplink.begin(e), "unhijacked robot refuses the link")
	e.hijack(60.0, player)
	e.escort_goal = Vector3(100, 0, 0)
	_check(not uplink.begin(e), "escort ally refuses the link")
	e.escort_goal = null

	# 9. A flyer climbs on jump.
	var f := _spawn(DRONE, Vector3(120, 3, 0))
	await _frames(4)
	f.hijack(60.0, player)
	_check(uplink.begin(f), "drone links")
	var y0: float = f.global_position.y
	Input.action_press("jump")
	await _frames(40)
	Input.action_release("jump")
	print("flyer: %.2f -> %.2f m" % [y0, f.global_position.y])
	_check(f.global_position.y > y0 + 1.0, "flying chassis climbs on jump")
	uplink.end("exit")

	# 10. Signature attacks.
	var rp := _spawn("res://scenes/enemies/raptor.tscn", Vector3(-120, 3, 0))
	var rp_t := _spawn(ENEMY, Vector3(-120, 0, -10))
	await _frames(6)
	rp_t.set_physics_process(false)
	rp.hijack(60.0, player)
	_check(uplink.begin(rp), "raptor links")
	var rp_one: float = EnemyBase.PILOT_DPS * rp.pilot_cooldown() # one generic shot
	var r0: float = rp_t.hp.current_health
	uplink.set("_yaw", 0.0)
	var to_t: Vector3 = rp_t.global_position + Vector3.UP * 1.0 - (rp.global_position + Vector3.UP * 1.2)
	uplink.set("_pitch", atan2(to_t.y, Vector2(to_t.x, to_t.z).length()))
	Input.action_press("fire")
	await _frames(2)
	Input.action_release("fire")
	await _frames(30)
	_check(r0 - rp_t.hp.current_health >= rp_one * 1.4, "a ridden raptor's belly gun strafes a burst on one pull (%.0f taken, one shot is %.0f)" % [r0 - rp_t.hp.current_health, rp_one])
	uplink.end("exit")

	var sk := _spawn("res://scenes/enemies/seeker.tscn", Vector3(-160, 1.2, 0))
	var sk_t := _spawn(ENEMY, Vector3(-160, 0, -9))
	await _frames(6)
	sk_t.set_physics_process(false)
	sk.hijack(60.0, player)
	_check(uplink.begin(sk), "seeker links")
	uplink.set("_yaw", 0.0)
	uplink.set("_pitch", -0.1)
	var s0: float = sk_t.hp.current_health
	_reasons.clear()
	Input.action_press("fire")
	await _frames(3)
	Input.action_release("fire")
	await _frames(90)
	_check(sk_t.hp.current_health < s0, "a ridden seeker dives and blasts the robot it aimed at (%.0f -> %.0f)" % [s0, sk_t.hp.current_health])
	_check(not is_instance_valid(sk) and _reasons.has("lost"), "the seeker is spent and the ride ends " + str(_reasons))

	var gn := _spawn("res://scenes/enemies/gunner.tscn", Vector3(-200, 0, 0))
	await _frames(6)
	gn.hijack(60.0, player)
	_check(uplink.begin(gn), "gunner links")
	var c0: float = gn.pilot_cooldown()
	Input.action_press("fire")
	await _frames(90)
	var c1: float = gn.pilot_cooldown()
	Input.action_release("fire")
	_check(c1 < c0 * 0.6, "a ridden gunner spins up (cadence %.2f -> %.2f s)" % [c0, c1])
	uplink.end("exit")

	var br := _spawn("res://scenes/enemies/brute.tscn", Vector3(-240, 0, 0))
	var br_t := _spawn(ENEMY, Vector3(-240, 0, 3)) # BEHIND it (it faces -Z)
	await _frames(6)
	br_t.set_physics_process(false)
	br.hijack(60.0, player)
	_check(uplink.begin(br), "brute links")
	uplink.set("_yaw", 0.0)
	var b0: float = br_t.hp.current_health
	Input.action_press("fire")
	await _frames(3)
	Input.action_release("fire")
	await _frames(10)
	_check(br_t.hp.current_health < b0, "a ridden brute's ground pound hits a robot behind it (%.0f -> %.0f)" % [b0, br_t.hp.current_health])
	uplink.end("exit")

	print("RESULT %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
