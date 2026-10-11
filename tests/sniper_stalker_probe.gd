extends Node3D
## Probe: the SNIPER (sniper.tscn, Quaternius "QuadShell": a shell on four long
## walking legs with a short gun barrel on each side, bones Gun.L / Gun.R)
## fights like it looks:
## (1) every charged beam leaves the front of one of its two barrels (0.83 m
##     ahead of that Gun bone), and successive shots alternate barrels;
## (2) shoot and scoot: after a shot it walks 4+ m to a new spot on its legs,
##     without closing on the player, on its Run clip (not Walk sped past its
##     stride) whenever it moves 3+ m/s.
##   godot --headless --path . --audio-driver Dummy res://tests/sniper_stalker_probe.tscn

const SCENE := "res://scenes/enemies/sniper.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _gun(e: Node3D, bone: String) -> Vector3:
	var sk: Skeleton3D = e.find_children("*", "Skeleton3D", true, false)[0]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin

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

	var sn: EnemyBase = (load(SCENE) as PackedScene).instantiate()
	nav.add_child(sn)
	sn.global_position = Vector3(0, 0.2, -30.0)
	sn.rotation.y = PI # face the player, or it never sees it
	for i in 20:
		await get_tree().physics_frame
	sn.target = player
	sn.set_state(EnemyBase.State.ATTACK)

	# Each hit on the player: which barrel the muzzle was at, and how far ahead of it.
	var shots: Array = [] # [nearest gun bone, distance to it, muzzle is ahead of the body's centre]
	var moves: Array = [] # per shot: [farthest it got from the firing spot in 3 s, top speed, closest to player]
	var on_hit := func(_amount: float, _src: Variant = null) -> void:
		var m: Vector3 = sn.muzzle.global_position
		var dl := m.distance_to(_gun(sn, "Gun.L"))
		var dr := m.distance_to(_gun(sn, "Gun.R"))
		var fwd: float = (m - sn.global_position).dot(-sn.global_transform.basis.z)
		shots.append(["L" if dl < dr else "R", minf(dl, dr), fwd])
		moves.append([sn.global_position, 0.0, 0.0, 999.0])
	pdmg.damaged.connect(on_hit)
	var anim: AnimationPlayer = sn.find_children("*", "AnimationPlayer", true, false)[0]
	var fast := 0     # frames moving 3+ m/s
	var fast_run := 0 # ... of them on the Run clip
	for f in 60 * 16:
		await get_tree().physics_frame
		if Vector2(sn.velocity.x, sn.velocity.z).length() >= 3.0:
			fast += 1
			if anim.current_animation == "Run":
				fast_run += 1
		if sn.state != EnemyBase.State.ATTACK and sn.state != EnemyBase.State.STAGGER:
			sn.set_state(EnemyBase.State.ATTACK)
		for mv in moves:
			if (mv[1] as float) < 3.0:
				mv[1] = (mv[1] as float) + 1.0 / 60.0
				mv[2] = maxf(mv[2], Vector2((sn.global_position - (mv[0] as Vector3)).x, (sn.global_position - (mv[0] as Vector3)).z).length())
				mv[3] = minf(mv[3], sn.global_position.distance_to(player.global_position))
		if shots.size() >= 3 and (moves[moves.size() - 1][1] as float) >= 3.0:
			break
	pdmg.damaged.disconnect(on_hit)
	var off_ok := shots.size() >= 2
	var sides := ""
	var alternate := shots.size() >= 2
	for i in shots.size():
		off_ok = off_ok and absf(float(shots[i][1]) - 0.83) < 0.15 and float(shots[i][2]) > 0.5
		sides += String(shots[i][0])
		if i > 0 and shots[i][0] == shots[i - 1][0]:
			alternate = false
	var dists := []
	for s in shots:
		dists.append(snappedf(float(s[1]), 0.01))
	var fwds := []
	for s in shots:
		fwds.append(snappedf(float(s[2]), 0.01))
	_check("each beam leaves the front of a barrel", off_ok, "shots=%d muzzle-to-gun-bone %s m, ahead of centre %s m" % [shots.size(), dists, fwds])
	_check("successive shots alternate barrels", alternate, "barrels %s" % sides)
	var scoot := moves.size() >= 1
	var far := []
	for mv in moves:
		far.append(snappedf(float(mv[2]), 0.1))
		scoot = scoot and float(mv[2]) >= 4.0 and float(mv[3]) > 18.0
	_check("after each shot it walks to a new spot, keeping its distance", scoot,
			"moved %s m within 3 s of each shot (closest to player %.1f m)" % [far, moves[0][3] if moves.size() > 0 else -1.0])

	_check("it runs on its Run clip while scooting", fast >= 30 and fast_run >= fast * 0.8,
			"%d of %d frames at 3+ m/s on Run" % [fast_run, fast])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
