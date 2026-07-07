extends Node3D
## Exercises Geofenced Signal Jamming end-to-end: a hive unit's shield eats damage
## while networked, a jam zone strips the shield + disorients it (full damage lands),
## the JamZone Area3D actually detects the enemy inside its boundary, and the
## JammerController plants a beacon+zone when fired. Screenshots the arena.

const HIVE := preload("res://scenes/enemies/hive.tscn")

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and player.get_node_or_null("Damageable"):
		player.get_node("Damageable").invulnerable = true
	# Softlock guard: exit must be navmesh-reachable from spawn.
	var def: Dictionary = LevelDefs.get_def("hivemind")
	var nav := NavigationServer3D.map_get_path(get_world_3d().get_navigation_map(), def["spawn"], def["exit"], true)
	var gap := 999.0
	if nav.size() >= 2:
		gap = Vector2(nav[-1].x - def["exit"].x, nav[-1].z - def["exit"].z).length()
	print("NAV spawn->exit pts=%d gap=%.1f %s" % [nav.size(), gap, "REACHABLE" if gap < 5.0 else "BLOCKED"])

	# Spawn a hive unit we control the fate of.
	var hive := HIVE.instantiate()
	lvl.add_child(hive)
	hive.global_position = Vector3(0, 1.0, -14)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp = hive.get_node("Damageable")
	var full: float = hp.current_health

	# 1) SHIELDED: damage should splash off (near-invuln).
	hp.apply_damage(50.0, null)
	var after_shield: float = hp.current_health
	print("SHIELD: %.0f dmg -> lost %.1f (jammed=%s)" % [50.0, full - after_shield, hive.jammed])

	# 2) JAMMED: link severed, full damage lands + it's disoriented.
	hive.enter_jam()
	await get_tree().physics_frame
	var pre: float = hp.current_health
	hp.apply_damage(50.0, null)
	print("JAMMED: 50 dmg -> lost %.1f (jammed=%s)" % [pre - hp.current_health, hive.jammed])
	hive.exit_jam()
	await get_tree().physics_frame
	print("UN-JAM: jammed=%s (shield back)" % hive.jammed)

	# 3) JamZone Area3D actually geofences the enemy.
	var hive2 := HIVE.instantiate()
	lvl.add_child(hive2)
	hive2.global_position = Vector3(6, 1.0, -14)
	await get_tree().physics_frame
	var zone := JamZone.new()
	zone.radius = 5.0
	zone.lifetime = 4.0
	lvl.add_child(zone)
	zone.global_position = Vector3(6, 1.0, -14)
	for i in 6:
		await get_tree().physics_frame
	print("ZONE geofence: hive inside jammed=%s" % hive2.jammed)

	# 4) JammerController plants a beacon+zone when fired.
	var jc = null
	for n in lvl.find_children("*", "JammerController", true, false):
		jc = n; break
	var before := get_tree().get_nodes_in_group("jam_zone").size()
	if jc and player:
		var cam := player.find_child("Camera3D", true, false) as Camera3D
		cam.global_position = Vector3(0, 3.0, -18)
		cam.look_at(Vector3(0, 0, -14), Vector3.FORWARD)
		jc._cd = 0.0
		jc._fire()
	await get_tree().physics_frame
	var after := get_tree().get_nodes_in_group("jam_zone").size()
	print("JAMMER fire: jam_zones %d -> %d (controller=%s)" % [before, after, jc != null])

	# Screenshot: overhead-ish of the arena with zones + hive.
	var cam2 := player.find_child("Camera3D", true, false) as Camera3D
	for c in get_tree().get_nodes_in_group("level_ceiling"):
		c.visible = false
	# Re-jam hive2 so its shield is visibly collapsed next to a still-shielded one.
	if is_instance_valid(hive2):
		hive2.enter_jam()
	if cam2:
		cam2.global_position = Vector3(-6, 2.6, -20)
		cam2.look_at(Vector3(3, 1.2, -14), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/jamming.png")
	print("JAMMING_PROBE_DONE")
	get_tree().quit()
