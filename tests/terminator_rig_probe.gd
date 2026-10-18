extends Node3D
## Probe: APEX ENDOFRAME walks on its legs and fights with its rotary cannons.
## combat_robot.glb is rig-less, cut offline into Body / GunP / GunN / BarrelP /
## BarrelN / ThighP / ThighN / ShinP / ShinN (tools/blender/split_regions.py,
## cfg_combat_robot_limbs.json). Toes (each shin's lowest point), barrel tips
## (each barrel's most forward point) and a point on each barrel's rim are
## measured at rest in their part's own frame and followed in the body frame.
## (1) the model is cut into its moving parts;
## (2) the muzzles sit on the barrel tips (they sat mid-chest, 0.6 m inboard);
## (3) chasing: toes swing >= 0.3 m along the run, legs in opposition
##     (r < -0.6), each foot lifts >= 0.05 m on its swing (the knee bends);
## (4) strafing: toes swing >= 0.3 m sideways, the way it moves;
## (5) aiming: with the target 39 deg above, both barrels pitch up (dir.y >
##     0.35), with it below they pitch down (< -0.2), and the muzzles stay on
##     the tips;
## (6) a burst spins the barrels (> 3 rad in 0.5 s); 3 s after, they are still;
## (7) stopped: toes and tips back within 0.03 m of rest.
##   godot --headless --path . --audio-driver Dummy res://tests/terminator_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _refs := {} ## "toe_L" -> [part, point in the part's frame]
var _axis := {} ## "L" -> barrel axis point at rest (body frame)

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
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(220, 1, 220)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _part(n: String) -> MeshInstance3D:
	return _e.find_child(n, true, false) as MeshInstance3D

## Side of a part: L for body x < 0.
func _side(mi: MeshInstance3D) -> String:
	return "L" if PartRig.mean(PartRig.body_points(_e, mi)).x < 0.0 else "R"

func _ref(key: String, mi: MeshInstance3D, body_pt: Vector3) -> void:
	_refs[key] = [mi, mi.global_transform.affine_inverse() * _e.global_transform * body_pt]

func _measure_rest() -> void:
	for n in ["ShinP", "ShinN"]:
		var mi := _part(n)
		if mi == null:
			continue
		var pts := PartRig.body_points(_e, mi)
		var lo := INF
		for q in pts:
			lo = minf(lo, q.y)
		var sel := PackedVector3Array()
		for q in pts:
			if q.y < lo + 0.03:
				sel.append(q)
		_ref("toe_" + _side(mi), mi, PartRig.mean(sel))
	for n in ["BarrelP", "BarrelN"]:
		var mi := _part(n)
		if mi == null:
			continue
		var pts := PartRig.body_points(_e, mi)
		var front := INF
		for q in pts:
			front = minf(front, q.z)
		var sel := PackedVector3Array()
		for q in pts:
			if q.z < front + 0.02:
				sel.append(q)
		var tip := PartRig.mean(sel)
		var s := _side(mi)
		_axis[s] = tip
		_ref("tip_" + s, mi, tip)
		_ref("root_" + s, mi, Vector3(tip.x, tip.y, tip.z + 0.4))
		# A rim point: the vertex farthest from the axis.
		var far := tip
		for q in pts:
			if Vector2(q.x - tip.x, q.y - tip.y).length() > Vector2(far.x - tip.x, far.y - tip.y).length():
				far = q
		_ref("rim_" + s, mi, far)

func _pts() -> Dictionary:
	var out := {}
	for k in _refs:
		var mi: MeshInstance3D = _refs[k][0]
		out[k] = _e.global_transform.affine_inverse() * mi.global_transform * (_refs[k][1] as Vector3)
	return out

## Body-frame position of a muzzle node.
func _muzzle(n: String) -> Vector3:
	return _e.global_transform.affine_inverse() * (_e.get_node(n) as Node3D).global_position

## Worst gap between each muzzle and the barrel tip on its side.
func _muzzle_gap() -> float:
	var p := _pts()
	var gap := 0.0
	for pair in [["MuzzleL", "tip_L"], ["MuzzleR", "tip_R"]]:
		gap = maxf(gap, _muzzle(pair[0]).distance_to(p[pair[1]]))
	return gap

## Rim angle about the barrel's own axis (tip -> root), in its own plane.
func _rim_angle(s: String, p: Dictionary) -> float:
	var tip: Vector3 = p["tip_" + s]
	var axis := ((p["root_" + s] as Vector3) - tip).normalized()
	var r := (p["rim_" + s] as Vector3) - tip
	r -= axis * r.dot(axis)
	var ref := axis.cross(Vector3.UP).normalized()
	return atan2(r.dot(axis.cross(ref)), r.dot(ref))

static func _corr(a: Array, b: Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

## Drives the boss at `vel` (world) for `seconds`, its legs only (no AI), and
## returns each toe's track: along-run position and height.
func _walk(vel: Vector3, seconds: float) -> Dictionary:
	var track := {"L": [], "R": [], "L_y": [], "R_y": []}
	var dir := vel.normalized()
	var t := 0.0
	while t < seconds:
		_e.velocity = vel
		await get_tree().process_frame
		t += get_process_delta_time()
		if t < 0.6:
			continue # up to stride
		var p := _pts()
		for s in ["L", "R"]:
			var toe: Vector3 = _e.global_transform.basis * (p["toe_" + s] as Vector3)
			(track[s] as Array).append(toe.dot(dir))
			(track[s + "_y"] as Array).append((p["toe_" + s] as Vector3).y)
	_e.velocity = Vector3.ZERO
	return track

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/terminator.tscn") as PackedScene).instantiate()
	_e.set("preview", true) # no eruption entrance, physics off: the probe drives it
	add_child(_e)
	_e.global_position = Vector3(0, 0.0, 0)
	for i in 8:
		await get_tree().process_frame

	# (1) parts
	var missing := []
	for n in ["GunP", "GunN", "BarrelP", "BarrelN", "ThighP", "ThighN", "ShinP", "ShinN"]:
		if _part(n) == null:
			missing.append(n)
	_check("model is cut into legs, gun arms and barrels", missing.is_empty(), "(missing %s)" % ", ".join(missing))
	if not missing.is_empty():
		print("RESULT FAIL")
		get_tree().quit()
		return
	_measure_rest()
	var rest := _pts()
	print("  rest %s" % rest)

	# (2) muzzles on the barrel tips
	_check("muzzles sit on the barrel tips", _muzzle_gap() < 0.12, "(worst %.2f m)" % _muzzle_gap())

	# (3) chasing straight ahead
	var fwd := -_e.global_transform.basis.z
	var tr := await _walk(fwd * 6.0, 2.0)
	for s in ["L", "R"]:
		var a: Array = tr[s]
		var y: Array = tr[s + "_y"]
		_check("toe_%s swings along the run" % s, a.max() - a.min() >= 0.3, "(%.2f m)" % (a.max() - a.min()))
		_check("toe_%s lifts on its swing" % s, y.max() - y.min() >= 0.05, "(%.3f m)" % (y.max() - y.min()))
	var r := _corr(tr["L"], tr["R"])
	_check("legs in opposition", r < -0.6, "(r %.2f)" % r)

	# (4) strafing sideways
	await get_tree().create_timer(1.0).timeout
	tr = await _walk(_e.global_transform.basis.x * 5.0, 2.0)
	for s in ["L", "R"]:
		var a: Array = tr[s]
		_check("toe_%s steps sideways with a strafe" % s, a.max() - a.min() >= 0.3, "(%.2f m)" % (a.max() - a.min()))
	await get_tree().create_timer(1.0).timeout

	# (5) aim: a target 39 deg up, then below.
	var mark := Node3D.new()
	add_child(mark)
	_e.set("target", mark)
	_e.call("set_state", 4) # ATTACK; physics stays off, so it neither moves nor fires
	for pass_ in [[Vector3(0, 8.0, -8.0), 1.0], [Vector3(0, -4.5, -8.0), -1.0]]:
		mark.global_position = _e.global_transform * (pass_[0] as Vector3)
		await get_tree().create_timer(1.2).timeout
		var p := _pts()
		var worst := INF if pass_[1] > 0.0 else -INF
		for s in ["L", "R"]:
			var d := ((p["tip_" + s] as Vector3) - (p["root_" + s] as Vector3)).normalized()
			worst = minf(worst, d.y) if pass_[1] > 0.0 else maxf(worst, d.y)
		if pass_[1] > 0.0:
			_check("barrels pitch up onto a high target", worst > 0.35, "(dir.y %.2f)" % worst)
		else:
			_check("barrels pitch down onto a low target", worst < -0.2, "(dir.y %.2f)" % worst)
		_check("muzzles stay on the tips while aimed", _muzzle_gap() < 0.12, "(worst %.2f m)" % _muzzle_gap())
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE

	# (6) a burst spins the barrels; they wind down after it.
	await get_tree().create_timer(1.5).timeout
	_e.set("_burst_remaining", 6)
	await get_tree().create_timer(0.4).timeout # spin-up
	var turned := 0.0
	var prev := _rim_angle("L", _pts())
	var t := 0.0
	while t < 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		var now := _rim_angle("L", _pts())
		turned += absf(wrapf(now - prev, -PI, PI))
		prev = now
	_check("a burst spins the barrels", turned > 3.0, "(%.1f rad in 0.5 s)" % turned)
	_e.set("_burst_remaining", 0)
	await get_tree().create_timer(3.0).timeout
	turned = 0.0
	prev = _rim_angle("L", _pts())
	t = 0.0
	while t < 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()
		var now := _rim_angle("L", _pts())
		turned += absf(wrapf(now - prev, -PI, PI))
		prev = now
	_check("barrels wind down after it", turned < 0.05, "(%.2f rad in 0.5 s)" % turned)

	# (7) rest
	var still := _pts()
	var worst_gap := 0.0
	for k in still:
		if String(k).begins_with("toe_") or String(k).begins_with("tip_"):
			worst_gap = maxf(worst_gap, (still[k] as Vector3).distance_to(rest[k]))
	_check("toes and barrel tips back at rest", worst_gap < 0.03, "(%.3f m)" % worst_gap)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
