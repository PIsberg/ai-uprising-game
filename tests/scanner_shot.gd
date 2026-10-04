extends Node3D
## Windowed visual check for vision scanners: for every campaign level that
## authors "scanners", frames each head from the floor in front of it (idle,
## then mid-alarm with the beam red). Headless gives black frames.
##   godot --path . res://tests/scanner_shot.tscn -- --out=<abs dir> [--levels=overseer]

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://scanner_shots")
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--levels="):
			only = Array(a.substr(9).split(",", false))
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
	for id in LevelDefs._defs().keys():
		if not only.is_empty() and not only.has(id):
			continue
		var def: Dictionary = LevelDefs.get_def(id)
		if def.get("scanners", []).is_empty():
			continue
		var lvl := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(lvl)
		# Park the player far overhead and out of every cone, so no alarm fires.
		var player := lvl.find_child("Player", false, false) as Node3D
		if player:
			player.process_mode = Node.PROCESS_MODE_DISABLED
			player.global_position += Vector3(0, 300, 0)
			player.visible = false
		for i in 8:
			await get_tree().create_timer(0.3).timeout
		for en in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(en):
				(en as Node3D).global_position += Vector3(0, -200, 0)
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam:
			pcam.current = false
		cam.current = true
		var n := 0
		for node in get_tree().get_nodes_in_group("scanner"):
			var sc := node as VisionScanner
			var fwd := sc.look_dir()
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
			var head := sc.eye_pos()
			var foot := Vector3(head.x, 0.0, head.z)
			# Side-on, so the cone reads in profile instead of from inside it. Take
			# whichever side has a clear sightline to the head (a tower or wall
			# beside the mast otherwise swallows the camera).
			var side := fwd.cross(Vector3.UP).normalized()
			var space := get_world_3d().direct_space_state
			var pick := foot + side * 11.0 + fwd * 5.0 + Vector3(0, 1.7, 0)
			for sgn in [1.0, -1.0, 0.6, -0.6]:
				var p: Vector3 = foot + side * 11.0 * sgn + fwd * 5.0 + Vector3(0, 1.7, 0)
				var q := PhysicsRayQueryParameters3D.create(p, head, 1)
				var hit := space.intersect_ray(q)
				if hit.is_empty() or (hit["position"] as Vector3).distance_to(head) < 0.8:
					pick = p
					break
			if sc.sweep_deg >= 359.0 or not sc.mast:
				# A full-turn head usually crowns a tower or centrepiece, among
				# towers whose visual-only lattice skins swallow a ground camera
				# (no collision, so the ray test cannot see them). Frame it from
				# above tower height instead: first of 8 directions with a clear ray.
				for k in 8:
					var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0)
					var p2: Vector3 = Vector3(head.x, head.y + 2.0, head.z) + dir * 16.0
					var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(p2, head, 1))
					if hit2.is_empty() or (hit2["position"] as Vector3).distance_to(head) < 0.8:
						pick = p2
						break
			cam.global_position = pick
			cam.look_at(head + Vector3(0, -2.5, 0) if (sc.sweep_deg >= 359.0 or not sc.mast) else foot + fwd * 5.0 + Vector3(0, 2.2, 0), Vector3.UP)
			await _save(out_dir, "%s_scan%d" % [id, n])
			sc._set_mode(VisionScanner.Mode.TRACK)
			for i in 3:
				await get_tree().create_timer(0.1).timeout
			await _save(out_dir, "%s_scan%d_alarm" % [id, n])
			sc._set_mode(VisionScanner.Mode.SWEEP)
			n += 1
		lvl.queue_free()
		await get_tree().process_frame
	print("SCANNER_SHOT_DONE")
	get_tree().quit()

func _save(out_dir: String, name: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 1280:
		img.resize(1280, int(round(float(img.get_height()) * 1280.0 / img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/%s.png" % [out_dir, name])
