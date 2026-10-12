extends Node3D
## Probe: the GUNSLINGER raises its gun-arm onto you and fires from it.
## steampunk_robot.glb hangs a revolver forearm at its right side (both
## forearms are one mesh, Object_158), while every slug left from a point in
## mid-air 0.7 m ahead of its chest. Measured off the model in the body frame,
## from the drawn forearm vertices on its right (x > 0): the elbow is their
## top band, the gun's tip the vertices farthest from it.
## (1) not engaged: the gun-arm hangs (pointing down);
## (2) engaged at 14 m: every slug (a recoil spike) leaves within 0.12 m of
##     the gun's tip, with the arm within 20 deg of the player;
## (3) disengaged (held idle, player out of sight): the arm hangs again
##     (within 10 deg) inside 2 s.
##   godot --headless --path . --audio-driver Dummy res://tests/gunslinger_arm_probe.tscn

var ok := true
var _e: Node3D

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

## Elbow and gun tip, measured once at rest off the right forearm (top band;
## the vertices farthest from it), kept in the forearm mesh's own frame so
## they follow the arm however it is posed. A top band is only the elbow while
## the arm hangs.
var _local_elbow := Vector3.ZERO
var _local_tip := Vector3.ZERO

func _measure_rest() -> void:
	var mi := _e.find_child("Object_158", true, false) as MeshInstance3D
	var arm := PackedVector3Array()
	for q in PartRig.body_points(_e, mi):
		if q.x > 0.0:
			arm.append(q)
	var top := -INF
	for q in arm:
		top = maxf(top, q.y)
	var band := PackedVector3Array()
	for q in arm:
		if q.y > top - 0.04:
			band.append(q)
	var elbow := PartRig.mean(band)
	var far := 0.0
	for q in arm:
		far = maxf(far, q.distance_to(elbow))
	var tip := PackedVector3Array()
	for q in arm:
		if q.distance_to(elbow) > far - 0.03:
			tip.append(q)
	var to_local := mi.global_transform.affine_inverse() * _e.global_transform
	_local_elbow = to_local * elbow
	_local_tip = to_local * PartRig.mean(tip)

## [elbow, tip] in the body frame, through whichever right-forearm mesh is drawn.
func _rifle() -> Array:
	var orig := _e.find_child("Object_158", true, false) as MeshInstance3D
	var drawn: MeshInstance3D = orig
	for m in orig.get_parent().find_children("Object_158_R", "MeshInstance3D", false, false):
		drawn = m
	var xf := _e.global_transform.affine_inverse() * drawn.global_transform
	return [xf * _local_elbow, xf * _local_tip]

func _drawn(name: String) -> PackedVector3Array:
	var n := _e.find_child(name, true, false)
	var out := PackedVector3Array()
	for m in n.get_parent().find_children("*", "MeshInstance3D", false, false):
		var mi := m as MeshInstance3D
		if mi.is_visible_in_tree() and (mi == n or String(mi.name).begins_with(name)):
			out.append_array(PartRig.body_points(_e, mi))
	return out

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -14)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	_e = (load("res://scenes/enemies/gunslinger.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3.ZERO
	_e.process_mode = Node.PROCESS_MODE_DISABLED # frozen while the rest pose is read
	for i in 4:
		await get_tree().physics_frame
	_measure_rest()
	var r0: Array = _rifle()
	var rest_dir: Vector3 = ((r0[1] as Vector3) - (r0[0] as Vector3)).normalized()
	print("  rest arm %s" % rest_dir)
	_check("gun-arm hangs when not engaged", rest_dir.y < -0.8, "(arm %s)" % rest_dir)
	_e.process_mode = Node.PROCESS_MODE_INHERIT
	_e.set("move_speed", 0.0)
	_e.set("_dodge_cd", 999.0)
	_e.set("target", player)
	_e.call("set_state", 4) # ATTACK

	var shots := []
	var prev := 0.0
	var t := 0.0
	while t < 12.0 and shots.size() < 4:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var rc: float = _e.get("recoil")
		if rc > 0.95 and prev <= 0.95:
			var r: Array = _rifle()
			var mz: Vector3 = _e.global_transform.affine_inverse() * (_e.get("muzzle") as Node3D).global_position
			var to_p: Vector3 = _e.global_transform.affine_inverse() * (player.global_position + Vector3.UP * 0.6) - (r[1] as Vector3)
			var bdir: Vector3 = ((r[1] as Vector3) - (r[0] as Vector3)).normalized()
			shots.append([mz.distance_to(r[1]), rad_to_deg(bdir.angle_to(to_p.normalized()))])
		prev = rc
	_check("slugs fired", shots.size() >= 2, "(%d in %.1f s)" % [shots.size(), t])
	for s in shots:
		print("  slug: %.3f m from the gun tip, arm %.1f deg off the player" % [s[0], s[1]])
		_check("slug leaves the gun tip", s[0] < 0.12, "(%.3f m)" % s[0])
		_check("arm on the player", s[1] < 20.0, "(%.1f deg)" % s[1])

	player.global_position = Vector3(0, 0.1, 150) # out of its sight: it does not reacquire
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	t = 0.0
	var back := false
	var d := Vector3.ZERO
	while t < 2.0 and not back:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		# Held disengaged: a robot that still knows your last position walks
		# there rifle up (correctly), which is not what this step measures.
		_e.call("set_state", 0)
		var r: Array = _rifle()
		d = ((r[1] as Vector3) - (r[0] as Vector3)).normalized()
		back = rad_to_deg(d.angle_to(rest_dir)) < 10.0
	_check("arm hangs again when it loses you", back, "(%.0f deg after %.1f s)" % [rad_to_deg(d.angle_to(rest_dir)), t])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
