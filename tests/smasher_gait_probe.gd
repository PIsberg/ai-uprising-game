extends Node3D
## Probe: BEHEMOTH-X faces where it walks, walks on its legs and fights with
## its claws, instead of gliding side-on as a statue.
## rusty_claws_robot.glb is rig-less, cut offline into Body / ArmP / ArmN /
## LegP / LegN (tools/blender/split_regions.py). Claw tips (each arm's lowest
## point) and toes (each leg's lowest point) are measured once at rest in their
## part's own frame and followed in the body frame.
## (1) facing: the shoulders span the body X axis (the model faced -X, with the
##     chest reactor floating off its flank) and the head juts toward -Z;
## (2) charging: toes swing fore and aft >= 0.6 m, legs in opposition
##     (r < -0.6), each arm swings with the opposite leg (r > 0.6);
## (3) overhead smash: the right claw rises over the head (> 10 m) in the
##     windup and is hammered forward and down (< 5 m, ahead) after the hit;
## (4) ground slam: both claws overhead in the windup, both down after it;
## (5) claw rake: both claws cock back behind the shoulders, then sweep ahead;
## (6) stopped: every claw and toe back within 0.05 m of rest.
##   godot --headless --path . --audio-driver Dummy res://tests/smasher_gait_probe.tscn

var ok := true
var _e: CharacterBody3D
var _refs := {} ## "claw_L" -> [part, point in the part's frame]

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
	nm.agent_radius = 1.0
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## Body-frame points of every visible model mesh.
func _all_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for mi in _e.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree():
			pts.append_array(PartRig.body_points(_e, mi))
	return pts

func _measure_rest() -> void:
	for part_name in ["ArmP", "ArmN", "LegP", "LegN"]:
		var mi := _e.find_child(part_name, true, false) as MeshInstance3D
		if mi == null:
			continue
		var pts := PartRig.body_points(_e, mi)
		var side := "R" if PartRig.mean(pts).x > 0.0 else "L"
		var lo := INF
		for q in pts:
			lo = minf(lo, q.y)
		var sel := PackedVector3Array()
		for q in pts:
			if q.y < lo + 0.15:
				sel.append(q)
		var key := ("claw_" if part_name.begins_with("Arm") else "toe_") + side
		_refs[key] = [mi, mi.global_transform.affine_inverse() * _e.global_transform * PartRig.mean(sel)]

func _pts() -> Dictionary:
	var out := {}
	for k in _refs:
		var mi: MeshInstance3D = _refs[k][0]
		out[k] = _e.global_transform.affine_inverse() * mi.global_transform * (_refs[k][1] as Vector3)
	return out

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

## Runs one attack's windup and watches both claws: highest and furthest back
## during the windup, then where they are `after` seconds past the strike.
func _attack(begin: String, windup: float, after: float) -> Dictionary:
	_e.velocity = Vector3.ZERO
	_e.call(begin)
	var top := {"claw_L": -INF, "claw_R": -INF}
	var back := {"claw_L": -INF, "claw_R": -INF}
	var t := 0.0
	while t < windup:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var p := _pts()
		for k in top:
			top[k] = maxf(top[k], (p[k] as Vector3).y)
			back[k] = maxf(back[k], (p[k] as Vector3).z)
	await _wait(after)
	return {"top": top, "back": back, "end": _pts()}

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -75) # in sight (80 m), far past its rake range
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0

	_e = (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate()
	_e.set("preview", true) # no wake-roar entrance: the probe drives it
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	for i in 6:
		await get_tree().physics_frame
	# (1) facing
	var xs := Vector2(INF, -INF)
	var zs := Vector2(INF, -INF)
	var head := PackedVector3Array()
	var torso := PackedVector3Array()
	for q in _all_points():
		if q.y > 7.0 and q.y < 8.5:
			xs = Vector2(minf(xs.x, q.x), maxf(xs.y, q.x))
			zs = Vector2(minf(zs.x, q.z), maxf(zs.y, q.z))
		if q.y > 9.0:
			head.append(q)
		elif q.y > 4.0:
			torso.append(q)
	var span_x := xs.y - xs.x
	var span_z := zs.y - zs.x
	_check("shoulders span the body X axis", span_x > span_z * 1.15, "(x %.2f m, z %.2f m)" % [span_x, span_z])
	var hz := PartRig.mean(head).z
	var tz := PartRig.mean(torso).z
	_check("head juts forward (-Z)", hz < tz - 0.2, "(head z %.2f, torso z %.2f)" % [hz, tz])

	_measure_rest()
	_check("model is cut into arms and legs", _refs.size() == 4, "(%s)" % ", ".join(_refs.keys()))
	if _refs.size() != 4:
		print("RESULT FAIL")
		get_tree().quit()
		return
	var rest := _pts()
	print("  rest %s" % rest)

	# (2) charging gait
	_e.set("preview", false)
	_e.set_physics_process(true)
	(_e.get("hp") as Node).set("invulnerable", false)
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	var track := {"claw_L": [], "claw_R": [], "toe_L": [], "toe_R": []}
	var speed := 0.0
	var t := 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t < 0.6:
			continue # getting up to speed
		var p := _pts()
		for k in track:
			(track[k] as Array).append((p[k] as Vector3).z)
		speed = maxf(speed, Vector2(_e.velocity.x, _e.velocity.z).length())
	print("  ran at up to %.1f m/s" % speed)
	_check("BEHEMOTH-X actually moved", speed > 2.0, "(%.1f m/s)" % speed)
	for k in ["toe_L", "toe_R"]:
		var a: Array = track[k]
		_check("%s swings fore and aft" % k, a.max() - a.min() >= 0.6, "(%.2f m)" % (a.max() - a.min()))
	for k in ["claw_L", "claw_R"]:
		var a: Array = track[k]
		_check("%s swings fore and aft" % k, a.max() - a.min() >= 0.8, "(%.2f m)" % (a.max() - a.min()))
	var legs := _corr(track["toe_L"], track["toe_R"])
	_check("legs in opposition", legs < -0.6, "(r %.2f)" % legs)
	var cross_l := _corr(track["claw_L"], track["toe_R"])
	var cross_r := _corr(track["claw_R"], track["toe_L"])
	_check("each arm swings with the opposite leg", cross_l > 0.6 and cross_r > 0.6, "(r %.2f, %.2f)" % [cross_l, cross_r])

	# Park it: the attacks below are driven by hand.
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.set("charge_speed", 0.0)
	_e.velocity = Vector3.ZERO
	await _wait(1.5)

	# (3) overhead smash: right claw over the head, then hammered down ahead.
	var sm := await _attack("_begin_smash", float(_e.get("smash_windup")), 0.2)
	var end: Dictionary = sm["end"]
	_check("smash windup raises the right claw overhead", sm["top"]["claw_R"] > 10.0, "(%.2f m)" % sm["top"]["claw_R"])
	_check("smash hammers the right claw down ahead", (end["claw_R"] as Vector3).y < 5.0 and (end["claw_R"] as Vector3).z < -2.0, "(%s)" % end["claw_R"])
	await _wait(1.0)

	# (4) ground slam: both claws overhead, then both down.
	var sl := await _attack("_begin_slam", float(_e.get("slam_windup")), 0.2)
	end = sl["end"]
	_check("slam windup raises both claws overhead", sl["top"]["claw_L"] > 10.0 and sl["top"]["claw_R"] > 10.0, "(%.2f, %.2f m)" % [sl["top"]["claw_L"], sl["top"]["claw_R"]])
	_check("slam brings both claws down", (end["claw_L"] as Vector3).y < 5.0 and (end["claw_R"] as Vector3).y < 5.0, "(%.2f, %.2f m)" % [(end["claw_L"] as Vector3).y, (end["claw_R"] as Vector3).y])
	await _wait(1.0)

	# (5) claw rake: cocked back behind the shoulders, then swept ahead. The
	# lunge needs a target to aim at; park the player out of reach.
	_e.set("target", player)
	var rk := await _attack("_begin_rake", float(_e.get("rake_windup")), 0.15)
	end = rk["end"]
	_e.set("target", null)
	_check("rake windup cocks both claws back", rk["back"]["claw_L"] > (rest["claw_L"] as Vector3).z + 1.5 and rk["back"]["claw_R"] > (rest["claw_R"] as Vector3).z + 1.5, "(z %.2f, %.2f)" % [rk["back"]["claw_L"], rk["back"]["claw_R"]])
	_check("rake sweeps both claws ahead", (end["claw_L"] as Vector3).z < -2.0 and (end["claw_R"] as Vector3).z < -2.0, "(z %.2f, %.2f)" % [(end["claw_L"] as Vector3).z, (end["claw_R"] as Vector3).z])

	# (6) stopped: everything back at rest.
	_e.velocity = Vector3.ZERO
	await _wait(2.0)
	var still := _pts()
	var worst := 0.0
	for k in still:
		worst = maxf(worst, (still[k] as Vector3).distance_to(rest[k]))
	_check("claws and toes back at rest when it stops", worst < 0.05, "(%.3f m)" % worst)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
