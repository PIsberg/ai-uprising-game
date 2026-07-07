extends Node3D
## Exercises the Generative Guardrails objective end-to-end: builds the level,
## confirms the GenerativeZone + task registered, that the AI raises hazard
## pillars, that firing an anchor tag locks a cell into a safe slab, and that
## bridging a path + reaching the override gate COMPLETES the task. Screenshots
## the field. Run windowed.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_guardrails.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var gz = null
	for n in lvl.find_children("*", "GenerativeZone", true, false):
		gz = n; break
	if gz == null:
		print("FAIL: no GenerativeZone"); get_tree().quit(); return
	print("zone found: cols=%d rows=%d" % [gz._cols, gz._rows])
	print("task registered: ", GameState.has_task("guardrails"), " done=", GameState.is_task_done("guardrails"))
	# Softlock guard: the exit must be navmesh-reachable from spawn across the base
	# floor (the hazard field is a gameplay layer, it doesn't carve the navmesh).
	var def: Dictionary = LevelDefs.get_def("guardrails")
	var nav := NavigationServer3D.map_get_path(get_world_3d().get_navigation_map(), def["spawn"], def["exit"], true)
	var gap := 999.0
	if nav.size() >= 2:
		gap = Vector2(nav[-1].x - def["exit"].x, nav[-1].z - def["exit"].z).length()
	print("NAV spawn->exit pts=%d gap=%.1f %s" % [nav.size(), gap, "REACHABLE" if gap < 5.0 else "BLOCKED"])

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var dmg := player.get_node_or_null("Damageable")
	if dmg: dmg.invulnerable = true

	# 1) AI hazard generation.
	for i in 6:
		gz._spawn_hazard()
	print("hazard pillars raised: ", gz._pillar.size())

	# 2) Anchor-tag FIRE path: aim the camera straight down at each forward cell in
	# the player's column and fire, walking the player up the bridge it builds.
	var col: int = gz._cols / 2
	var anchored := 0
	for r in range(gz._rows):
		var target: Vector3 = gz._cell_world(r, col)
		player.global_position = target + Vector3(0, gz.SLAB_H + 0.1, 0)
		var cam := player.find_child("Camera3D", true, false) as Camera3D
		if cam:
			cam.global_position = target + Vector3(0, 3.0, 0)
			cam.look_at(target, Vector3.FORWARD) # straight down
		gz._t_cd = 0.0
		# Fire on the SAME synchronous beat as the aim — the player controller
		# re-drives its camera every physics frame, so an await here would snap the
		# aim back to eye-level before the shot lands.
		gz._fire_anchor()
		if gz._state[r][col] == gz.ANCHORED:
			anchored += 1
		await get_tree().physics_frame
	print("cells anchored by firing: %d / %d" % [anchored, gz._rows])

	# 3) Reach the override gate on the bridged path.
	player.global_position = gz._gate_pos + Vector3(0, gz.SLAB_H + 0.2, 0)
	for i in 20:
		await get_tree().physics_frame
		gz._check_goal()
		if GameState.is_task_done("guardrails"):
			break
	print("REACHED_GATE task_done=", GameState.is_task_done("guardrails"))

	# Screenshot the bridged field at eye level from behind the start pad: the safe
	# blue slab path should read down the middle with red unstable cells + hazard
	# pillars flanking it, and the override gate glowing at the far end.
	player.global_position = gz.field_center + Vector3(0, 1.0, -20)
	var cam2 := player.find_child("Camera3D", true, false) as Camera3D
	if cam2:
		cam2.global_position = gz.field_center + Vector3(0, 2.4, -21)
		cam2.look_at(gz.field_center + Vector3(0, 1.2, 8), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/guardrails.png")
	print("GUARDRAILS_PROBE_DONE")
	get_tree().quit()
