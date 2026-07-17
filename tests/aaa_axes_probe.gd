# @lat: [[testing#Verification Philosophy]]
extends Node3D

## Verifies batch 3 (five-axis AAA gaps) on a real level (gpt = lava + grunts):
##  1. reinforcement warp-in: telegraph pillar first, robot lands after
##  2. lava beds grow heat-haze curtains (screen-space refraction quads)
##  3. par time exists per level and fast clears earn a speed bonus
##  4. wounded grunts roll a cover-seek fallback on the evade channel
##  5. close kills splatter the lens overlay

func _ready() -> void:
	# Heat haze is quality-gated (LOW sheds it, like the other screen-space
	# effects) and this machine's persisted profile is LOW — force the tier UP
	# before the level builds. Direct var write: the setter would persist it.
	GraphicsSettings.quality = GraphicsSettings.Quality.HIGH
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D

	# 2) Heat haze: any hazard bed should carry quads with the haze shader.
	var haze := 0
	print("diag: hazards=%d quality=%d" % [
		get_tree().get_nodes_in_group("hazard").size(), int(GraphicsSettings.quality)])
	for hz in get_tree().get_nodes_in_group("hazard"):
		for c in (hz as Node).get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh:
				var m = ((c as MeshInstance3D).mesh as QuadMesh).material
				if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
						and String((m as ShaderMaterial).shader.resource_path).contains("heat_haze"):
					haze += 1
	print("heat_haze_quads=%d" % haze)

	# 1) Warp-in telegraph: spawner announces, then lands the robot.
	var live := get_tree().get_nodes_in_group("enemy")
	var donor: Node3D = null
	for e in live:
		if e is EnemyBase:
			donor = e
			break
	if donor == null:
		print("warp_in: SKIP (no donor enemy)")
	else:
		var sp := EnemySpawner.new()
		sp.spawn_on_ready = false
		sp.enemy_scene = load(donor.scene_file_path)
		add_child(sp)
		sp.global_position = donor.global_position + Vector3(2, 0.2, 0)
		var n0 := get_tree().get_nodes_in_group("enemy").size()
		sp._spawn()
		await get_tree().create_timer(0.15).timeout
		var pillar := false
		for c in get_tree().current_scene.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh \
					and is_equal_approx(((c as MeshInstance3D).mesh as CylinderMesh).top_radius, 0.45):
				pillar = true
		var n_mid := get_tree().get_nodes_in_group("enemy").size()
		await get_tree().create_timer(0.8).timeout
		var n_after := get_tree().get_nodes_in_group("enemy").size()
		print("warp_in: pillar=%s held=%s landed=%s" % [pillar, n_mid == n0, n_after == n0 + 1])

	# 3) Par time + speed bonus in the grade.
	var par: float = GameState.level_par_time("gpt")
	GameState.current_level_path = "res://scenes/levels/level_gpt.tscn"
	GameState.level_start_ms = Time.get_ticks_msec() - 30000 # a 30 s blitz clear
	GameState.stat_shots = 10
	GameState.stat_hits = 8
	var g: Dictionary = GameState.grade_level()
	var st: Dictionary = g["stats"]
	print("par_time: par=%.0fs stat_par=%.0f speed_bonus=%.1f" % [
		par, float(st.get("par", 0.0)), float(st.get("speed_bonus", 0.0))])

	# 4) Cover-seek: a wounded grounded grunt rolls a fallback (45% per roll —
	# reset the latch and reroll until it takes, bounded).
	var grunt: EnemyBase = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and not ("hover_height" in e) and (e as EnemyBase).hp != null \
				and (e as EnemyBase).hp.max_health < 500.0:
			grunt = e
			break
	if grunt == null:
		print("cover_seek: SKIP (no grounded grunt)")
	else:
		grunt.hp.current_health = grunt.hp.max_health * 0.2
		var took := false
		for _i in 40:
			grunt._cover_seek_done = false
			grunt._consider_cover_seek(5.0, player)
			if grunt._evade_t >= 1.5:
				took = true
				break
		print("cover_seek: evade_engaged=%s evade_t=%.2f" % [took, grunt._evade_t])

	# 5) Kill splatter overlay reacts to a point-blank kill report.
	var spl := get_tree().root.find_children("*", "KillSplatter", true, false)
	if spl.is_empty():
		print("splatter: MISSING")
	else:
		var k: Control = spl[0]
		GameState.report_player_hit(50.0, player.global_position + Vector3(1, 1, 0), true, false)
		await get_tree().process_frame
		print("splatter: blobs=%d" % (k._blobs as Array).size())

	print("AAA_AXES_PROBE_DONE")
	get_tree().quit()
