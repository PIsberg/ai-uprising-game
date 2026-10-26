extends Node3D
## Probe: the WHIRLWIND's blade rig. reaper_whirlwind.glb is cut offline into
## Core and Blades (tools/blender/cfg_reaper_whirlwind_parts.json);
## EnemyWhirlwind._setup_rig shifts the model so the fist the blades hang from
## sits on the body's axis and _tick_rig whirls, revs and lifts the blades
## about it while the core keeps still. A tip is marked once at rest in the
## blades' own frame and followed through their transform in the body frame.
## (1) the parts are there, the blades' root sits on the axis (within 0.08 m,
##     HUB_Y up) and the core's centre is on the body (within 0.35 m; the box
##     fit had it 0.9 m off);
## (2) idle: the blades turn at SPIN_IDLE (1.6 rad/s, measured from the tip
##     within 0.4) with the tip at its rest height;
## (3) with you in sight: the whirl runs up to spin_speed (7.5, measured within 1);
## (4) a dive: the whirl revs to SPIN_DIVE (18, measured 15+) and the blades
##     lift, the tip rising 0.5+ m;
## (5) the dive over: back to spin_speed and the tip back at rest height;
## (6) dead: the whirl is winding down 0.3 s in (under 5 rad/s from 7.5);
## (7) throughout, the core's transform never changes and the Mesh node is not
##     spun (the old rig turned the whole model).
##   godot --headless --path . --audio-driver Dummy res://tests/whirlwind_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _parts := {}
var _tip_local := Vector3.ZERO
var _tip_rest_y := 0.0
var _core_xf: Transform3D

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
	return _e.call("rig_frame")

## The tip now, in the body frame with the chassis lean taken out: RobotModel
## banks the `Mesh` node the parts hang under, so the tip is read in that
## node's frame and put back through the fitted (and shifted) base.
func _tip() -> Vector3:
	var mi: MeshInstance3D = _parts["Blades"]
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * _tip_local))

func _azimuth(p: Vector3) -> float:
	return atan2(p.x, p.z)

## The blades' turn rate from the tip's azimuth about the hub, over `frames`
## process frames (the rig ticks in _process).
func _rate(frames: int) -> float:
	var hub: Vector3 = _e.get("_hub")
	var prev := _azimuth(_tip() - hub)
	var turned := 0.0
	var dt := 0.0
	for i in frames:
		await get_tree().process_frame
		var a := _azimuth(_tip() - hub)
		turned += absf(wrapf(a - prev, -PI, PI))
		prev = a
		dt += get_process_delta_time()
	return turned / maxf(dt, 0.0001)

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/whirlwind.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 2.2, 0)
	_e.set("sight_range", 0.0)
	var frames := 0
	while frames < 240 and not bool(_e.get("_rig_ready")):
		await get_tree().process_frame
		frames += 1
	await get_tree().physics_frame
	for n in ["Core", "Blades"]:
		_parts[n] = _e.find_child(n, true, false) as MeshInstance3D
	var have := bool(_e.get("_rig_ready")) and not _parts.values().has(null) and not (_e.get("_blades_e") as Array).is_empty()
	_check("rig set up on the two offline parts", have, "(ready %s, parts %s)" % [_e.get("_rig_ready"), _parts.keys()])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	# (1) the hub and the core on the axis.
	var hub: Vector3 = _e.get("_hub")
	var blades: MeshInstance3D = _parts["Blades"]
	var pts: PackedVector3Array = PartRig.body_points(_e, blades)
	var top := -INF
	for p in pts:
		top = maxf(top, p.y)
	var root := PackedVector3Array()
	var far := Vector3.ZERO
	for p in pts:
		if p.y > top - 0.12:
			root.append(p)
		if (p - hub).length() > (far - hub).length():
			far = p
	var root_c := PartRig.mean(root)
	_check("the blades' root sits on the body's axis", Vector2(root_c.x, root_c.z).length() < 0.08 and absf(root_c.y - hub.y) < 0.06, "(root %s, hub %s)" % [root_c, hub])
	var core: MeshInstance3D = _parts["Core"]
	var cb: AABB = _frame().affine_inverse() * (core.global_transform * core.mesh.get_aabb())
	var cc := cb.get_center()
	_check("the core's centre is on the body", Vector2(cc.x, cc.z).length() < 0.35 and absf(cc.y) < 0.4, "(centre %s)" % cc)
	_check("the blades reach 2+ m from the fist", (far - hub).length() > 2.0, "(%.2f m, tip %s)" % [(far - hub).length(), far])
	_tip_local = blades.global_transform.affine_inverse() * (_frame() * far)
	_tip_rest_y = far.y
	_core_xf = core.transform
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var mesh_yaw := mesh_node.rotation.y
	# (2) idle.
	await _wait(1.0)
	var r_idle: float = await _rate(24)
	_check("idle, the blades turn lazily", absf(r_idle - float(_e.get("SPIN_IDLE"))) < 0.4 and absf(float(_e.get("_spin_rate")) - float(_e.get("SPIN_IDLE"))) < 0.05, "(%.2f rad/s measured, rate %.2f)" % [r_idle, _e.get("_spin_rate")])
	_check("idle, the tip hangs at its rest height", absf(_tip().y - _tip_rest_y) < 0.05, "(%.2f vs %.2f)" % [_tip().y, _tip_rest_y])
	# (3) a player in sight at 10 m: the whirl runs up.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -10)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("sight_range", 40.0)
	_e.set("target", player)
	_e.set("_dive_timer", 999.0)
	_e.call("set_state", 3) # CHASE
	await _wait(1.5)
	var r_chase: float = await _rate(12)
	_check("with you in sight, the whirl runs up", absf(r_chase - float(_e.get("spin_speed"))) < 1.0 and absf(float(_e.get("_spin_rate")) - float(_e.get("spin_speed"))) < 0.1, "(%.2f rad/s measured, rate %.2f, state %s)" % [r_chase, _e.get("_spin_rate"), _e.get("state")])
	# (4) a dive: revs and lifts.
	_e.set("_diving", true)
	_e.set("_dive_time", 5.0)
	await _wait(0.75)
	var r_dive: float = await _rate(10)
	_check("a dive revs the whirl", r_dive > 15.0 and float(_e.get("_spin_rate")) >= 17.0, "(%.2f rad/s measured, rate %.2f)" % [r_dive, _e.get("_spin_rate")])
	var rise := _tip().y - _tip_rest_y
	_check("a dive lifts the blades toward level", rise > 0.5, "(tip up %.2f m)" % rise)
	# (5) the dive over.
	_e.set("_diving", false)
	_e.set("_dive_timer", 999.0)
	await _wait(1.4)
	var r_after: float = await _rate(12)
	_check("the dive over, back to the running whirl", absf(r_after - float(_e.get("spin_speed"))) < 1.0 and absf(float(_e.get("_spin_rate")) - float(_e.get("spin_speed"))) < 0.1, "(%.2f rad/s measured, rate %.2f)" % [r_after, _e.get("_spin_rate")])
	_check("the dive over, the blades hang again", absf(_tip().y - _tip_rest_y) < 0.05, "(%.2f vs %.2f)" % [_tip().y, _tip_rest_y])
	# (7) nothing but the blades moved.
	_check("the core never turned", core.transform.is_equal_approx(_core_xf), "")
	_check("the Mesh node is not spun", absf(wrapf(mesh_node.rotation.y - mesh_yaw, -PI, PI)) < 0.001, "(yaw %.3f, was %.3f)" % [mesh_node.rotation.y, mesh_yaw])
	# (6) dead: winds down as it falls (it bursts on the floor and is freed
	# soon after, so the rate is read 0.3 s in: 7.5 less 10 rad/s^2).
	(_e.get_node("Damageable") as Node).call("apply_damage", 99999.0, self)
	await _wait(0.3)
	var alive := is_instance_valid(_e)
	var rate_dead: float = float(_e.get("_spin_rate")) if alive else -1.0
	_check("dead, the whirl winds down", alive and rate_dead < 5.0, "(rate %.2f 0.3 s in, valid %s)" % [rate_dead, alive])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
