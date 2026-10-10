extends Node3D
## Probe: the MODEL HALLUCINATION skirmish event (GameState._event_hallucination,
## PlayerPhantom, EnemyBase._perceive).
## (1) the event spawns EVENT_PHANTOMS phantoms around the player and announces it;
## (2) a robot closer to a phantom than to the player targets the phantom and
##     its fire lands on the phantom, not the player;
## (3) a robot closer to the player keeps the player;
## (4) phantoms are not in the "player" group and the player's own fire passes
##     through them;
## (5) when the hallucination ends the phantoms are gone and the robot turns
##     back to the player.
##   godot --headless --path . --audio-driver Dummy res://tests/hallucination_probe.tscn

const ANDROID := "res://scenes/enemies/android.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4
	pcap.height = 1.8
	pcs.shape = pcap
	pcs.position.y = 0.9
	player.add_child(pcs)
	var php := Damageable.new()
	php.name = "Damageable"
	php.max_health = 100000.0
	player.add_child(php)
	add_child(player)
	GameState.current_state = GameState.State.PLAYING

	# 1. The event.
	var titles: Array[String] = []
	var on_event := func(t: String, _d: String) -> void: titles.append(t)
	GameState.skirmish_event.connect(on_event)
	GameState._event_hallucination()
	await _frames(2)
	var phantoms := get_tree().get_nodes_in_group("player_phantom")
	_check("event spawns the phantoms", phantoms.size() == GameState.EVENT_PHANTOMS, "%d" % phantoms.size())
	_check("event announces itself", titles.has("MODEL HALLUCINATION"))
	GameState.skirmish_event.disconnect(on_event)
	for p in phantoms:
		(p as PlayerPhantom).pop(false)
	await _frames(15)

	# 2/3. A robot near a phantom turns on it; one near the player keeps the player.
	var ph := PlayerPhantom.new()
	add_child(ph)
	ph.global_position = Vector3(30, 0, 0)
	var near_ph := _robot(Vector3(30, 0, -8))
	var near_pl := _robot(Vector3(0, 0, -8))
	await _frames(30)
	_check("robot near a phantom targets it", near_ph.target == ph)
	_check("robot near the player keeps the player", near_pl.target == player)
	_check("phantom is not a player", not ph.is_in_group("player"))
	near_pl.process_mode = Node.PROCESS_MODE_DISABLED # only the deceived robot fires now
	var ph_hp := ph.get_node("Damageable") as Damageable
	var ph0 := ph_hp.current_health
	var pl0 := php.current_health
	for i in 360:
		await get_tree().physics_frame
		if not is_instance_valid(ph) or ph_hp.current_health < ph0:
			break
	_check("its fire lands on the phantom", not is_instance_valid(ph) or ph_hp.current_health < ph0,
			"%.0f -> %.0f" % [ph0, ph_hp.current_health if is_instance_valid(ph) else 0.0])
	_check("not on the player", php.current_health == pl0)

	# 4. The player's own fire passes through a phantom.
	if is_instance_valid(ph):
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(ph.global_position + Vector3(0, 1, 5), ph.global_position + Vector3(0, 1, -5))
		q.collision_mask = 0b0000101 # the player's fire: world + enemy
		var hit := space.intersect_ray(q)
		_check("player fire passes through", hit.is_empty() or hit.collider != ph)

	# 5. The hallucination ends.
	if is_instance_valid(ph):
		ph.life = 0.05
	await _frames(40)
	_check("phantom gone when it ends", not is_instance_valid(ph))
	near_pl.process_mode = Node.PROCESS_MODE_INHERIT
	await _frames(20)
	_check("robot turns back to the player", near_ph.target == player)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	return e
