extends Node3D
## Dev probe: stages the two new hazard-world enemies (MAGMA WRAITH + ANGLER UNIT)
## side by side under even light and screenshots them, so their silhouettes/FX can
## be eyeballed. Run WINDOWED (headless can't render):
##   godot --path . res://tests/enemy_view_probe.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/new_enemies.png"

func _ready() -> void:
	# Even neutral lighting + a dark ground so the emissive parts read.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.04, 0.05, 0.07)
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.3
	add_child(sun)

	_spawn("res://scenes/enemies/magma.tscn", Vector3(-1.4, 1.0, 0))
	_spawn("res://scenes/enemies/fishbot.tscn", Vector3(1.4, 1.0, 0))

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.position = Vector3(0, 1.15, 4.2)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.current = true
	add_child(cam)
	_shoot.call_deferred()

func _spawn(path: String, pos: Vector3) -> void:
	var e: Node3D = load(path).instantiate()
	add_child(e)
	e.global_position = pos

func _shoot() -> void:
	await get_tree().create_timer(0.8).timeout # let FX + optics warm up
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
