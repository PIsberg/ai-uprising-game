extends Node3D
## Windowed look-check for the HIVE uplink fork: a networked unit (front 3/4, beacon
## lit, shield up) beside a jammed one (rear 3/4, beacon dead, shield down). The
## camera looks down +Z, so the jammed unit (world +X) is on the LEFT of the frame.
## Saves user://hive_uplink.png. Run: godot --path . res://tests/hive_uplink_shot.tscn

const HIVE := preload("res://scenes/enemies/hive.tscn")

func _ready() -> void:
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

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor_body.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	fm.mesh = bm
	floor_body.add_child(fm)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	var yaws := [25.0, 155.0]
	var hives: Array = []
	for i in 2:
		var h := HIVE.instantiate() as Node3D
		add_child(h)
		h.global_position = Vector3(-1.6 + 3.2 * i, 0.1, 0)
		h.rotation_degrees.y = yaws[i]
		hives.append(h)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.9, -5.2), Vector3(0, 1.2, 0), Vector3.UP)
	cam.fov = 50.0
	cam.make_current()

	for i in 10:
		await get_tree().physics_frame
	hives[1].call("enter_jam")
	for i in 50:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, int(1280.0 * img.get_height() / img.get_width()))
	img.save_png("user://hive_uplink.png")
	print("SHOT ", ProjectSettings.globalize_path("user://hive_uplink.png"))
	get_tree().quit()
