extends Node3D
## Probe: RONIN faces where it walks and shoots its revolvers.
## robot-killer_model.glb was imported facing +X, so the RONIN walked, dashed
## and cut sideways, its katana on its left side instead of its back.
## (1) facing: its two hands sit either side of the body across x (|x| > 0.2
##     each, opposite signs) and the katana's scabbard (Cube_023) is behind
##     it (z > +0.1);
## (2) every revolver slug leaves within 0.12 m of a drawn barrel's tip (the
##     barrel meshes' vertices, Material.040 / .041), the shots alternate
##     hands (left/right of the body), and at the shot that barrel points at
##     the player (within 20 deg; held, the barrels point at the floor).
##   godot --headless --path . --audio-driver Dummy res://tests/ronin_revolver_probe.tscn

const BARREL_MATS := ["Material.040", "Material.041"]

var ok := true

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

## Body-frame centroid of every vertex of the meshes under `n`.
func _centroid(e: Node3D, n: Node) -> Vector3:
	var inv := e.global_transform.affine_inverse()
	var c := Vector3.ZERO
	var k := 0
	var list: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		list.append(n)
	for m in list:
		var mi := m as MeshInstance3D
		for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			c += inv * mi.global_transform * (p as Vector3)
			k += 1
	return c / maxf(k, 1)

## World positions of every drawn barrel vertex.
func _barrel_verts(e: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in e.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat == null or not (mat.resource_name in BARREL_MATS):
				continue
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if idx.is_empty():
				for p in v:
					out.append(mi.global_transform * p)
			else:
				# Only vertices a triangle still uses (a split mesh keeps the
				# full vertex array and drops the other side's triangles).
				var used := {}
				for i in idx:
					used[i] = true
				for i in used:
					out.append(mi.global_transform * v[i])
	return out

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, 0)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	var e: Node3D = (load("res://scenes/enemies/ronin.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = Vector3(0, 0, -16)
	e.rotation = Vector3(0, PI, 0) # face the player
	# Frozen while it is measured: a moving RONIN leans and banks the model.
	# (RobotModel's deferred fit still runs.)
	e.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 4:
		await get_tree().physics_frame

	# (1) Facing, measured off the parts before anything moves.
	var hand_l := e.find_child("Cube_006", true, false)
	var hand_r := e.find_child("Cube_011", true, false)
	var scab := e.find_child("Cube_023", true, false)
	var hl := _centroid(e, hand_l)
	var hr := _centroid(e, hand_r)
	var sc := _centroid(e, scab)
	print("  hands %s %s, scabbard %s (body frame)" % [hl, hr, sc])
	_check("hands either side across x", absf(hl.x) > 0.2 and absf(hr.x) > 0.2 and signf(hl.x) != signf(hr.x))
	_check("katana on its back", sc.z > 0.1, "(z %.2f)" % sc.z)

	# (2) Slugs. Held at slug range: no dash, no closing for the katana.
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set("move_speed", 0.0)
	e.set("dash_cooldown", 999.0)
	e.set("_dash_cd", 999.0)
	var shots := []
	var cb := func(n: Node) -> void:
		if n is Node3D and n.has_method("launch") and shots.size() < 4:
			var mz: Vector3 = (e.get("muzzle") as Node3D).global_position
			var vs := _barrel_verts(e)
			var tip := Vector3.INF
			for p in vs:
				if p.distance_to(mz) < tip.distance_to(mz):
					tip = p
			var back := tip
			for p in vs:
				if p.distance_to(tip) < 0.4 and p.distance_to(tip) > back.distance_to(tip):
					back = p
			var to_player := (player.global_position + Vector3.UP * 1.0 - tip).normalized()
			var side := (e.global_transform.affine_inverse() * mz).x
			shots.append([mz.distance_to(tip), rad_to_deg((tip - back).normalized().angle_to(to_player)), side])
	get_tree().node_added.connect(cb)
	e.set("target", player)
	e.call("set_state", 4) # ATTACK
	var t := 0.0
	while shots.size() < 4 and t < 14.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	get_tree().node_added.disconnect(cb)
	_check("four slugs fired", shots.size() == 4, "(%d in %.1f s)" % [shots.size(), t])
	var sides := []
	for s in shots:
		print("  slug: %.3f m from a barrel tip, barrel %.1f deg off the player, side x %.2f" % [s[0], s[1], s[2]])
		_check("slug leaves a barrel tip", s[0] < 0.12, "(%.3f m)" % s[0])
		_check("barrel aimed at the player", s[1] < 20.0, "(%.1f deg)" % s[1])
		sides.append(signf(s[2]))
	var alternates := sides.size() >= 2
	for i in range(1, sides.size()):
		alternates = alternates and sides[i] != sides[i - 1]
	_check("shots alternate hands", alternates, str(sides))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
