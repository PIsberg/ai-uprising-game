extends Node3D
## Windowed visual check for hazard surges (flood_surge.gd): for every campaign
## level whose survive hold authors a "flood", frames the arena from 14 m over
## the exit side looking at the centre and saves three frames: before,
## mid-warning, and after the beds have risen. Headless gives black frames.
##   godot --path . res://tests/flood_shot.tscn -- --out=<abs dir> [--levels=lava_world]

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://flood_shots")
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--levels="):
			only = Array(a.substr(9).split(",", false))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	for id in LevelDefs._defs().keys():
		if not only.is_empty() and not only.has(id):
			continue
		var def: Dictionary = LevelDefs.get_def(id)
		var flood: Dictionary = {}
		for t in def.get("tasks", []):
			for w in t.get("waves", []):
				if w.has("flood"):
					flood = (w["flood"] as Dictionary).duplicate(true)
		if flood.is_empty():
			continue
		var lvl := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as LevelBuilder
		add_child(lvl)
		var player := lvl.find_child("Player", false, false) as Node3D
		if player:
			player.process_mode = Node.PROCESS_MODE_DISABLED
			player.global_position += Vector3(0, 300, 0)
			player.visible = false
		# Short waits: one long SceneTreeTimer stalls autoload ticking.
		for i in 8:
			await get_tree().create_timer(0.3).timeout
		for en in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(en):
				(en as Node3D).global_position += Vector3(0, -200, 0)
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam:
			pcam.current = false
		cam.current = true
		var ex: Vector3 = def.get("exit", Vector3.ZERO)
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		cam.global_position = Vector3(ex.x * 0.8 - sp.x * 0.3, 14.0, ex.z * 0.8 - sp.z * 0.3)
		cam.look_at(Vector3(sp.x * 0.25, 0.0, sp.z * 0.25), Vector3.UP)
		GameState.current_state = GameState.State.PLAYING
		await _snap(out_dir, "%s_0_before" % id)
		flood["warn"] = 2.0
		lvl._start_flood(flood, "flood_shot_never_done")
		await get_tree().create_timer(1.2).timeout
		await _snap(out_dir, "%s_1_warning" % id)
		for i in 12:
			await get_tree().create_timer(0.3).timeout
		await _snap(out_dir, "%s_2_flooded" % id)
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(stem + ".png")
	img.save_png(path)
	print("saved ", path)
