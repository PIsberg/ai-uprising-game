extends Node
## CPU-cost sweep (report-only instrument): for every campaign level, build it,
## wake every enemy onto the player, and sample the main-thread process time per
## frame and physics time per tick for a few seconds (tests/tick_clock.gd).
## Headless has no GPU, so this is the pure script + physics cost the level
## carries in combat - the number that decides whether a busy fight stutters on
## a low-end CPU. Prints one line per level (enemies, median/p90 process ms,
## median/p90/max physics ms) and flags any level whose typical cost is more
## than 2x the campaign median. Until 2026-10-08 it read
## Performance.TIME_PROCESS/TIME_PHYSICS_PROCESS, which hold the worst tick of
## the last second, and so reported spikes as the typical cost (#89).
## Findings live in docs/PERF_NOTES.md.
##   godot --headless --path . --audio-driver Dummy res://tests/cpu_cost_sweep.tscn

const BUILD_WAIT := 2.4
const SAMPLE_SECONDS := 5.0
const TickClock := preload("res://tests/tick_clock.gd")

var _clock

func _ready() -> void:
	_run.call_deferred()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().create_timer(0.25).timeout
		t += 0.25

func _sample(seconds: float) -> Dictionary:
	_clock.reset()
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()
	return {"n": _clock.count(), "p_med": _clock.process_percentile(0.5), "p_p90": _clock.process_percentile(0.9),
		"ph_med": _clock.percentile(0.5), "ph_p90": _clock.percentile(0.9), "ph_max": _clock.percentile(1.0)}

func _run() -> void:
	_clock = TickClock.attach(self)
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
		rows.append({"id": id, "enemies": enemies.size(), "p_med": full["p_med"], "p_p90": full["p_p90"],
			"ph_med": full["ph_med"], "ph_p90": full["ph_p90"], "ph_max": full["ph_max"], "nodes": objs, "ticks": full["n"],
			"ph_nonav": nonav["ph_med"], "ph_frozen": frozen["ph_med"],
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
	# Median of the combined typical cost, for the outlier flag.
	var costs: Array[float] = []
	for r in rows:
		costs.append(float(r["p_med"]) + float(r["ph_med"]))
	costs.sort()
	var median: float = costs[costs.size() / 2] if costs.size() > 0 else 0.0
	print("CPU  %-13s enemies  proc p50/p90 ms   phys p50/p90/max ms     phys p50:nonav frozen   bodies pairs agents polys  flag" % "level")
	var flagged := 0
	for r in rows:
		var total: float = float(r["p_med"]) + float(r["ph_med"])
		var flag := ""
		if median > 0.0 and total > median * 2.0:
			flag = "HOT x%.1f" % (total / median)
			flagged += 1
		print("CPU  %-13s %5d   %6.2f / %6.2f     %6.2f / %6.2f / %7.2f   %6.2f   %6.2f   %5d %5d %5d %5d  %s" % [
			r["id"], r["enemies"], r["p_med"], r["p_p90"], r["ph_med"], r["ph_p90"], r["ph_max"], r["ph_nonav"], r["ph_frozen"],
			r["bodies"], r["pairs"], r["nav_agents"], r["nav_polys"], flag])
	print("CPU_COST_SWEEP_DONE median=%.2fms flagged=%d" % [median, flagged])
	print("RESULT PASS")
	get_tree().quit()
