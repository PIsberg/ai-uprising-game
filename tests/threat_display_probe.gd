extends Node3D
## Probe: a robot BRISTLES at first contact. The moment a non-boss robot
## first locks onto the player (EnemyBase.set_state's first-contact hook) its
## chassis rears back and lifts for about 0.4 s (EnemyBase._bristle, folded
## into the flinch/stagger nudge on the Model node), then settles.
## (1) ANDROID and DRONE: within 0.3 s of first contact the Model node has
##     reared back 0.15+ rad and risen 0.04+ m; 0.8 s on it is back within
##     0.01 rad and 0.005 m of its base;
## (2) a second state change while engaged does not re-trigger it; dropping
##     back to IDLE re-arms it;
## (3) a boss (MANUS) never bristles.
##   godot --headless --path . --audio-driver Dummy res://tests/threat_display_probe.tscn

var ok := true
var _player: CharacterBody3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

## Spawn `scene` out of the player's sight, idle, with its base pose settled.
func _spawn(scene: String, at: Vector3) -> CharacterBody3D:
	var e: CharacterBody3D = (load(scene) as PackedScene).instantiate()
	add_child(e)
	e.global_position = at
	e.set("sight_range", 0.0)
	e.set("hearing_range", 0.0)
	e.set("_attack_timer", 999.0)
	await _wait(0.4)
	return e

func _bristle_of(e: CharacterBody3D, tag: String) -> void:
	var model: Node3D = e.get_node("Model")
	var base_rot: float = model.rotation.x
	var base_y: float = model.position.y
	# Let it see the player from here on, or its own AI drops back to IDLE
	# (which re-arms the display) between the checks.
	e.set("sight_range", 60.0)
	e.set("target", _player)
	e.call("set_state", 3) # CHASE: first contact
	var rear := 0.0
	var rise := 0.0
	var t := 0.0
	while t < 0.3:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		e.set("_attack_timer", 999.0)
		rear = maxf(rear, base_rot - model.rotation.x)
		rise = maxf(rise, model.position.y - base_y)
	_check("%s rears back at first contact" % tag, rear >= 0.15, "(%.2f rad)" % rear)
	_check("%s lifts at first contact" % tag, rise >= 0.04, "(%.3f m)" % rise)
	await _wait(0.5)
	var off_rot: float = absf(model.rotation.x - base_rot)
	var off_y: float = absf(model.position.y - base_y)
	_check("%s settles back" % tag, off_rot < 0.01 and off_y < 0.005, "(%.3f rad, %.3f m)" % [off_rot, off_y])

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	add_child(floor_body)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.1, -12)
	_player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = _player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0

	var a := await _spawn("res://scenes/enemies/android.tscn", Vector3(0, 0.1, 0))
	await _bristle_of(a, "ANDROID")
	# (2) Engaged already: another state change is not a first contact.
	a.call("set_state", 4) # ATTACK
	await get_tree().physics_frame
	_check("no second bristle while engaged", float(a.get("_bristle")) <= 0.0, "(%.2f)" % float(a.get("_bristle")))
	a.set("sight_range", 0.0)
	a.set("target", null)
	a.call("set_state", 0) # IDLE re-arms
	a.set("sight_range", 60.0)
	a.set("target", _player)
	a.call("set_state", 3)
	await get_tree().physics_frame
	_check("re-armed after it drops to IDLE", float(a.get("_bristle")) > 0.5, "(%.2f)" % float(a.get("_bristle")))
	a.queue_free()

	var d := await _spawn("res://scenes/enemies/drone.tscn", Vector3(3, 2.5, 0))
	await _bristle_of(d, "DRONE")
	d.queue_free()

	# (3) A boss keeps its composure (it has an entrance for that).
	var b := await _spawn("res://scenes/enemies/manus.tscn", Vector3(-6, 0.1, 0))
	b.set("target", _player)
	b.call("set_state", 3)
	await get_tree().physics_frame
	_check("a boss never bristles", float(b.get("_bristle")) <= 0.0, "(%.2f)" % float(b.get("_bristle")))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
