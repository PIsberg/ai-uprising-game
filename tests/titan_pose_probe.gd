extends Node3D
## Dev probe: render the giant_robot.glb (PROMETHEUS-0 / TITAN model) from front
## and side so its arm pose can be judged, and dump each mesh part's local
## position + aabb so the arm cluster can be identified. Run windowed:
##   godot --path . res://tests/titan_pose_probe.tscn

const SHOTS := [
	["front", Vector3(0, 1.1, 4.6)],
	["side", Vector3(4.6, 1.1, 0.2)],
	["q3", Vector3(3.4, 1.4, 3.4)],
]

func _ready() -> void:
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

	var model: Node3D = (load("res://assets/models/boss/giant_robot.glb") as PackedScene).instantiate()
	add_child(model)
	# Toggle: tint the buckets to verify selection, or actually re-pose.
	var tint_only := "--tint" in OS.get_cmdline_user_args()
	if tint_only:
		_tint_buckets(model)
	else:
		ModelPoser.pose_giant_robot_arms(model)
	# Recenter so the model sits on y=0 and is framed.
	var aabb := _merged_aabb(model)
	model.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	var h := aabb.size.y
	print("MODEL height=", h, " center=", aabb.get_center(), " size=", aabb.size)

	# Dump parts sorted by height for arm identification.
	var parts: Array = []
	for c in model.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var ab := mi.get_aabb()
			var ctr := mi.transform * ab.get_center()
			parts.append({"name": mi.name, "pos": ctr, "size": ab.size})
	parts.sort_custom(func(a, b): return a.pos.y > b.pos.y)
	for p in parts:
		print("PART ", p.name, " pos=(%.2f, %.2f, %.2f)" % [p.pos.x, p.pos.y, p.pos.z], " size=(%.2f, %.2f, %.2f)" % [p.size.x, p.size.y, p.size.z])

	var cam := Camera3D.new()
	add_child(cam)
	var focus := Vector3(0, h * 0.5, 0)
	for shot in SHOTS:
		var p: Vector3 = shot[1]
		p.y = h * 0.55
		# scale camera distance to model height
		cam.global_position = focus + (p - Vector3(0, p.y, 0)).normalized() * (h * 0.82) + Vector3(0, p.y, 0)
		cam.look_at(focus, Vector3.UP)
		await get_tree().create_timer(0.4).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/titan_" + shot[0] + ".png")
		print("SAVED titan_", shot[0], ".png")
	get_tree().quit()

func _merged_aabb(root: Node) -> AABB:
	# Recurse: after re-posing, arm parts live under pivot nodes.
	var out := AABB()
	var first := true
	for mi in _all_meshes(root):
		var ab: AABB = root.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb())
		if first:
			out = ab
			first = false
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

func _tint_buckets(model: Node3D) -> void:
	const X_ARM := 0.42
	const Y_FLOOR := -0.70
	for c in model.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi := c as MeshInstance3D
		var ctr: Vector3 = mi.transform * mi.get_aabb().get_center()
		var col := Color(0.4, 0.4, 0.45)
		if ctr.y >= Y_FLOOR:
			if ctr.x > X_ARM:
				col = Color(1, 0.2, 0.2)   # right arm
			elif ctr.x < -X_ARM:
				col = Color(0.2, 0.4, 1)   # left arm
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		mi.material_override = m
