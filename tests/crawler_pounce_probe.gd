extends Node3D
## Probe: the SPIDER's and SKITTER's pounce posture (CrawlerPounce on the
## two-legged disc walker). The Model node's scale and pitch are read; the
## rig frame must not carry them.
## For each of spider.tscn and skitter.tscn:
## (1) the coil: part way into the windup the Model is squashed (y scale
##     under 0.85) and tipped nose-down (pitch under -0.1 rad), while the
##     Mesh node read through rig_frame() is where it was at rest (within
##     0.01 m and 0.01 rad: the posture is a nudge the rig frame takes out);
## (2) the spring: in the first 0.12 s of the leap the Model is stretched
##     (y over 1.05); rising, the body pitches nose-up (over 0.1) with the
##     Hanging clip playing; falling, nose-down (under -0.1);
## (3) the landing: within 0.1 s of touching down the Model is squashed
##     (under 0.9), 0.5 s later it is back to rest (y over 0.98, pitch
##     within 0.03) and the Hanging clip has been released;
## (4) the bite plays the Attack clip (recoil spikes in _bite_if_close);
## (5) SPIDER only: the scuttle's assess freeze plays the Look clip, and
##     moving again drops it within 0.4 s.
##   godot --headless --path . --audio-driver Dummy res://tests/crawler_pounce_probe.tscn

var ok := true
var _e: CharacterBody3D
var _player: CharacterBody3D

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
	pm.size = Vector2(160, 160)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _model() -> Node3D:
	return _e.get_node("Model")

func _clip() -> String:
	return (_e.find_child("AnimationPlayer", true, false) as AnimationPlayer).current_animation

func _pitch() -> float:
	return _model().rotation.x

func _run_one(scene: String, label: String, with_assess: bool) -> void:
	_e = (load(scene) as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_e.set("sight_range", 0.0)
	_e.set("_leap_cd", 999.0)
	await _wait(0.6)
	var base_y: float = _model().scale.y
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var mesh_rest: Transform3D = (_e.call("rig_frame") as Transform3D).affine_inverse() * mesh_node.global_transform
	# A player 8 m ahead, in leap range, and the windup forced.
	_player.global_position = Vector3(0, 0.1, -8)
	_e.set("target", _player)
	_e.call("_begin_windup")
	var windup: float = _e.get("leap_windup")
	await _wait(minf(0.25, windup * 0.6))
	var sy: float = _model().scale.y / base_y
	var mesh_now: Transform3D = (_e.call("rig_frame") as Transform3D).affine_inverse() * mesh_node.global_transform
	var rf_off := mesh_now.origin.distance_to(mesh_rest.origin)
	var rf_turn := (mesh_now.basis.orthonormalized().inverse() * mesh_rest.basis.orthonormalized()).get_euler().length()
	_check("%s coils through the windup" % label, sy < 0.85 and _pitch() < -0.1 and rf_off < 0.01 and rf_turn < 0.01, "(scale y %.2f, pitch %.2f, windup %s; the Mesh in the rig frame moved %.3f m, turned %.3f rad)" % [sy, _pitch(), _e.get("_windup"), rf_off, rf_turn])
	# (2) the spring.
	var frames := 0
	while frames < 120 and not bool(_e.get("_leaping")):
		await get_tree().physics_frame
		frames += 1
	var leaping: bool = _e.get("_leaping")
	# Followed through the flight: the tallest the Model gets in the first
	# 0.12 s, the highest pitch while rising, the lowest while falling.
	var stretch := 0.0
	var pitch_up := -INF
	var pitch_down := INF
	var clip_up := ""
	var t := 0.0
	while bool(_e.get("_leaping")) and t < 3.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		if t < 0.12:
			stretch = maxf(stretch, _model().scale.y / base_y)
		if _e.velocity.y > 0.5:
			if _pitch() > pitch_up:
				pitch_up = _pitch()
				clip_up = _clip()
		elif _e.velocity.y < -0.5:
			pitch_down = minf(pitch_down, _pitch())
	_check("%s springs: stretched at take-off, nose up rising, nose down falling, hanging" % label, leaping and stretch > 1.05 and pitch_up > 0.1 and clip_up == "Hanging" and pitch_down < -0.1, "(stretch %.2f, pitch up to %.2f (clip %s), down to %.2f, flight %.2f s)" % [stretch, pitch_up, clip_up, pitch_down, t])
	# (3) the landing.
	frames = 0
	while frames < 300 and bool(_e.get("_leaping")):
		await get_tree().physics_frame
		frames += 1
	await get_tree().process_frame
	await get_tree().process_frame
	var land_sy: float = _model().scale.y / base_y
	await _wait(0.5)
	var rest_sy: float = _model().scale.y / base_y
	_check("%s lands: a squash that recovers, the Hanging clip released" % label, land_sy < 0.9 and rest_sy > 0.98 and absf(_pitch()) < 0.03 and _clip() != "Hanging", "(landing y %.2f, 0.5 s later %.2f, pitch %.2f, clip %s)" % [land_sy, rest_sy, _pitch(), _clip()])
	# (4) the bite, through the attack state (recoil spiked inside the physics
	# step, where RobotModel reads it; a spike from a process frame has decayed
	# by the next tick).
	_player.global_position = _e.global_position + Vector3(0, 0, -1.0)
	_e.set("_leap_cd", 999.0)
	_e.set("sight_range", 40.0)
	_e.call("set_state", 4) # ATTACK
	_e.set("_attack_timer", 0.0)
	frames = 0
	while frames < 30 and _clip() != "Attack":
		await get_tree().physics_frame
		frames += 1
	_check("%s bites with the Attack clip" % label, _clip() == "Attack", "(clip %s after %d ticks, state %s)" % [_clip(), frames, _e.get("state")])
	_e.set("sight_range", 0.0)
	_e.set("target", null)
	if with_assess:
		await _wait(0.5)
		_e.set_physics_process(false) # the physics step clears the freeze each tick
		_e.set("_frozen", true)
		await _wait(0.25)
		var look := _clip()
		_e.set("_frozen", false)
		await _wait(0.4)
		_check("%s looks around while it freezes to assess, then moves on" % label, look == "Look" and _clip() != "Look", "(frozen: %s, after: %s)" % [look, _clip()])
		_e.set_physics_process(true)
	_e.queue_free()
	await get_tree().process_frame

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.1, -300)
	_player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = _player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	await _run_one("res://scenes/enemies/spider.tscn", "SPIDER", true)
	await _run_one("res://scenes/enemies/skitter.tscn", "SKITTER", false)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
