extends Node3D
## Probe: the two siege walkers fire out of the guns their models carry.
## (1) WARMECH (Quaternius Mech, twin shoulder cannons): every shell of a
##     salvo leaves within 0.3 m of a cannon's muzzle, the salvo alternates
##     cannons, and the charge glows in both;
## (2) HOWITZER (walking_robot_gun.glb, one long barrel on its back): every
##     shell leaves within 0.3 m of the barrel's muzzle.
## Muzzles are found from the model itself at the moment of firing: the front
## vertices of each cannon on the POSED (skinned) mesh, or of the static Gun
## mesh, so the check shares no numbers with the code under test.
##   godot --headless --path . --audio-driver Dummy res://tests/siege_cannon_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## World positions of every vertex of `mi` as drawn this frame (skinned when rigged).
func _skinned(mi: MeshInstance3D) -> Array:
	var out := []
	var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin: Skin = mi.skin
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if sk == null or skin == null or arr[Mesh.ARRAY_BONES] == null:
			for p in v:
				out.append([mi.global_transform * p, ""])
			continue
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per: int = bones.size() / v.size()
		var mats: Array = []
		for b in skin.get_bind_count():
			var bi: int = skin.get_bind_bone(b)
			if bi < 0:
				bi = sk.find_bone(skin.get_bind_name(b))
			mats.append([sk.global_transform * sk.get_bone_global_pose(bi) * skin.get_bind_pose(b), sk.get_bone_name(bi)])
		for i in v.size():
			var acc := Vector3.ZERO
			var top := 0.0
			var topn := ""
			for j in per:
				var w: float = wts[i * per + j]
				if w <= 0.0:
					continue
				var m: Array = mats[bones[i * per + j]]
				acc += ((m[0] as Transform3D) * v[i]) * w
				if w > top:
					top = w
					topn = m[1]
			out.append([acc, topn])
	return out


## The weapon muzzles of `e` right now, in world space: WARMECH's two cannons
## (front 6 cm of vertices in its top 1.2 m, each side) or HOWITZER's barrel.
func _muzzles(e: Node3D, howitzer: bool) -> Array:
	var pts: Array = []
	for mi: MeshInstance3D in e.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or (howitzer and not String(mi.name).begins_with("Gun")):
			continue
		for p: Array in _skinned(mi):
			pts.append(e.to_local(p[0]))
	var hi := -99.0
	for l: Vector3 in pts:
		hi = maxf(hi, l.y)
	var out: Array = []
	for side: float in ([0.0] if howitzer else [-1.0, 1.0]):
		var minz := 99.0
		for l: Vector3 in pts:
			if (howitzer or (l.x * side > 0.15 and l.y > hi - 1.2)) and l.z < minz:
				minz = l.z
		var acc := Vector3.ZERO
		var n := 0
		for l: Vector3 in pts:
			if (howitzer or (l.x * side > 0.15 and l.y > hi - 1.2)) and l.z < minz + 0.06:
				acc += l
				n += 1
		out.append(e.to_global(acc / maxf(n, 1)))
	return out

## Shells fired by `e` within `frames`, each as [distance to the nearest muzzle,
## which muzzle (index)], sampled the frame the shell appears.
func _watch(e: EnemyBase, shell_scene: String, howitzer: bool, frames: int) -> Array:
	var shots: Array = []
	var pending: Array = []
	var on_added := func(n: Node) -> void:
		if n.scene_file_path == shell_scene:
			pending.append(n)
	get_tree().node_added.connect(on_added)
	for f in frames:
		await get_tree().physics_frame
		if e.state != EnemyBase.State.ATTACK and e.state != EnemyBase.State.STAGGER:
			e.set_state(EnemyBase.State.ATTACK)
		if e is EnemyWarmech and (e as EnemyWarmech)._winding and (e as EnemyWarmech)._windup_t < 0.1 and shots.is_empty() and not has_meta("orbs"):
			var tips := _muzzles(e, false)
			var orb_d: Array = []
			for orb: Node in e.find_children("*", "MeshInstance3D", true, false):
				if (orb as MeshInstance3D).mesh is SphereMesh:
					var d := 99.0
					for t: Vector3 in tips:
						d = minf(d, (orb as Node3D).global_position.distance_to(t))
					orb_d.append(d)
			set_meta("orbs", orb_d)
		for n: Node in pending:
			if not is_instance_valid(n):
				continue
			var tips := _muzzles(e, howitzer)
			var best := 99.0
			var which := -1
			for i in tips.size():
				var d: float = (n as Node3D).global_position.distance_to(tips[i])
				if d < best:
					best = d
					which = i
			shots.append([best, which])
		pending.clear()
	get_tree().node_added.disconnect(on_added)
	return shots

func _run() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(100, 1, 100)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	nav.add_child(sb)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	for i in 10:
		await get_tree().physics_frame

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	pcs.shape = cap
	pcs.position = Vector3(0, 0.9, 0)
	player.add_child(pcs)
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(0, 0.05, 0)

	# 1. WARMECH
	var wm: EnemyBase = (load("res://scenes/enemies/warmech.tscn") as PackedScene).instantiate()
	nav.add_child(wm)
	wm.global_position = Vector3(0, 0.2, -24.0)
	wm.rotation.y = PI # face the player, or it never sees it
	for i in 20:
		await get_tree().physics_frame
	wm.target = player
	wm.set_state(EnemyBase.State.ATTACK)
	var shots: Array = await _watch(wm, "res://scenes/weapons/projectile_warmech.tscn", false, 60 * 6)
	var far := 0.0
	var seq := ""
	for s: Array in shots:
		far = maxf(far, float(s[0]))
		seq += "LR"[int(s[1])] if int(s[1]) >= 0 else "?"
	var alt := shots.size() >= 3
	for i in range(1, shots.size()):
		alt = alt and shots[i][1] != shots[i - 1][1]
	_check("WARMECH: every shell leaves a shoulder cannon", shots.size() >= 3 and far < 0.3,
			"shells=%d farthest from a cannon muzzle=%.2f m" % [shots.size(), far])
	_check("WARMECH: the salvo alternates cannons", alt, "cannons %s" % seq)
	var orbs: Array = get_meta("orbs", [])
	var orbs_ok := orbs.size() == 2
	# 0.4 m: a full orb is ~0.35 m in radius, and the Shoot_Big pose is still
	# rearing during the charge (sampled a step behind it, ~0.26 m)
	for d: float in orbs:
		orbs_ok = orbs_ok and d < 0.4
	_check("WARMECH: the charge glows in both cannons", orbs_ok, "charge orbs %s m from a cannon" % [orbs])
	wm.queue_free()

	# 2. HOWITZER
	var hw: EnemyBase = (load("res://scenes/enemies/howitzer.tscn") as PackedScene).instantiate()
	nav.add_child(hw)
	hw.global_position = Vector3(0, 0.2, -26.0)
	hw.rotation.y = PI
	for i in 20:
		await get_tree().physics_frame
	hw.target = player
	hw.set_state(EnemyBase.State.ATTACK)
	var hshots: Array = await _watch(hw, "res://scenes/weapons/projectile_howitzer.tscn", true, 60 * 8)
	var hfar := 0.0
	for s: Array in hshots:
		hfar = maxf(hfar, float(s[0]))
	_check("HOWITZER: every shell leaves its barrel", hshots.size() >= 1 and hfar < 0.3,
			"shells=%d farthest from the barrel muzzle=%.2f m" % [hshots.size(), hfar])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
