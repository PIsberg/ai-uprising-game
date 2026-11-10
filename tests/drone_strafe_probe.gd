extends Node3D
## Probe: the DRONE's STRAFING RUN (EnemyDrone._tick_run). Its dive used to be
## a swoop with the ordinary shots still coming; now the dive is the attack:
##   - the plain drone strafes, a subclass built on it (QUANTIZER) does not;
##   - when a dive starts the eye flares and nothing is fired for STRAFE_LEAD;
##   - then exactly STRAFE_SHOTS rounds leave the muzzle, STRAFE_GAP apart;
##   - their lines meet the floor in a row walking at the player: the first
##     STRAFE_SHORT short, each one nearer, the last on the player;
##   - no ordinary shot is fired during the dive (the run is all it fires);
##   - out of a dive it fires its ordinary single shots at the player again.
## Timed in physics frames.
##   godot --headless --path . --audio-driver Dummy res://tests/drone_strafe_probe.tscn

var ok := true
var shots: Array = [] ## [frame, origin, velocity] per projectile added
var frame := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	cs.shape = box
	sb.add_child(cs)
	sb.position.y = -0.5
	add_child(sb)
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	frame += 1

func _on_node(n: Node) -> void:
	if n.has_method("launch") and n is Node3D:
		_note.call_deferred(n, frame)

func _note(n: Node3D, at: int) -> void:
	if is_instance_valid(n):
		shots.append([at, n.global_position, n.get("_velocity")])

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var q: Node = (load("res://scenes/enemies/quantizer.tscn") as PackedScene).instantiate()
	add_child(q)
	q.global_position = Vector3(40, 3, 40)
	var drone: EnemyDrone = (load("res://scenes/enemies/drone.tscn") as PackedScene).instantiate()
	add_child(drone)
	drone.global_position = Vector3(0, 2.5, 0)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 5000.0
	player.add_child(d)
	add_child(player)
	d.current_health = 5000.0
	player.global_position = Vector3(0, 0, -11)
	await get_tree().physics_frame
	_check("the plain drone strafes", drone._strafing)
	_check("a subclass built on it does not", not q.get("_strafing"))
	q.queue_free()
	# Into the fight, with the dive held off.
	drone._dive_timer = 999.0
	for i in 600:
		await get_tree().physics_frame
		if drone.state == EnemyBase.State.ATTACK:
			break
	_check("the drone is fighting the player", drone.state == EnemyBase.State.ATTACK and drone.target == player)
	get_tree().node_added.connect(_on_node)
	# Ordinary fire, no dive.
	shots.clear()
	for i in 90:
		await get_tree().physics_frame
	await get_tree().process_frame
	var plain := shots.size()
	var on_player := shots.all(func(s) -> bool: return _line_miss(s, player) < 1.2)
	_check("out of a dive it fires single shots at the player", plain >= 2 and on_player, "%d shots" % plain)
	# The dive.
	var eye: OmniLight3D = drone.get_node("Eye/EyeLight")
	var calm := eye.light_energy
	shots.clear()
	drone._attack_timer = 0.0
	drone._dive_timer = 0.0
	var start := frame
	var flare := 0.0
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame
		flare = maxf(flare, eye.light_energy)
	_check("a dive starts", drone._diving)
	_check("the eye flares before any round", flare > 3.5 and shots.is_empty(), "%.1f against %.1f calm, %d rounds" % [flare, calm, shots.size()])
	while drone._diving and frame - start < 120:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check("the run is exactly STRAFE_SHOTS rounds", shots.size() == EnemyDrone.STRAFE_SHOTS, str(shots.size()))
	if shots.size() == EnemyDrone.STRAFE_SHOTS:
		var first: float = (shots[0][0] - start) / 60.0
		_check("nothing is fired for STRAFE_LEAD", absf(first - EnemyDrone.STRAFE_LEAD) < 0.07, "first round at %.2f s" % first)
		var gaps_ok := true
		for i in range(1, shots.size()):
			if absf((shots[i][0] - shots[i - 1][0]) / 60.0 - EnemyDrone.STRAFE_GAP) > 0.05:
				gaps_ok = false
		_check("the rounds are STRAFE_GAP apart", gaps_ok, str(shots.map(func(s) -> int: return s[0] - start)))
		var miss: Array = shots.map(func(s) -> float: return _floor_miss(s, player))
		var walking := true
		for i in range(1, miss.size()):
			if i < miss.size() - 1 and miss[i] >= miss[i - 1] - 0.5:
				walking = false
		_check("the first lands STRAFE_SHORT short", absf(miss[0] - EnemyDrone.STRAFE_SHORT) < 0.8, "%.1f m" % miss[0])
		_check("each lands nearer than the last", walking, str(miss))
		var last_miss := _line_miss(shots[shots.size() - 1], player)
		_check("the last is on the player", last_miss < 1.2, "%.1f m off the chest" % last_miss)
		# Short of the player on the drone's side, not past them.
		var p0 := _floor_point(shots[0])
		_check("the row starts on the drone's side of the player", p0.z > player.global_position.z + 1.5, "z %.1f" % p0.z)
	get_tree().node_added.disconnect(_on_node)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Where a round's line meets the floor.
func _floor_point(s: Array) -> Vector3:
	var o: Vector3 = s[1]
	var v: Vector3 = s[2]
	if v.y >= -0.001:
		return o + v.normalized() * 100.0
	return o + v * (-o.y / v.y)

## Metres a round's line passes from the player's chest.
func _line_miss(s: Array, player: Node3D) -> float:
	var o: Vector3 = s[1]
	var v: Vector3 = (s[2] as Vector3).normalized()
	var to := player.global_position + Vector3.UP * 0.8 - o
	return (to - v * to.dot(v)).length()

## Metres between that point and the player's feet.
func _floor_miss(s: Array, player: Node3D) -> float:
	var p := _floor_point(s)
	return Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()
