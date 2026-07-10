extends Node
## Dev probe: validates the skirmish-event director.
## (1) ASSASSIN: spawns a live hunter near the player, pre-marked as the
##     tracked bounty (no double-marking by the bounty director);
## (2) SUPPLY FLARE: spawns a cache root with pickups + beacon that despawns;
## (3) GRID SURGE: ultimate charge builds at exactly double rate while live;
## (4) gating: no events on boss/convoy levels or past the per-level cap.
##   godot --headless --path . res://tests/events_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	# Minimal world: floor + a "player".
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(300, 1, 300)
	cs.shape = sh
	floor_body.add_child(cs)
	get_tree().root.add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.5, 0)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	get_tree().root.add_child(player)
	player.global_position = Vector3(0, 1, 0)
	get_tree().current_scene = get_tree().root.get_child(get_tree().root.get_child_count() - 1) if get_tree().current_scene == null else get_tree().current_scene

	GameState.set_state(GameState.State.PLAYING)
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState._bounty = null

	# 1. ASSASSIN.
	var enemies0: int = get_tree().get_nodes_in_group("enemy").size()
	GameState._event_assassin()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hunters := get_tree().get_nodes_in_group("enemy")
	var assassin: EnemyBase = null
	for e in hunters:
		if e is EnemyBase and (e as EnemyBase).is_bounty:
			assassin = e
	var tracked: bool = GameState._bounty != null and GameState._bounty.get_ref() == assassin
	print("ASSASSIN: spawned=%s bounty_marked=%s tracked=%s" % [hunters.size() == enemies0 + 1, assassin != null, tracked])
	if not (hunters.size() == enemies0 + 1 and assassin != null and tracked):
		ok = false
	if assassin:
		assassin.queue_free()
	GameState._bounty = null

	# 2. SUPPLY FLARE (spawn + timed despawn wiring).
	GameState._event_supply_flare()
	await get_tree().physics_frame
	var flare := get_tree().current_scene.find_children("SupplyFlare", "", true, false)
	var has_parts: bool = not flare.is_empty() and (flare[0] as Node).get_child_count() >= 3
	print("FLARE: spawned=%s parts=%d" % [not flare.is_empty(), (flare[0] as Node).get_child_count() if not flare.is_empty() else 0])
	if not has_parts:
		ok = false
	if not flare.is_empty():
		(flare[0] as Node).queue_free()

	# 3. GRID SURGE doubles ultimate gain.
	GameState.ultimate_charge = 0.0
	GameState._surge_t = 0.0
	GameState.add_ultimate_charge(0.1)
	var base_gain: float = GameState.ultimate_charge
	GameState.ultimate_charge = 0.0
	GameState._event_grid_surge()
	GameState.add_ultimate_charge(0.1)
	var surged: bool = is_equal_approx(GameState.ultimate_charge, base_gain * 2.0)
	print("SURGE: base=%.2f surged=%.2f doubled=%s" % [base_gain, GameState.ultimate_charge, surged])
	if not surged:
		ok = false
	GameState._surge_t = 0.0
	GameState.ultimate_charge = 0.0

	# 4. Gating: boss/convoy levels refuse; the per-level cap holds.
	GameState.current_level_path = "res://scenes/levels/level_titan.tscn" # boss arena
	var boss_blocked: bool = not GameState._events_allowed_here()
	GameState.current_level_path = "res://scenes/levels/level_convoy.tscn"
	var convoy_blocked: bool = not GameState._events_allowed_here()
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	var open_ok: bool = GameState._events_allowed_here()
	GameState._level_events = GameState.EVENTS_PER_LEVEL
	GameState._event_cd = 0.0
	var count0: int = get_tree().get_nodes_in_group("enemy").size()
	GameState._tick_events(1.0) # capped: must not roll anything
	await get_tree().physics_frame
	var capped: bool = get_tree().get_nodes_in_group("enemy").size() == count0 and GameState._surge_t == 0.0
	print("GATES: boss_blocked=%s convoy_blocked=%s normal_ok=%s cap_holds=%s" % [boss_blocked, convoy_blocked, open_ok, capped])
	if not (boss_blocked and convoy_blocked and open_ok and capped):
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
