extends Node3D
## Probe: the MAULER's GROUND POUND (EnemyMauler._tick_pound). Its slam used to
## land the instant it came off cooldown, on anything inside 5 m: 34 damage
## with no tell and no way to dodge. Now:
##   - in reach it marks the floor where the player stands with a ring of
##     POUND_RADIUS (group "telegraph_ring") before any damage, and holds its
##     ground for POUND_WINDUP;
##   - a player who stands in the ring takes slam_damage once when the windup
##     ends, and is thrown outward; the ring is gone, and the next pound waits
##     out the attack cooldown;
##   - a player who leaves the ring takes nothing, and the MAULER stays stuck
##     where it hit for POUND_STUCK instead of chasing, then pounds again;
##   - a MAULER killed mid-windup leaves no ring and deals nothing;
##   - a MAULER that overloads mid-windup drops the pound;
##   - an overloading MAULER does not pound at all: its charge ends in the
##     blast alone (it used to slam on the way in as well, 76 in all).
## Timed in physics frames. Each case is its own MAULER on its own lane.
##   godot --headless --path . --audio-driver Dummy res://tests/mauler_pound_probe.tscn

const WINDUP := 0.75 ## spec, mirrored by EnemyMauler.POUND_WINDUP
const RADIUS := 2.0 ## EnemyMauler.POUND_RADIUS
const STUCK := 0.9 ## EnemyMauler.POUND_STUCK

var ok := true
var player: CharacterBody3D
var hp: Damageable
var hurt := 0.0
var hits := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _rings() -> Array:
	return get_tree().get_nodes_in_group("telegraph_ring").filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	# A floor with a navmesh: the MAULER walks.
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 60)
	fmi.mesh = pm
	nav.add_child(fmi)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(140, 1, 60)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	nav.add_child(floor_body)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	for i in 10:
		await get_tree().physics_frame
	player = CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 0
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 100000.0
	player.add_child(hp)
	add_child(player)
	hp.current_health = 100000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void:
		hurt += amount
		hits += 1)
	await get_tree().physics_frame

	# 1. A player who stands in the ring.
	var m := await _stage(Vector3(0, 0, 0), 2.2)
	var slam: float = m.slam_damage
	var seen := await _until_ring(m, 600)
	_check("in reach it marks the floor before any damage", seen["ring"] != null and seen["hurt"] == 0.0,
			"ring %s, %.1f damage first" % [seen["ring"] != null, seen["hurt"]])
	if seen["ring"] != null:
		var ring: Node3D = seen["ring"]
		var off := Vector2(ring.global_position.x - player.global_position.x, ring.global_position.z - player.global_position.z).length()
		_check("the ring lies on the floor where the player stands", off < 0.3 and absf(ring.global_position.y) < 0.3, "%.2f m off, y %.2f" % [off, ring.global_position.y])
		_check("the ring is POUND_RADIUS wide", absf(float(ring.get_meta("radius", 0.0)) - RADIUS) < 0.01, str(ring.get_meta("radius", 0.0)))
	# The windup: no damage, no walking.
	var fast := 0.0
	var early := 0.0
	var frames := int(WINDUP * 60.0)
	for i in frames - 5:
		await get_tree().physics_frame
		if i > 12 and is_instance_valid(m):
			fast = maxf(fast, Vector2(m.velocity.x, m.velocity.z).length())
		early = hurt
	_check("no damage while it winds up", early == 0.0, "%.1f" % early)
	_check("it holds its ground while it winds up", fast < 1.0, "%.1f m/s" % fast)
	player.velocity = Vector3.ZERO
	for i in 14:
		await get_tree().physics_frame
	_check("a player in the ring takes slam_damage once when the windup ends", absf(hurt - slam) < 0.5 and hits == 1, "%.1f in %d hits against %.1f" % [hurt, hits, slam])
	var thrown := Vector2(player.velocity.x, player.velocity.z).length()
	_check("and is thrown outward", thrown > 3.0 and player.velocity.y > 0.5, "%.1f m/s, up %.1f" % [thrown, player.velocity.y])
	_check("the ring is gone after the slam", _rings().is_empty(), str(_rings().size()))
	# The next pound waits out the cooldown.
	player.velocity = Vector3.ZERO
	var wait := 0
	for i in 400:
		await get_tree().physics_frame
		wait += 1
		if not _rings().is_empty():
			break
	_check("the next pound waits out the attack cooldown", wait >= int(m.attack_cooldown * 60.0) - 6 and wait < 400, "%.2f s" % (wait / 60.0))
	m.queue_free()
	await _clear()

	# 2. A player who leaves the ring.
	m = await _stage(Vector3(45, 0, 0), 2.2)
	await _until_ring(m, 600)
	for i in 20:
		await get_tree().physics_frame
	player.global_position += Vector3(4.5, 0, 0)
	for i in frames - 20 + 8:
		await get_tree().physics_frame
	_check("a player who leaves the ring takes nothing", hurt == 0.0 and _rings().is_empty(), "%.1f damage, %d rings" % [hurt, _rings().size()])
	# Stuck: it does not come after the player (4.5 m off, out of reach).
	var moved_from := m.global_position
	var stuck_fast := 0.0
	for i in int(STUCK * 60.0) - 12:
		await get_tree().physics_frame
		if i > 14:
			stuck_fast = maxf(stuck_fast, Vector2(m.velocity.x, m.velocity.z).length())
	_check("it stays stuck where it hit for POUND_STUCK", stuck_fast < 1.0 and _rings().is_empty(), "%.1f m/s at most" % stuck_fast)
	var again := await _until_ring(m, 600)
	_check("then it comes on and pounds again", again["ring"] != null and m.global_position.distance_to(moved_from) > 1.0,
			"ring %s, walked %.1f m" % [again["ring"] != null, m.global_position.distance_to(moved_from)])
	m.queue_free()
	await _clear()

	# 3. Killed mid-windup.
	m = await _stage(Vector3(-45, 0, 0), 2.2)
	await _until_ring(m, 600)
	for i in 10:
		await get_tree().physics_frame
	m.hp.apply_damage(100000.0, null)
	for i in 3:
		await get_tree().physics_frame
	var left := _rings().size()
	for i in 70:
		await get_tree().physics_frame
	_check("a MAULER killed mid-windup leaves no ring and deals nothing", left == 0 and hurt == 0.0, "%d rings, %.1f damage" % [left, hurt])
	if is_instance_valid(m):
		m.queue_free()
	await _clear()

	# 4. Overloads mid-windup: the pound is dropped (the blast follows, it is 2.2 m off).
	m = await _stage(Vector3(0, 0, 20), 2.2)
	await _until_ring(m, 600)
	for i in 10:
		await get_tree().physics_frame
	m.hp.current_health = m.hp.max_health * 0.2
	for i in 3:
		await get_tree().physics_frame
	_check("a MAULER that overloads mid-windup drops the pound", _rings().is_empty(), str(_rings().size()))
	for i in 30:
		await get_tree().physics_frame
	if is_instance_valid(m):
		m.queue_free()
	await _clear()

	# 5. An overloading MAULER does not pound: only the blast.
	m = await _stage(Vector3(0, 0, -20), 9.0)
	var blast: float = m.overload_damage
	m.hp.current_health = m.hp.max_health * 0.2
	var ringed := false
	for i in 400:
		await get_tree().physics_frame
		if not _rings().is_empty():
			ringed = true
		if not is_instance_valid(m) or m.state == EnemyBase.State.DEAD:
			break
	for i in 10:
		await get_tree().physics_frame
	_check("an overloading MAULER does not pound: only the blast", not ringed and absf(hurt - blast) < 0.5, "ring %s, %.1f damage against %.1f" % [ringed, hurt, blast])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## The stand-in at `at`, a fresh MAULER `gap` metres up the lane (+Z), awake.
func _stage(at: Vector3, gap: float) -> EnemyMauler:
	player.global_position = at
	player.velocity = Vector3.ZERO
	var m: EnemyMauler = (load("res://scenes/enemies/mauler.tscn") as PackedScene).instantiate()
	add_child(m)
	m.global_position = at + Vector3(0, 0.3, gap)
	await get_tree().physics_frame
	await get_tree().physics_frame
	m.target = player
	m.set_state(EnemyBase.State.CHASE)
	hurt = 0.0
	hits = 0
	return m

## Run until a telegraph ring stands (or `frames` pass, or the stand-in is hurt).
func _until_ring(m: EnemyMauler, frames: int) -> Dictionary:
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(m):
			break
		var r := _rings()
		if not r.is_empty():
			return {"ring": r[0], "hurt": hurt}
		if hurt > 0.0:
			break
	return {"ring": null, "hurt": hurt}

func _clear() -> void:
	for i in 4:
		await get_tree().physics_frame
	hurt = 0.0
	hits = 0
