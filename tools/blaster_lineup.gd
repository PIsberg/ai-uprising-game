# Dev probe: renders all 18 Kenney blasters in a labeled grid and saves a
# screenshot to user://blaster_lineup.png, then quits. Run windowed:
#   godot --path . --script tools/blaster_lineup.gd
extends SceneTree

func _init() -> void:
	var root_node := Node3D.new()
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.3, 3.0)
	cam.look_at_from_position(cam.position, Vector3(0, 0, 0))
	root_node.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	root_node.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.22, 0.26)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 1.0
	env.environment = e
	root_node.add_child(env)
	var letters := "abcdefghijklmnopqr"
	for i in letters.length():
		var c := letters[i]
		var ps: PackedScene = load("res://assets/models/weapons/blaster-%s.glb" % c)
		if ps == null:
			continue
		var inst := ps.instantiate() as Node3D
		# 6 per row; +Z rotated to screen-right so muzzle direction is legible.
		inst.position = Vector3((i % 6) * 1.45 - 3.6, 1.2 - floorf(i / 6.0) * 1.2, 0)
		inst.rotation.y = PI * 0.5
		root_node.add_child(inst)
		var lbl := Label3D.new()
		lbl.text = c
		lbl.font_size = 64
		lbl.position = inst.position + Vector3(0, 0.45, 0)
		root_node.add_child(lbl)
	get_root().add_child(root_node)
	_capture()

func _capture() -> void:
	for i in 12:
		await process_frame
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/blaster_lineup.png")
	print("SAVED ", OS.get_user_data_dir() + "/blaster_lineup.png")
	quit()
