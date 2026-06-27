extends Node3D
## Dev probe: renders the available CC0 enemy models side by side so I can pick
## distinct bases for the hazard-world flyers (currently all share EyeDrone).
##   godot --path . res://tests/model_gallery_probe.tscn

const OUT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/model_gallery.png"
const MODELS := [
	"res://assets/models/robots/Enemy_EyeDrone.gltf",
	"res://assets/models/robots/Enemy_QuadShell.gltf",
	"res://assets/models/robots/Enemy_Trilobite.gltf",
	"res://assets/models/aliens/robot_flyer.glb",
	"res://assets/models/robots/quaternius_flyergun.glb",
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
	var x := -4.0
	for path in MODELS:
		if ResourceLoader.exists(path):
			var m: Node3D = load(path).instantiate()
			add_child(m)
			m.global_position = Vector3(x, 0, 0)
			m.scale = Vector3.ONE * 1.0
		x += 2.0
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, 7.5)
	add_child(cam)
	_shoot.call_deferred()

func _shoot() -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("SAVED ", OUT)
	get_tree().quit()
