extends Node3D
## Shows the two new enemies (dog + server) lit, facing the camera, so we can
## confirm the look, facing (-Z front), and the glowing red eyes survive.
## Run windowed: godot --path . --quit-after 200 res://tests/newenemy_probe.tscn

func _ready() -> void:
	var we := WorldEnvironment.new(); we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.09, 0.1, 0.13)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.45, 0.5, 0.6)
	we.environment.ambient_light_energy = 0.9
	we.environment.glow_enabled = true
	add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-38, 25, 0); sun.light_energy = 1.8
	add_child(sun)
	# Both face -Z by default; the camera sits on -Z looking +Z so we see their faces.
	var dog: Node3D = (load("res://scenes/enemies/dog.tscn") as PackedScene).instantiate()
	add_child(dog); dog.position = Vector3(-1.7, 0, 0)
	dog.set_physics_process(false)
	var srv: Node3D = (load("res://scenes/enemies/server.tscn") as PackedScene).instantiate()
	add_child(srv); srv.position = Vector3(1.7, 0, 0)
	srv.set_physics_process(false)
	var cam := Camera3D.new(); cam.current = true; add_child(cam)
	cam.global_position = Vector3(0, 1.3, -4.2)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/newenemies.png")
	print("NEWENEMY_DONE")
	get_tree().quit()
