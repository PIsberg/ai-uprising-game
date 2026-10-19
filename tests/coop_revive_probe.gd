extends Node3D
## Probe: co-op DOWN and REVIVE, stage 4 of local co-op (#402). Two real players
## on a floor:
## (1) a player at 0 HP while the partner stands goes DOWN: is_down(), the level
##     plays on (no GAME_OVER) and a robot turns to the partner;
## (2) the partner holding interact within REVIVE_RANGE for REVIVE_TIME stands
##     them back up at REVIVE_HEALTH_FRAC with their weapons live; letting go
##     early starts the hold over, and holding from out of range does nothing;
## (3) the last one standing going down is game over;
## (4) the checkpoint respawn brings BOTH back, player two beside player one;
## (5) solo, 0 HP is game over exactly as before.
##   godot --headless --path . --audio-driver Dummy res://tests/coop_revive_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
const ANDROID := "res://scenes/enemies/android.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

func _player(index: int, pos: Vector3) -> CharacterBody3D:
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("player_index", index)
	add_child(p)
	p.global_position = pos
	return p

func _kill(p: Node) -> void:
	(p.get("hp") as Damageable).apply_damage(99999.0, null, false, null, true)

func _hp_frac(p: Node) -> float:
	var hp := p.get("hp") as Damageable
	return hp.current_health / hp.max_health

func _run() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	GameState.set_state(GameState.State.PLAYING)
	var p1 := _player(0, Vector3(-1, 0.1, 0))
	var p2 := _player(1, Vector3(5, 0.1, 0))
	await _wait_game(0.5) # past the spawn grace
	for p in [p1, p2]:
		(p.get("hp") as Damageable).invulnerable = false

	# 1. Down, not out.
	var bot: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	add_child(bot)
	bot.global_position = Vector3(6, 0, -8)
	bot.set_physics_process(false)
	await _wait_game(0.2)
	_kill(p2)
	await _wait_game(0.3)
	_check("a player at 0 HP with a partner standing goes down", p2.is_down() and p2.get("downed") == true)
	_check("the level plays on", GameState.current_state == GameState.State.PLAYING, "state %d" % GameState.current_state)
	_check("a robot turns to the partner", bot.call("_find_player") == p1)

	# 2. Revive: out of range does nothing, an early release starts over, a full hold stands them up.
	Input.action_press("interact")
	await _wait_game(1.0)
	_check("holding interact out of range does nothing", float(p2.get("revive_progress")) == 0.0,
			"%.2f" % float(p2.get("revive_progress")))
	p1.global_position = Vector3(3.5, 0.1, 0)
	await _wait_game(1.2)
	var mid := float(p2.get("revive_progress"))
	Input.action_release("interact")
	await _wait_game(0.2)
	_check("letting go early starts the hold over", mid > 0.2 and float(p2.get("revive_progress")) == 0.0,
			"%.2f then %.2f" % [mid, float(p2.get("revive_progress"))])
	Input.action_press("interact")
	await _wait_game(Player.REVIVE_TIME + 0.3)
	Input.action_release("interact")
	_check("a full hold stands them back up", not p2.is_down() and p2.get("downed") == false)
	_check("at REVIVE_HEALTH_FRAC", absf(_hp_frac(p2) - Player.REVIVE_HEALTH_FRAC) < 0.01, "%.2f" % _hp_frac(p2))
	var wh: Node = p2.get("weapon_holder")
	_check("with their weapons live again", wh != null and wh.process_mode != Node.PROCESS_MODE_DISABLED)
	await _wait_game(Player.RESPAWN_GRACE_TIME + 0.2)

	# 3. The last one standing going down is game over.
	GameState.set_checkpoint()
	p1.global_position = Vector3(-10, 0.1, 4)
	p2.global_position = Vector3(10, 0.1, 4)
	await _wait_game(0.2)
	_kill(p2)
	await _wait_game(0.2)
	_check("one down: still playing", GameState.current_state == GameState.State.PLAYING)
	_kill(p1)
	await _wait_game(0.2)
	_check("both down: game over", GameState.current_state == GameState.State.GAME_OVER, "state %d" % GameState.current_state)

	# 4. The checkpoint respawn brings both back.
	GameState.respawn_at_checkpoint()
	await _wait_game(0.3)
	_check("checkpoint respawn stands player one up", not p1.is_down())
	_check("checkpoint respawn stands player two up", not p2.is_down() and p2.get("downed") == false)
	var gap := p2.global_position.distance_to(p1.global_position)
	_check("player two respawns beside player one", gap > 1.0 and gap < 2.5, "%.2f m apart" % gap)
	_check("playing again", GameState.current_state == GameState.State.PLAYING)

	# 5. Solo: 0 HP is game over, as before.
	p2.queue_free()
	await _wait_game(0.2)
	await _wait_game(Player.RESPAWN_GRACE_TIME + 0.2)
	_kill(p1)
	await _wait_game(0.2)
	_check("solo: 0 HP is game over", GameState.current_state == GameState.State.GAME_OVER and p1.get("downed") == false,
			"state %d downed %s" % [GameState.current_state, p1.get("downed")])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
