extends Node3D
## Regression probe: an enemy standing INSIDE the player's capsule must still
## "see" the player and keep attacking.
##
## Enemies only mask the world (collision_mask = 1), so a leaping skitter, a
## brute pressing in, or anything arriving during the dash's i-frames can end
## up with its eye inside the player's 0.35 m capsule. EnemyBase._compute_can_see
## then fires a ray that STARTS inside the player's shape; Godot's default
## (hit_from_inside = false) never reports that shape, the ray hits nothing,
## "see" returns false, and the robot drops ATTACK -> CHASE toward a target it
## is already touching - stuck and passive, at point-blank. The telemetry rig
## caught a skitter doing exactly this: 4 bites, then dist=0.0 see=false CHASE
## for the rest of the window.
##
## Spawns a skitter AT the player's position, drops it into ATTACK, and asserts
## (1) _compute_can_see is true at zero distance and (2) bites keep landing.
##   godot --headless --path . --audio-driver Dummy res://tests/pointblank_los_probe.tscn

const WINDOW := 6.0
const MIN_BITES := 2

var _fail: Array[String] = []
var _player: Node3D
var _hits: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_player.set_physics_process(false) # no soft-separation push: hold the overlap
	await get_tree().physics_frame
	var hp: Node = _player.get_node_or_null("Damageable")
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	hp.damaged.connect(func(_amount: float, _src): _hits += 1)
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	var e: Node3D = (load("res://scenes/enemies/skitter.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = _player.global_position # inside the capsule
	e.set_physics_process(false) # pin it there: the question is sight, not motion
	for i in 3:
		await get_tree().physics_frame
	e.set("target", _player)
	var dist: float = e.global_position.distance_to(_player.global_position)
	var sees: bool = e._compute_can_see(_player)
	print("skitter at dist %.2f m: _compute_can_see = %s" % [dist, sees])
	_check(sees, "enemy inside the player's capsule still sees the player")

	# Now let it fight from there.
	e.set_physics_process(true)
	if e.has_method("set_state"):
		e.call("set_state", 4) # State.ATTACK
	var t := 0.0
	var states: Dictionary = {}
	while t < WINDOW:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var s := str(e.get("state"))
		states[s] = int(states.get(s, 0)) + 1
		hp.current_health = 1000000.0
	print("bites landed in %.0fs: %d   state histogram (physics frames): %s" % [WINDOW, _hits, states])
	_check(_hits >= MIN_BITES, "at least %d bites landed from point-blank (%d)" % [MIN_BITES, _hits])

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
