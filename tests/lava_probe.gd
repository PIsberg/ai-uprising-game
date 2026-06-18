extends Node3D
## Dev probe: load a real level with lava, wait for the navmesh bake, then prove
## the lava both carved the navmesh AND left a connected (longer) path from spawn
## to exit. Also renders a top-down shot so the beds can be eyeballed. Pass the
## level scene after `--`:
##   godot --path . res://tests/lava_probe.tscn -- res://scenes/levels/level_titan.tscn

func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var scene_path := "res://scenes/levels/level_titan.tscn"
	if argv.size() >= 1:
		scene_path = argv[0]
	var level: Node3D = (load(scene_path) as PackedScene).instantiate()
	add_child(level)
	# Let the build + deferred navmesh bake finish.
	await get_tree().create_timer(1.5).timeout

	var def: Dictionary = LevelDefs.get_def(level.level_id)
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var exit: Vector3 = def.get("exit", Vector3.ZERO)
	var hazards := get_tree().get_nodes_in_group("hazard")
	print("LAVA beds=", hazards.size())

	# Path query on the level's navigation map.
	var map := level.get_world_3d().navigation_map
	var from := NavigationServer3D.map_get_closest_point(map, spawn)
	var to := NavigationServer3D.map_get_closest_point(map, exit)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var plen := 0.0
	for i in range(1, path.size()):
		plen += path[i].distance_to(path[i - 1])
	var straight := from.distance_to(to)
	print("PATH points=", path.size(), " length=%.1f straight=%.1f ratio=%.2f reachable=%s" % [plen, straight, (plen / maxf(straight, 0.01)), str(path.size() > 1 and path[path.size() - 1].distance_to(to) < 3.0)])

	# Check the path actually skirts the lava (no waypoint sits inside a bed).
	var inside := 0
	for p in path:
		for h in hazards:
			var lh := h as LavaHazard
			var local: Vector3 = lh.to_local(p)
			if absf(local.x) < lh.size.x * 0.5 and absf(local.z) < lh.size.y * 0.5:
				inside += 1
	print("PATH waypoints_inside_lava=", inside)

	# Damage check: drop the player into the first bed and confirm HP falls.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player and not hazards.is_empty():
		var pdmg := player.get_node_or_null("Damageable") as Damageable
		var lh := hazards[0] as Node3D
		player.global_position = lh.global_position + Vector3(0, 1.0, 0)
		var hp0: float = pdmg.current_health if pdmg else -1.0
		await get_tree().create_timer(0.9).timeout
		var hp1: float = pdmg.current_health if pdmg else -1.0
		print("LAVA_DMG hp_before=%.0f hp_after=%.0f burned=%s" % [hp0, hp1, str(hp1 < hp0)])

	# Top-down render.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var fs: Vector2 = def.get("floor_size", Vector2(60, 60))
	cam.size = maxf(fs.x, fs.y) * 1.05
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 80, 0.01), Vector3.ZERO, Vector3.FORWARD)
	cam.current = true
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/lava_top.png")
	print("SAVED lava_top.png")
	# Ground-level look at the first lava bed to judge the shader.
	if not hazards.is_empty():
		var lh := hazards[0] as Node3D
		var p: Vector3 = lh.global_position
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.look_at_from_position(p + Vector3(0, 5, 14), p + Vector3(0, 0.2, 0), Vector3.UP)
		await get_tree().create_timer(0.4).timeout
		img = get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/lava_close.png")
		print("SAVED lava_close.png")
	get_tree().quit()
