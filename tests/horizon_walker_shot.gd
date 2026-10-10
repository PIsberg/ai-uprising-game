extends Node3D
## Windowed visual check for the horizon walker: for every open-sky level,
## stands at the spawn at eye height, turns toward the walker and saves one
## frame. Headless gives black frames.
##   godot --path . res://tests/horizon_walker_shot.tscn -- --out=<abs dir> [--levels=gemini,grok] [--wide]
## --wide keeps the camera level (the game's own pitch) instead of framing it;
## --close frames it from 300 m in front of it, level with its head.

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://horizon_walker_shots")
	var only: Array = []
	var wide := false
	var close := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--levels="):
			only = Array(a.substr(9).split(",", false))
		elif a == "--wide":
			wide = true
		elif a == "--close":
			close = true
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
		var holo := lvl.get_node_or_null("HorizonWalker") as Node3D
		if holo == null:
			print("NO FACE ", id)
			lvl.queue_free()
			await get_tree().process_frame
			continue
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		cam.global_position = sp + Vector3(0, 1.7, 0)
		var at := holo.global_position + Vector3.UP * 120.0
		if close:
			var face := lvl.get_node_or_null("OverlordHolo") as Node3D
			if face:
				face.hide() # its eyes would sit right behind the walker's
			var fwd := holo.global_transform.basis.z.normalized() * (-1.0 if OS.get_cmdline_user_args().has("--back") else 1.0)
			cam.global_position = holo.global_position + fwd * 300.0 + Vector3.UP * 140.0
			cam.look_at(holo.global_position + Vector3.UP * 110.0, Vector3.UP)
		elif wide:
			cam.look_at(Vector3(at.x, cam.global_position.y, at.z), Vector3.UP)
		else:
			cam.look_at(at, Vector3.UP)
		for i in 3:
			await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_dir.path_join("walker_%s%s.png" % [id, "_close" if close else ("_wide" if wide else "")]))
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit()
