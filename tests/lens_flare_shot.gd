extends Node3D
## Windowed visual check for the lens flare: loads each level, parks the
## player, and looks at the level's sun (or moon) from above the spawn, the
## light up and left of centre so the ghosts and streak cross the frame. Uses
## the player's own LensFlare (re-pointed at this camera), so the post grade,
## grain and vignette apply as in play. Headless gives black frames.
##   godot --path . res://tests/lens_flare_shot.tscn -- --out=<abs dir> --levels=desert,suburb

const OUT_WIDTH := 1920

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://lens_flare_shots")
	var levels: Array = ["desert", "suburb", "gemini", "frostbreak"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--levels="):
			levels = Array(a.substr(9).split(",", false))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 72.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	for id in levels:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("skip ", id)
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var player := lvl.find_child("Player", false, false) as Node3D
		var spawn: Vector3 = player.global_position if player else Vector3(16, 2, 16)
		var flare: LensFlare = null
		if player:
			var pd := player.find_child("Damageable", true, false)
			if pd:
				pd.invulnerable = true
			player.process_mode = Node.PROCESS_MODE_DISABLED
			player.global_position = spawn + Vector3(0, 300, 0)
			player.visible = false
			flare = player.find_child("LensFlare", true, false) as LensFlare
		for i in 8:
			await get_tree().create_timer(0.3).timeout
		var src := LensFlare.source_for(lvl)
		if src.is_empty() or flare == null:
			print("NO_SOURCE ", id)
			lvl.queue_free()
			await get_tree().process_frame
			continue
		flare.camera = cam
		flare.source_root = lvl
		flare._src_checked = false
		flare.process_mode = Node.PROCESS_MODE_ALWAYS
		cam.current = true
		var dir: Vector3 = src["dir"]
		# Stand above the spawn until the sun clears the walls (eye, then up).
		var eye := Vector3(spawn.x, maxf(spawn.y, 0.0) + 1.6, spawn.z)
		for h in [0.0, 6.0, 14.0, 26.0]:
			var q := PhysicsRayQueryParameters3D.create(eye + Vector3.UP * h, eye + Vector3.UP * h + dir * 600.0, 1)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				eye += Vector3.UP * h
				break
		cam.global_position = eye
		# Aim a little right of and below the light: it sits up-left in frame.
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var right := flat.cross(Vector3.UP).normalized()
		cam.look_at(eye + dir + right * 0.32 - Vector3.UP * 0.16, Vector3.UP)
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img.get_width() > OUT_WIDTH:
			img.resize(OUT_WIDTH, int(round(float(img.get_height()) * OUT_WIDTH / img.get_width())), Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/flare_%s.png" % [out_dir, id])
		print("SAVED ", id, " strength=", snappedf(flare.strength, 0.01), " h=", snappedf(eye.y, 0.1))
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit()
