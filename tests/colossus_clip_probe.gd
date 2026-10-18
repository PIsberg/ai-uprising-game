extends Node3D
## Probe: GOLIATH-IX's George rig acts out each attack and its markers ride the
## body. The rig's clips used to be one generic Shoot for every attack, and the
## reactor, eye and muzzles were plain children of the boss while the Body bone
## bobs ~1.9 m through each walk cycle and leaps ~3.8 m in the Jump clip.
## (1) walking: every seismic footfall ring lands under a planted foot (foot
##     within 0.3 m of the floor, ring within 1.5 m of it), at least 3 in 4 s;
## (2) walking: the reactor rides the Body bone (their height gap varies
##     < 0.1 m);
## (3) ground slam: the Jump clip plays, the Body leaps >= 2.5 m over its idle
##     height in the windup and is back down (< +0.4 m) when the slam lands;
## (4) artillery plays Shoot;
## (5) the sweeping beam holds Shoot for its whole sweep.
##   godot --headless --path . --audio-driver Dummy res://tests/colossus_clip_probe.tscn

var ok := true
var _e: CharacterBody3D
var _ap: AnimationPlayer
var _sk: Skeleton3D

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
	nm.agent_radius = 1.5
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## A bone's position in the boss's world.
func _bone(n: String) -> Vector3:
	return _sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone(n)).origin

## Height above the boss's feet (body frame).
func _h(world: Vector3) -> float:
	return (_e.global_transform.affine_inverse() * world).y

func _footfall_rings() -> Array:
	var out := []
	for c in get_tree().current_scene.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is TorusMesh \
				and is_equal_approx(((c as MeshInstance3D).mesh as TorusMesh).inner_radius, 0.85):
			out.append(c)
	return out

func _physics_wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/colossus.tscn") as PackedScene).instantiate()
	_e.set("preview", true) # no sky-drop: the probe drives it
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	await _physics_wait(0.5)
	_ap = _e.find_children("*", "AnimationPlayer", true, false)[0]
	_sk = _e.find_children("*", "Skeleton3D", true, false)[0]
	_e.set_physics_process(true)
	(_e.get("hp") as Node).set("invulnerable", false)
	var reactor: Node3D = _e.get_node("Reactor")

	# (1) + (2) walking toward a far target.
	var goal: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(goal)
	goal.global_position = Vector3(0, 0.1, -60) # inside its 70 m sight, past its 34 m lumber band
	goal.set_physics_process(false)
	var php: Node = goal.get_node("Damageable")
	php.set("max_health", 1000000.0)
	php.set("current_health", 1000000.0)
	_e.set("target", goal)
	_e.call("set_state", 3) # CHASE
	await _physics_wait(1.0) # up to its lumber
	var seen := {}
	for r in _footfall_rings():
		seen[r] = true
	var rings := 0
	var bad := []
	var gap := Vector2(INF, -INF)
	var t := 0.0
	while t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var g := _h(reactor.global_position) - _h(_bone("Body"))
		gap = Vector2(minf(gap.x, g), maxf(gap.y, g))
		for r in _footfall_rings():
			if seen.has(r):
				continue
			seen[r] = true
			rings += 1
			var near := INF
			for f in ["Foot.L", "Foot.R"]:
				var fp := _bone(f)
				if _h(fp) < 0.3:
					near = minf(near, Vector2(fp.x - r.global_position.x, fp.z - r.global_position.z).length())
			if near > 1.5:
				bad.append("%.2f m" % near)
	print("  walked at %.1f m/s" % Vector2(_e.velocity.x, _e.velocity.z).length())
	_check("footfalls quake while it walks", rings >= 3, "(%d in 4 s)" % rings)
	_check("every footfall lands under a planted foot", bad.is_empty(), "(off by %s)" % ", ".join(bad))
	_check("the reactor rides the body", gap.y - gap.x < 0.1, "(gap varied %.2f m)" % (gap.y - gap.x))

	# Park it.
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.velocity = Vector3.ZERO
	await _physics_wait(2.0)
	var idle_y := _h(_bone("Body"))

	# (3) ground slam
	_e.call("_begin_slam")
	await get_tree().physics_frame
	_check("the slam plays the Jump clip", _ap.current_animation == "Jump", "(%s)" % _ap.current_animation)
	var peak := -INF
	var at_impact := INF
	while true:
		var before: float = _e.get("_slam_windup")
		await get_tree().process_frame
		peak = maxf(peak, _h(_bone("Body")) - idle_y)
		if before > 0.0 and float(_e.get("_slam_windup")) <= 0.0:
			at_impact = _h(_bone("Body")) - idle_y
			break
	_check("it leaps in the windup", peak >= 2.5, "(+%.2f m)" % peak)
	_check("and is down when the slam lands", at_impact < 0.4, "(%+.2f m)" % at_impact)
	await _physics_wait(1.5)

	# (4) artillery
	_e.set("target", goal)
	_e.call("_fire_artillery")
	await _physics_wait(0.1)
	_check("artillery plays Shoot", _ap.current_animation == "Shoot", "(%s)" % _ap.current_animation)
	await _physics_wait(1.5)

	# (5) beam
	_e.call("_begin_beam")
	var held := []
	for s in [0.4, 0.5, 0.4]:
		await _physics_wait(s)
		held.append(String(_ap.current_animation))
	_check("the beam holds Shoot through its sweep", held == ["Shoot", "Shoot", "Shoot"], "(%s)" % [held])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
