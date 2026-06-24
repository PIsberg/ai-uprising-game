extends Node3D
## Windowed probe: view the freshly-sourced Quaternius Mech (Idle pose) to confirm
## scale/orientation/look before building an enemy from it. Run windowed:
##   godot --path . res://tests/mech_shot.tscn

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0); sun.light_energy = 1.4
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.62)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.07, 0.08, 0.11)
	add_child(env)
	var cam := Camera3D.new()
	add_child(cam)

	var model: Node3D = (load("res://assets/models/robots/quaternius_mech.glb") as PackedScene).instantiate()
	add_child(model)
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clips: Array = ap.get_animation_list() if ap else []
	if ap and ap.has_animation("RobotArmature|Idle"):
		ap.play("RobotArmature|Idle")
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var aabb := _merged_aabb(model)
	model.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
	var h: float = maxf(aabb.size.y, 0.6)
	cam.global_position = Vector3(h * 0.5, h * 0.6, h * 1.25)
	cam.look_at(Vector3(0, h * 0.5, 0), Vector3.UP)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/mech_shot.png")
	print("SHOT saved  size=(%.2f,%.2f,%.2f)  clips=%d  %s" % [aabb.size.x, aabb.size.y, aabb.size.z, clips.size(), str(clips)])
	get_tree().quit()

func _merged_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		if first: out = a; first = false
		else: out = out.merge(a)
	return out
