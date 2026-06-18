extends Node3D
## Dev probe: render an arbitrary model scene front/side/q3 to judge its pose.
## Pass the resource path after `--`:
##   godot --path . res://tests/model_view_probe.tscn -- res://assets/models/robots/George.fbx tag

func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var path := "res://assets/models/robots/George.fbx"
	var tag := "model"
	if argv.size() >= 1:
		path = argv[0]
	if argv.size() >= 2:
		tag = argv[1]

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.66)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.12)
	add_child(env)

	var model: Node3D = (load(path) as PackedScene).instantiate()
	add_child(model)
	var aabb := _merged_aabb(model)
	model.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	var h: float = maxf(aabb.size.y, 0.5)
	print("MODEL ", path, " height=", h, " size=", aabb.size)

	var cam := Camera3D.new()
	add_child(cam)
	var focus := Vector3(0, h * 0.5, 0)
	for shot in [["front", Vector3(0, 1, 1)], ["side", Vector3(1, 1, 0.04)], ["q3", Vector3(0.75, 1, 0.75)]]:
		var dir: Vector3 = (shot[1] as Vector3).normalized()
		cam.global_position = focus + dir * (h * 0.95)
		cam.global_position.y = h * 0.55
		cam.look_at(focus, Vector3.UP)
		await get_tree().create_timer(0.4).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/" + tag + "_" + str(shot[0]) + ".png")
		print("SAVED ", tag, "_", shot[0], ".png")
	get_tree().quit()

func _merged_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all_meshes(root):
		var ab: AABB = root.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb())
		if first:
			out = ab; first = false
		else:
			out = out.merge(ab)
	return out

func _all_meshes(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out
