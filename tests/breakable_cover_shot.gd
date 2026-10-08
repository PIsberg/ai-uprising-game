extends Node3D
## Windowed visual check for breakable cover: frames one block of a level at eye
## height and saves it intact, cracked (stage 1), failing (stage 2), mid-shatter
## and as rubble. Headless gives black frames.
##   godot --path . res://tests/breakable_cover_shot.tscn -- --out=<abs dir> [--level=neon]

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://breakable_cover_shots")
	var id := "neon"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--level="):
			id = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 72.0
	add_child(cam)
	var lvl := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
	add_child(lvl)
	var player := lvl.find_child("Player", false, false) as Node3D
	for i in 8:
		await get_tree().create_timer(0.3).timeout
	for en in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(en):
			en.process_mode = Node.PROCESS_MODE_DISABLED
			(en as Node3D).global_position += Vector3(0, -200, 0)
	var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	cam.current = true
	var covers := get_tree().get_nodes_in_group("breakable_cover")
	if covers.is_empty():
		print("RESULT FAIL no breakable cover in ", id)
		get_tree().quit(1)
		return
	var bc: BreakableCover = covers[0]
	var at := bc.global_position
	# Look at the block from the arena side, 5 m out, at eye height.
	var to_mid := Vector3(-at.x, 0, -at.z).normalized()
	if to_mid.length() < 0.5:
		to_mid = Vector3.BACK
	cam.global_position = at + to_mid * (maxf(bc.size.x, bc.size.z) * 0.5 + 4.5) + Vector3(0, 1.7 - (at.y - bc.size.y * 0.5) * 0.0, 0)
	cam.global_position.y = at.y - bc.size.y * 0.5 + 1.7
	cam.look_at(at, Vector3.UP)
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
		player.global_position = cam.global_position + Vector3(0, 300, 0)
		player.visible = false
	var hpmax: float = bc.hp.max_health
	await _save(out_dir, "%s_0_intact" % id)
	# Same block from a raised three-quarter view, then a solid DefWall for comparison.
	var front := cam.global_transform
	cam.global_position = at + Vector3(4.5, 3.5, 4.5)
	cam.look_at(at, Vector3.UP)
	await _save(out_dir, "%s_0b_intact_diag" % id)
	for dw in lvl.find_children("DefWall*", "StaticBody3D", true, false):
		var dp := (dw as Node3D).global_position
		cam.global_position = dp + Vector3(5.0, 1.0, 5.0)
		cam.look_at(dp, Vector3.UP)
		await _save(out_dir, "%s_0c_solid_wall" % id)
		break
	cam.global_transform = front
	bc.hp.apply_damage(bc.hp.current_health - hpmax * 0.6, player)
	await _save(out_dir, "%s_1_cracked" % id)
	bc.hp.apply_damage(bc.hp.current_health - hpmax * 0.3, player)
	await _save(out_dir, "%s_2_failing" % id)
	bc.hp.apply_damage(99999.0, player)
	await _save(out_dir, "%s_3_shatter" % id, 4)
	for i in 6:
		await get_tree().create_timer(0.4).timeout
	await _save(out_dir, "%s_4_rubble" % id)
	print("RESULT PASS")
	get_tree().quit()

func _save(out_dir: String, name: String, frames: int = 12) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.get_width() > 1280:
		img.resize(1280, int(round(float(img.get_height()) * 1280.0 / img.get_width())), Image.INTERPOLATE_LANCZOS)
	img.save_png("%s/%s.png" % [out_dir, name])
	print("SAVED ", name)
