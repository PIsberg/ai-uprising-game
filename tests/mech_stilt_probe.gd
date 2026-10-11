extends Node3D
## Probe: the MECH (enemy_mech.gd, Quaternius "Stan": a lean robot on spike
## stilts, one open hand, no launcher) fights like it looks:
## (1) it lopes: Run clip while moving, 5+ m/s on the approach;
## (2) at range it fires bolts from its right palm (the Shoot clip's raised
##     hand), 2+ of them, and no rockets; the muzzle (which parents the flash)
##     is at world scale ~1, not the rig's counter-scale;
## (3) inside LEAP_RANGE it telegraphs (0.4 s+ planted, a ground warning at
##     the landing spot) and then leaps off its stilts (body 0.4 m+ up);
## (4) it lands spike-first next to the player: kick damage + knockback.
##   godot --headless --path . --audio-driver Dummy res://tests/mech_stilt_probe.tscn

const SCENE := "res://scenes/enemies/mech.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _palm(m: Node3D) -> Vector3:
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("PalmI.R")).origin

func _run() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(90, 90)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(90, 1, 90)
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

	var mech: EnemyMech = (load(SCENE) as PackedScene).instantiate()
	nav.add_child(mech)
	mech.global_position = Vector3(0, 0.2, -26.0)
	mech.rotation.y = PI
	for i in 20:
		await get_tree().physics_frame
	var floor_y := mech.global_position.y
	var anim: AnimationPlayer = mech.find_children("*", "AnimationPlayer", true, false)[0]
	mech.target = player
	mech.set_state(EnemyBase.State.CHASE)

	# 1-2. Approach and fire from range.
	var palm_d: Array[float] = []
	var splashers: Array[float] = [] # an Array: a lambda captures a local int by value
	var on_added := func(n: Node) -> void:
		if n is Projectile:
			# Position and launch() land right after add_child: read them at idle time.
			(func() -> void:
				if is_instance_valid(n) and is_instance_valid(mech):
					palm_d.append((n as Node3D).global_position.distance_to(_palm(mech)))
					if float(n.get("_splash_radius")) > 0.0:
						splashers.append(float(n.get("_splash_radius")))).call_deferred()
	get_tree().node_added.connect(on_added)
	var top_speed := 0.0
	var ran := false
	for f in 60 * 7:
		await get_tree().physics_frame
		var hs := Vector2(mech.velocity.x, mech.velocity.z).length()
		if not mech.is_leaping():
			top_speed = maxf(top_speed, hs)
		if hs > 2.0 and anim.current_animation == "Run":
			ran = true
	get_tree().node_added.disconnect(on_added)
	_check("it lopes on the Run clip", ran and top_speed >= 5.0, "top=%.1f m/s run=%s" % [top_speed, ran])
	var far := 0.0
	for d in palm_d:
		far = maxf(far, d)
	_check("bolts leave its right palm, no splash rockets", palm_d.size() >= 2 and far < 1.2 and splashers.is_empty(),
			"shots=%d farthest=%.2f m splash=%d" % [palm_d.size(), far, splashers.size()])
	# The muzzle flash and telegraph orb are parented to the muzzle: on a node
	# under the rig's BoneAttachment they inherit its counter-scale and render huge.
	var ms := mech.muzzle.global_transform.basis.get_scale()
	_check("the palm muzzle is unscaled", ms.x > 0.5 and ms.x < 2.0 and ms.y > 0.5 and ms.y < 2.0,
			"world scale %s" % ms)

	# 3-4. Close in: telegraphed leap that lands spike-first.
	mech.global_position = Vector3(0, floor_y, -7.0)
	mech.velocity = Vector3.ZERO
	mech._attack_timer = 9.0 # keep the gun quiet so the leap is what lands
	player.velocity = Vector3.ZERO
	var hp0 := pdmg.current_health
	var planted := -1
	var takeoff := -1
	var peak := 0.0
	var landed := false
	var kicked := 0.0
	var knock := 0.0
	var land_d := 99.0
	for f in 60 * 5:
		await get_tree().physics_frame
		var up := mech.global_position.y - floor_y
		if mech.is_leaping() and planted < 0:
			planted = f
		if planted >= 0 and takeoff < 0 and up > 0.15:
			takeoff = f
		peak = maxf(peak, up)
		if takeoff >= 0 and not landed and pdmg.current_health < hp0:
			landed = true
			kicked = hp0 - pdmg.current_health
			knock = player.velocity.length()
			land_d = Vector2(mech.global_position.x, mech.global_position.z).distance_to(Vector2.ZERO)
		if landed and not mech.is_leaping():
			break
	var tele := float(takeoff - planted) / 60.0
	_check("the leap is telegraphed", planted >= 0 and takeoff > planted and tele >= 0.4,
			"%.2f s planted" % tele)
	_check("it leaps off its stilts", peak >= 0.4, "peak %.2f m" % peak)
	_check("it lands spike-first next to the player", landed and kicked > 0.0 and knock > 5.0
			and land_d <= EnemyMech.KICK_RADIUS,
			"dmg=%.0f knock=%.1f m/s at %.2f m" % [kicked, knock, land_d])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
