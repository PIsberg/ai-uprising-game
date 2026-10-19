extends RefCounted
## Reckless reference player for playtest drivers (the survival_probe bot, made
## reusable): turns toward the nearest live robot, closes to ~14 m, strafes and
## fires; with nothing in sight it walks at the nearest unspawned spawner; hops
## when stuck. It never reloads by hand (auto-reload covers it) and never uses
## cover, so it is the new player who walks at hostiles in the open, not a good one.
##   var bot = preload("res://tests/playtest_bot.gd").new(self)
##   var stats: Dictionary = await bot.fight(60.0)
## Time is GAME time (physics frames), never create_timer: see tests/README.md.

var host: Node ## any node in the tree; the bot awaits on its tree
var wall_limit_ms := 120_000 ## a slow runner cannot turn N game seconds into many minutes

func _init(h: Node) -> void:
	host = h

func _tree() -> SceneTree:
	return host.get_tree()

func player() -> CharacterBody3D:
	return _tree().get_first_node_in_group("player") as CharacterBody3D

func wait_game(seconds: float) -> float:
	var acc := 0.0
	while acc < seconds:
		await _tree().physics_frame
		acc += host.get_physics_process_delta_time()
	return acc

## Fight for `seconds` of game time, or until the player dies. Returns
## {t, kills, damage_taken, hits_taken, min_hp, died, killer, pace, wall_capped}.
func fight(seconds: float) -> Dictionary:
	var p := player()
	if p == null:
		return {}
	var cam: Camera3D = p.get("camera")
	var head: Node3D = p.get_node_or_null("Head")
	var taken := [0.0, 0]
	var on_hit := func(amount: float, _src: Node) -> void:
		taken[0] += amount
		taken[1] += 1
	p.hp.damaged.connect(on_hit)
	var kills0: int = GameState.kills
	var t := 0.0
	var wall0 := Time.get_ticks_msec()
	var min_hp: float = p.hp.current_health
	var last_pos := p.global_position
	var stuck := 0
	var capped := false
	while t < seconds:
		if Time.get_ticks_msec() - wall0 > wall_limit_ms:
			capped = true
			break
		if not is_instance_valid(p) or not p.hp.is_alive() or GameState.current_state != GameState.State.PLAYING:
			break
		min_hp = minf(min_hp, p.hp.current_health)
		if last_pos.distance_to(p.global_position) < 0.01:
			stuck += 1
		else:
			stuck = 0
		last_pos = p.global_position
		if stuck > 3:
			Input.action_press("jump")
			await wait_game(0.15)
			Input.action_release("jump")
			stuck = 0
		var e := _nearest_enemy(p)
		Input.action_release("move_left")
		if e:
			_aim(p, cam, head, e.global_position + Vector3(0, 0.6, 0))
			if p.global_position.distance_to(e.global_position) > 14.0:
				Input.action_press("move_forward")
			else:
				Input.action_release("move_forward")
				Input.action_press("move_left")
			Input.action_press("fire")
		else:
			var sp := _nearest_spawner(p)
			if sp:
				_aim(p, cam, head, sp.global_position + Vector3(0, 1.0, 0))
				Input.action_press("move_forward")
			else:
				Input.action_release("move_forward")
		t += await wait_game(0.25)
		Input.action_release("fire")
		t += await wait_game(0.08)
	release_all()
	if is_instance_valid(p) and p.hp.damaged.is_connected(on_hit):
		p.hp.damaged.disconnect(on_hit)
	var alive: bool = is_instance_valid(p) and p.hp.is_alive()
	return {"t": t, "kills": GameState.kills - kills0, "damage_taken": taken[0], "hits_taken": taken[1],
		"min_hp": min_hp if alive else 0.0, "died": not alive,
		"killer": GameState.last_killer if not alive else "",
		"pace": t / maxf(0.001, (Time.get_ticks_msec() - wall0) / 1000.0), "wall_capped": capped}

func release_all() -> void:
	for a in ["move_forward", "move_left", "fire", "jump"]:
		Input.action_release(a)

func _aim(p: CharacterBody3D, cam: Camera3D, head: Node3D, target: Vector3) -> void:
	var d := target - cam.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	if head:
		head.rotation.x = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)

func _nearest_enemy(p: Node3D) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for e in _tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			var d: float = p.global_position.distance_to((e as Node3D).global_position)
			if d < bd:
				bd = d
				best = e
	return best

func _nearest_spawner(p: Node3D) -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for s in _tree().root.find_children("*", "EnemySpawner", true, false):
		if s.get("_spawned"):
			continue
		var d: float = p.global_position.distance_to((s as Node3D).global_position)
		if d < bd:
			bd = d
			best = s
	return best
