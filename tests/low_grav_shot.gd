extends Node3D
## Windowed visual check for a level's low-gravity field (the Hollow's by
## default): the violet column at the foot of the deck it reaches, from eye
## height 10 m off. Headless gives black frames.
##   godot --path . res://tests/low_grav_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "alien"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://low_grav_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var f := lvl.find_children("*", "LowGravField", true, false)[0] as LowGravField
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(0, 40, -200)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = f.global_position + Vector3(7.0, 1.7, -7.0)
	cam.look_at(f.global_position + Vector3(0, 2.0, 1.0))
	for i in 60:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/low_grav_%s_column.png" % [_out_dir, _level])
	print("SHOT column")
	print("RESULT PASS")
	get_tree().quit()
