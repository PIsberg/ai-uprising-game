extends Node3D
## Windowed probe: render the new RAVAGER beside a REAPER (same chassis, smaller)
## so its scale/tint read as a fiercer, heavier bruiser. Run windowed:
##   godot --path . res://tests/ravager_shot.tscn

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
	cam.global_position = Vector3(0, 2.6, 8.0)
	cam.look_at(Vector3(0, 1.4, 0), Vector3.UP)

	for item in [["res://scenes/enemies/reaper.tscn", -2.4], ["res://scenes/enemies/ravager.tscn", 2.4]]:
		var e: Node3D = (load(item[0]) as PackedScene).instantiate()
		add_child(e)
		e.set_physics_process(false)   # pose only — no AI/nav
		e.set_process(false)
		e.global_position = Vector3(item[1], 0, 0)
		var ap := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("CharacterArmature|Idle"):
			ap.play("CharacterArmature|Idle")
	await get_tree().process_frame
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/ravager_shot.png")
	print("SHOT saved")
	get_tree().quit()
