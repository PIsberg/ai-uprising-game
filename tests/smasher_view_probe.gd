extends Node3D
## Dev probe: screenshots BEHEMOTH-X (the smasher boss) in preview mode to check
## the cover-art look (silver chassis + glowing red chest reactor + red head).
##   godot --path . res://tests/smasher_view_probe.tscn
const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/smasher.png"

func _ready() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_color = Color(0.5, 0.55, 0.65)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -35, 0)
	sun.light_energy = 2.8
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-7, 8, 8); fill.light_energy = 3.0; fill.omni_range = 30.0
	add_child(fill)
	var sm: Node3D = load("res://scenes/enemies/smasher.tscn").instantiate()
	if "preview" in sm:
		sm.preview = true
	add_child(sm)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 6.5, 15.0)
	cam.look_at_from_position(Vector3(0, 6.5, 15.0), Vector3(0, 5.5, 0), Vector3.UP)
	add_child(cam)
	_shoot.call_deferred()

func _shoot() -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
