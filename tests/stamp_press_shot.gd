extends Node3D
## Windowed visual check for The Assembly's stamping presses: the press in the
## east bulkhead gap and the three-press line across the dock lane, from the
## yard side, at three moments of the wave; then one press close up as it
## cocks and at the bottom of its slam. Headless gives black frames.
##   godot --path . res://tests/stamp_press_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://stamp_press_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/press_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_assembly.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var presses: Array = []
	for n in lvl.find_children("*", "StampPress", true, false):
		presses.append(n)
	print("presses: ", presses.size())
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	cam.current = true
	# From the dock side of the lane, looking back north at the line.
	cam.global_position = Vector3(58.0, 4.5, 58.0)
	cam.look_at(Vector3(58.0, 1.8, 44.0))
	for k in 3:
		await _shot("line_%d" % k)
		var t := 0.0
		while t < 1.2:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
	var p: StampPress = presses[0]
	cam.global_position = p.global_position + Vector3(-9.0, 3.2, -6.0)
	cam.look_at(p.global_position + Vector3(0, 2.0, 0))
	var seen_tele := false
	var guard := 0.0
	while guard < 8.0:
		await get_tree().physics_frame
		guard += get_physics_process_delta_time()
		if p.telegraphing and not seen_tele:
			seen_tele = true
			var w := 0.0
			while w < 0.4:
				await get_tree().physics_frame
				w += get_physics_process_delta_time()
			await _shot("gap_cocked")
		if seen_tele and p.head_bottom() < 0.2:
			await _shot("gap_slam")
			break
	print("RESULT PASS")
	get_tree().quit()
