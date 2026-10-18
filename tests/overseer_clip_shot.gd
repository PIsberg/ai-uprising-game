extends Node3D
## Windowed look-check of the OVERSEER's rig and crash: hovering, reared up in
## the barrage tell, mid-BackFlip on its phase change, falling, and the impact.
## Headless gives black frames.
##   godot --path . res://tests/overseer_clip_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://overseer_clip_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/overseer_%s.png" % [_out_dir, name])
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
	body.collision_layer = 1
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
	cam.fov = 60.0
	add_child(cam)
	cam.global_position = Vector3(16, 6, -10)
	cam.look_at(Vector3(0, 9, 0), Vector3.UP)
	cam.make_current()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -25)
	player.set_physics_process(false)
	cam.make_current()

	var b := (load("res://scenes/enemies/overseer.tscn") as PackedScene).instantiate() as CharacterBody3D
	b.set("preview", true)
	add_child(b)
	b.set("target", player)
	b.set("sight_range", 0.0)
	b.set_physics_process(true)
	await _game_wait(1.5)
	cam.make_current()
	await _shot("hover")
	b.set("_barrage_cd", 0.0)
	b.call("_perform_attack")
	await _game_wait(0.6)
	await _shot("rear")
	await _game_wait(2.0)
	var hp: Node = b.get_node("Damageable")
	hp.set("invulnerable", false)
	hp.set("armor", 0.0)
	hp.call("apply_damage", float(hp.get("max_health")) * 0.4, null)
	await _game_wait(0.45)
	await _shot("flip")
	await _game_wait(2.0)
	hp.call("apply_damage", float(hp.get("max_health")) * 2.0, null)
	await _game_wait(0.5)
	await _shot("crash")
	while is_instance_valid(b):
		await get_tree().process_frame
	await _game_wait(0.1)
	await _shot("impact")
	Engine.time_scale = 1.0
	get_tree().quit()
