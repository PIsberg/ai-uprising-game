extends Node3D
## Windowed visual check for hero landmarks: for every open-sky level, stands at
## the spawn at eye height facing the landmark (pitched up a little) and saves
## one frame. Headless gives black frames.
##   godot --path . res://tests/landmark_shot.tscn -- --out=<abs dir> [--levels=gemini,grok] [--cam_y=40]
## --cam_y lifts the camera off eye level (default 1.7 m), to see what a
## perimeter wall hides.

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://landmark_shots")
	var only: Array = []
	var cam_y := 1.7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam_y="):
			cam_y = float(a.substr(8))
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
		if not def.get("open_sky", false):
			continue
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		var lvl := (load(path) as PackedScene).instantiate() as Node3D
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
		var lm := lvl.get_node_or_null("Landmark") as Node3D
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		cam.global_position = sp + Vector3(0, cam_y, 0)
		if lm:
			var look := lm.global_position + Vector3(0, 70.0, 0)
			var flat := Vector3(look.x, cam.global_position.y, look.z)
			cam.look_at(flat.lerp(look, 0.35), Vector3.UP)
		GameState.current_state = GameState.State.PLAYING
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("landmark_%s.png" % id))
		print("saved ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit()
