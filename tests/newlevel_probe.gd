extends Node3D
## Builds the redesigned levels, confirms the exit is navmesh-reachable from the
## spawn (softlock guard), and captures an eye-level shot of each.
## Run windowed: godot --path . --quit-after 2000 res://tests/newlevel_probe.tscn

const IDS := ["frostbreak", "mistral", "alien", "neon", "grok"]

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 75.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.4
	cam.attributes = ca
	add_child(cam)
	for id in IDS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg:
			pdmg.invulnerable = true
		await get_tree().create_timer(2.5).timeout  # build geometry + bake navmesh
		# Nav reachability: spawn -> exit must return a path that lands near the exit.
		var def: Dictionary = LevelDefs.get_def(id)
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		var exit: Vector3 = def.get("exit", Vector3.ZERO)
		var map := get_world_3d().get_navigation_map()
		var verdict := "?"
		var p := NavigationServer3D.map_get_path(map, spawn, exit, true)
		if p.size() >= 2:
			var endp := p[p.size() - 1]
			var gap := Vector2(endp.x - exit.x, endp.z - exit.z).length()
			verdict = "REACHABLE gap=%.1f pts=%d" % [gap, p.size()] if gap < 5.0 else "BLOCKED gap=%.1f" % gap
		else:
			verdict = "NO-PATH"
		print("NAV %s: %s  (spawn=%s exit=%s)" % [id, verdict, spawn, exit])
		# Eye-level shot from near the spawn toward arena centre.
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam:
			pcam.current = false
		cam.current = true
		cam.global_position = Vector3(spawn.x * 0.55, 2.4, spawn.z * 0.55)
		cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/new_%s.png" % id)
		print("SHOT ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("NEWLEVEL_DONE")
	get_tree().quit()
