extends Node3D
## Visual check of the flyer trio whose codex entries looked broken: whirlwind
## (streak), breaker (tilt), fishbot (flip). Spawns them side by side, physics
## off, and saves user://flyer_pose.png plus prints each model's fitted size.
##   godot --path . res://tests/flyer_pose_probe.tscn

const SCENES := {
	"whirlwind": "res://scenes/enemies/whirlwind.tscn",
	"breaker": "res://scenes/enemies/breaker.tscn",
	"fishbot": "res://scenes/enemies/fishbot.tscn",
}

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	var x := -3.0
	for key in SCENES:
		var bot: Node3D = load(SCENES[key]).instantiate()
		add_child(bot)
		bot.set_physics_process(false)
		bot.position = Vector3(x, 1.2, 0)
		x += 3.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 5.5)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/flyer_pose.png")
	var i := 0
	for key in SCENES:
		var bot := get_child(2 + i) as Node3D # env, sun, then bots
		var model := bot.get_node_or_null("Model")
		if model:
			var mesh := model.get_child(0) as Node3D
			print(key, " mesh_scale=", mesh.scale if mesh else null,
				" mesh_pos=", mesh.position if mesh else null)
		i += 1
	print("RESULT PASS")
	get_tree().quit()
