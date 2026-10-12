extends Node3D
## Windowed visual check for LAVA WORLD's cargo lift: the shaft on the NE
## island with the car down, the car at the ladle gantry, and the view over the
## forge from the gantry. Headless gives black frames.
##   godot --path . res://tests/cargo_lift_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://cargo_lift_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/lift_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_lava_world.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var lifts := lvl.find_children("*", "CargoLift", true, false)
	print("lifts: ", lifts.size())
	var lift := lifts[0] as CargoLift
	var at := lift.global_position
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 65.0
	cam.global_position = at + Vector3(9.0, 3.5, 9.0)
	cam.look_at(at + Vector3(-3.0, 3.5, 0))
	await _shot("down")
	lift.set("_goal", float(lift.get("_rise")))
	var t := 0.0
	while t < 5.0 and not lift.at_top():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _shot("up")
	cam.global_position = Vector3(at.x - 4.0, lift.top + 1.7, at.z)
	cam.look_at(Vector3(-6.0, 1.5, 6.0))
	await _shot("view")
	print("RESULT PASS")
	get_tree().quit()
