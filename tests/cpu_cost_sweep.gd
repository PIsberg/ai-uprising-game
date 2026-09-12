extends Node
## CPU-cost sweep (report-only instrument): for every campaign level, build it,
## wake every enemy onto the player, and sample the main-thread process and
## physics time per frame for a few seconds. Headless has no GPU, so this is the
## pure script + physics cost the level carries in combat - the number that
## decides whether a busy fight stutters on a low-end CPU. Prints one line per
## level (enemies, avg/max process ms, avg/max physics ms) and flags any level
## whose average is more than 2x the campaign median. Findings live in
## docs/PERF_NOTES.md.
##   godot --headless --path . --audio-driver Dummy res://tests/cpu_cost_sweep.tscn

const BUILD_WAIT := 2.4
const SAMPLE_SECONDS := 5.0

func _ready() -> void:
	_run.call_deferred()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().create_timer(0.25).timeout
		t += 0.25

func _sample(seconds: float) -> Dictionary:
	var n := 0
	var p_sum := 0.0
	var p_max := 0.0
	var ph_sum := 0.0
	var ph_max := 0.0
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
		var p := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var ph := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		p_sum += p; ph_sum += ph
		p_max = maxf(p_max, p); ph_max = maxf(ph_max, ph)
		n += 1
	return {"n": n, "p_avg": p_sum / maxf(n, 1), "p_max": p_max, "ph_avg": ph_sum / maxf(n, 1), "ph_max": ph_max}

func _run() -> void:
	var rows: Array = []
	for path in GameState.campaign():
		var id := GameState.level_id_from_path(String(path))
		if not ResourceLoader.exists(path):
			continue
		GameState.current_level_path = String(path)
		GameState.reset_level_stats()
		GameState.set_state(GameState.State.PLAYING)
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		await _wait(BUILD_WAIT)
		var player: Node = lvl.find_child("Player", true, false)
		var hp: Node = player.get_node_or_null("Damageable") if player else null
		if hp:
			hp.invulnerable = true
		# Wake the whole roster so the sample is a full fight, not idle patrols.
		var enemies := get_tree().get_nodes_in_group("enemy")
		for e in enemies:
			if is_instance_valid(e) and player and "target" in e:
				e.set("target", player)
				if e.has_method("set_state"):
					e.call("set_state", 3) # CHASE
		# Three samples: the full fight, the fight with the navigation map switched
		# off (path queries return empty, enemies fall back to straight lines), and
		# every enemy's physics frozen - so a physics-time spike gets attributed.
		var full := await _sample(SAMPLE_SECONDS)
		var map: RID = get_viewport().find_world_3d().navigation_map
		NavigationServer3D.map_set_active(map, false)
		var nonav := await _sample(SAMPLE_SECONDS * 0.6)
		NavigationServer3D.map_set_active(map, true)
		for e in enemies:
			if is_instance_valid(e):
				e.set_physics_process(false)
		var frozen := await _sample(SAMPLE_SECONDS * 0.6)
		var objs := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		rows.append({"id": id, "enemies": enemies.size(), "p_avg": full["p_avg"], "p_max": full["p_max"],
			"ph_avg": full["ph_avg"], "ph_max": full["ph_max"], "nodes": objs, "frames": full["n"],
			"ph_nonav": nonav["ph_avg"], "ph_frozen": frozen["ph_avg"],
			"bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			"pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
			"nav_agents": Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT),
			"nav_polys": Performance.get_monitor(Performance.NAVIGATION_POLYGON_COUNT)})
		lvl.queue_free()
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				e.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	# Median of the combined average cost, for the outlier flag.
	var costs: Array[float] = []
	for r in rows:
		costs.append(float(r["p_avg"]) + float(r["ph_avg"]))
	costs.sort()
	var median: float = costs[costs.size() / 2] if costs.size() > 0 else 0.0
	print("CPU  %-13s enemies  proc avg/max ms   phys avg/max ms  phys:nonav frozen   bodies pairs agents polys  flag" % "level")
	var flagged := 0
	for r in rows:
		var total: float = float(r["p_avg"]) + float(r["ph_avg"])
		var flag := ""
		if median > 0.0 and total > median * 2.0:
			flag = "HOT x%.1f" % (total / median)
			flagged += 1
		print("CPU  %-13s %5d   %6.2f / %6.2f     %6.2f / %6.2f   %6.2f   %6.2f   %5d %5d %5d %5d  %s" % [
			r["id"], r["enemies"], r["p_avg"], r["p_max"], r["ph_avg"], r["ph_max"], r["ph_nonav"], r["ph_frozen"],
			r["bodies"], r["pairs"], r["nav_agents"], r["nav_polys"], flag])
	print("CPU_COST_SWEEP_DONE median=%.2fms flagged=%d" % [median, flagged])
	print("RESULT PASS")
	get_tree().quit()
