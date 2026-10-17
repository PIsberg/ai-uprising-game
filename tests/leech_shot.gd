extends Node3D
## Windowed visual check for the TELEMETRY LEECH: a real leech in a lit room,
## first in flight from the side, then latched behind a stand-in player's head
## seen from behind (where the player never sees it). Headless gives black
## frames.
##   godot --path . res://tests/leech_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://leech_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/leech_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	GameState.current_state = GameState.State.PLAYING
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	add_child(floor_mi)
	# Stand-in player: a grey capsule body with a head and a camera node.
	var p := CharacterBody3D.new()
	p.add_to_group("player")
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.7
	body.mesh = cap
	body.position.y = 0.85
	p.add_child(body)
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.6
	p.add_child(head)
	var pcam := Node3D.new()
	pcam.name = "Camera3D"
	head.add_child(pcam)
	add_child(p)
	var l := (load("res://scenes/enemies/leech.tscn") as PackedScene).instantiate() as EnemyLeech
	l.position = Vector3(2.5, 1.5, -1.5)
	add_child(l)
	l.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50.0
	cam.global_position = Vector3(5.5, 1.8, 2.0)
	cam.look_at(Vector3(1.5, 1.4, -0.5))
	for i in 20:
		await get_tree().process_frame
	await _shot("flight")
	l.latch(p)
	l.set_physics_process(true)
	cam.global_position = Vector3(0.8, 2.1, 2.6)
	cam.look_at(Vector3(0, 1.6, 0))
	for i in 10:
		await get_tree().physics_frame
	await _shot("latched")
	print("RESULT PASS")
	get_tree().quit()
