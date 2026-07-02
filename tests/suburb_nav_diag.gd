extends Node3D
## Scratch diagnostic: which leg of the suburb canal crossing fails?
## Chain: spawn -> west bridgehead -> deck centre -> east bridgehead -> exit,
## plus the tower (high road) route. Raw def coords x WORLD_SCALE 1.4.
## Run: godot --headless --path . --quit-after 2500 res://tests/suburb_nav_diag.tscn

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_suburb.tscn") as PackedScene).instantiate()
	add_child(lvl)
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.invulnerable = true
	await get_tree().create_timer(2.5).timeout
	var S := 1.4
	var pts := [
		["spawn", Vector3(-26 * S, 0.6, -26 * S)],
		["west bridgehead", Vector3(-10 * S, 0.3, 8 * S)],
		["deck centre", Vector3(0, 1.9, 8 * S)],
		["east bridgehead", Vector3(10 * S, 0.3, 8 * S)],
		["exit", Vector3(26 * S, 1.5, 26 * S)],
		["west tower top", Vector3(-17 * S, 9.2, 0)],
		["east tower top", Vector3(13 * S, 7.2, 0)],
	]
	for i in range(pts.size() - 1):
		_q(pts[i], pts[i + 1])
	_q(pts[0], pts[4]) # full route
	var map := get_world_3d().get_navigation_map()
	for p in pts:
		var c := NavigationServer3D.map_get_closest_point(map, p[1])
		print("closest navmesh to %-16s %s -> %s (d=%.2f)" % [p[0], p[1], c, (p[1] as Vector3).distance_to(c)])
	# Visual: frame the canal + bridge crossing from above the west bank.
	var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(-20, 10, 24)
	cam.look_at(Vector3(2, 1.5, 8), Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/suburb_canal.png")
	print("SAVED suburb_canal.png")
	print("SUBURB_NAV_DIAG_DONE")
	get_tree().quit()

func _q(a: Array, b: Array) -> void:
	var map := get_world_3d().get_navigation_map()
	var p := NavigationServer3D.map_get_path(map, a[1], b[1], true)
	if p.size() >= 2:
		var gap := Vector2(p[p.size() - 1].x - (b[1] as Vector3).x, p[p.size() - 1].z - (b[1] as Vector3).z).length()
		print("%-16s -> %-16s pts=%2d gap=%.1f %s" % [a[0], b[0], p.size(), gap, "OK" if gap < 3.0 else "BLOCKED"])
	else:
		print("%-16s -> %-16s NO-PATH" % [a[0], b[0]])
