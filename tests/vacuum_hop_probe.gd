extends Node3D
## Probe: the CUSTODIAN (enemy_vacuum.gd) springs up to shoot. Risen, it fires
## only from the top of a hop on its four legs, so every shot is a moment it is
## up at eye height and easy to hit:
## (1) it fires (2+ shots in the window; damage dealt is reported, not asserted);
## (2) every shot leaves while its body is HOP_HEIGHT * 0.7+ above where it stands;
## (3) each launch follows a crouch: the chassis dips before the body leaves the floor;
## (4) hits while it is airborne crit (x AIR_DAMAGE_MULT), on the floor they do not;
## (5) after the window it is back on the floor, alive and fighting;
## (6) killed at the top of a hop, the wreck drops to the floor (no mid-air topple).
##   godot --headless --path . --audio-driver Dummy res://tests/vacuum_hop_probe.tscn

const SCENE := "res://scenes/enemies/vacuum.tscn"
const WINDOW_FRAMES := 60 * 9
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fmi.mesh = pm
	nav.add_child(fmi)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
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

	var vac: EnemyVacuum = (load(SCENE) as PackedScene).instantiate()
	nav.add_child(vac)
	vac.global_position = Vector3(0, 0.3, -13.0)
	vac.rotation.y = PI
	for i in 30: # settle on the floor
		await get_tree().physics_frame
	var floor_y := vac.global_position.y
	vac.target = player
	vac._begin_rise()

	var shot_heights: Array[float] = []
	var on_added := func(n: Node) -> void:
		if n is Projectile:
			shot_heights.append(vac.global_position.y - floor_y)
	get_tree().node_added.connect(on_added)

	var hp0 := pdmg.current_health
	var launches := 0
	var crouched_launches := 0
	var low_before := false
	var was_down := true
	var air_mult := 0.0
	var floor_mult := 0.0
	for f in WINDOW_FRAMES:
		await get_tree().physics_frame
		if not is_instance_valid(vac):
			break
		var up := vac.global_position.y - floor_y
		var down := up < 0.08
		if down and vac._phase == EnemyVacuum.Phase.COMBAT:
			if floor_mult == 0.0 and not vac.is_airborne():
				floor_mult = vac.weakpoint_multiplier(vac.global_position + Vector3.UP * 0.6)
		if was_down and not down:
			launches += 1
			if low_before: # crouched on the last frame it stood on the floor
				crouched_launches += 1
		low_before = down and vac._chassis.position.y < vac.rise_height * 0.75
		if vac.is_airborne() and up > 0.5 and air_mult == 0.0:
			air_mult = vac.weakpoint_multiplier(vac.global_position + Vector3.UP * 0.6)
		was_down = down
	get_tree().node_added.disconnect(on_added)

	var dealt := hp0 - pdmg.current_health
	# Report-only damage: from 13 m, 4-6 scattered bolts all miss in about 1 run in 4.
	_check("it fires", shot_heights.size() >= 2,
			"shots=%d dealt=%.0f" % [shot_heights.size(), dealt])
	var lowest := 99.0
	for h in shot_heights:
		lowest = minf(lowest, h)
	_check("every shot leaves from the top of a hop", not shot_heights.is_empty()
			and lowest >= EnemyVacuum.HOP_HEIGHT * 0.7,
			"lowest=%.2f m (want >= %.2f)" % [lowest, EnemyVacuum.HOP_HEIGHT * 0.7])
	_check("every launch follows a crouch", launches >= 1 and crouched_launches == launches,
			"%d of %d" % [crouched_launches, launches])
	_check("airborne hits crit, grounded ones do not",
			is_equal_approx(air_mult, EnemyVacuum.AIR_DAMAGE_MULT) and is_equal_approx(floor_mult, 1.0),
			"air=%.2f floor=%.2f" % [air_mult, floor_mult])
	# Let a hop in flight finish before judging where it ended up.
	for i in 120:
		if is_instance_valid(vac) and not vac.is_hopping():
			break
		await get_tree().physics_frame
	_check("it lands and keeps fighting", is_instance_valid(vac) and vac.state != EnemyBase.State.DEAD
			and vac.is_on_floor() and vac._phase == EnemyVacuum.Phase.COMBAT and not vac.is_hopping())

	# 6. Shot down at the top of a hop, the wreck falls on the floor.
	var apex := -1.0
	for i in 60 * 6:
		await get_tree().physics_frame
		if vac.is_airborne() and vac.global_position.y - floor_y > EnemyVacuum.HOP_HEIGHT * 0.8:
			apex = vac.global_position.y - floor_y
			break
	vac.hp.apply_damage(99999.0, null)
	await get_tree().physics_frame
	var wreck_y := vac.global_position.y - floor_y
	_check("killed mid-hop, the wreck drops to the floor", apex > 0.0 and vac.state == EnemyBase.State.DEAD
			and absf(wreck_y) < 0.2, "killed at %.2f m, wreck at %.2f m" % [apex, wreck_y])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
