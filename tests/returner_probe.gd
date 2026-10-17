extends Node3D
## RETURNER elite (Elite "returner" -> GrenadeReturner). On a flat floor with a
## stand-in player and a real android elite (AI frozen; the returner runs):
##   - a player frag landing within CATCH_RANGE in its sight is caught (gone,
##     held), and the first catch teaches the rule;
##   - after WINDUP it lobs a hostile charge that lands by the player and hurts
##     the player (at most RETURN_DAMAGE + RETURN_SPLASH), never the robot;
##   - shot during the wind-up it fumbles: the player's own charge blows up at
##     its feet (the robot is hurt, the far player is not), +FUMBLE_BONUS;
##   - no catch for a charge out of range, one about to blow, an EMP-stunned
##     returner, a plain (non-elite) android, or a hostile charge;
##   - the AI Director answers a frag habit with "returner";
##   - the marker is an upright ring of its own colour (elite_marker_probe
##     checks it differs from the rest).
##   godot --headless --path . --audio-driver Dummy res://tests/returner_probe.tscn

var _fails: Array[String] = []
var _hints: Array[String] = []
var _toasts: Array[String] = []
var _player: CharacterBody3D
var _pdmg: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	GameState.teach_hint.connect(func(t: String) -> void: _hints.append(t))
	GameState.skirmish_event.connect(func(t: String, _d: String) -> void: _toasts.append(t))
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	_build_floor()
	await _catch_and_return()
	await _fumble()
	await _no_catch()
	_director()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second)))

func _build_floor() -> void:
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
	_pdmg.max_health = 1000.0
	_player.add_child(_pdmg)
	_player.position = Vector3(0, 0.05, -12)
	add_child(_player)

func _elite(kind: String, at: Vector3) -> EnemyBase:
	var e := (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate() as EnemyBase
	if kind != "":
		Elite.apply(e, kind)
	e.position = at
	add_child(e)
	e.set_physics_process(false) # freeze its AI; the returner child still runs
	e.set_process(false)
	return e

func _frag(at: Vector3, vel: Vector3 = Vector3.ZERO) -> Grenade:
	var g := (load("res://scenes/weapons/grenade.tscn") as PackedScene).instantiate() as Grenade
	add_child(g)
	g.global_position = at
	g.throw_grenade(vel, _player)
	return g

func _catch_and_return() -> void:
	print("catch and return:")
	var e := _elite("returner", Vector3.ZERO)
	await _frames(10)
	var r := e.get_node_or_null("GrenadeReturner") as GrenadeReturner
	_check(r != null, "a returner elite carries a GrenadeReturner")
	if r == null:
		return
	var marker := e.get_node_or_null("EliteMarker")
	var ring := marker.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D if marker else null
	_check(ring != null and ring.mesh is TorusMesh and absf(ring.rotation.x) > 1.0, "its marker is an upright ring")
	_hints.clear()
	var g := _frag(Vector3(2.5, 0.4, -2.0))
	await _frames(6)
	_check(not is_instance_valid(g) and r.holding and r.catches == 1, "a frag 3 m away is caught and held")
	_check(_hints.has(GrenadeReturner.TEACH_TEXT), "the first catch teaches the rule")
	var hp0 := _pdmg.current_health
	var robot_hp0 := e.hp.current_health
	await _seconds(GrenadeReturner.WINDUP + 0.1)
	_check(not r.holding and r.returns == 1, "after the wind-up it throws it back")
	var thrown: Grenade = null
	for n in get_children():
		if n is Grenade and (n as Grenade).hostile:
			thrown = n
	_check(thrown != null and thrown.hit_mask & 2 != 0 and thrown.hit_mask & 4 == 0, "the return is hostile: world + player, not enemies")
	var land := Vector3.INF
	for i in int(GrenadeReturner.RETURN_FUSE / 0.05) + 4:
		if not is_instance_valid(thrown):
			break
		land = thrown.global_position
		await _seconds(0.05)
	var flat := Vector2(land.x - _player.global_position.x, land.z - _player.global_position.z).length()
	_check(flat < 2.0, "it blows up by the player (%.1f m off)" % flat)
	var took := hp0 - _pdmg.current_health
	_check(took > 0.0 and took <= GrenadeReturner.RETURN_DAMAGE + GrenadeReturner.RETURN_SPLASH + 0.01,
		"the player takes the return's blast (%.1f, max %.0f)" % [took, GrenadeReturner.RETURN_DAMAGE + GrenadeReturner.RETURN_SPLASH])
	_check(is_equal_approx(e.hp.current_health, robot_hp0), "the robot is not hurt by its own throw")
	# Fair: read the throw and step aside, and it misses.
	await _seconds(GrenadeReturner.COOLDOWN)
	var g2 := _frag(Vector3(-2.5, 0.4, -2.0))
	await _frames(6)
	while r.holding:
		await get_tree().physics_frame
	_player.global_position += Vector3(5.5, 0, 0)
	var hp1 := _pdmg.current_health
	await _seconds(GrenadeReturner.RETURN_FUSE + 0.3)
	_check(not is_instance_valid(g2) and r.returns == 2 and is_equal_approx(_pdmg.current_health, hp1),
		"stepping 5.5 m aside after the throw takes nothing (%.1f)" % (hp1 - _pdmg.current_health))
	_player.global_position -= Vector3(5.5, 0, 0)
	e.queue_free()
	await _frames(4)

func _fumble() -> void:
	print("fumble:")
	_player.global_position = Vector3(0, 0.05, -14)
	var hp0 := _pdmg.current_health
	var e := _elite("returner", Vector3.ZERO)
	await _frames(10)
	var r := e.get_node("GrenadeReturner") as GrenadeReturner
	var g := _frag(Vector3(-2.0, 0.4, 2.0))
	await _frames(6)
	_check(not is_instance_valid(g) and r.holding, "caught")
	_toasts.clear()
	var s0 := GameState.score
	e.hp.apply_damage(1.0, _player)
	var robot_hp := e.hp.current_health
	await _frames(2)
	_check(not r.holding and r.fumbles == 1 and r.returns == 0, "a hit during the wind-up makes it fumble")
	await _seconds(GrenadeReturner.FUMBLE_FUSE + 0.3)
	_check(not is_instance_valid(e) or e.hp.current_health < robot_hp - 20.0,
		"the player's own charge blows up at its feet (%.1f -> %.1f)" % [robot_hp, e.hp.current_health if is_instance_valid(e) else 0.0])
	_check(is_equal_approx(_pdmg.current_health, hp0), "the far player is not hurt")
	_check(GameState.score - s0 >= GrenadeReturner.FUMBLE_BONUS and _toasts.has("FUMBLED"), "it pays +%d and says FUMBLED" % GrenadeReturner.FUMBLE_BONUS)
	if is_instance_valid(e):
		e.queue_free()
	await _seconds(0.5)

func _no_catch() -> void:
	print("no catch:")
	var e := _elite("returner", Vector3.ZERO)
	await _frames(10)
	var r := e.get_node("GrenadeReturner") as GrenadeReturner
	var far := _frag(Vector3(GrenadeReturner.CATCH_RANGE + 2.0, 0.4, 0))
	await _frames(6)
	_check(is_instance_valid(far) and not r.holding, "not a charge out of range")
	far.queue_free()
	var late := _frag(Vector3(2.0, 0.4, 0))
	late._t = late.fuse - GrenadeReturner.MIN_FUSE + 0.05
	await _frames(3)
	_check(r.catches == 0, "not a charge about to blow")
	await _seconds(0.6)
	var hostile := _frag(Vector3(-2.0, 0.4, 0))
	hostile.hostile = true
	hostile.hit_mask = 0b0000011
	await _frames(6)
	_check(r.catches == 0, "not a hostile charge")
	if is_instance_valid(hostile):
		hostile.queue_free()
	await _seconds(0.1)
	e.emp_disable(3.0)
	var g := _frag(Vector3(0, 0.4, 2.0))
	await _frames(6)
	_check(r.catches == 0 and is_instance_valid(g), "not while EMP-stunned")
	g.queue_free()
	e.queue_free()
	var plain := _elite("", Vector3(20, 0, 0))
	await _frames(6)
	var g2 := _frag(Vector3(21, 0.4, 0))
	await _frames(6)
	_check(plain.get_node_or_null("GrenadeReturner") == null and is_instance_valid(g2), "a plain android never catches")
	g2.queue_free()
	plain.queue_free()
	await _frames(4)

func _director() -> void:
	print("director:")
	_check(AIDirector._counter_for(0.3, 0.1, 0.5, 0.5, 0.4, true) == "returner", "a frag habit is countered with returner")
	_check(AIDirector._counter_for(0.3, 0.1, 0.5, 0.5, 0.4) == "", "no habit, no returner")
	AIDirector.reset_profile()
	for i in 24:
		AIDirector.note_shot("AR-7 Pulse Rifle")
	for i in 2:
		AIDirector.note_frag()
	_check(not AIDirector.frag_habit(), "2 frags is not yet a habit")
	AIDirector.note_frag()
	_check(AIDirector.frag_habit() and AIDirector.counter_affix() == "returner", "3 frags in 24 shots is (counter %s)" % AIDirector.counter_affix())
	for i in 30:
		AIDirector.note_shot("AR-7 Pulse Rifle")
	_check(not AIDirector.frag_habit(), "3 frags in 54 shots is not")
	AIDirector.reset_profile()
	_check(not AIDirector.frag_habit(), "a new level forgets it")
