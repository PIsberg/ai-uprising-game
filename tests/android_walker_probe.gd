extends Node3D
## Probe: the ANDROID (android.tscn, Quaternius "Leela": an armless walker on
## digitigrade claw legs, one round lens on its face pod, clips Run/Shoot/Kick/
## Jump) fights like it looks:
## (1) its burst leaves the face lens: the muzzle rides the Head bone, unscaled;
## (2) its evasive jukes are side-HOPS on those legs, not flat slides;
## (3) up close it winds up and kicks (Kick clip): damage + knockback;
## (4) none of that leaks into an EnemyAndroid subclass (ENFORCER), whose own
##     model is an armed humanoid.
##   godot --headless --path . --audio-driver Dummy res://tests/android_walker_probe.tscn

const SCENE := "res://scenes/enemies/android.tscn"
const SUBCLASS := "res://scenes/enemies/enforcer.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _head(e: Node3D) -> Vector3:
	var sk: Skeleton3D = e.find_children("*", "Skeleton3D", true, false)[0]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head")).origin

func _spawn(path: String, at: Vector3, parent: Node) -> EnemyBase:
	var e: EnemyBase = (load(path) as PackedScene).instantiate()
	parent.add_child(e)
	e.global_position = at
	e.rotation.y = PI # face the player, or it never sees it
	return e

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

	var and_: EnemyAndroid = _spawn(SCENE, Vector3(0, 0.2, -12.0), nav)
	for i in 20:
		await get_tree().physics_frame
	var floor_y := and_.global_position.y
	var anim: AnimationPlayer = and_.find_children("*", "AnimationPlayer", true, false)[0]
	and_.target = player
	and_.set_state(EnemyBase.State.ATTACK)

	# 1-2. At range: count shots (sampled where the muzzle is when each fires)
	# and watch the jukes for air.
	var shots: Array = [] # [muzzle-to-head distance, muzzle height above floor, muzzle world scale]
	var on_added := func(n: Node) -> void:
		if n.scene_file_path.ends_with("tracer_red.tscn") and is_instance_valid(and_):
			shots.append([and_.muzzle.global_position.distance_to(_head(and_)),
					and_.muzzle.global_position.y - floor_y,
					and_.muzzle.global_transform.basis.get_scale().x])
	get_tree().node_added.connect(on_added)
	var peak := 0.0
	var air_side := 0.0 # fastest lateral speed while off the floor
	for f in 60 * 10:
		await get_tree().physics_frame
		if and_.state != EnemyBase.State.ATTACK:
			and_.set_state(EnemyBase.State.ATTACK)
		var h := and_.global_position.y - floor_y
		peak = maxf(peak, h)
		if h > 0.2:
			air_side = maxf(air_side, absf(and_.velocity.x))
	get_tree().node_added.disconnect(on_added)
	var far := 0.0
	var low := 99.0
	var sc_ok := true
	for s in shots:
		far = maxf(far, float(s[0]))
		low = minf(low, float(s[1]))
		sc_ok = sc_ok and float(s[2]) > 0.5 and float(s[2]) < 2.0
	_check("its burst leaves the face lens", shots.size() >= 5 and far < 0.5 and low > 1.3 and sc_ok,
			"shots=%d farthest from head=%.2f m lowest=%.2f m unscaled=%s" % [shots.size(), far, low, sc_ok])
	_check("its jukes are side-hops", peak > 0.3 and air_side > 3.0,
			"peak %.2f m, lateral %.1f m/s airborne" % [peak, air_side])

	# 3. Up close: a telegraphed kick.
	and_.global_position = Vector3(0, floor_y, -2.0)
	and_.velocity = Vector3.ZERO
	and_._attack_timer = 9.0 # no burst: the kick is what lands
	and_._burst_remaining = 0 # nor the tail of one from the ranged phase
	and_._dodge_cd = 9.0
	player.velocity = Vector3.ZERO
	var hp0 := pdmg.current_health
	var wound := -1
	var hit := -1
	var knock := 0.0
	for f in 60 * 4:
		await get_tree().physics_frame
		if anim.current_animation == "Kick" and wound < 0:
			wound = f
		if pdmg.current_health < hp0 and hit < 0:
			hit = f
			knock = player.velocity.length()
			break
	var windup := float(hit - wound) / 60.0
	_check("up close it winds up and kicks", wound >= 0 and hit > wound and windup >= 0.25 and knock > 5.0,
			"windup %.2f s dmg=%.0f knock=%.1f m/s" % [windup, hp0 - pdmg.current_health, knock])
	and_.queue_free()

	# 4. A subclass on its own model keeps its gun muzzle and never kicks.
	var enf: EnemyAndroid = _spawn(SUBCLASS, Vector3(0, 0.2, -2.0), nav)
	for i in 20:
		await get_tree().physics_frame
	enf.target = player
	enf.set_state(EnemyBase.State.ATTACK)
	enf._attack_timer = 9.0
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 0.05, 0)
	var enf_knock := 0.0
	for f in 60 * 2:
		await get_tree().physics_frame
		enf.global_position.z = -2.0
		enf_knock = maxf(enf_knock, Vector2(player.velocity.x, player.velocity.z).length())
	_check("ENFORCER keeps its own muzzle and does not kick", enf.muzzle.name == "Muzzle" and enf_knock < 1.0,
			"muzzle=%s knock=%.1f m/s" % [enf.muzzle.name, enf_knock])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
