extends Node3D
## Probe: RONIN draws its katana and cuts with it.
## The katana stayed sheathed on its back through the two-cut combo. Measured
## off the GLB's own handle parts (Cylinder_003, Circle_040 and the guard
## Cube_024), in the robot's body frame:
## (1) sheathed while nobody is near: the handle sits where the model has it;
## (2) a player within 2 m: the sword is drawn: the blade no longer hangs
##     point-down in its sheath (blade y > -0.5) and the guard is in front of
##     the body (z < -0.15) between 0.8 and 1.8 m up. (A lunging, leaning
##     RONIN alone pushes the sheathed guard 0.25 m forward, so position is
##     not enough);
## (3) every cut that hurts the player lands with the blade (guard minus
##     handle centre) pointing forward (z < -0.3), and each cut's blade sweeps
##     at least 90 deg;
## (4) the player gone (16 m away): the sword is back in its sheath (handle
##     within 0.05 m of rest, blade within 10 deg of its rest direction)
##     inside 3 s.
##   godot --headless --path . --audio-driver Dummy res://tests/ronin_katana_probe.tscn

const HANDLE := ["Cylinder_003", "Circle_040"]
const GUARD := "Cube_024"

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

## Body-frame centroid of the drawn vertices of the named parts.
func _centroid(names: Array) -> Vector3:
	var inv := _e.global_transform.affine_inverse()
	var c := Vector3.ZERO
	var k := 0
	for nm in names:
		var n := _e.find_child(nm, true, false)
		for m in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
			var mi := m as MeshInstance3D
			if not mi.is_visible_in_tree():
				continue
			for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				c += inv * mi.global_transform * (p as Vector3)
				k += 1
	return c / maxf(k, 1)

func _blade() -> Vector3:
	return (_centroid([GUARD]) - _centroid(HANDLE)).normalized()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 30)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	_e = (load("res://scenes/enemies/ronin.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3.ZERO
	_e.process_mode = Node.PROCESS_MODE_DISABLED # frozen while the rest pose is read
	for i in 4:
		await get_tree().physics_frame
	var rest := _centroid(HANDLE)
	var rest_blade := _blade()
	print("  rest handle %s, blade %s" % [rest, _blade()])
	_e.process_mode = Node.PROCESS_MODE_INHERIT
	_e.set("move_speed", 0.0)
	_e.set("dash_cooldown", 999.0)
	_e.set("_dash_cd", 999.0)
	_e.set("slug_cooldown", 999.0)
	_e.set("_slug_cd", 999.0)
	for i in 30:
		await get_tree().physics_frame
	_check("sheathed with nobody near", _centroid(HANDLE).distance_to(rest) < 0.05, "(%.3f m)" % _centroid(HANDLE).distance_to(rest))

	# Close in: 2 m in front of it.
	player.global_position = _e.global_transform * Vector3(0, 0.1, -2.0)
	_e.set("target", player)
	_e.call("set_state", 4) # ATTACK
	var drawn := false
	var t := 0.0
	while t < 1.0 and not drawn:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var g := _centroid([GUARD])
		drawn = g.z < -0.15 and g.y > 0.8 and g.y < 1.8 and _blade().y > -0.5
	_check("katana drawn in front of it", drawn, "(guard %s after %.2f s)" % [_centroid([GUARD]), t])

	# Cuts: blade direction when each hit lands, and the sweep of each cut.
	var at_hit: Array[Vector3] = []
	var hit_cb := func(_a: float, src) -> void:
		if src == _e:
			at_hit.append(_blade())
	php.damaged.connect(hit_cb)
	var dirs: Array[Vector3] = []
	var times: Array[float] = []
	t = 0.0
	while t < 4.0 and at_hit.size() < 4:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		player.global_position = _e.global_transform * Vector3(0, 0.1, -2.0)
		dirs.append(_blade())
		times.append(t)
	php.damaged.disconnect(hit_cb)
	_check("cuts landed", at_hit.size() >= 2, "(%d)" % at_hit.size())
	for b in at_hit:
		_check("cut lands with the blade forward", b.z < -0.3, "(blade %s)" % b)
	# Sweep: the widest angle the blade covers inside any 0.2 s window.
	var sweep := 0.0
	for i in dirs.size():
		for j in range(i + 1, dirs.size()):
			if times[j] - times[i] > 0.2:
				break
			sweep = maxf(sweep, rad_to_deg(dirs[i].angle_to(dirs[j])))
	_check("a cut sweeps the blade 90+ deg", sweep >= 90.0, "(%.0f deg)" % sweep)

	# Walk away: sheathed again.
	player.global_position = _e.global_transform * Vector3(0, 0.1, -16.0)
	t = 0.0
	var back := false
	while t < 3.0 and not back:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		back = _centroid(HANDLE).distance_to(rest) < 0.05 and rad_to_deg(_blade().angle_to(rest_blade)) < 10.0
	_check("sheathed again once you are gone", back, "(%.3f m after %.1f s)" % [_centroid(HANDLE).distance_to(rest), t])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
