extends Node3D
## Probe: the SEEKER's TERMINAL DIVE (EnemySeeker._tick_dive). It used to home
## on the player until it touched, so no sidestep ever mattered. Now:
##   - inside DIVE_LOCK with a line of sight it stops and arms for DIVE_ARM
##     (no blast while it arms);
##   - then it flies one straight line at DIVE_SPEED: a player who stands
##     takes the full blast;
##   - a player walking steadily sideways is led and still takes it;
##   - a player who moves off the line after it commits takes nothing: the
##     seeker flies past, hangs spent for DIVE_RECOVER without going off beside
##     them, then comes round and dives again;
##   - a dive that meets a wall goes off on the wall;
##   - the warning band stands on the hull's surface (it was buried inside the
##     hull and showed nothing), burns steady and bright while armed and is
##     dark while spent.
## Timed in physics frames. Each case is its own seeker on its own lane.
##   godot --headless --path . --audio-driver Dummy res://tests/seeker_dive_probe.tscn

var ok := true
var player: CharacterBody3D
var hp: Damageable
var hurt := 0.0
var drift := Vector3.ZERO ## the stand-in walks at this velocity
var watched: EnemySeeker ## its ARM and DIVE starts are stamped in physics frames
var frame := 0
var arm_frame := -1
var dive_frame := -1

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(400, 1, 400))
	_run.call_deferred()

func _physics_process(delta: float) -> void:
	frame += 1
	if is_instance_valid(watched):
		if arm_frame < 0 and watched._dive == EnemySeeker.Dive.ARM:
			arm_frame = frame
		if dive_frame < 0 and watched._dive == EnemySeeker.Dive.DIVE:
			dive_frame = frame
	if player and drift != Vector3.ZERO:
		player.velocity = drift
		player.global_position += drift * delta

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
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
	hp.damaged.connect(func(amount: float, _src: Node) -> void: hurt += amount)
	await get_tree().physics_frame

	# 1. A player who stands still.
	var s := await _stage(Vector3(0, 0, 0))
	var fuse: float = s.detonate_radius
	watched = s
	# The band is a ring on the hull, not inside it.
	var hull := 0.0
	var inv := s.global_transform.affine_inverse()
	for mi in s.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var ab: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
			hull = maxf(hull, maxf(absf(ab.position.x), absf(ab.end.x)))
	var band_r := 0.0
	for mi in s.find_children("*", "MeshInstance3D", true, false):
		var cm := (mi as MeshInstance3D).mesh as CylinderMesh
		if cm and cm.material == s._band_mat:
			band_r = cm.top_radius
	_check("the warning band stands on the hull's surface", hull > 0.3 and band_r >= hull * 0.97 and band_r <= hull * 1.15,
			"band %.2f m, hull %.2f m" % [band_r, hull])
	var arm := await _until_armed(s, 600)
	_check("inside DIVE_LOCK it stops and arms", arm["armed"], "at %.1f m, %.1f m/s" % [arm["dist"], arm["speed"]])
	_check("it arms inside DIVE_LOCK, outside its blast fuse",
			arm["dist"] <= EnemySeeker.DIVE_LOCK + 0.5 and arm["dist"] > fuse + 1.0, "%.1f m" % arm["dist"])
	await get_tree().physics_frame
	var armed_glow: float = s._band_mat.emission_energy_multiplier if is_instance_valid(s) else 0.0
	await get_tree().physics_frame
	var armed_glow2: float = s._band_mat.emission_energy_multiplier if is_instance_valid(s) else 0.0
	_check("armed, the band burns steady and bright", armed_glow >= 8.0 and armed_glow == armed_glow2, "%.1f then %.1f" % [armed_glow, armed_glow2])
	var dive := await _until_dive(s, 120)
	_check("no blast while it arms", dive["hurt_before"] == 0.0, "%.1f damage" % dive["hurt_before"])
	var armed_for := (dive_frame - arm_frame) / 60.0
	_check("it arms for DIVE_ARM", arm_frame > 0 and absf(armed_for - EnemySeeker.DIVE_ARM) < 0.05, "%.2f s" % armed_for)
	_check("then it dives at DIVE_SPEED", dive["dove"] and absf(dive["speed"] - EnemySeeker.DIVE_SPEED) < 3.0, "%.1f m/s" % dive["speed"])
	await _settle(s, 90)
	_check("a player who stands takes the blast", hurt > 20.0 and not is_instance_valid(s), "%.1f damage" % hurt)

	# 2. A player walking steadily sideways is led.
	s = await _stage(Vector3(100, 0, 0))
	drift = Vector3(4.5, 0, 0)
	await _until_dive(s, 900)
	await _settle(s, 90)
	drift = Vector3.ZERO
	player.velocity = Vector3.ZERO
	_check("a player walking steadily sideways is led and takes the blast", hurt > 15.0 and not is_instance_valid(s), "%.1f damage" % hurt)

	# 3. A player who moves off the line after it commits.
	s = await _stage(Vector3(-100, 0, 0))
	await _until_dive(s, 900)
	player.global_position += Vector3(6, 0, 0)
	var near := INF
	var spent_near := 0
	var spent := 0
	var seen_spent := false
	var spent_glow := 99.0
	for i in 150:
		await get_tree().physics_frame
		if not is_instance_valid(s):
			break
		var d := s.global_position.distance_to(player.global_position + Vector3.UP)
		near = minf(near, d)
		if s.velocity.length() < 6.0 and i > 5:
			seen_spent = true
		if seen_spent and s.velocity.length() < 6.0:
			spent += 1
			if spent == 10:
				spent_glow = s._band_mat.emission_energy_multiplier
		elif seen_spent:
			break
	_check("a dodged dive does no damage", hurt == 0.0 and is_instance_valid(s), "%.1f damage" % hurt)
	_check("it flew past and hangs spent for DIVE_RECOVER", seen_spent and absf(spent / 60.0 - EnemySeeker.DIVE_RECOVER) < 0.5, "%.2f s slow" % (spent / 60.0))
	_check("spent, the band is dark", spent_glow <= 0.5, "%.1f" % spent_glow)
	# Spent, it does not go off beside the player: walk the stand-in onto it.
	s = await _stage(Vector3(-200, 0, 0))
	await _until_dive(s, 900)
	player.global_position += Vector3(6, 0, 0)
	for i in 120:
		await get_tree().physics_frame
		if is_instance_valid(s) and s.velocity.length() < 6.0 and i > 5:
			break
	if is_instance_valid(s):
		player.global_position = s.global_position + Vector3(0.8, -1.0, 0)
		for i in 20:
			await get_tree().physics_frame
			if is_instance_valid(s):
				spent_near += 1
	_check("spent, it does not go off beside the player", hurt == 0.0 and spent_near == 20, "%.1f damage, alive %d of 20 frames" % [hurt, spent_near])
	if is_instance_valid(s):
		player.global_position += Vector3(0, 0, -12)
		player.global_position.y = 0.0
		await _settle(s, 600)
	_check("it comes round and dives again", hurt > 20.0 and not is_instance_valid(s), "%.1f damage" % hurt)

	# 4. A dive that meets a wall goes off on the wall.
	s = await _stage(Vector3(0, 0, 150))
	var wall := _box(player.global_position + Vector3(0, 2, -3.0), Vector3(12, 4, 0.6))
	await _until_dive(s, 900)
	player.global_position += Vector3(40, 0, 0)
	var last := Vector3.ZERO
	for i in 120:
		await get_tree().physics_frame
		if not is_instance_valid(s):
			break
		last = s.global_position
	_check("a dive that meets a wall goes off on it", not is_instance_valid(s) and absf(last.z - (wall.global_position.z + 0.3)) < 1.6 and hurt == 0.0,
			"last seen %s, wall face z %.1f, %.1f damage" % [last, wall.global_position.z + 0.3, hurt])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Put the stand-in at `at` and a fresh seeker 20 m up the lane (+Z) from it.
func _stage(at: Vector3) -> EnemySeeker:
	player.global_position = at
	player.velocity = Vector3.ZERO
	hurt = 0.0
	var s: EnemySeeker = (load("res://scenes/enemies/seeker.tscn") as PackedScene).instantiate()
	add_child(s)
	s.global_position = at + Vector3(0, 1.5, 20)
	await get_tree().physics_frame
	return s

## Wait until the seeker has stopped short of the player (armed).
func _until_armed(s: EnemySeeker, frames: int) -> Dictionary:
	var moved := false
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(s):
			break
		var d := s.global_position.distance_to(player.global_position + Vector3.UP)
		if s.velocity.length() > 5.0:
			moved = true
		if moved and s.velocity.length() < 1.5:
			return {"armed": true, "dist": d, "speed": s.velocity.length()}
	return {"armed": false, "dist": -1.0, "speed": -1.0}

## Wait until the seeker is diving (faster than it ever chases). `frames` counts
## from the call; "frames" in the result is how long it took.
func _until_dive(s: EnemySeeker, frames: int) -> Dictionary:
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(s):
			break
		if s.velocity.length() > 15.0:
			return {"dove": true, "frames": i + 1, "speed": s.velocity.length(), "hurt_before": hurt}
	return {"dove": false, "frames": frames, "speed": 0.0, "hurt_before": hurt}

## Run until the seeker is gone, or `frames` pass.
func _settle(s: EnemySeeker, frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		if not is_instance_valid(s):
			break
	await get_tree().physics_frame

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb
