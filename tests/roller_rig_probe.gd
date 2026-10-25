extends Node3D
## Probe: the ROLLER's monowheel rig. wheeled_robot.glb is cut offline into
## Body, Wheel, ArmL and ArmR (tools/blender/cfg_wheeled_robot_parts.json);
## EnemyRoller._setup_rig takes the axle and the shoulders from the parts'
## bounds and _tick_rig rolls, rears, tips and whips them. Points are measured
## once at rest in each part's own frame and followed through its transform.
## (1) the parts are there and the axle and shoulders land on the model
##     (the wheel's centre and the arms' innermost points, read headless);
## (2) chasing: the wheel turns forward (its front dips) by the distance
##     rolled over its radius (within 20%) while the claws only flex (and lean);
## (3) the ram's plant: the claws sweep back 0.12+ m, the head rears back
##     0.03+ m and the wheel spins 2+ rad on the spot;
## (4) the charge: the claws lash forward 0.12+ m of rest, the head tips in;
## (5) stopped: claws and head back within 0.03 m of rest, the wheel still.
##   godot --headless --path . --audio-driver Dummy res://tests/roller_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _parts := {}   ## name -> MeshInstance3D
var _marks := {}   ## name -> [part name, point in the part's frame]
var _rest := {}    ## name -> body-frame point at rest
var _axle := Vector3.ZERO
var _r := 0.3

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var region := NavigationRegion3D.new()
	add_child(region)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## A part's bounds in the body frame.
func _box(mi: MeshInstance3D) -> AABB:
	return _e.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())

## Remember a body-frame point as a point in `part`'s own frame.
func _mark(name: String, part: String, body_p: Vector3) -> void:
	var mi: MeshInstance3D = _parts[part]
	_marks[name] = [part, mi.global_transform.affine_inverse() * (_e.global_transform * body_p)]

## Where a mark is now, in the body frame.
func _at(name: String) -> Vector3:
	var m: Array = _marks[name]
	var mi: MeshInstance3D = _parts[m[0]]
	return _e.global_transform.affine_inverse() * (mi.global_transform * (m[1] as Vector3))

## Angle of the wheel mark about the axle: 0 at the front, rising as the
## wheel rolls forward (the front of a wheel rolling forward moves down
## toward the contact patch while its top moves forward).
func _phi() -> float:
	var p := _at("wheel")
	return atan2(_axle.y - p.y, _axle.z - p.z)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/roller.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	var t := 0.0
	while t < 2.0 and not bool(_e.get("_rig_ready")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	for n in ["Body", "Wheel", "ArmL", "ArmR"]:
		_parts[n] = _e.find_child(n, true, false) as MeshInstance3D
	var have := bool(_e.get("_rig_ready")) and not _parts.values().has(null)
	_check("rig set up on the four offline parts", have, "(ready %s, parts %s)" % [_e.get("_rig_ready"), _parts.keys()])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	_axle = _e.get("_axle")
	_r = _e.get("_wheel_r")
	var wb := _box(_parts["Wheel"])
	_check("axle is the wheel's centre on the model", _axle.distance_to(Vector3(0.03, 0.33, 0.08)) < 0.04 and absf(_r - 0.33) < 0.03,
		"(axle %s r %.3f)" % [_axle, _r])
	var pivots: Array = _e.get("_arm_pivot")
	for side in 2:
		var mi: MeshInstance3D = _parts["ArmL" if side == 0 else "ArmR"]
		var pts := PartRig.body_points(_e, mi)
		var shoulder := AimedPart.band_mean(pts, Vector3.RIGHT if side == 0 else Vector3.LEFT, 0.05)
		var d: float = (pivots[side] as Vector3).distance_to(shoulder)
		_check("%s shoulder sits where the coil leaves the drum" % mi.name, d < 0.08, "(pivot %s, innermost %s, %.3f m)" % [pivots[side], shoulder, d])
	# Marks: the front of the tire at axle height, each claw's front-most
	# point, the head's top.
	_mark("wheel", "Wheel", Vector3(_axle.x, _axle.y, wb.position.z))
	for n in ["ArmL", "ArmR"]:
		var b := _box(_parts[n])
		var c := b.get_center()
		_mark(n, n, Vector3(c.x, c.y, b.position.z))
	var hb := _box(_parts["Body"])
	_mark("head", "Body", Vector3(hb.get_center().x, hb.end.y, hb.get_center().z))
	for k in _marks:
		_rest[k] = _at(k)
	print("  rest %s" % _rest)

	# (2) Chase a far player: the wheel rolls forward by the distance covered.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -26) # in sight, past the 11 m ram band for the whole run
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	var phi_prev := _phi()
	var phi_total := 0.0
	var odometer := 0.0
	var speed_max := 0.0
	var claw_dev := 0.0
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var phi := _phi()
		phi_total += wrapf(phi - phi_prev, -PI, PI)
		phi_prev = phi
		var fwd: float = _e.velocity.dot(-_e.global_transform.basis.z)
		odometer += fwd * dt
		speed_max = maxf(speed_max, fwd)
		for n in ["ArmL", "ArmR"]:
			claw_dev = maxf(claw_dev, absf(_at(n).z - (_rest[n] as Vector3).z))
	_check("roller actually rolled toward the player", speed_max > 3.0, "(%.1f m/s)" % speed_max)
	_check("wheel turned forward (front dipping)", phi_total > 1.0, "(%.2f rad)" % phi_total)
	var ratio := phi_total * _r / maxf(odometer, 0.001)
	_check("wheel turned by the distance rolled over its radius", absf(ratio - 1.0) < 0.2, "(%.2f rad x %.3f m vs %.2f m: x%.2f)" % [phi_total, _r, odometer, ratio])
	# The chassis lean (RobotModel, 0.14 rad at speed) carries the claws about
	# 0.15 m; the plant's cock moves them 0.4 m.
	_check("claws only flex on the roll", claw_dev < 0.22, "(%.3f m)" % claw_dev)

	# (3) The plant: cock, rear, spin up on the spot.
	_e.set("_ram_windup_t", 0.35)
	var claw_back := 0.0
	var head_back := 0.0
	var spun_still := 0.0
	phi_prev = _phi()
	t = 0.0
	while t < 0.33:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var phi := _phi()
		var d := wrapf(phi - phi_prev, -PI, PI)
		phi_prev = phi
		if Vector2(_e.velocity.x, _e.velocity.z).length() < 1.0:
			spun_still += d
		for n in ["ArmL", "ArmR"]:
			claw_back = maxf(claw_back, _at(n).z - (_rest[n] as Vector3).z)
		head_back = maxf(head_back, _at("head").z - (_rest["head"] as Vector3).z)
	_check("plant: claws cocked back", claw_back >= 0.12, "(%.3f m)" % claw_back)
	_check("plant: drum reared back over the wheel", head_back >= 0.03, "(head %.3f m back)" % head_back)
	_check("plant: wheel spun up on the spot", spun_still >= 2.0, "(%.2f rad while stopped)" % spun_still)

	# (4) The charge: lash forward, tip in.
	t = 0.0
	while t < 0.2 and not bool(_e.get("_ramming")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("the ram launched after the plant", bool(_e.get("_ramming")))
	var claw_fwd := INF
	var head_fwd := INF
	t = 0.0
	while t < 0.6 and bool(_e.get("_ramming")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		for n in ["ArmL", "ArmR"]:
			claw_fwd = minf(claw_fwd, _at(n).z - (_rest[n] as Vector3).z)
		head_fwd = minf(head_fwd, _at("head").z - (_rest["head"] as Vector3).z)
	_check("charge: claws lashed forward", claw_fwd <= -0.12, "(%.3f m)" % claw_fwd)
	_check("charge: drum tipped into it", head_fwd <= -0.03, "(head %.3f m)" % head_fwd)

	# (5) Stop: everything back to rest, wheel still.
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.velocity = Vector3.ZERO
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var worst := 0.0
	for n in ["ArmL", "ArmR", "head"]:
		worst = maxf(worst, _at(n).distance_to(_rest[n]))
	_check("stopped: claws and head back at rest", worst < 0.03, "(%.3f m)" % worst)
	phi_prev = _phi()
	t = 0.0
	while t < 0.3:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("stopped: wheel still", absf(wrapf(_phi() - phi_prev, -PI, PI)) < 0.05)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
