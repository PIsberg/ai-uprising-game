extends Node3D
## Probe: the BOWLER ("STRIKER-9", Mike.fbx: a heavy biped whose Punch clip
## draws its right fist back to z +0.98 at 0.20 s and drives it out to
## z -1.6 at 0.40-0.45 s) bowls like it looks:
## (1) every Molten Orb appears at its right fist (PalmI.R, within 0.5 m),
##     0.35 s or more into the Punch swing: released at the extension, not
##     conjured in front of its chest the instant the clip starts;
## (2) during the wind-up a glowing orb is held in that fist (a visible
##     sphere within 0.4 m of the palm) before it is thrown.
##   godot --headless --path . --audio-driver Dummy res://tests/bowler_throw_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _palm(e: Node3D) -> Vector3:
	var sk: Skeleton3D = e.find_children("*", "Skeleton3D", true, false)[0]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("PalmI.R")).origin

## A visible sphere mesh (not part of the model) within `r` of the right palm.
func _held_orb(e: Node3D, r: float) -> bool:
	var palm := _palm(e)
	for mi: MeshInstance3D in e.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is SphereMesh and mi.is_visible_in_tree() and mi.global_position.distance_to(palm) < r:
			return true
	return false

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

	var bw: EnemyBase = (load("res://scenes/enemies/bowler.tscn") as PackedScene).instantiate()
	nav.add_child(bw)
	bw.global_position = Vector3(0, 0.2, -18.0)
	bw.rotation.y = PI # face the player, or it never sees it
	for i in 20:
		await get_tree().physics_frame
	bw.target = player
	bw.set_state(EnemyBase.State.ATTACK)
	var anim: AnimationPlayer = bw.find_children("*", "AnimationPlayer", true, false)[0]
	var throws: Array = [] # [distance from the right palm, seconds into Punch (-1 = not playing)]
	var pending: Array = []
	var on_added := func(n: Node) -> void:
		if n is EnemyOrb:
			pending.append(n)
	get_tree().node_added.connect(on_added)
	var held := 0
	for f in 60 * 14:
		await get_tree().physics_frame
		if bw.state != EnemyBase.State.ATTACK and bw.state != EnemyBase.State.STAGGER:
			bw.set_state(EnemyBase.State.ATTACK)
		if throws.is_empty() and _held_orb(bw, 0.4):
			held += 1
		for n: Node in pending:
			if is_instance_valid(n):
				var into := anim.current_animation_position if anim.current_animation == "Punch" else -1.0
				throws.append([snappedf((n as Node3D).global_position.distance_to(_palm(bw)), 0.01), snappedf(into, 0.01)])
		pending.clear()
		if throws.size() >= 2:
			break
	get_tree().node_added.disconnect(on_added)
	var from_fist := throws.size() >= 2
	for t: Array in throws:
		from_fist = from_fist and float(t[0]) < 0.5 and float(t[1]) >= 0.35
	_check("each orb leaves its right fist at the swing's extension", from_fist,
			"throws [palm distance m, s into Punch] = %s" % [throws])
	_check("it holds a glowing orb in that fist through the wind-up", held >= 10,
			"%d frames with an orb in the fist before the first throw" % held)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
