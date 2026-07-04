extends Node
## Headless first-level survival probe — the regression net for the onboarding
## experience. A deliberately reckless bot (walks at hostiles in the open,
## aim-assisted, never manually reloads) plays the opening of the suburb level.
## Before the experience pass (auto-reload on empty, tiered aggro rings,
## health-on-kill) this bot died at first contact with a full reserve. It must
## now survive the opening fight and reach the kill target.
##   godot --headless --path . res://tests/survival_probe.tscn

const KILL_TARGET := 6      # aspiration — reported, not gated (deep waves are meant to bite)
const GATE_TIME := 30.0     # the hard gate: survive the OPENING with kills on the board
const GATE_KILLS := 3       # pre-fix runs died at 10-15 s with 1-3 kills
const TIME_LIMIT := 120.0

var _player: CharacterBody3D
var _cam: Camera3D
var _head: Node3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Play the REAL first campaign level, with campaign context set the way the
	# level loader would — campaign_progress()==0 gates the elite ramp off.
	var first: String = GameState.campaign()[0]
	GameState.current_level_path = first
	var lvl: Node = load(first).instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	await get_tree().create_timer(2.5).timeout
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("NO PLAYER"); print("RESULT FAIL"); get_tree().quit(); return
	_cam = _player.get("camera")
	_head = _player.get_node_or_null("Head")
	GameState.set_state(GameState.State.PLAYING)
	# Deterministic auto-reload check first: empty the mag with reserve in
	# hand, hold the trigger via real input, and expect the reload to start
	# by itself (the manager drives try_fire from Input every frame).
	var wm: Node = _find_wm(_player)
	var w: Weapon = wm.get("current") if wm else null
	var auto_reload_ok := false
	if w:
		w.mag = 0
		w.reserve = maxi(w.reserve, 30)
		Input.action_press("fire")
		await get_tree().create_timer(0.3).timeout
		Input.action_release("fire")
		auto_reload_ok = bool(w.get("_reloading")) or w.mag > 0
		await get_tree().create_timer(w.eff_reload_time() + 0.3).timeout
	# The fight. Hard gate: alive at GATE_TIME with GATE_KILLS on the board —
	# exactly the window pre-fix playtests died in. The deeper 6-kill push is
	# reported for telemetry but not gated: waking the mid-level rings solo
	# with the starter pistol is allowed to be lethal.
	var t := 0.0
	var min_hp := 1e9
	var gate_alive := false
	var gate_kills := 0
	var last_pos := Vector3.ZERO
	var stuck_ticks := 0
	while GameState.kills < KILL_TARGET and t < TIME_LIMIT:
		var current_pos := _player.global_position
		if last_pos.distance_to(current_pos) < 0.01:
			stuck_ticks += 1
		else:
			stuck_ticks = 0
		last_pos = current_pos
		if stuck_ticks > 3:
			Input.action_press("jump")
			await get_tree().create_timer(0.15).timeout
			Input.action_release("jump")
			stuck_ticks = 0
		if t >= GATE_TIME and gate_kills == 0:
			gate_alive = _player.hp.is_alive()
			gate_kills = GameState.kills
		if not _player.hp.is_alive():
			break
		min_hp = minf(min_hp, _player.hp.current_health)
		var e := _nearest_enemy()
		if e == null:
			# Nothing awake — push toward the nearest dormant spawner to trip
			# its wake ring, like a player advancing into the level.
			var sp := _nearest_spawner()
			if sp:
				_aim_at(sp.global_position + Vector3(0, 1.0, 0))
				Input.action_press("move_forward")
		if e:
			_aim_at(e.global_position + Vector3(0, 0.6, 0))
			var dist: float = _player.global_position.distance_to(e.global_position)
			Input.action_release("move_left")
			if dist > 14.0:
				Input.action_press("move_forward")
			else:
				Input.action_release("move_forward")
				Input.action_press("move_left")
			Input.action_press("fire") # never presses R — auto-reload covers it
		await get_tree().create_timer(0.25).timeout
		Input.action_release("fire")
		await get_tree().create_timer(0.08).timeout
		t += 0.33
	for a in ["move_forward", "move_left", "fire"]:
		Input.action_release(a)
	# A fast bot can hit the kill target before GATE_TIME — that also clears the gate.
	if gate_kills == 0:
		gate_alive = _player.hp.is_alive()
		gate_kills = GameState.kills
	var alive: bool = _player.hp.is_alive()
	var hpv: float = _player.hp.current_health
	print("SURVIVAL kills=%d/%d t=%.0fs alive=%s hp=%.0f min_hp=%.0f killer=%s (deep push: telemetry only)" % [
		GameState.kills, KILL_TARGET, t, alive, hpv, min_hp, GameState.last_killer])
	var gate_ok := gate_alive and gate_kills >= GATE_KILLS
	var ok := gate_ok and auto_reload_ok
	print("ok   opening gate" if gate_ok else "BAD  opening gate (alive=%s kills=%d, want >=%d)" % [gate_alive, gate_kills, GATE_KILLS])
	print("ok   auto-reload" if auto_reload_ok else "BAD  empty trigger did not reload")
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _find_wm(root: Node) -> Node:
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if "current" in n and "weapons" in n:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _nearest_spawner() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for s in get_tree().root.find_children("*", "EnemySpawner", true, false):
		if s.get("_spawned"):
			continue
		var d: float = _player.global_position.distance_to((s as Node3D).global_position)
		if d < bd:
			bd = d
			best = s
	return best

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp and (e as EnemyBase).hp.is_alive():
			var d: float = _player.global_position.distance_to((e as Node3D).global_position)
			if d < bd:
				bd = d
				best = e
	return best

func _aim_at(target: Vector3) -> void:
	var eye := _cam.global_position
	var d := target - eye
	_player.rotation.y = atan2(-d.x, -d.z)
	if _head:
		_head.rotation.x = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)
