extends Node3D
## Probe: robots whose model carries a gun on a "Gun" bone fire from that
## gun's barrel, not from a fixed point in the air. For HUNTER, DIFFUSION,
## OVERFITTER, DEEPFAKE, HIVE and QUANTIZER (a flyer), every shot (a projectile or tracer spawned
## while it fights a stand-in player) is fired with the muzzle within 0.25 m of
## the barrel's front: the front-most vertices skinned to the Gun bone, on the
## mesh as posed that frame, so the check shares no numbers with the code.
## (The old fixed muzzles measured 0.42-2.59 m off; QUANTIZER's 1.24-1.34 m.)
## The twin-barrel guns (HUNTER, OVERFITTER) must alternate barrels: each shot
## within 0.25 m of one barrel's front, the next from the other (#253).
##   godot --headless --path . --audio-driver Dummy res://tests/gun_muzzle_probe.tscn

const SCENES := ["hunter", "diffusion", "overfitter", "deepfake", "hive", "quantizer"]
const TWIN := ["hunter", "overfitter"] ## guns with a barrel each side of the bone
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
			mats.append([sk.global_transform * _drawn(sk, bi) * skin.get_bind_pose(b), sk.get_bone_name(bi)])
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


## A bone's pose as last drawn: the robot's HeadTrack aims the gun after the
## clip, and outside the skeleton's update the bone reads as the clip alone.
func _drawn(sk: Skeleton3D, idx: int) -> Transform3D:
	var track := sk.get_node_or_null("HeadTrack") as HeadTrackModifier
	var clip := sk.get_bone_global_pose(idx)
	return track.rendered_pose(idx, clip) if track else clip

## The front of the gun: centroid of the Gun-bone vertices within 5 cm of the
## front-most one along the gun's own axis (the bone's +Z, the way every
## barrel here points), in world space. Measured along the gun, not the body:
## a gun pitching through its Shoot clip changes which lip is front-most
## along the body's forward, and the twin-barrel guns (HUNTER, OVERFITTER)
## resolve to the centre of their front face either way.
func _barrel_front(e: Node3D, side: float = 0.0) -> Vector3:
	var sk: Skeleton3D = e.find_children("*", "Skeleton3D", true, false)[0]
	var pose: Transform3D = sk.global_transform * _drawn(sk, sk.find_bone("Gun"))
	var frame := Transform3D(pose.basis.orthonormalized(), pose.origin)
	var inv := frame.affine_inverse()
	var pts: Array = []
	for mi: MeshInstance3D in e.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for p: Array in _skinned(mi):
			if p[1] == "Gun":
				var l: Vector3 = inv * (p[0] as Vector3)
				if side == 0.0 or l.x * side > 0.05: # one barrel of a twin gun
					pts.append(l)
	var maxz := -99.0
	for l: Vector3 in pts:
		maxz = maxf(maxz, l.z)
	var acc := Vector3.ZERO
	var n := 0
	for l: Vector3 in pts:
		if l.z > maxz - 0.05:
			acc += l
			n += 1
	return frame * (acc / maxf(n, 1))

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

	for name: String in SCENES:
		var e: EnemyBase = (load("res://scenes/enemies/%s.tscn" % name) as PackedScene).instantiate()
		nav.add_child(e)
		e.global_position = Vector3(0, 0.2, -14.0)
		e.rotation.y = PI # face the player, or it never sees it
		for i in 20:
			await get_tree().physics_frame
		e.target = player
		e.set_state(EnemyBase.State.ATTACK)
		var fired: Array = [] # shots spawned this frame, checked after it
		var on_added := func(n: Node) -> void:
			if n is Projectile or n.scene_file_path.contains("tracer"):
				fired.append(n)
		get_tree().node_added.connect(on_added)
		var dists: Array = []
		var sides := ""
		for f in 60 * 7:
			await get_tree().physics_frame
			if not is_instance_valid(e):
				break
			if e.state != EnemyBase.State.ATTACK and e.state != EnemyBase.State.STAGGER:
				e.set_state(EnemyBase.State.ATTACK)
			if not fired.is_empty():
				fired.clear()
				if dists.size() < 6:
					if name in TWIN:
						var dl := e.muzzle.global_position.distance_to(_barrel_front(e, -1.0))
						var dr := e.muzzle.global_position.distance_to(_barrel_front(e, 1.0))
						dists.append(snappedf(minf(dl, dr), 0.01))
						sides += "L" if dl < dr else "R"
					else:
						dists.append(snappedf(e.muzzle.global_position.distance_to(_barrel_front(e)), 0.01))
		get_tree().node_added.disconnect(on_added)
		var far := 0.0
		for d: float in dists:
			far = maxf(far, d)
		_check("%s fires from its gun's barrel" % name.to_upper(), dists.size() >= 2 and far < 0.25,
				"shots sampled=%d muzzle-to-barrel %s m" % [dists.size(), dists])
		if name in TWIN:
			var alt := sides.length() >= 4
			for i in range(1, sides.length()):
				alt = alt and sides[i] != sides[i - 1]
			_check("%s alternates its twin barrels" % name.to_upper(), alt, "barrels %s" % sides)
		if is_instance_valid(e):
			e.queue_free()
		for i in 10:
			await get_tree().physics_frame

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
