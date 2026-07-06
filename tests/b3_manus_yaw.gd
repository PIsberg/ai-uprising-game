extends Node3D
## Four MANUS instances, Model yawed 0/90/180/270, shot from the -Z front.
## Pick the yaw where the FINGERS point at the camera.
const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/4f2aa26d-c9cb-4e2f-aeea-a17e19a4e75b/scratchpad/"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.08, 0.11)
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 1.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -20, 0)
	sun.light_energy = 1.8
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	_go.call_deferred(cam)

func _go(cam: Camera3D) -> void:
	for i in 4:
		var bot: Node3D = load("res://scenes/enemies/manus.tscn").instantiate()
		bot.set("preview", true)
		add_child(bot)
		bot.global_position = Vector3(i * 40.0, 0.1, 0)
		var model: Node3D = bot.get_node("Model")
		model.rotation.y = deg_to_rad(90.0 * i)
	for f in 20:
		await get_tree().process_frame
	for i in 4:
		var c := Vector3(i * 40.0, 2.6, 0)
		cam.look_at_from_position(c + Vector3(0, 4.0, -16.0), c, Vector3.UP)
		await get_tree().create_timer(0.15).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + "manus_yaw_%d.png" % (i * 90))
		print("SAVED yaw ", i * 90)
	print("MANUS YAW SWEEP DONE")
	get_tree().quit()
