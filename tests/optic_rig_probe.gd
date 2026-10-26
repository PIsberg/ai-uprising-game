extends Node3D
## Probe: the OPTIC's rig. utility_robot.glb is cut offline into Body, WheelL,
## WheelR, TorchL and TorchR (tools/blender/cfg_utility_robot_parts.json);
## EnemyOptic._setup_rig takes each axle from its wheel's bounds and the torches'
## hinges and tips from measured constants, and _tick_rig rolls the wheels and
## swings the torches onto the player through the cutting beam. Points are
## measured once at rest in each part's own frame and followed through its
## transform, read with the chassis lean and the first-contact bristle taken out.
## (1) the parts are there, each axle is its wheel's centre, each hinge sits on
##     the barrel at the top of its torch and each tip on the welding point
##     (the torch's farthest vertices from the hinge, read headless);
## (2) chasing: the wheels turn forward (their fronts dip) by the distance
##     rolled over their radius (within 20%) while the torches hang still;
## (3) the beam's charge: both tips rise 0.3+ m and each torch points its tip
##     down the hinge-to-player line within 0.12 rad; the beam's origin is the
##     right tip (within 0.02 m of the tip followed through the mesh);
## (4) the beam burns the player (health drops while it sweeps);
## (5) the beam over: both torches back within 0.04 m of rest; stopped, the
##     wheels are still.
##   godot --headless --path . --audio-driver Dummy res://tests/optic_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _parts := {}   ## name -> MeshInstance3D
var _marks := {}   ## name -> [part name, point in the part's frame]
var _rest := {}    ## name -> body-frame point at rest
var _axle := Vector3.ZERO
var _r := 0.12

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

func _frame() -> Transform3D:
	return _e.call("rig_frame") as Transform3D

## A part's bounds in the body frame.
func _box(mi: MeshInstance3D) -> AABB:
	return _frame().affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())

## Remember a body-frame point as a point in `part`'s own frame.
func _mark(name: String, part: String, body_p: Vector3) -> void:
	var mi: MeshInstance3D = _parts[part]
	_marks[name] = [part, mi.global_transform.affine_inverse() * (_frame() * body_p)]

## Where a mark is now, in the body frame with the chassis nudges taken out:
## RobotModel leans the `Mesh` node the parts hang under and EnemyBase rears
## the `Model` node above it at first contact (the bristle), so the mark is
## read in the Mesh node's frame and put back through the fitted base.
func _at(name: String) -> Vector3:
	var m: Array = _marks[name]
	var mi: MeshInstance3D = _parts[m[0]]
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * (m[1] as Vector3)))

## A mark's world position, as the renderer places it.
func _world(name: String) -> Vector3:
	var m: Array = _marks[name]
	var mi: MeshInstance3D = _parts[m[0]]
	return mi.global_transform * (m[1] as Vector3)

## Angle of the left wheel's mark about its axle: 0 at the front, rising as
## the wheel rolls forward (the front of a wheel rolling forward moves down
## toward the contact patch while its top moves forward).
func _phi() -> float:
	var p := _at("wheel")
	return atan2(_axle.y - p.y, _axle.z - p.z)

func _mirror(v: Vector3, side: int) -> Vector3:
	return Vector3(v.x * (-1.0 if side == 0 else 1.0), v.y, v.z)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/optic.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	# The rig sets itself up on the tick after RobotModel's deferred fit lands,
	# and deferred calls run on PROCESS frames: a loaded CI runner packs up to
	# 8 physics steps into one frame, so a physics-time wait ran out before
	# the fit had had a frame. Count process frames (up to about 4 s), then
	# step back onto the physics clock the rig poses on.
	var t := 0.0
	var frames := 0
	while frames < 240 and not bool(_e.get("_rig_ready")):
		await get_tree().process_frame
		frames += 1
	await get_tree().physics_frame
	var names := ["Body", "WheelL", "WheelR", "TorchL", "TorchR"]
	for n in names:
		_parts[n] = _e.find_child(n, true, false) as MeshInstance3D
	var torches: Array = _e.get("_torch")
	var have := bool(_e.get("_rig_ready")) and not _parts.values().has(null) and torches[0] != null
	_check("rig set up on the five offline parts", have, "(ready %s, parts %s)" % [_e.get("_rig_ready"), _parts.keys()])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	var axles: Array = _e.get("_axle")
	_axle = axles[0]
	_r = _e.get("_wheel_r")
	var wb := _box(_parts["WheelL"])
	for side in 2:
		var b := _box(_parts["WheelL" if side == 0 else "WheelR"])
		var d: float = (axles[side] as Vector3).distance_to(b.get_center())
		_check("%s axle is the wheel's centre on the model" % ["left", "right"][side], d < 0.01 and absf(_r - b.size.y * 0.5) < 0.01,
			"(axle %s, centre %s, r %.3f)" % [axles[side], b.get_center(), _r])
	var hinge_c: Vector3 = _e.get("TORCH_HINGE")
	var tip_c: Vector3 = _e.get("TORCH_TIP")
	for side in 2:
		var mi: MeshInstance3D = _parts["TorchL" if side == 0 else "TorchR"]
		var pts := PartRig.body_points(_e, mi)
		var hinge := _mirror(hinge_c, side)
		var barrel := AimedPart.band_mean(pts, Vector3.UP, 0.08)
		var point := AimedPart.far_mean(pts, hinge, 0.03)
		var dh := hinge.distance_to(barrel)
		var dt := _mirror(tip_c, side).distance_to(point)
		_check("%s hinge sits on the barrel at the top of the torch" % mi.name, dh < 0.08, "(hinge %s, barrel %s, %.3f m)" % [hinge, barrel, dh])
		_check("%s tip is the welding point" % mi.name, dt < 0.03, "(tip %s, point %s, %.3f m)" % [_mirror(tip_c, side), point, dt])
	# Marks: the front of the left wheel at axle height, each torch's tip.
	_mark("wheel", "WheelL", Vector3(_axle.x, _axle.y, wb.position.z))
	_mark("TorchL", "TorchL", _mirror(tip_c, 0))
	_mark("TorchR", "TorchR", _mirror(tip_c, 1))
	for k in _marks:
		_rest[k] = _at(k)
	print("  rest %s" % _rest)

	# (2) Chase a far player: the wheels roll forward by the distance covered.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -31) # in sight (34 m), past the beam's 26 m
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("_beam_cd", 999.0) # no beam through the chase
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	var phi_prev := _phi()
	var phi_total := 0.0
	var odometer := 0.0
	var speed_max := 0.0
	var torch_dev := 0.0
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var phi := _phi()
		phi_total += wrapf(phi - phi_prev, -PI, PI)
		phi_prev = phi
		var ground := Vector2(_e.velocity.x, _e.velocity.z).length()
		odometer += ground * dt
		speed_max = maxf(speed_max, ground)
		for n in ["TorchL", "TorchR"]:
			torch_dev = maxf(torch_dev, _at(n).distance_to(_rest[n]))
	_check("optic actually rolled toward the player", speed_max > 2.0, "(%.1f m/s)" % speed_max)
	_check("wheels turned forward (fronts dipping)", phi_total > 1.0, "(%.2f rad)" % phi_total)
	var ratio := phi_total * _r / maxf(odometer, 0.001)
	_check("wheels turned by the distance rolled over their radius", absf(ratio - 1.0) < 0.2, "(%.2f rad x %.3f m vs %.2f m: x%.2f)" % [phi_total, _r, odometer, ratio])
	_check("torches hang still on the roll", torch_dev < 0.04, "(%.3f m)" % torch_dev)

	# (3) The beam: plant the player at 12 m and let the attack start it.
	player.global_position = _e.global_position + Vector3(0, 0, -12)
	for i in 2:
		await get_tree().physics_frame
	_e.set("_beam_cd", 0.0)
	_e.call("set_state", 4) # ATTACK
	t = 0.0
	while t < 1.0 and not bool(_e.call("_beaming")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("the beam started on the player at 12 m", bool(_e.call("_beaming")))
	var rise := [0.0, 0.0]
	var misaim := [INF, INF]
	var origin_off := INF
	var chest: Vector3 = player.global_position + Vector3.UP * 0.7
	t = 0.0
	while t < 0.75 and float(_e.get("_beam_windup")) > 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		for side in 2:
			var n := "TorchL" if side == 0 else "TorchR"
			rise[side] = maxf(rise[side], _at(n).y - (_rest[n] as Vector3).y)
			var hinge_w: Vector3 = _frame() * _mirror(hinge_c, side)
			var tip_w := _world(n)
			misaim[side] = minf(misaim[side], (tip_w - hinge_w).angle_to(chest - hinge_w))
		var tips: Array = _e.get("_torch_tip")
		origin_off = minf(origin_off, (_e.call("_beam_origin") as Vector3).distance_to(_world("TorchR")))
		origin_off = maxf(origin_off, (tips[1] as Vector3).distance_to(_world("TorchR")))
	for side in 2:
		var n := "TorchL" if side == 0 else "TorchR"
		_check("charge: %s raised onto the player" % n, rise[side] >= 0.3, "(tip up %.3f m)" % rise[side])
		_check("charge: %s points down the hinge-to-player line" % n, misaim[side] < 0.12, "(%.3f rad)" % misaim[side])
	_check("the beam leaves the right torch's tip", origin_off < 0.02, "(%.3f m off the tip)" % origin_off)

	# (4) It burns.
	var hp_before: float = php.current_health
	t = 0.0
	while t < 1.3 and bool(_e.call("_beaming")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("the beam burned the player", php.current_health < hp_before - 0.5, "(%.1f -> %.1f)" % [hp_before, php.current_health])
	_check("the beam ended", not bool(_e.call("_beaming")))

	# (5) Over: torches back down; stopped, wheels still.
	_e.set("_beam_cd", 999.0)
	t = 0.0
	while t < 0.8:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var worst := 0.0
	for n in ["TorchL", "TorchR"]:
		worst = maxf(worst, _at(n).distance_to(_rest[n]))
	_check("beam over: torches hanging at rest again", worst < 0.04, "(%.3f m)" % worst)
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.velocity = Vector3.ZERO
	t = 0.0
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	phi_prev = _phi()
	t = 0.0
	while t < 0.3:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("stopped: wheels still", absf(wrapf(_phi() - phi_prev, -PI, PI)) < 0.05)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
