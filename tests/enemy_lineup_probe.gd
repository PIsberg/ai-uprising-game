extends Node3D
## Dev probe: render each humanoid model front-on, playing its Idle clip when
## rigged (so the pose matches what the player sees in-game), to find the model
## stuck in a Y / hands-up pose. Run windowed:
##   godot --path . res://tests/enemy_lineup_probe.tscn

const MODELS := [
	"res://assets/models/robots/Leela.fbx",
	"res://assets/models/robots/Mike.fbx",
	"res://assets/models/robots/Stan.fbx",
	"res://assets/models/robots/quaternius_bot.glb",
	"res://assets/models/robots/quaternius_gunner.glb",
	"res://assets/models/robots/quaternius_flyergun.glb",
	"res://assets/models/aliens/robot_flyer.glb",
	"res://assets/models/scene.gltf",
	"res://assets/models/robots/Enemy_QuadShell.gltf",
	"res://assets/models/robots/Enemy_Trilobite.gltf",
]

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0); sun.light_energy = 1.3
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

	for path in MODELS:
		var model: Node3D = (load(path) as PackedScene).instantiate()
		add_child(model)
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var rigged := _find_skel(model) != null
		var played := "-"
		if ap:
			for clip in ["Idle", "RobotArmature|Idle"]:
				if ap.has_animation(clip):
					ap.play(clip); played = clip; break
		await get_tree().process_frame
		await get_tree().create_timer(0.2).timeout
		var aabb := _merged_aabb(model)
		model.position = Vector3(-aabb.get_center().x, -aabb.position.y, -aabb.get_center().z)
		var h: float = maxf(aabb.size.y, 0.4)
		cam.global_position = Vector3(0, h * 0.55, h * 1.05)
		cam.look_at(Vector3(0, h * 0.5, 0), Vector3.UP)
		await get_tree().create_timer(0.15).timeout
		var fname: String = path.get_file().get_basename()
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/lu_" + fname + ".png")
		print("SAVED lu_", fname, "  rigged=", rigged, " idle=", played, " size=(%.2f,%.2f,%.2f)" % [aabb.size.x, aabb.size.y, aabb.size.z])
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find_skel(c)
		if r: return r
	return null

func _merged_aabb(root: Node) -> AABB:
	var out := AABB(); var first := true
	for mi in _all_meshes(root):
		if mi.mesh == null: continue
		var ab: AABB = root.global_transform.affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())
		if first: out = ab; first = false
		else: out = out.merge(ab)
	return out

func _all_meshes(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is MeshInstance3D: out.append(c)
		out.append_array(_all_meshes(c))
	return out
