extends Node3D
## A/B probe for the always-on glowing optic (RobotModel.eye_glow). Four stand-in
## enemies: drone OFF | drone ON | sentinel OFF | sentinel ON, under an interior
## env with bloom so the eye reads. Windowed:
##   godot --path . tests/eye_glow_probe.tscn

const RM := preload("res://scripts/enemies/robot_model.gd")
const DRONE := preload("res://assets/models/robots/Enemy_EyeDrone.gltf")
const HEAVY := preload("res://assets/models/robots/quaternius_heavy.glb")

func _ready() -> void:
	_environment()
	# drone: mesh flip (-1,1,-1); Eye node at z=-0.36 with EyeLight under it
	var drone_x := Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)), Vector3.ZERO)
	var heavy_x := Transform3D(Basis(Vector3(-0.85, 0, 0), Vector3(0, 0.85, 0), Vector3(0, 0, -0.85)), Vector3.ZERO)
	_spawn(Vector3(-4.5, 1.2, 0), DRONE, drone_x, Color(1, 0.3, 0.2), Vector3(0, 0, -0.36), Color.WHITE, 0.0, true)
	_spawn(Vector3(-1.5, 1.2, 0), DRONE, drone_x, Color(1, 0.3, 0.2), Vector3(0, 0, -0.36), Color.WHITE, 1.2, true)
	# sentinel: heavy mesh flip 0.85; EyeLight at (0,1.3,-0.5)
	_spawn(Vector3(1.5, 0, 0), HEAVY, heavy_x, Color(1, 0.28, 0.18), Vector3(0, 1.3, -0.5), Color(0.85, 0.62, 0.6), 0.0, false)
	_spawn(Vector3(4.5, 0, 0), HEAVY, heavy_x, Color(1, 0.28, 0.18), Vector3(0, 1.3, -0.5), Color(0.85, 0.62, 0.6), 1.0, false)
	_camera()
	_shoot()

func _spawn(pos: Vector3, mesh_scene: PackedScene, mesh_xform: Transform3D, eye_col: Color,
		eye_pos: Vector3, tint: Color, eye_glow: float, drone: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = PI # face the camera (enemies front is -Z; in-game they face the player)
	var model := Node3D.new()
	model.name = "Model"
	model.set_script(RM)
	var mesh := mesh_scene.instantiate()
	mesh.transform = mesh_xform
	model.add_child(mesh)
	# EyeLight (under an "Eye" node for the drone, mirroring the real scenes)
	var light := OmniLight3D.new()
	light.name = "EyeLight"
	light.light_color = eye_col
	light.light_energy = 1.8
	light.omni_range = 6.0
	if drone:
		var eye := Node3D.new()
		eye.name = "Eye"
		eye.position = eye_pos
		eye.add_child(light)
		root.add_child(eye)
	else:
		light.position = eye_pos
		root.add_child(light)
	root.add_child(model)
	# set exports before the node enters the tree so _ready picks them up
	model.set("tint", tint)
	model.set("eye_glow", eye_glow)
	model.set("anim_walk", "")
	add_child(root)

func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.55)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.85
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 0.95
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 25, 0)
	key.light_energy = 1.1
	add_child(key)

func _camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 48.0
	cam.position = Vector3(0, 1.5, 10.5)
	add_child(cam)
	cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)

func _shoot() -> void:
	for i in 36:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_user_data_dir() + "/eye_glow.png"
	img.save_png(out)
	print("SAVED ", out)
	get_tree().quit()
