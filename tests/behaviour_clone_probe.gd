extends Node3D
## BEHAVIOUR CLONE skirmish event (BehaviourClone, GameState._event_behaviour_clone).
## On a flat floor with a stand-in player that is walked and "fires" (bumps
## GameState.stat_shots) by script, aiming along +X:
##   - the event announces itself and the clone trains where the player stood;
##   - after TRAIN_TIME it walks the player's path TRAIN_TIME behind them;
##   - walking on along your own line of fire gets you shot in the back, and a
##     robot standing in that line neither takes a bolt nor shields you;
##   - stepping off the line, the replayed shots miss;
##   - standing still where you fired, they hit (from inside you);
##   - its laser is on while it replays; it fades after LIFE with no bonus;
##   - a second roll while one is alive is a SUPPLY FLARE instead;
##   - HEALTH damage deletes it: BONUS and CLONE DELETED.
##   godot --headless --path . --audio-driver Dummy res://tests/behaviour_clone_probe.tscn

var _fails: Array[String] = []
var _toasts: Array[String] = []
var _player: CharacterBody3D
var _pdmg: Damageable
var _shoot_t := 0.0

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.skirmish_event.connect(func(t: String, _d: String) -> void: _toasts.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	_build()
	await _run()
	await _kill()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _build() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	add_child(sb)
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position = Vector3.UP * 0.9
	_player.add_child(pcs)
	_pdmg = Damageable.new()
	_pdmg.name = "Damageable"
	_pdmg.max_health = 10000.0
	_player.add_child(_pdmg)
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.6
	head.rotation.y = -PI * 0.5 # camera -Z looks along +X
	_player.add_child(head)
	var cam := Node3D.new()
	cam.name = "Camera3D"
	head.add_child(cam)
	add_child(_player)

func _clone() -> BehaviourClone:
	for c in get_tree().get_nodes_in_group("behaviour_clone"):
		if c is BehaviourClone and (c as BehaviourClone).phase != BehaviourClone.Phase.DONE:
			return c
	return null

## Walks the player `step` per physics frame for `s` seconds, firing every
## 0.25 s when `fire`. Returns the damage taken meanwhile.
func _act(s: float, step: Vector3, fire: bool) -> float:
	var hp0 := _pdmg.current_health
	for i in int(round(s * Engine.physics_ticks_per_second)):
		_player.global_position += step
		if fire:
			_shoot_t -= 1.0 / Engine.physics_ticks_per_second
			if _shoot_t <= 0.0:
				_shoot_t = 0.25
				GameState.stat_shots += 1
		await get_tree().physics_frame
	return hp0 - _pdmg.current_health

func _run() -> void:
	print("replay:")
	_player.global_position = Vector3(0, 0.05, 0)
	await _frames(4)
	var robot := StaticBody3D.new()
	robot.add_to_group("enemy")
	robot.collision_layer = 4
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(0.8, 2.0, 0.8)
	rcs.shape = rbox
	rcs.position.y = 1.0
	robot.add_child(rcs)
	var rdmg := Damageable.new()
	rdmg.name = "Damageable"
	rdmg.max_health = 100.0
	robot.add_child(rdmg)
	robot.position = Vector3(12, 0, 0)
	add_child(robot)
	_toasts.clear()
	GameState._event_behaviour_clone()
	await _frames(2)
	var c := _clone()
	_check(c != null and _toasts.has("BEHAVIOUR CLONE"), "the event announces itself and spawns a clone")
	if c == null:
		return
	_check(c.phase == BehaviourClone.Phase.TRAIN and c.global_position.distance_to(Vector3(0, 0.05, 0)) < 0.2, "it trains where the player stood")
	var v := 2.0 / Engine.physics_ticks_per_second # 2 m/s along +X
	var trained := await _act(BehaviourClone.TRAIN_TIME, Vector3(v, 0, 0), true)
	_check(trained == 0.0 and c.shots_fired == 0, "while it trains it fires nothing")
	_check(c.phase == BehaviourClone.Phase.REPLAY and c._laser.visible, "then it replays, laser on")
	var mid := await _act(BehaviourClone.TRAIN_TIME * 0.5, Vector3(v, 0, 0), true)
	_check(c.global_position.distance_to(Vector3(4, 0.05, 0)) < 0.3, "it walks the player's path %.0f s behind (at %s)" % [BehaviourClone.TRAIN_TIME, c.global_position])
	var on_line := mid + await _act(BehaviourClone.TRAIN_TIME * 0.5, Vector3(v, 0, 0), true)
	_check(on_line > 0.0 and c.hits >= 3, "walking on along your own line of fire gets you shot (%.0f, %d hits)" % [on_line, c.hits])
	_check(is_equal_approx(rdmg.current_health, 100.0), "a robot in that line is neither hurt nor a shield")
	# Step off the line and stop shooting: the shots fired on the way out replay along z = 0.
	_player.global_position += Vector3(0, 0, 4.0)
	var hits0 := c.hits
	var off_line := await _act(BehaviourClone.TRAIN_TIME, Vector3.ZERO, false)
	_check(off_line == 0.0 and c.hits == hits0 and c.shots_fired > hits0, "off the line its shots miss (%.0f damage, %d shots)" % [off_line, c.shots_fired - hits0])
	# Stand still and fire: four seconds later it stands inside you, firing.
	await _act(BehaviourClone.TRAIN_TIME, Vector3.ZERO, true)
	var still := await _act(BehaviourClone.TRAIN_TIME, Vector3.ZERO, false)
	_check(still > 0.0, "standing still where you fired gets you shot (%.0f)" % still)
	_toasts.clear()
	GameState._event_behaviour_clone()
	await _frames(2)
	_check(_toasts.has("SUPPLY FLARE") and get_tree().get_nodes_in_group("behaviour_clone").size() == 1, "a second roll while one is alive is a supply flare")
	for n in get_tree().root.find_children("SupplyFlare", "", true, false):
		n.queue_free()
	var s0 := GameState.score
	var left := BehaviourClone.LIFE - BehaviourClone.TRAIN_TIME * 4.0 + 0.5
	await _act(left, Vector3.ZERO, false)
	_check(_clone() == null and GameState.score == s0, "after %.0f s it fades, no bonus" % BehaviourClone.LIFE)
	robot.queue_free()
	await _frames(20)
	_check(get_tree().get_nodes_in_group("behaviour_clone").is_empty(), "and frees itself")

func _kill() -> void:
	print("kill:")
	GameState._event_behaviour_clone()
	await _frames(2)
	var c := _clone()
	_toasts.clear()
	var s0 := GameState.score
	c.hp.apply_damage(BehaviourClone.HEALTH + 1.0, _player)
	await _frames(2)
	_check(c.phase == BehaviourClone.Phase.DONE and GameState.score - s0 == BehaviourClone.BONUS and _toasts.has("CLONE DELETED"),
		"shot apart it is deleted: +%d and the toast (%d, %s)" % [BehaviourClone.BONUS, GameState.score - s0, _toasts])
	var q := PhysicsRayQueryParameters3D.create(Vector3(c.global_position.x, 1.0, -5), Vector3(c.global_position.x, 1.0, 5), 0b0000101)
	await _frames(1)
	_check(get_world_3d().direct_space_state.intersect_ray(q).is_empty() or not is_instance_valid(c), "and stops catching fire")
	await _frames(20)
