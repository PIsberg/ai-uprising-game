extends Node3D
## Dev probe: drone and seeker side by side so their silhouettes can be
## compared; saves user://flyers.png and quits. Run windowed:
##   godot --path . res://tests/flyer_screenshot.tscn

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.4, 4.5)
	add_child(cam)
	for spec in [["res://scenes/enemies/drone.tscn", -1.4], ["res://scenes/enemies/seeker.tscn", 1.4]]:
		var bot: Node3D = (load(spec[0]) as PackedScene).instantiate()
		add_child(bot)
		bot.global_position = Vector3(spec[1], 1.0, 0)
		bot.rotation.y = PI
		bot.set_physics_process(false)
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/flyers.png")
	print("SAVED flyers.png")
	get_tree().quit()
