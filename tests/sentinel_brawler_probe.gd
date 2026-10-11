extends Node3D
## Probe: the SENTINEL (enemy_sentinel.gd, Quaternius "Robot": a big-headed
## biped with heavy fists, clips Walking/Punch, no gun) fights like it looks:
## (1) it walks on its Walking clip;
## (2) everything it fires (slugs and the bomb salvo) leaves its right fist,
##     thrown with the Punch clip playing, 3+ throws including a bomb;
## (3) up close it winds up (0.3 s+) and punches: damage + knockback.
##   godot --headless --path . --audio-driver Dummy res://tests/sentinel_brawler_probe.tscn

const SCENE := "res://scenes/enemies/sentinel.tscn"
const PUNCH_CLIP := "RobotArmature|Robot_Punch"
const WALK_CLIP := "RobotArmature|Robot_Walking"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _fist(m: Node3D) -> Vector3:
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Palm1.R")).origin

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

	var sen: EnemySentinel = (load(SCENE) as PackedScene).instantiate()
	nav.add_child(sen)
	sen.global_position = Vector3(0, 0.2, -32.0)
	sen.rotation.y = PI # face the player, or it never sees it
	for i in 20:
		await get_tree().physics_frame
	var floor_y := sen.global_position.y
	var anim: AnimationPlayer = sen.find_children("*", "AnimationPlayer", true, false)[0]
	sen.target = player
	sen.set_state(EnemyBase.State.CHASE)

	# 1-2. Walk in and throw from range.
	var throws: Array = [] # [distance from the right fist, punch clip playing, is a bomb]
	var on_added := func(n: Node) -> void:
		if n is Projectile or n is EnemyBomb:
			(func() -> void:
				if is_instance_valid(n) and is_instance_valid(sen):
					throws.append([(n as Node3D).global_position.distance_to(_fist(sen)),
							anim.current_animation == PUNCH_CLIP, n is EnemyBomb])).call_deferred()
	get_tree().node_added.connect(on_added)
	var walked := false
	for f in 60 * 14:
		await get_tree().physics_frame
		if Vector2(sen.velocity.x, sen.velocity.z).length() > 1.0 and anim.current_animation == WALK_CLIP:
			walked = true
	get_tree().node_added.disconnect(on_added)
	_check("it walks on its Walking clip", walked)
	var far := 0.0
	var all_punch := true
	var bombs := 0
	for t in throws:
		far = maxf(far, float(t[0]))
		all_punch = all_punch and bool(t[1])
		if bool(t[2]):
			bombs += 1
	_check("every shot is thrown from its right fist", throws.size() >= 3 and bombs >= 1 and far < 1.2 and all_punch,
			"throws=%d bombs=%d farthest=%.2f m punch_clip=%s" % [throws.size(), bombs, far, all_punch])
	var ms := sen.muzzle.global_transform.basis.get_scale()
	_check("the fist muzzle is unscaled", ms.x > 0.5 and ms.x < 2.0, "world scale %s" % ms)

	# 3. Up close: a telegraphed punch.
	sen.global_position = Vector3(0, floor_y, -2.2)
	sen.velocity = Vector3.ZERO
	sen._attack_timer = 9.0 # nothing thrown: the fist is what lands
	player.velocity = Vector3.ZERO
	var hp0 := pdmg.current_health
	var wound := -1
	var hit := -1
	var knock := 0.0
	for f in 60 * 4:
		await get_tree().physics_frame
		if sen.is_punching() and wound < 0:
			wound = f
		if pdmg.current_health < hp0 and hit < 0:
			hit = f
			knock = player.velocity.length()
			break
	var windup := float(hit - wound) / 60.0
	_check("up close it winds up and punches", wound >= 0 and hit > wound and windup >= 0.3 and knock > 5.0,
			"windup %.2f s dmg=%.0f knock=%.1f m/s" % [windup, hp0 - pdmg.current_health, knock])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
