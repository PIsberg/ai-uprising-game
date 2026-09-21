extends Node3D
## Windowed look-check for the RAPTOR strike fork: a chase view of one unit caught mid-stoop
## (wings level, V tail, talons hanging, thrusters swung aft, belly gun raking the line down
## onto a target dummy) with a second unit holding its hover beyond, facing the camera
## (beak, eye, belly gun, thrusters straight down).
## Everything stands on a stage node 50 m from the scene root: impact explosions emit their
## first frame of particles at the current scene's origin, not at the impact.
## Saves user://raptor_stoop.png. Run: godot --path . res://tests/raptor_stoop_shot.tscn

const RAPTOR := preload("res://scenes/enemies/raptor.tscn")

func _ready() -> void:
	var stage := Node3D.new()
	stage.position = Vector3(50, 0, 50)
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 150, 0)
	sun.light_energy = 1.4
	add_child(sun)

	# A floor to look at but not to hit: nothing here walks, and bolts landing in frame
	# bury both models under impact flashes and shockwave rings.
	var floor_body := Node3D.new()
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(200, 1, 200)
	fm.mesh = bm
	floor_body.add_child(fm)
	stage.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)

	# The target the stoop is flown at: a plain capsule so the dive has something to read against.
	var player := StaticBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	player.add_child(pcs)
	var pm := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.4
	cm.height = 1.8
	pm.mesh = cm
	player.add_child(pm)
	stage.add_child(player)
	player.position = Vector3(3.5, 0.9, 1.0)

	var hoverer := RAPTOR.instantiate() as Node3D
	stage.add_child(hoverer)
	hoverer.position = Vector3(7.5, 3.0, -3.2)
	hoverer.rotation_degrees.y = 68.0
	hoverer.set_physics_process(false) # hold the pose; its AI would turn on the target

	var diver := RAPTOR.instantiate() as Node3D
	stage.add_child(diver)
	diver.position = Vector3(-14.0, 5.1, 1.0)

	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(50, 2.4, 40.5), Vector3(50, 2.5, 51), Vector3.UP)
	cam.fov = 52.0
	cam.make_current()

	for i in 30:
		await get_tree().physics_frame
	diver.set("_run_cd", 0.0)
	# Catch it on the way down, a few metres short of the target.
	for i in 60 * 6:
		await get_tree().physics_frame
		if float(diver.get("_run_t")) > 0.0:
			var ahead: float = ((diver.get("_run_aim") as Vector3) - diver.global_position).dot(diver.get("_run_dir") as Vector3)
			if ahead < 5.0:
				break
	var mesh_node := diver.get_node("Model/Mesh") as Node3D
	print("SHOT diver fwd=%s run_dir=%s vel=%s mesh_rot=%s" % [-diver.global_transform.basis.z, diver.get("_run_dir"), diver.get("velocity"), mesh_node.rotation])
	print("SHOT diver at %s pitch=%.2f thrust=%s" % [diver.position, (diver.get_node("Model") as Node3D).rotation.x, diver.call("thrust_dir")])
	# Chase camera: behind, above and a little left of the diver, looking down its line.
	var rd := diver.get("_run_dir") as Vector3
	var side := rd.cross(Vector3.UP).normalized()
	cam.look_at_from_position(diver.global_position - rd * 5.0 - side * 2.2 + Vector3(0, 1.1, 0),
			diver.global_position + rd * 3.0 - Vector3(0, 0.8, 0), Vector3.UP)
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, int(1280.0 * img.get_height() / img.get_width()))
	img.save_png("user://raptor_stoop.png")
	print("SHOT ", ProjectSettings.globalize_path("user://raptor_stoop.png"))
	get_tree().quit()
