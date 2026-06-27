extends Node
## Dev probe: validates the lava/water hazard-balance arenas at runtime. Builds
## each level, then checks: a hazard bed exists, flying enemies spawned, and the
## player came to rest ON a walkway (HP stays ~full instead of draining in the
## sea — proves spawn-on-platform works and the player didn't fall through void).
##   godot --path . --headless res://tests/hazard_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	ok = await _check("res://scenes/levels/level_lava_world.tscn", "LAVA", false) and ok
	ok = await _check("res://scenes/levels/level_water_world.tscn", "WATER", true) and ok
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _check(scene_path: String, tag: String, expect_water: bool) -> bool:
	var lvl: Node = load(scene_path).instantiate()
	get_tree().root.add_child(lvl)
	await _wait(2.6) # build + navmesh bake + settle the player onto the walkway

	var hazards := get_tree().get_nodes_in_group("hazard")
	var enemies := get_tree().get_nodes_in_group("enemy")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var py := player.global_position.y if player else -999.0
	var hp_ratio := 1.0
	if player and player.hp and player.hp.max_health > 0.0:
		hp_ratio = player.hp.current_health / player.hp.max_health
	var water_ok := true
	if not hazards.is_empty():
		water_ok = (hazards[0].water == expect_water)

	var pass_hazard := hazards.size() >= 1 and water_ok
	var pass_enemies := enemies.size() > 0
	# On a raised walkway the player rests at ~1.6 (island top). The floor would be
	# ~0.6 and a fall-through void would be negative — so a high, stable y proves the
	# spawn-on-platform geometry works. (HP is combat-confounded by the flyers, so
	# it's printed for info only, not asserted.)
	var pass_player := py > 1.2 and py < 3.0
	print("%s hazards=%d water_mode_ok=%s enemies=%d player_y=%.2f hp=%.0f%% -> %s" % [
		tag, hazards.size(), water_ok, enemies.size(), py, hp_ratio * 100.0,
		"OK" if (pass_hazard and pass_enemies and pass_player) else "BAD"])
	lvl.queue_free()
	await _wait(0.3)
	return pass_hazard and pass_enemies and pass_player

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
