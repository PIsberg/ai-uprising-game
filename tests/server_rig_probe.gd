extends Node3D
## Probe: the MAITRE-D' (SERVER) fights with its head and arms. serving_bot.glb
## is built in four meshes (tools/blender/build_server.py: Head, ArmL, ArmR and
## the column, ServingBot); EnemyServer._setup_rig takes them by name with
## measured neck, shoulders and hands, and _tick_rig turns the head, throws
## with the right arm and flings both arms through the tray-bash's pirouette.
## Marks are measured once at rest in each part's own frame and followed
## through its transform, read in the Mesh node's frame (chassis lean and
## first-contact bristle taken out) and, for the whirl, with the Model node's
## spin left in.
## (1) the parts are there and the neck, shoulders and hands land on the
##     model (the head's bottom, the arms' rear and front ends, read headless);
## (2) engaged on a player 50 deg to its left with the body unable to turn,
##     the face turns 0.6+ rad onto it (within 0.12 rad of the line from the
##     head's centre);
## (3) a cleaver throw: no pirouette (the model's yaw sweeps under 30 deg),
##     the right hand rises 0.4+ m over the shoulder first, and the cleaver
##     appears within 0.45 m of the hand (the old origin over the column is
##     0.6+ m from it);
## (4) the tray-bash: the model whirls 300+ deg inside 0.6 s, both hands fling
##     0.25+ m outward, and the face stays on the player through the spin
##     (within 0.35 rad in every frame);
## (5) idle: head forward within 0.05 rad, hands within 0.03 m of rest, the
##     model facing forward within 5 deg.
##   godot --headless --path . --audio-driver Dummy res://tests/server_rig_probe.tscn

var ok := true
var _e: CharacterBody3D
var _parts := {}
var _marks := {}
var _rest := {}

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
	pm.size = Vector2(80, 80)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _frame() -> Transform3D:
	return _e.call("rig_frame") as Transform3D

func _mark(name: String, part: String, body_p: Vector3) -> void:
	var mi: MeshInstance3D = _parts[part]
	_marks[name] = [part, mi.global_transform.affine_inverse() * (_frame() * body_p)]

## A mark in the Mesh node's frame put back through the fitted base: the
## chassis lean and the bristle nudge drop out, the whirl's spin stays.
func _at(name: String) -> Vector3:
	var m: Array = _marks[name]
	var mi: MeshInstance3D = _parts[m[0]]
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * (m[1] as Vector3)))

func _world(name: String) -> Vector3:
	var m: Array = _marks[name]
	var mi: MeshInstance3D = _parts[m[0]]
	return mi.global_transform * (m[1] as Vector3)

## The model's yaw relative to the body (radians).
func _model_yaw() -> float:
	var model := _e.get_node("Model") as Node3D
	var rel := _e.global_transform.basis.inverse() * model.global_transform.basis
	var f := rel * Vector3.FORWARD
	return atan2(-f.x, -f.z)

## The face's yaw in the world (from the head's centre to its face, both marks
## on the head, so the chassis lean moving the whole head does not count),
## and the yaw from the head's centre to a point.
func _face_yaw_world() -> float:
	var d := _world("face") - _world("crown")
	return atan2(-d.x, -d.z)

func _yaw_to(p: Vector3) -> float:
	var d := p - _world("crown")
	return atan2(-d.x, -d.z)

func _wait(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/server.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3.ZERO
	var frames := 0
	while frames < 240 and not bool(_e.get("_rig_ready")):
		await get_tree().process_frame
		frames += 1
	await get_tree().physics_frame
	for n in ["ServingBot", "Head", "ArmL", "ArmR"]:
		_parts[n] = _e.find_child(n, true, false) as MeshInstance3D
	var have := bool(_e.get("_rig_ready")) and not _parts.values().has(null) and not (_e.get("_head_e") as Array).is_empty()
	_check("rig set up on the four built parts", have, "(ready %s, parts %s)" % [_e.get("_rig_ready"), _parts.keys()])
	if not have:
		print("RESULT FAIL")
		get_tree().quit()
		return
	var neck: Vector3 = _e.get("NECK")
	var shoulder_c: Vector3 = _e.get("SHOULDER")
	var hand_c: Vector3 = _e.get("HAND")
	var head_pts := PartRig.body_points(_e, _parts["Head"])
	var chin := AimedPart.band_mean(head_pts, Vector3.DOWN, 0.03)
	_check("neck sits under the head", neck.distance_to(chin) < 0.06, "(neck %s, head bottom %s)" % [neck, chin])
	for side in 2:
		var n := "ArmL" if side == 0 else "ArmR"
		var pts := PartRig.body_points(_e, _parts[n])
		var sx := -1.0 if side == 0 else 1.0
		var shoulder := Vector3(shoulder_c.x * sx, shoulder_c.y, shoulder_c.z)
		var hand := Vector3(hand_c.x * sx, hand_c.y, hand_c.z)
		var rear := AimedPart.band_mean(pts, Vector3.BACK, 0.03)
		var front := AimedPart.band_mean(pts, Vector3.FORWARD, 0.03)
		_check("%s shoulder is the arm's root at the column" % n, shoulder.distance_to(rear) < 0.03, "(%s vs %s)" % [shoulder, rear])
		_check("%s hand is the arm's tip on the tray" % n, hand.distance_to(front) < 0.03, "(%s vs %s)" % [hand, front])
	_mark("face", "Head", Vector3(0, 1.817, -0.329))
	_mark("crown", "Head", Vector3(0, 1.835, 0.0))
	_mark("handL", "ArmL", Vector3(-hand_c.x, hand_c.y, hand_c.z))
	_mark("handR", "ArmR", hand_c)
	for k in _marks:
		_rest[k] = _at(k)

	# (2) Head onto a player off to the left, the body pinned.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	var side_dir := Vector3(-sin(deg_to_rad(50)), 0, -cos(deg_to_rad(50)))
	player.global_position = side_dir * 8.0 + Vector3.UP * 0.1
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame
	_e.set("move_speed", 0.0)
	_e.set("turn_speed", 0.0)
	_e.set("_cleaver_cd", 999.0)
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	await _wait(0.8)
	var eyes: Vector3 = player.global_position + Vector3.UP * 1.5
	var face_yaw := _face_yaw_world()
	var want := _yaw_to(eyes)
	_check("head turned onto the player at its side", face_yaw > 0.6 and absf(wrapf(face_yaw - want, -PI, PI)) < 0.12,
		"(face yaw %.2f rad, line to the player %.2f)" % [face_yaw, want])

	# (3) A cleaver throw from 9 m straight ahead.
	player.global_position = Vector3(0, 0.1, -9)
	_e.set("turn_speed", 4.2)
	await _wait(0.4)
	_e.set("_cleaver_cd", 0.0)
	var t := 0.0
	while t < 1.0 and float(_e.get("_throw_t")) < 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("a throw started", float(_e.get("_throw_t")) >= 0.0)
	var hand_rise := 0.0
	var swept := 0.0
	var prev_yaw := _model_yaw()
	var cleaver_off := INF
	var seen := {}
	t = 0.0
	while t < 1.0 and float(_e.get("_throw_t")) >= 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		hand_rise = maxf(hand_rise, _at("handR").y - (_rest["handR"] as Vector3).y)
		var y := _model_yaw()
		swept += absf(wrapf(y - prev_yaw, -PI, PI))
		prev_yaw = y
		for c in get_tree().current_scene.get_children():
			if c is ThrownCleaver and not seen.has(c):
				seen[c] = true
				cleaver_off = minf(cleaver_off, (c as Node3D).global_position.distance_to(_world("handR")))
	_check("throw: no pirouette", rad_to_deg(swept) < 30.0, "(%.0f deg)" % rad_to_deg(swept))
	_check("throw: the right hand cocked up over the shoulder", hand_rise >= 0.4, "(%.3f m)" % hand_rise)
	_check("throw: the cleaver left the right hand", cleaver_off < 0.45, "(%d cleavers, nearest %.3f m from the hand)" % [seen.size(), cleaver_off])

	# (4) The tray-bash up close (3.2 m: the attack lunges it 1.5 m closer).
	player.global_position = _e.global_position + Vector3(0, 0.1, -3.2)
	_e.set("_cleaver_cd", 999.0)
	_e.call("set_state", 4) # ATTACK
	t = 0.0
	while t < 2.0 and float(_e.get("_whirl_t")) < 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("a bash whirl started", float(_e.get("_whirl_t")) >= 0.0)
	swept = 0.0
	prev_yaw = _model_yaw()
	var fling := [0.0, 0.0]
	var face_off := 0.0
	t = 0.0
	while t < 0.6 and float(_e.get("_whirl_t")) >= 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var y := _model_yaw()
		swept += absf(wrapf(y - prev_yaw, -PI, PI))
		prev_yaw = y
		fling[0] = maxf(fling[0], (_rest["handL"] as Vector3).x - _at("handL").x)
		fling[1] = maxf(fling[1], _at("handR").x - (_rest["handR"] as Vector3).x)
		eyes = player.global_position + Vector3.UP * 1.5
		face_off = maxf(face_off, absf(wrapf(_face_yaw_world() - _yaw_to(eyes), -PI, PI)))
	_check("bash: whirled a full turn", rad_to_deg(swept) >= 300.0, "(%.0f deg in %.2f s)" % [rad_to_deg(swept), t])
	_check("bash: arms flung out", fling[0] >= 0.25 and fling[1] >= 0.25, "(left %.3f m, right %.3f m)" % [fling[0], fling[1]])
	_check("bash: the face stayed on the player through the spin", face_off < 0.35, "(worst %.2f rad off)" % face_off)

	# (5) Idle: the player out of sight, or it re-acquires and keeps looking.
	player.global_position = Vector3(0, 0.1, 300)
	_e.set("sight_range", 0.0)
	_e.set("target", null)
	_e.call("set_state", 0)
	await _wait(1.2)
	var worst := 0.0
	for n in ["handL", "handR"]:
		worst = maxf(worst, _at(n).distance_to(_rest[n]))
	var fwd: Vector3 = -_e.global_transform.basis.z
	var face_rest := absf(wrapf(_face_yaw_world() - atan2(-fwd.x, -fwd.z), -PI, PI))
	_check("idle: head forward", face_rest < 0.05, "(%.3f rad)" % face_rest)
	_check("idle: hands at rest", worst < 0.03, "(%.3f m)" % worst)
	_check("idle: model facing forward", rad_to_deg(absf(_model_yaw())) < 5.0, "(%.1f deg)" % rad_to_deg(absf(_model_yaw())))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
