extends Node3D
## Probe: the FISHBOT's swim rig. EnemyFishbot hangs its box fins under the
## model's Mesh node, beats the tail about its front edge, flutters and
## pitches the pectorals, trails and kicks the lander legs with a
## BoneSweepModifier, spits from the lens of the eye and darts sideways off
## each spit. The tail's tip is marked once at rest in the fin's own frame
## and followed through its transform in the body frame, lean taken out.
## (1) the four fins hang under Model/Mesh (the node RobotModel banks), the
##     tail behind the body with its hinge on its front edge, and the muzzle
##     sits at the lens (within 0.08 m of the Eye bone, 0.1 m forward and up;
##     the scene's old Muzzle node was 0.8 m off, under the body);
## (2) hanging still: the tail sculls at BEAT_IDLE (within 0.5 rad/s) with
##     the tip swinging 0.06-0.3 m peak to peak;
## (3) chasing at full speed: the beat runs up to BEAT_SWIM (within 0.5),
##     the tip swings 0.26+ m, and each foot trails 0.25+ m behind its hip
##     and no lower than 0.15 m above the body's origin (the clip hangs it
##     0.44 m below the hip), within 0.25 rad of LEG_TRAIL from the hip;
## (4) a descent (vy under -2 m/s): the pectorals pitch nose-down (under
##     -0.15 rad), the front edge below the rear edge;
## (5) a spit: the bolt leaves 0.3+ m above the body's origin (the lens, not
##     the old point under it), the body darts sideways at 4.5+ m/s with the
##     strafe side flipped, and the tail stroke widens past TAIL_SWIM;
## (6) dead: 0.3 s in, the beat is winding down (under 10 rad/s from 19) and
##     the legs are going limp (sweep weight under 0.6).
##   godot --headless --path . --audio-driver Dummy res://tests/fishbot_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _fins := {}
var _tip_local := Vector3.ZERO

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

## A point of a fin now, in the body frame with the chassis lean taken out:
## the fins hang under the `Mesh` node RobotModel banks, so the point is
## read in that node's frame and put back through its base transform.
func _fin_point(fin: MeshInstance3D, local: Vector3) -> Vector3:
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (fin.global_transform * local))

func _tip() -> Vector3:
	return _fin_point(_fins["Tail"], _tip_local)

## The tail tip's side-to-side swing, peak to peak, over `seconds`.
func _swing(seconds: float) -> float:
	var lo := INF
	var hi := -INF
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var x := _tip().x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo

## A bone's origin in the body frame. The skeleton hands the clip's pose
## back once a frame is drawn, so a swept bone is read from the sweep's own
## record of what it posed (BoneSweepModifier.posed), as HeadTrack's gun
## bones are.
func _bone(name: String) -> Vector3:
	var sk := _e.find_child("Skeleton3D", true, false) as Skeleton3D
	var sweep: Node = _e.get("_sweep")
	var pose: Transform3D = sweep.call("posed", name) if sweep else sk.get_bone_global_pose(sk.find_bone(name))
	return _frame().affine_inverse() * (sk.global_transform * pose).origin

## A fin's own-frame coordinates of a body-frame point of it AT REST (the
## entry's rest transform, whatever the fin is doing now).
func _rest_local(e: Array, p: Vector3) -> Vector3:
	var rest_to_body: Transform3D = (e[2] as Transform3D).affine_inverse() * (e[1] as Transform3D)
	return rest_to_body.affine_inverse() * p

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/fishbot.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 2.5, 0)
	_e.set("sight_range", 0.0)
	var frames := 0
	while frames < 240 and _e.get("_rig_ready") != true:
		await get_tree().process_frame
		frames += 1
	await get_tree().physics_frame
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	for n in ["Dorsal", "Tail", "PectoralR", "PectoralL"]:
		_fins[n] = _e.find_child(n, true, false) as MeshInstance3D
	var have: bool = _e.get("_rig_ready") == true and not _fins.values().has(null) and _e.get("_sweep") != null
	_check("rig set up: four fins and the leg sweep", have, "(ready %s, fins %s, sweep %s)" % [_e.get("_rig_ready"), _fins.keys(), _e.get("_sweep")])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	# (1) where things hang.
	var under := true
	for f in _fins.values():
		under = under and (f as Node).get_parent() == mesh_node
	_check("the fins hang under the Mesh node the chassis banks", under, "")
	var tail: MeshInstance3D = _fins["Tail"]
	var tpts: PackedVector3Array = PartRig.body_points(_e, tail)
	var hinge: Vector3 = _e.get("_tail_hinge")
	var front := INF
	for p in tpts:
		front = minf(front, p.z)
	_check("the tail is behind the body, hinged on its front edge", hinge.z > 0.15 and absf(hinge.z - front) < 0.03, "(hinge %s, front z %.2f)" % [hinge, front])
	var tail_e: Array = _e.get("_tail_e")
	_tip_local = _rest_local(tail_e, AimedPart.band_mean(PartRig.rest_points(tail_e), Vector3.BACK, 0.02))
	var muzzle: Node3D = _e.get("muzzle")
	var m_body: Vector3 = _frame().affine_inverse() * muzzle.global_position
	var lens := _bone("Eye") + Vector3(0.0, 0.04, -0.1)
	var old := Vector3(0.0, -0.1, -0.42)
	_check("the muzzle sits at the lens of the eye", muzzle.name == "BoneMuzzle" and m_body.distance_to(lens) < 0.08, "(muzzle %s, lens %s, old node %.2f m off)" % [m_body, lens, m_body.distance_to(old)])
	var foot_rest := _bone("Foot.L")
	var hip_rest := _bone("Leg1.L")
	# (2) hanging still.
	await _wait(1.0)
	var idle_rate: float = _e.get("_beat_rate")
	var idle_swing: float = await _swing(1.5)
	_check("hanging still, the tail sculls", absf(idle_rate - float(_e.get("BEAT_IDLE"))) < 0.5 and idle_swing > 0.06 and idle_swing < 0.3, "(beat %.1f rad/s, swing %.3f m)" % [idle_rate, idle_swing])
	# (3) chasing a player 45 m off at full speed (attack range is 20 m: the
	# chase has 3 s before it closes to a slower ATTACK approach).
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -45)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("sight_range", 60.0)
	_e.set("target", player)
	_e.set("_dive_timer", 999.0)
	_e.set("_strafe_change_timer", 999.0) # the strafe side stays where the probe puts it
	_e.global_rotation = Vector3.ZERO # the idle scan had turned its eye off the player
	_e.call("set_state", 3) # CHASE
	frames = 0
	while frames < 240 and Vector2(_e.velocity.x, _e.velocity.z).length() < float(_e.get("move_speed")) - 0.2:
		await get_tree().physics_frame
		frames += 1
	await _wait(0.4) # the beat settles (BEAT_RATE)
	var swim_rate: float = _e.get("_beat_rate")
	var spd := Vector2(_e.velocity.x, _e.velocity.z).length()
	var swim_swing: float = await _swing(0.5)
	_check("at speed, the tail beats fast and wide", absf(swim_rate - float(_e.get("BEAT_SWIM"))) < 0.5 and swim_swing > 0.26, "(beat %.1f rad/s, swing %.3f m, %.1f m/s, state %s)" % [swim_rate, swim_swing, spd, _e.get("state")])
	var foot := _bone("Foot.L")
	var hip := _bone("Leg1.L")
	var foot_r := _bone("Foot.R")
	var hip_r := _bone("Leg1.R")
	var trail: Vector3 = _e.get("LEG_TRAIL")
	var off_l := (foot - hip).angle_to(trail * Vector3(-1, 1, 1))
	var off_r := (foot_r - hip_r).angle_to(trail)
	_check("the legs trail behind the hips", foot.z - hip.z > 0.25 and foot_r.z - hip_r.z > 0.25 and foot.y > 0.15 and foot_r.y > 0.15 and off_l < 0.25 and off_r < 0.25, "(L foot %s hip %s %.2f rad off; R foot %s hip %s %.2f rad off; the clip hangs the foot %.2f m below)" % [foot, hip, off_l, foot_r, hip_r, off_r, hip_rest.y - foot_rest.y])
	# (4) a descent: the hover height pulled down 2 m under it, read once it
	# is dropping at 2.5+ m/s and the pitch has had 0.15 s to follow.
	_e.set("hover_height", 0.5)
	frames = 0
	while frames < 90 and _e.velocity.y > -2.5:
		await get_tree().physics_frame
		frames += 1
	await _wait(0.15)
	var vy := _e.velocity.y
	var pitch: float = _e.get("_pec_pitch")
	var pec: MeshInstance3D = _fins["PectoralR"]
	var ppts := PartRig.rest_points(_e.get("_pec_e")[0])
	var p_front := AimedPart.band_mean(ppts, Vector3.FORWARD, 0.02)
	var p_rear := AimedPart.band_mean(ppts, Vector3.BACK, 0.02)
	var front_now := _fin_point(pec, _rest_local(_e.get("_pec_e")[0], p_front))
	var rear_now := _fin_point(pec, _rest_local(_e.get("_pec_e")[0], p_rear))
	_check("a descent pitches the pectorals nose-down", vy < -2.0 and pitch < -0.15 and front_now.y < rear_now.y - 0.02, "(vy %.1f, pitch %.2f, front y %.3f rear y %.3f)" % [vy, pitch, front_now.y, rear_now.y])
	_e.set("hover_height", 2.5)
	# (5) a spit and the dart, from attack range: the player on the floor 8 m
	# ahead of it, and it in ATTACK with the player in sight before the timer
	# is tripped (the descent left it low; a flyer sees nothing for a few
	# frames after its target is moved).
	player.global_position = Vector3(_e.global_position.x, 0.1, _e.global_position.z - 8.0)
	_e.set("_strafe_dir", 1.0)
	_e.set("_attack_timer", 999.0)
	frames = 0
	while frames < 210 and not (int(_e.get("state")) == 4 and bool(_e.call("_can_see", player)) and frames > 30):
		await get_tree().physics_frame
		_e.set("_attack_timer", 999.0) # held off: a spit of its own in the approach would be read as this one
		frames += 1
	_e.set("_dart_t", 0.0)
	var before := get_tree().current_scene.get_child_count()
	var side_before: float = _e.get("_strafe_dir")
	_e.set("_attack_timer", 0.0)
	var fired := false
	var lat := 0.0
	var bolt_y := -9.0
	for i in 12:
		await get_tree().physics_frame
		if float(_e.get("_dart_t")) > 0.0:
			fired = true
			var to := player.global_position - _e.global_position
			to.y = 0.0
			lat = _e.velocity.dot(to.normalized().cross(Vector3.UP))
			var root := get_tree().current_scene
			for c in range(before, root.get_child_count()):
				var n := root.get_child(c)
				if n is Node3D and n.has_method("launch"):
					bolt_y = (n as Node3D).global_position.y - _e.global_position.y
			break
	_check("a spit darts it sideways, the next the other way", fired and lat * side_before > 4.5 and float(_e.get("_strafe_dir")) == -side_before, "(fired %s, sideways %.1f m/s, strafe side %s was %s, state %s)" % [fired, lat, _e.get("_strafe_dir"), side_before, _e.get("state")])
	_check("the bolt leaves the lens, not the old point under the body", bolt_y > 0.3, "(bolt %.2f m above the body's origin)" % bolt_y)
	await _wait(0.2)
	_check("the dart thrashes the tail", float(_e.get("_amp")) > float(_e.get("TAIL_SWIM")) + 0.05, "(stroke %.2f rad, dart %.2f s left)" % [_e.get("_amp"), _e.get("_dart_t")])
	# (6) dead: the beat winds down and the legs go limp (it bursts on the
	# floor and is freed soon after, so both are read 0.3 s in).
	_e.set("_attack_timer", 999.0)
	await _wait(0.6)
	_e.global_position.y = 4.0 # room to fall: it bursts on the floor
	_e.velocity = Vector3.ZERO
	await get_tree().physics_frame
	(_e.get_node("Damageable") as Node).call("apply_damage", 99999.0, self)
	await _wait(0.3)
	var alive := is_instance_valid(_e)
	var rate_dead: float = float(_e.get("_beat_rate")) if alive else -1.0
	var w_dead: float = float((_e.get("_sweep") as Node).get("weight")) if alive else -1.0
	_check("dead, the beat winds down and the legs go limp", alive and rate_dead < 10.0 and w_dead < 0.6, "(beat %.1f, sweep weight %.2f, valid %s)" % [rate_dead, w_dead, alive])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
