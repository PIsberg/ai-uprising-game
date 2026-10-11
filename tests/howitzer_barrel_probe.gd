extends Node3D
## Probe: the HOWITZER lays and fires the barrel its model carries.
## walking_robot_gun.glb keeps the 3.6 m barrel as its own node (Gun), so the
## gun can move like artillery instead of staying welded flat to the back:
## (1) at the shot the barrel points along the shell's launch pitch (within
##     2.5 deg), for a near target (shell dips down at it) and a far one
##     (shell lofted), and the far shot sits at least 4 deg higher;
## (2) the shell leaves from the barrel's front end as drawn (within 0.3 m);
## (3) the shot slides the barrel back along its own axis by 0.3 m or more,
##     and it runs out again (back within 0.06 m) inside 2 s;
## (4) no drawn mesh outside the Gun keeps a copy of the barrel's muzzle end
##     (the GLB's Cell meshes duplicate the whole model, barrel included, and
##     left a ghost barrel behind when the real one laid).
## The barrel is measured from the Gun mesh's vertices (front-end centroid and
## a centroid 1.4 m further back), so the check shares no numbers with the
## code under test.
##   godot --headless --path . --audio-driver Dummy res://tests/howitzer_barrel_probe.tscn

var ok := true
var _player: Node3D

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
	pm.size = Vector2(140, 140)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## Barrel front-end centroid and a centroid 1.4 m behind it, in the Gun mesh's
## own frame (fixed for the life of the mesh, whatever the gun node does).
func _barrel_local(e: Node3D, gm: MeshInstance3D) -> Array:
	var v: PackedVector3Array = gm.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var to_body := e.global_transform.affine_inverse() * gm.global_transform
	var min_z := 1e9
	for p in v:
		min_z = minf(min_z, (to_body * p).z)
	var front := Vector3.ZERO
	var mid := Vector3.ZERO
	var nf := 0
	var nm := 0
	for p in v:
		var z := (to_body * p).z
		if z < min_z + 0.1:
			front += p
			nf += 1
		elif absf(z - (min_z + 1.4)) < 0.08:
			mid += p
			nm += 1
	return [front / maxf(nf, 1), mid / maxf(nm, 1)]

## One engagement at `dist` m: returns [barrel pitch at the shot, launch pitch,
## muzzle-to-front distance, kick (m along the barrel), residual kick after 2 s].
func _engage(dist: float) -> Array:
	var e: Node3D = (load("res://scenes/enemies/howitzer.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = Vector3(0, 0, -dist)
	e.rotation = Vector3(0, PI, 0) # face the player: sight forward is -Z
	for i in 6:
		await get_tree().physics_frame
	e.set("preferred_range", dist) # hold the spot: kick is read in the body frame,
	e.set("move_speed", 0.0)       # and a walk changes the range (and so the lay)
	var inv := func() -> Transform3D: return e.global_transform.affine_inverse()
	var gun := e.find_child("Gun", true, false) as Node3D
	var gm := gun.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var loc: Array = _barrel_local(e, gm)
	if dist < 20.0:
		var tip: Vector3 = gm.global_transform * (loc[0] as Vector3)
		var ghosts := []
		for m in e.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if not mi.is_visible_in_tree() or gun.is_ancestor_of(mi):
				continue
			for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if (mi.global_transform * (p as Vector3)).distance_to(tip) < 0.12:
					ghosts.append(String(mi.name))
					break
		_check("no ghost copy of the barrel left on the body", ghosts.is_empty(), str(ghosts))
	var shot := [null]
	var at_shot := []
	var cb := func(n: Node) -> void:
		if shot[0] == null and n is Node3D and n.has_method("launch") and n.scene_file_path.contains("howitzer"):
			shot[0] = n
			var f: Vector3 = gm.global_transform * (loc[0] as Vector3)
			var m: Vector3 = gm.global_transform * (loc[1] as Vector3)
			at_shot.append_array([f, m, (e.get("muzzle") as Node3D).global_position])
	get_tree().node_added.connect(cb)
	e.set("target", _player)
	e.call("set_state", 4) # State.ATTACK
	var before := Vector3.ZERO
	var t := 0.0
	while shot[0] == null and t < 12.0:
		before = (inv.call() as Transform3D) * gm.global_transform * (loc[0] as Vector3)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	get_tree().node_added.disconnect(cb)
	if shot[0] == null:
		e.queue_free()
		return []
	await get_tree().physics_frame
	var vel: Vector3 = shot[0].get("_velocity")
	var axis: Vector3 = ((at_shot[0] as Vector3) - (at_shot[1] as Vector3)).normalized()
	var axis_b: Vector3 = (inv.call() as Transform3D).basis.orthonormalized() * axis
	var kick := 0.0
	var tt := 0.0
	while tt < 0.35:
		kick = maxf(kick, (before - (inv.call() as Transform3D) * gm.global_transform * (loc[0] as Vector3)).dot(axis_b))
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
	while tt < 2.0:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
	var rest: float = (before - (inv.call() as Transform3D) * gm.global_transform * (loc[0] as Vector3)).dot(axis_b)
	var out := [rad_to_deg(asin(axis.y)), rad_to_deg(asin(vel.normalized().y)),
		(at_shot[2] as Vector3).distance_to(at_shot[0]), kick, rest]
	e.queue_free()
	await get_tree().physics_frame
	return out

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_player.set_physics_process(false)
	await get_tree().physics_frame
	var hp: Node = _player.get_node_or_null("Damageable")
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	var pitches := {}
	for dist in [18.0, 48.0]:
		var r: Array = await _engage(dist)
		_check("shell fired at %d m" % dist, not r.is_empty())
		if r.is_empty():
			continue
		print("  %d m: barrel %.1f deg, launch %.1f deg, muzzle-front %.2f m, kick %.2f m, after 2 s %.3f m"
			% [dist, r[0], r[1], r[2], r[3], r[4]])
		pitches[dist] = r[0]
		_check("barrel laid on the launch pitch at %d m" % dist, absf(r[0] - r[1]) < 2.5,
			"(%.1f vs %.1f deg)" % [r[0], r[1]])
		_check("shell leaves the barrel's front at %d m" % dist, r[2] < 0.3, "(%.2f m)" % r[2])
		_check("barrel kicks back on the shot at %d m" % dist, r[3] >= 0.3, "(%.2f m)" % r[3])
		_check("barrel runs out again at %d m" % dist, absf(r[4]) < 0.06, "(%.3f m)" % r[4])
	if pitches.size() == 2:
		_check("far shot elevated over the near one", pitches[48.0] - pitches[18.0] >= 4.0,
			"(%.1f vs %.1f deg)" % [pitches[48.0], pitches[18.0]])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
