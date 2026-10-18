extends Node3D
## Windowed look-check of GOLIATH-IX's attack clips: the ground slam's
## crouch, leap and landing (reactor and eye riding the body), the artillery
## Shoot, and a walk frame at a footfall. Physics runs; the boss is parked.
## Headless gives black frames.
##   godot --path . res://tests/colossus_clip_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://colossus_clip_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/colossus_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _game_wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.28, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45, 35, 0)
	add_child(key)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position.y = -0.5
	body.add_child(cs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	fm.mesh = pm
	body.add_child(fm)
	add_child(body)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.global_position = Vector3(22, 7, -6)
	cam.look_at(Vector3(0, 6, 0), Vector3.UP)
	cam.make_current()

	var b := (load("res://scenes/enemies/colossus.tscn") as PackedScene).instantiate() as CharacterBody3D
	b.set("preview", true)
	add_child(b)
	await _game_wait(0.8)
	b.set_physics_process(true)
	await _shot("idle")
	b.call("_begin_slam")
	for f in [["crouch", 0.06], ["leap", 0.16], ["landing", 0.28]]:
		await _game_wait(f[1] - (0.0 if f[0] == "crouch" else 0.0))
		await _shot(f[0])
	await _game_wait(1.5)
	var mark := Node3D.new()
	add_child(mark)
	mark.global_position = Vector3(0, 1, -40)
	b.set("target", mark)
	b.call("_fire_artillery")
	await _game_wait(0.2)
	await _shot("artillery")
	get_tree().quit()
