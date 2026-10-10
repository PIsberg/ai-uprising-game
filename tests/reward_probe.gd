extends Node
## Probe: the REWARD MODEL (enemy_reward.gd), reinforcement learning from the
## player's pain.
## (1) it is wired: level builder, codex, one on MISTRAL and one on the vault;
## (2) a robot near it that hurts the player is rewarded: attack cooldown x
##     REWARD_CD, a reward tag over it; rewards wait REWARD_GAP between hits and
##     cap at REWARD_MAX;
## (3) no reward for a robot out of REWARD_RANGE, a boss-sized one, or damage
##     with no robot behind it;
## (4) its death revokes every reward: cooldowns back, tags gone.
##   godot --headless --path . --audio-driver Dummy res://tests/reward_probe.tscn

const SCENE := "res://scenes/enemies/reward.tscn"
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

func _count(level: String) -> int:
	var n := 0
	for en in LevelDefs.get_def(level).get("enemies", []):
		if en.get("type", "") == "reward":
			n += 1
	return n

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	return e

func _run() -> void:
	# 1. Wiring.
	_check("level builder knows reward", LevelBuilder.ENEMY_SCENES.get("reward", "") == SCENE)
	_check("codex entry", EnemyCodex.has("reward") and "reward" in EnemyCodex.ORDER)
	_check("one on MISTRAL", _count("mistral") == 1, str(_count("mistral")))
	_check("one in the CLAUDE vault", _count("claude") == 1, str(_count("claude")))

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
	var php := Damageable.new()
	php.name = "Damageable"
	php.max_health = 1000000.0
	player.add_child(php)
	add_child(player)
	player.global_position = Vector3(0, 0, 30)

	var rm: EnemyReward = (load(SCENE) as PackedScene).instantiate()
	add_child(rm)
	rm.global_position = Vector3(0, 3, 0)
	rm.set_physics_process(false) # posed: it listens, it does not fly
	var near := _robot(Vector3(4, 0, 2))
	var far := _robot(Vector3(0, 0, -(EnemyReward.REWARD_RANGE + 10.0)))
	var boss := _robot(Vector3(-4, 0, 2))
	boss.score_value = 1000
	await _frames(3)
	var c0 := near.attack_cooldown
	var cf := far.attack_cooldown
	var cb := boss.attack_cooldown

	# 2. Rewarded for the hit.
	php.apply_damage(5.0, near)
	_check("a nearby robot that hurts the player is rewarded", EnemyReward.level_of(near) == 1
			and is_equal_approx(near.attack_cooldown, c0 * EnemyReward.REWARD_CD),
			"level %d, cd %.2f -> %.2f" % [EnemyReward.level_of(near), c0, near.attack_cooldown])
	_check("it wears a reward tag", near.get_node_or_null("RewardTag") is Label3D)
	php.apply_damage(5.0, near)
	_check("not again inside REWARD_GAP", EnemyReward.level_of(near) == 1)
	for i in EnemyReward.REWARD_MAX + 2:
		await _frames(int(EnemyReward.REWARD_GAP * 60.0) + 3)
		php.apply_damage(5.0, near)
	_check("rewards cap at REWARD_MAX", EnemyReward.level_of(near) == EnemyReward.REWARD_MAX
			and is_equal_approx(near.attack_cooldown, c0 * pow(EnemyReward.REWARD_CD, EnemyReward.REWARD_MAX)),
			"level %d" % EnemyReward.level_of(near))

	# 3. No reward.
	php.apply_damage(5.0, far)
	php.apply_damage(5.0, boss)
	php.apply_damage(5.0, null)
	_check("out of range: none", EnemyReward.level_of(far) == 0 and is_equal_approx(far.attack_cooldown, cf))
	_check("boss-sized: none", EnemyReward.level_of(boss) == 0 and is_equal_approx(boss.attack_cooldown, cb))

	# 4. Death revokes.
	rm.hp.apply_damage(99999.0, player)
	await _frames(3)
	_check("its death revokes the rewards", EnemyReward.level_of(near) == 0 and is_equal_approx(near.attack_cooldown, c0)
			and near.get_node_or_null("RewardTag") == null, "cd %.2f vs %.2f" % [near.attack_cooldown, c0])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
