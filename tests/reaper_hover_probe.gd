extends Node3D
## Visual check: the reaper hovers over the ground (no walk shamble) with the
## flyer bank. Saves user://reaper_hover.png.
##   godot --path . res://tests/reaper_hover_probe.tscn

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new(); var fbs := BoxShape3D.new(); fbs.size = Vector3(30, 1, 30)
	fcs.shape = fbs; fcs.position = Vector3(0, -0.5, 0); floor_body.add_child(fcs)
	var fmi := MeshInstance3D.new(); var fpm := PlaneMesh.new(); fpm.size = Vector2(30, 30)
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.3, 0.32, 0.36)
	fpm.material = fmat; fmi.mesh = fpm; floor_body.add_child(fmi)
	add_child(floor_body)
	var bot: Node3D = load("res://scenes/enemies/reaper.tscn").instantiate()
	add_child(bot)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(2.6, 1.5, -3.0)
	_run.call_deferred(bot, cam)

func _run(bot: Node3D, cam: Camera3D) -> void:
	await get_tree().create_timer(1.2).timeout
	cam.look_at(bot.global_position + Vector3(0, 1.1, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/reaper_hover.png")
	var model := bot.get_node("Model") as Node3D
	print("model_y=%.2f (hover expects ~0.42)" % model.position.y)
	print("RESULT ", "PASS" if model.position.y > 0.25 else "FAIL")
	get_tree().quit()
