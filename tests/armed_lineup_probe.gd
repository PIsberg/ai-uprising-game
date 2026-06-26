extends Node3D
## Lines up the Blender-armed bot forks so we can SEE the welded weapons.
## Run windowed: godot --path . --quit-after 200 res://tests/armed_lineup_probe.tscn

const MODELS := [
	"res://assets/models/robots/quaternius_bot_armed.glb",
	"res://assets/models/robots/quaternius_gunner_armed.glb",
	"res://assets/models/robots/quaternius_flyergun_armed.glb",
]

func _ready() -> void:
	var we := WorldEnvironment.new(); we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.1, 0.11, 0.14)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	we.environment.ambient_light_energy = 1.0
	add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 35, 0); sun.light_energy = 2.0
	add_child(sun)
	var xs := [-3.0, 0.0, 3.0]
	for i in MODELS.size():
		var b: Node3D = (load(MODELS[i]) as PackedScene).instantiate()
		add_child(b)
		b.position = Vector3(xs[i], 0, 0)
		b.rotation.y = PI * 0.85   # 3/4 front so the forward-facing guns read
	var cam := Camera3D.new(); cam.current = true; add_child(cam)
	cam.global_position = Vector3(0, 1.6, 5.2)
	cam.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/armed_lineup.png")
	print("ARMED_LINEUP_DONE")
	get_tree().quit()
