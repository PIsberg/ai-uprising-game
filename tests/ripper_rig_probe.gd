extends Node3D
## Probe: the RIPPER's minigun rig. robot_minigun.glb slings a three-barrel
## minigun at the mech's hips as two meshes, the barrel cluster under a
## Barrel node and the housing; EnemyRipper._setup_rig takes both, hangs
## the muzzle on the housing at the cluster's far end, and _tick_rig spins
## the cluster about the gun's axis through the spin-up and the saw while an
## AimedPart turns the whole gun onto the walking saw point. Marks are taken
## once at rest in each part's own frame and followed through its
## transform, in the body frame.
## (1) both meshes are there, nothing was split, the cluster is forward of
##     the housing (0.3+ m), and the muzzle sits at the cluster's tip (within
##     0.04 m; the scene's old Muzzle node was 0.6 m off, up at a shoulder);
## (2) idle: the barrels are still (a mark on them moves under 0.03 m over
##     0.3 s, the idle clip bobs the hips) and the gun points down its rest line;
## (3) the spin-up: the cluster is turning at 15+ rad/s about the gun's axis
##     (measured from the mark) before any shot, while the housing is not;
## (4) the saw: the cluster holds 45 rad/s (40+ measured about the live axis)
##     and the gun's pivot-to-tip line points at the saw point within 0.15
##     rad (a player 30 deg off its nose);
## (5) the saw over: the spin runs down under 5 rad/s and the gun eases back
##     within 0.05 rad of its rest line.
##   godot --headless --path . --audio-driver Dummy res://tests/ripper_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _parts := {}
var _marks := {}
var _axis_pt := Vector3.ZERO  ## body frame, on the gun's axis at rest
var _axis := Vector3.FORWARD  ## body frame, at rest
var _rest_dir := Vector3.FORWARD

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

func _mark(name: String, part: String, body_p: Vector3) -> void:
	var mi: MeshInstance3D = _parts[part]
	_marks[name] = [part, mi.global_transform.affine_inverse() * (_frame() * body_p)]

## A mark now, in the body frame with the chassis lean taken out (read in
## the Mesh node's frame, put back through the fitted base).
func _at(name: String) -> Vector3:
	var m: Array = _marks[name]
	var mi: MeshInstance3D = _parts[m[0]]
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * (m[1] as Vector3)))

## A mark's angle about the gun's axis as it is now (the tip and rear marks
## on the housing turn with the aim).
func _angle(name: String) -> float:
	var tip := _at("tip")
	var axis := (tip - _at("rear")).normalized()
	var d := _at(name) - tip
	d -= axis * d.dot(axis)
	var u := axis.cross(Vector3.UP).normalized()
	var v := axis.cross(u)
	return atan2(d.dot(v), d.dot(u))

## Turn rate of a mark about the axis over `frames` physics frames.
func _rate(name: String, frames: int) -> float:
	var prev := _angle(name)
	var turned := 0.0
	var dt := 0.0
	for i in frames:
		await get_tree().physics_frame
		var a := _angle(name)
		turned += absf(wrapf(a - prev, -PI, PI))
		prev = a
		dt += get_physics_process_delta_time()
	return turned / maxf(dt, 0.0001)

## The gun's pivot-to-tip direction now, in the body frame.
func _gun_dir() -> Vector3:
	return (_at("tip") - _at("rear")).normalized()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/ripper.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_e.set("sight_range", 0.0)
	var frames := 0
	while frames < 240 and not bool(_e.get("_rig_ready")):
		await get_tree().process_frame
		frames += 1
	await get_tree().physics_frame
	_parts["barrels"] = _e.find_child(String(_e.get("BARREL_NAME")), true, false) as MeshInstance3D
	_parts["housing"] = _e.find_child(String(_e.get("HOUSING_NAME")), true, false) as MeshInstance3D
	var have := bool(_e.get("_rig_ready")) and not _parts.values().has(null) and _e.get("_gun") != null
	var copies: int = _e.find_children("*MiniGun_0_*", "MeshInstance3D", true, false).size()
	_check("the rig is on the gun's two meshes, nothing split", have and _parts["barrels"].visible and _parts["housing"].visible and copies == 0, "(ready %s, parts %s, copies %d)" % [_e.get("_rig_ready"), _parts.keys(), copies])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	# (1) the cut and the muzzle.
	var bp: PackedVector3Array = PartRig.body_points(_e, _parts["barrels"])
	var rp: PackedVector3Array = PartRig.body_points(_e, _parts["housing"])
	var bc := PartRig.mean(bp)
	var rc := PartRig.mean(rp)
	_check("the cluster is forward of the housing", rc.z - bc.z > 0.3, "(cluster z %.2f, housing z %.2f)" % [bc.z, rc.z])
	var gun: AimedPart = _e.get("_gun")
	_axis = (gun.tip - gun.pivot).normalized()
	_axis_pt = gun.tip
	var tip_far := AimedPart.band_mean(bp, _axis, 0.03)
	var muzzle: Node3D = _e.get("muzzle")
	var muzzle_body: Vector3 = _frame().affine_inverse() * muzzle.global_position
	_check("the muzzle sits at the cluster's tip", muzzle_body.distance_to(tip_far) < 0.04, "(%.3f m; muzzle %s, tip %s)" % [muzzle_body.distance_to(tip_far), muzzle_body, tip_far])
	# A mark on the cluster off its axis at the tip, one on the housing, the
	# gun's rear and tip.
	var off := Vector3.ZERO
	var best := 0.0
	for p in bp:
		if p.dot(_axis) > tip_far.dot(_axis) - 0.03:
			var d := p - _axis_pt
			d -= _axis * d.dot(_axis)
			if d.length() > best:
				best = d.length()
				off = p
	_mark("barrel", "barrels", off)
	var roff := Vector3.ZERO
	best = 0.0
	for p in rp:
		var d := p - _axis_pt
		d -= _axis * d.dot(_axis)
		if d.length() > best:
			best = d.length()
			roff = p
	_mark("housing", "housing", roff)
	_mark("tip", "housing", gun.tip)
	_mark("rear", "housing", gun.pivot)
	_rest_dir = _gun_dir()
	_check("the mark sits off the axis", best > 0.02 and (off - _axis_pt - _axis * (off - _axis_pt).dot(_axis)).length() > 0.02, "(cluster %.3f m, housing %.3f m)" % [(off - _axis_pt - _axis * (off - _axis_pt).dot(_axis)).length(), best])
	# (2) idle.
	var b0 := _at("barrel")
	await _wait(0.3)
	_check("idle, the barrels are still", _at("barrel").distance_to(b0) < 0.03 and float(_e.get("_spin_rate")) == 0.0, "(%.3f m; the idle clip bobs the hips)" % _at("barrel").distance_to(b0))
	# (3) the spin-up: a player 30 deg off the nose at 12 m.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-6.0, 0.1, -10.4)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("sight_range", 40.0)
	_e.set("target", player)
	_e.set("turn_speed", 0.0)
	_e.call("set_state", 4) # ATTACK
	_e.set("_attack_timer", 999.0)
	_e.call("_start_burst")
	var t := 0.0
	while t < 1.0 and float(_e.get("_spin_rate")) < 20.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_e.set("_attack_timer", 999.0)
	var spinning: bool = _e.get("_spinning")
	var r_up: float = await _rate("barrel", 4)
	var r_recv: float = await _rate("housing", 4)
	_check("the spin-up turns the cluster before the saw", spinning and r_up > 15.0 and int(_e.get("_burst_remaining")) == 0, "(%.1f rad/s %.2f s in, spinning %s)" % [r_up, t, spinning])
	_check("the housing does not spin", r_recv < 3.0, "(%.1f rad/s)" % r_recv)
	# (4) the saw: starts once the barrels are at speed.
	t = 0.0
	while t < 1.5 and int(_e.get("_burst_remaining")) == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_e.set("_attack_timer", 999.0)
	var r_saw: float = await _rate("barrel", 6)
	var saw_aim: Vector3 = _e.get("_saw_aim")
	var want: Vector3 = (_frame().affine_inverse() * saw_aim - _at("rear")).normalized()
	var off_aim := _gun_dir().angle_to(want)
	_check("the saw holds the cluster at speed", int(_e.get("_burst_remaining")) > 0 and r_saw > 40.0 and float(_e.get("_spin_rate")) >= 44.9, "(%.1f rad/s, rate %.1f, %d shots left)" % [r_saw, _e.get("_spin_rate"), _e.get("_burst_remaining")])
	_check("the gun turns onto the saw point", off_aim < 0.15 and _rest_dir.angle_to(want) > 0.1, "(%.2f rad off it; the saw point is %.2f rad off the rest line)" % [off_aim, _rest_dir.angle_to(want)])
	# (5) over: no more bursts.
	_e.set("target", null)
	_e.set("sight_range", 0.0)
	player.global_position = Vector3(0, 0.1, -300)
	_e.call("set_state", 0) # IDLE
	t = 0.0
	while t < 4.0 and (int(_e.get("_burst_remaining")) > 0 or bool(_e.get("_spinning"))):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _wait(2.2)
	_check("the saw over, the spin runs down", float(_e.get("_spin_rate")) < 5.0, "(rate %.1f)" % _e.get("_spin_rate"))
	_check("the saw over, the gun is back on its rest line", _gun_dir().angle_to(_rest_dir) < 0.05, "(%.3f rad)" % _gun_dir().angle_to(_rest_dir))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
