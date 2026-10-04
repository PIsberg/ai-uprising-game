extends Node3D
## Windowed visual check for firewalls: for every campaign level that authors
## "firewalls", frames each barrier from the spawn side at eye height, then each
## relay node, then the first barrier mid-collapse. Headless gives black frames.
##   godot --path . res://tests/firewall_shot.tscn -- --out=<abs dir> [--levels=claude,gemini]

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://firewall_shots")
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
		if def.get("firewalls", []).is_empty():
			continue
		var lvl := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
		add_child(lvl)
		var player := lvl.find_child("Player", false, false) as Node3D
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
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
		var fws := get_tree().get_nodes_in_group("firewall")
		var n := 0
		for fw in fws:
			var f := fw as FirewallBarrier
			var normal := f.global_transform.basis.z.normalized()
			if (spawn - f.global_position).dot(normal) < 0.0:
				normal = -normal
			var eye := f.global_position + normal * 6.5 + Vector3(0, 1.7, 0) + f.global_transform.basis.x * 1.5
			cam.global_position = eye
			cam.look_at(f.global_position + Vector3(0, 1.8, 0), Vector3.UP)
			await _save(out_dir, "%s_fw%d" % [id, n])
			if is_instance_valid(f.relay):
				var r := f.relay.global_position
				cam.global_position = r + Vector3(4.0, 2.2, 4.0)
				cam.look_at(r + Vector3(0, 1.4, 0), Vector3.UP)
				await _save(out_dir, "%s_fw%d_relay" % [id, n])
			n += 1
		if not fws.is_empty():
			var f0 := fws[0] as FirewallBarrier
			var normal0 := f0.global_transform.basis.z.normalized()
			if (spawn - f0.global_position).dot(normal0) < 0.0:
				normal0 = -normal0
			cam.global_position = f0.global_position + normal0 * 6.5 + Vector3(0, 1.7, 0)
			cam.look_at(f0.global_position + Vector3(0, 1.8, 0), Vector3.UP)
			f0.open()
			for i in 2:
				await get_tree().create_timer(0.25).timeout
			await _save(out_dir, "%s_fw0_collapse" % id)
		lvl.queue_free()
		await get_tree().process_frame
	print("FIREWALL_SHOT_DONE")
	get_tree().quit()

func _save(out_dir: String, name: String) -> void:
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 1280:
		img.resize(1280, int(round(float(img.get_height()) * 1280.0 / img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/%s.png" % [out_dir, name])
	print("SAVED ", name)