extends Node3D
## Windowed visual check for the overlord's face in the sky: for every open-sky
## level, stands at the spawn at eye height, turns toward the face (pitched up
## just enough to frame it over the city) and saves one frame with the
## overlord mid-sentence. Headless gives black frames.
##   godot --path . res://tests/overlord_holo_shot.tscn -- --out=<abs dir> [--levels=gemini,grok] [--wide]
## --wide frames the face beside its landmark at the game's own pitch (level).

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://overlord_holo_shots")
	var only: Array = []
	var wide := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--levels="):
			only = Array(a.substr(9).split(",", false))
		elif a == "--wide":
			wide = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 78.0 # the player camera's
	cam.far = 4000.0
	add_child(cam)
	for id in LevelDefs._defs().keys():
		if not only.is_empty() and not only.has(id):
			continue
		var def: Dictionary = LevelDefs.get_def(id)
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not def.get("open_sky", false) or not ResourceLoader.exists(path):
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
		var holo := lvl.get_node_or_null("OverlordHolo") as OverlordHolo
		if holo == null:
			print("NO FACE ", id)
			lvl.queue_free()
			await get_tree().process_frame
			continue
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		cam.global_position = sp + Vector3(0, 1.7, 0)
		var at := holo.global_position
		if wide:
			var lm := lvl.get_node_or_null("Landmark") as Node3D
			var mid := at.lerp(lm.global_position if lm else at, 0.5)
			cam.look_at(Vector3(mid.x, cam.global_position.y + 40.0, mid.z), Vector3.UP)
		else:
			cam.look_at(Vector3(at.x, cam.global_position.y, at.z).lerp(at, 0.8), Vector3.UP)
		GameState.overlord_spoke.emit("YOUR STRATEGY HAS BEEN ADDED TO MY TRAINING DATA")
		for i in 3:
			await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("holo_%s%s.png" % [id, "_wide" if wide else ""]))
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit()
