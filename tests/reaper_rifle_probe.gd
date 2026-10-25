extends Node3D
## Probe: the REAPER (reaper.tscn, a static battle-droid soldier model carrying
## a heavy rifle at its right hip, no blades) fights like it looks:
## (1) closing in, it fires bursts out of the rifle's barrel: every shot leaves
##     the muzzle with the muzzle inside the rifle mesh's front end;
## (2) it fires on the move: it keeps closing while shooting (marching fire);
## (3) up close it strikes with the rifle (a lunge): damage + a shove.
##   godot --headless --path . --audio-driver Dummy res://tests/reaper_rifle_probe.tscn

const SCENE := "res://scenes/enemies/reaper.tscn"
const RIFLE_MESH := "Gun2" ## the rifle body in another_robot.glb (its Gun2 material, kept whole by the offline leg cut; front end at the barrel)
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## Distance from `p` to the rifle's barrel end (its vertices within 0.08 m
## of its front-most point, in the body's frame).
func _off_barrel(e: Node3D, p: Vector3) -> float:
	var mi: MeshInstance3D = e.find_child(RIFLE_MESH, true, false)
	var best := 99.0
	# The barrel end: the rifle's vertices within 0.08 m of its front-most point.
	for s in mi.mesh.get_surface_count():
		for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var w: Vector3 = mi.global_transform * v
			var local := e.to_local(w)
			if local.z < _front_z(e, mi) + 0.08:
				best = minf(best, w.distance_to(p))
	return best

var _front_cache := {}
func _front_z(e: Node3D, mi: MeshInstance3D) -> float:
	var key := mi.get_instance_id()
	if _front_cache.has(key):
		return _front_cache[key]
	var z := 99.0
	for s in mi.mesh.get_surface_count():
		for v in (mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			z = minf(z, e.to_local(mi.global_transform * v).z)
	_front_cache[key] = z
	return z

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

	var rp: EnemyBase = (load(SCENE) as PackedScene).instantiate()
	nav.add_child(rp)
	rp.global_position = Vector3(0, 0.2, -22.0)
	rp.rotation.y = PI # face the player, or it never sees it
	for i in 20:
		await get_tree().physics_frame
	var floor_y := rp.global_position.y
	rp.target = player
	rp.set_state(EnemyBase.State.CHASE)

	# 1-2. Closing from 22 m: shots, where the muzzle is, and whether it moves.
	var shots: Array = [] # [muzzle distance from the barrel end, horizontal speed, distance to player]
	var on_added := func(n: Node) -> void:
		if n.scene_file_path.ends_with("tracer_red.tscn") and is_instance_valid(rp):
			shots.append([_off_barrel(rp, rp.muzzle.global_position),
					Vector2(rp.velocity.x, rp.velocity.z).length(),
					rp.global_position.distance_to(player.global_position)])
	get_tree().node_added.connect(on_added)
	var d0 := rp.global_position.distance_to(player.global_position)
	for f in 60 * 4:
		await get_tree().physics_frame
		if rp.global_position.distance_to(player.global_position) < 6.0:
			break
	get_tree().node_added.disconnect(on_added)
	var far := 0.0
	var moving := 0
	for s in shots:
		far = maxf(far, float(s[0]))
		if float(s[1]) > 3.0:
			moving += 1
	_check("it fires out of the rifle barrel", shots.size() >= 3 and far < 0.2,
			"shots=%d farthest from the barrel end=%.2f m" % [shots.size(), far])
	var d1 := rp.global_position.distance_to(player.global_position)
	_check("it fires on the move while closing", moving >= 2 and d0 - d1 > 6.0,
			"shots on the move=%d closed %.1f m" % [moving, d0 - d1])

	# 3. Up close: the rifle strike.
	rp.global_position = Vector3(0, floor_y, -2.2)
	rp.velocity = Vector3.ZERO
	rp.set_state(EnemyBase.State.ATTACK)
	rp._attack_timer = 0.0
	player.velocity = Vector3.ZERO
	var hp0 := pdmg.current_health
	var knock := 0.0
	var melee_hit := false
	for f in 60 * 3:
		await get_tree().physics_frame
		player.global_position = Vector3(0, 0.05, 0)
		var v := Vector2(player.velocity.x, player.velocity.z).length()
		if v > knock:
			knock = v
		if pdmg.current_health < hp0 and knock > 4.0:
			melee_hit = true
			break
		player.velocity = Vector3.ZERO
	_check("up close it strikes with the rifle and shoves", melee_hit,
			"dmg=%.0f knock=%.1f m/s" % [hp0 - pdmg.current_health, knock])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
