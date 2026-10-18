extends Node3D
## Probe: the OVERSEER gunship flies its fight on its EyeDrone rig instead of
## firing everything instantly and vanishing.
## (1) the rocket barrage is telegraphed: no rocket leaves on the call, the
##     Charging clip plays and the gunship rears up (nose >= 0.2 rad up);
##     after the windup the full barrage (7 in phase 1) lobs and it plays Attack;
## (2) its bolt volley still fires on the call and plays Attack;
## (3) crossing into phase II it flips (BackFlip);
## (4) killed, it crashes: collision off, still there 0.5 s on and falling
##     (>= 1 m in 0.5 s of the death slow-mo) while it spins, then gone within 4 s, its kill counted once.
##   godot --headless --path . --audio-driver Dummy res://tests/overseer_clip_probe.tscn

var ok := true
var _e: CharacterBody3D
var _ap: AnimationPlayer

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _bombs() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c is EnemyBomb:
			n += 1
	return n

func _bolts() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c.scene_file_path.ends_with("projectile_drone.tscn"):
			n += 1
	return n

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -25)
	player.set_physics_process(false)
	var php: Node = player.get_node("Damageable")
	php.set("max_health", 1000000.0)
	php.set("current_health", 1000000.0)

	_e = (load("res://scenes/enemies/overseer.tscn") as PackedScene).instantiate()
	_e.set("preview", true) # no portal arrival: the probe drives it
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	await _wait(0.5)
	_ap = _e.find_children("*", "AnimationPlayer", true, false)[0]
	var hp: Node = _e.get_node("Damageable")
	hp.set("invulnerable", false)
	hp.set("armor", 0.0)
	_e.set("target", player)
	# Physics on (the rear-up and the hover live there), the AI blind so it never
	# attacks on its own: the probe makes every call.
	_e.set("sight_range", 0.0)
	_e.set_physics_process(true)
	await _wait(1.0) # up to its hover height
	var model: Node3D = _e.get_node("Model")

	# (1) barrage
	_e.set("_barrage_cd", 0.0)
	var before := _bombs()
	_e.call("_perform_attack")
	await get_tree().process_frame
	_check("the barrage does not fire on the call", _bombs() == before, "(%d rockets)" % (_bombs() - before))
	_check("its windup plays Charging", String(_ap.current_animation) == "Charging", "(%s)" % _ap.current_animation)
	var rear := 0.0
	var t := 0.0
	while _bombs() == before and t < 2.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		rear = maxf(rear, model.rotation.x)
	_check("it rears up for the barrage", rear >= 0.2, "(%.2f rad)" % rear)
	_check("then lobs the full barrage", _bombs() - before == 7, "(%d after %.2f s)" % [_bombs() - before, t])
	await get_tree().process_frame
	_check("and plays Attack", String(_ap.current_animation) == "Attack", "(%s)" % _ap.current_animation)
	await _wait(1.5)

	# (2) volley
	_e.set("_barrage_cd", 30.0)
	var bolts := _bolts()
	_e.call("_perform_attack")
	await get_tree().process_frame
	_check("the bolt volley fires on the call", _bolts() > bolts, "(%d bolts)" % (_bolts() - bolts))
	_check("and plays Attack", String(_ap.current_animation) == "Attack", "(%s)" % _ap.current_animation)
	await _wait(1.5)

	# (3) phase II
	var maxh: float = hp.get("max_health")
	hp.call("apply_damage", maxh * 0.4, null)
	await _wait(0.1)
	_check("phase II: it flips", String(_ap.current_animation) == "BackFlip", "(%s)" % _ap.current_animation)
	Engine.time_scale = 1.0
	await _wait(2.0)

	# (4) crash
	var kills_before: int = GameState.get("kills") if GameState.get("kills") != null else 0
	var y0 := model.global_position.y
	var yaw0 := model.global_rotation.y
	hp.call("apply_damage", maxh * 2.0, null)
	await _wait(0.5)
	_check("killed, its collision goes off", is_instance_valid(_e) and _e.collision_layer == 0, "")
	_check("it is still there, falling", is_instance_valid(_e) and y0 - model.global_position.y >= 1.0, "(fell %.2f m)" % ((y0 - model.global_position.y) if is_instance_valid(_e) else -1.0))
	_check("and spinning", is_instance_valid(_e) and absf(wrapf(model.global_rotation.y - yaw0, -PI, PI)) > 0.3, "")
	t = 0.0
	while is_instance_valid(_e) and t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check("then it is gone", not is_instance_valid(_e), "(after %.1f s)" % t)
	var kills_after: int = GameState.get("kills") if GameState.get("kills") != null else 0
	_check("its kill counted once", kills_after - kills_before == 1, "(%d)" % (kills_after - kills_before))
	Engine.time_scale = 1.0
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
