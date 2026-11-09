extends Node3D
## Probe: the BRUTE's SHIELD RUSH (EnemyBrute.Rush). Shooting its shield is what
## sets it off, and dodging it is what opens it up:
##   - left alone at 12 m it never rushes;
##   - damage it takes in the back does not provoke it;
##   - RUSH_PROVOKE of damage blocked on the shield does: it plants for
##     RUSH_TELL (holds its ground), then runs a straight line at RUSH_SPEED;
##   - a player who stands still is bashed for RUSH_DAMAGE and thrown back, and
##     the shield stays up (a rush that lands is not punished);
##   - a player who steps aside lets it run into the wall behind them: it is
##     stunned for RUSH_STUN with the shield swung open, and a hit from the
##     front lands in full (5x and more what the raised shield let through);
##     after RUSH_STUN the shield is back up and blocks again;
##   - with no wall to hit, a dodged rush runs RUSH_TIME and leaves the shield
##     open for the shorter RUSH_MISS_OPEN;
##   - an EMP during the tell cancels the rush;
##   - it does not rush again inside RUSH_COOLDOWN.
## Timed in physics frames (60 a second), so a slow machine reads the same.
##   godot --headless --path . --audio-driver Dummy res://tests/brute_rush_probe.tscn

const BRUTE := "res://scenes/enemies/brute.tscn"

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_box(Vector3(0, -0.5, 0), Vector3(160, 1, 160))
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	await _case_unprovoked()
	await _case_bash()
	await _case_wall()
	await _case_miss()
	await _case_emp()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Left alone, and shot in the back: no rush.
func _case_unprovoked() -> void:
	var s := await _stage(12.0)
	var brute: EnemyBrute = s[0]
	var player: CharacterBody3D = s[1]
	var top := 0.0
	var rushed := false
	for i in 180:
		await get_tree().physics_frame
		top = maxf(top, Vector2(brute.velocity.x, brute.velocity.z).length())
		rushed = rushed or brute.rush != EnemyBrute.Rush.NONE
	_check("left alone it never rushes", not rushed and top < 4.0, "top speed %.1f m/s" % top)
	# 200 damage from straight behind it: not blocked, so not a provocation.
	brute.hp.apply_damage(200.0, player, false, brute.global_position + brute.global_basis.z * 3.0)
	rushed = false
	for i in 90:
		await get_tree().physics_frame
		rushed = rushed or brute.rush != EnemyBrute.Rush.NONE
	_check("damage in the back does not provoke it", not rushed)
	await _clear(s)

## Provoked, player stands still: tell, straight run, bash.
func _case_bash() -> void:
	var s := await _stage(12.0)
	var brute: EnemyBrute = s[0]
	var player: CharacterBody3D = s[1]
	var php: Damageable = player.get_node("Damageable")
	var hp0 := php.current_health
	brute.hp.apply_damage(EnemyBrute.RUSH_PROVOKE + 5.0, player)
	var f := await _until(func() -> bool: return brute.rush == EnemyBrute.Rush.TELL, 30)
	_check("RUSH_PROVOKE of blocked damage starts the tell", f >= 0, "after %d frames" % f)
	var at_tell := brute.global_position
	var tell_frames := await _until(func() -> bool: return brute.rush != EnemyBrute.Rush.TELL, 120)
	_check("the tell lasts RUSH_TELL", absf(tell_frames / 60.0 - EnemyBrute.RUSH_TELL) < 0.1, "%.2f s" % (tell_frames / 60.0))
	_check("it holds its ground through the tell", brute.global_position.distance_to(at_tell) < 0.4,
			"moved %.2f m" % brute.global_position.distance_to(at_tell))
	_check("then it rushes", brute.rush == EnemyBrute.Rush.RUSH)
	var start := brute.global_position
	var top := 0.0
	var frames := 0
	while brute.rush == EnemyBrute.Rush.RUSH and frames < 150:
		await get_tree().physics_frame
		frames += 1
		top = maxf(top, Vector2(brute.velocity.x, brute.velocity.z).length())
	var run := brute.global_position - start
	_check("at RUSH_SPEED", top > EnemyBrute.RUSH_SPEED * 0.85, "top %.1f m/s" % top)
	_check("in a straight line at the player", absf(run.x) < 0.6 and run.z < -4.0, "ran %s" % run)
	var lost := hp0 - php.current_health
	_check("a player who stands still is bashed for RUSH_DAMAGE", absf(lost - EnemyBrute.RUSH_DAMAGE) < 0.5, "lost %.1f" % lost)
	_check("and thrown back", player.velocity.z < -4.0, "velocity %s" % player.velocity)
	_check("a rush that lands leaves the shield up", not brute.shield_open())
	await _clear(s)

## Provoked, player steps aside, wall behind: stunned and open.
func _case_wall() -> void:
	var s := await _stage(10.0)
	var brute: EnemyBrute = s[0]
	var player: CharacterBody3D = s[1]
	var wall := _box(Vector3(0, 2.0, -12.5), Vector3(20, 4, 1)) # face at z = -12, inside the rush's 14.3 m
	# What the raised shield lets through, for the comparison below.
	var h := brute.hp.current_health
	brute.hp.apply_damage(EnemyBrute.RUSH_PROVOKE + 5.0, player)
	var blocked := h - brute.hp.current_health
	await _until(func() -> bool: return brute.rush == EnemyBrute.Rush.RUSH, 120)
	player.global_position.x += 6.0 # the sidestep
	var f := await _until(func() -> bool: return brute.rush != EnemyBrute.Rush.RUSH, 150)
	_check("a dodged rush runs into the wall behind you", brute.global_position.z < -10.0 and f >= 0 and f < int(EnemyBrute.RUSH_TIME * 60.0) - 5,
			"stopped at z %.1f after %d frames" % [brute.global_position.z, f])
	_check("and leaves the shield open", brute.rush == EnemyBrute.Rush.OPEN and brute.shield_open())
	var rig := brute.get_node("ShieldRig") as Node3D
	_check("the shield is swung aside", absf(rig.rotation.y) > 0.6, "%.2f rad" % rig.rotation.y)
	# Stand in front of it again and hit it with the same damage.
	player.global_position = brute.global_position - brute.global_basis.z * 5.0
	h = brute.hp.current_health
	brute.hp.apply_damage(EnemyBrute.RUSH_PROVOKE + 5.0, player)
	var open_hit := h - brute.hp.current_health
	_check("a hit from the front lands in full while it is open", open_hit > blocked * 5.0,
			"%.1f open vs %.1f blocked" % [open_hit, blocked])
	var open_frames := await _until(func() -> bool: return not brute.shield_open(), 400)
	_check("it stays open about RUSH_STUN", absf(open_frames / 60.0 - EnemyBrute.RUSH_STUN) < 0.25, "%.2f s" % (open_frames / 60.0))
	_check("it did not move while stunned", brute.global_position.z < -10.0, "z %.1f" % brute.global_position.z)
	await _frames(20)
	# Shield back up: the same hit from the front is blocked again. (It turns to
	# face the player first, so hit from where it is looking.)
	h = brute.hp.current_health
	brute.hp.apply_damage(40.0, player, false, brute.global_position - brute.global_basis.z * 3.0)
	var again := h - brute.hp.current_health
	_check("then the shield is up again and blocks", again < 10.0 and absf(rig.rotation.y) < 0.2, "lost %.1f, rig %.2f rad" % [again, rig.rotation.y])
	# Provoked again at once: inside RUSH_COOLDOWN it does not rush.
	brute.hp.apply_damage(EnemyBrute.RUSH_PROVOKE + 5.0, player, false, brute.global_position - brute.global_basis.z * 3.0)
	var re := await _until(func() -> bool: return brute.rush != EnemyBrute.Rush.NONE, 60)
	_check("it does not rush again inside RUSH_COOLDOWN", re < 0)
	wall.queue_free()
	await _clear(s)

## Provoked, player steps aside, open floor: a shorter opening.
func _case_miss() -> void:
	var s := await _stage(10.0)
	var brute: EnemyBrute = s[0]
	var player: CharacterBody3D = s[1]
	brute.hp.apply_damage(EnemyBrute.RUSH_PROVOKE + 5.0, player)
	await _until(func() -> bool: return brute.rush == EnemyBrute.Rush.RUSH, 120)
	player.global_position.x += 6.0
	var start := brute.global_position
	var f := await _until(func() -> bool: return brute.rush != EnemyBrute.Rush.RUSH, 150)
	_check("with nothing to hit the rush runs RUSH_TIME", absf(f / 60.0 - EnemyBrute.RUSH_TIME) < 0.1, "%.2f s" % (f / 60.0))
	_check("and covers the ground", brute.global_position.distance_to(start) > EnemyBrute.RUSH_SPEED * EnemyBrute.RUSH_TIME * 0.8,
			"%.1f m" % brute.global_position.distance_to(start))
	var open_frames := await _until(func() -> bool: return not brute.shield_open(), 300)
	_check("a miss leaves it open for RUSH_MISS_OPEN", brute.rush == EnemyBrute.Rush.NONE and absf(open_frames / 60.0 - EnemyBrute.RUSH_MISS_OPEN) < 0.2,
			"%.2f s" % (open_frames / 60.0))
	await _clear(s)

## An EMP during the tell cancels it.
func _case_emp() -> void:
	var s := await _stage(10.0)
	var brute: EnemyBrute = s[0]
	var player: CharacterBody3D = s[1]
	brute.hp.apply_damage(EnemyBrute.RUSH_PROVOKE + 5.0, player)
	await _until(func() -> bool: return brute.rush == EnemyBrute.Rush.TELL, 30)
	brute.emp_disable(1.0)
	var rushed := false
	var start := brute.global_position
	for i in 120:
		await get_tree().physics_frame
		rushed = rushed or brute.rush == EnemyBrute.Rush.RUSH
	_check("an EMP during the tell cancels the rush", not rushed and brute.global_position.distance_to(start) < 1.5,
			"moved %.1f m" % brute.global_position.distance_to(start))
	await _clear(s)

## A brute at the origin facing -Z and a player `dist` metres in front of it,
## once the brute has the player as its target.
func _stage(dist: float) -> Array:
	var brute: EnemyBrute = (load(BRUTE) as PackedScene).instantiate()
	add_child(brute)
	brute.global_position = Vector3(0, 0.1, 0)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	player.add_child(cs)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 500.0
	player.add_child(d)
	add_child(player)
	d.current_health = 500.0
	player.global_position = Vector3(0, 0.05, -dist)
	await _until(func() -> bool: return brute.target == player, 240)
	return [brute, player]

func _clear(s: Array) -> void:
	for n in s:
		if is_instance_valid(n):
			(n as Node).queue_free()
	await _frames(4)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Physics frames until `cond` holds, or -1 when it has not after `limit`.
func _until(cond: Callable, limit: int) -> int:
	for i in limit + 1:
		if cond.call():
			return i
		await get_tree().physics_frame
	return -1

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
