extends Node3D
## Dev probe: renders the available CC0 enemy models side by side so I can pick
## distinct bases for the hazard-world flyers (currently all share EyeDrone).
##   godot --path . res://tests/model_gallery_probe.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/model_gallery.png"
const MODELS := [
	"res://assets/models/robots/George_smasher.glb",
	"res://assets/models/robots/RobotExpressive.glb",
	"res://assets/models/robots/quaternius_gunner.glb",
	"res://assets/models/robots/quaternius_heavy.glb",
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.07, 0.1)
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -40, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var x := -4.5
	for path in MODELS:
		if ResourceLoader.exists(path):
			var m: Node3D = load(path).instantiate()
			add_child(m)
			m.global_position = Vector3(x, 0, 0)
		x += 3.0
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 11.0)
	cam.look_at_from_position(Vector3(0, 1.6, 11.0), Vector3(0, 1.2, 0), Vector3.UP)
	add_child(cam)
	_shoot.call_deferred()

func _shoot() -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
