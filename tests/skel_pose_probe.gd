extends Node3D
## Dev probe: sweep candidate ArmRelaxModifier rotations on the George rig (idle
## clip playing) and render each, so the angle that drops the arms to a natural
## carry can be picked. Run windowed:
##   godot --path . res://tests/skel_pose_probe.tscn

const MODEL := "res://assets/models/robots/George.fbx"
# Candidates: euler (deg, local) for UpperArm.L / UpperArm.R.
const CANDIDATES := [
	["z70", Vector3(0, 0, -70), Vector3(0, 0, 70)],
	["z85", Vector3(0, 0, -85), Vector3(0, 0, 85)],
	["z100", Vector3(0, 0, -100), Vector3(0, 0, 100)],
]
# Optional forearm (LowerArm) straighten paired with each upper-arm candidate.
const FOREARM := Vector3(0, 0, 25)

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0); sun.light_energy = 1.3
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.6, 0.66)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.12)
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)

	for cand in CANDIDATES:
		var model: Node3D = (load(MODEL) as PackedScene).instantiate()
		add_child(model)
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("Idle"):
			ap.play("Idle")
		var mod := ModelPoser.relax_skeleton_arms(model, [
			{"bone": "UpperArm.L", "euler": cand[1]},
			{"bone": "UpperArm.R", "euler": cand[2]},
			{"bone": "LowerArm.L", "euler": FOREARM},
			{"bone": "LowerArm.R", "euler": -FOREARM},
		])
		# Let the anim + modifier settle.
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.2).timeout
		var aabb := _merged_aabb(model)
		model.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
		var h: float = maxf(aabb.size.y, 0.5)
		for view in [["q3", Vector3(0.7, 0.55, 0.7)], ["front", Vector3(0, 0.5, 1)]]:
			cam.global_position = (view[1] as Vector3).normalized() * (h * 1.0)
			cam.global_position.y = h * 0.55
			cam.look_at(Vector3(0, h * 0.5, 0), Vector3.UP)
			await get_tree().create_timer(0.15).timeout
			var img := get_viewport().get_texture().get_image()
			img.save_png(OS.get_user_data_dir() + "/cand_" + str(cand[0]) + "_" + str(view[0]) + ".png")
		print("SAVED cand_", cand[0], "  h=", h)
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _merged_aabb(root: Node) -> AABB:
	var out := AABB(); var first := true
	for mi in _all_meshes(root):
		var ab: AABB = root.global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb())
		if first: out = ab; first = false
		else: out = out.merge(ab)
	return out

func _all_meshes(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is MeshInstance3D: out.append(c)
		out.append_array(_all_meshes(c))
	return out
