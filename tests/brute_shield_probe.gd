extends Node3D
## Visual check: does the BRUTE still visibly carry its frontal shield slab?
## Captures front and three-quarter shots to user://brute_shield_*.png.
##   godot --path . res://tests/brute_shield_probe.tscn

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.glow_enabled = true
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var bot: Node3D = load("res://scenes/enemies/brute.tscn").instantiate()
	add_child(bot)
	bot.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	_run.call_deferred(bot, cam)

func _run(bot: Node3D, cam: Camera3D) -> void:
	await get_tree().create_timer(0.5).timeout
	var gs := get_node_or_null("/root/GraphicsSettings")
	print("triplanar=", gs.get("robot_triplanar_enabled") if gs else "no-gs")
	var slab := bot.get_node_or_null("ShieldRig/ShieldSlab") as MeshInstance3D
	var rim := bot.get_node_or_null("ShieldRig/ShieldRim") as MeshInstance3D
	var plate := bot.get_node_or_null("ShieldRig/ShieldPlate") as MeshInstance3D
	print("slab=", slab != null, " mat=", slab.material_override if slab else null)
	print("rim=", rim != null, " rim_vis=", rim.visible if rim else "-")
	print("plate=", plate != null)
	# Front view (shield arc faces -Z).
	cam.global_position = Vector3(-0.6, 1.6, -4.5)
	cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/brute_shield_front.png")
	# Three-quarter view.
	cam.global_position = Vector3(-3.2, 1.8, -3.2)
	cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/brute_shield_quarter.png")
	print("RESULT PASS")
	get_tree().quit()
