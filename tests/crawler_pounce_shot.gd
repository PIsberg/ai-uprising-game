extends Node3D
## Windowed visual check for the SPIDER's pounce posture (CrawlerPounce):
## at rest, coiled in the windup, at take-off, mid-flight rising and
## falling, just landed, and frozen to assess (the Look clip), from the
## side. Headless gives black frames.
##   godot --path . res://tests/crawler_pounce_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://crawler_pounce_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/spider_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _aim(from: Vector3, at: Vector3) -> void:
	_cam.make_current()
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)

func _side() -> void:
	_aim(_e.global_position + Vector3(-3.2, 1.2, 0.0), _e.global_position + Vector3.UP * 0.6)

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.25, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.32, 0.34)
	pm.material = fm
	floor_mi.mesh = pm
	add_child(floor_mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(100, 1, 100)
	cs.shape = bx
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	_e = (load("res://scenes/enemies/spider.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_e.set("sight_range", 0.0)
	_e.set("_leap_cd", 999.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	await _wait(0.6)
	_side()
	await _shot("rest")
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -9)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("target", player)
	_e.call("_begin_windup")
	await _wait(0.3)
	_side()
	await _shot("coil")
	var frames := 0
	while frames < 120 and not bool(_e.get("_leaping")):
		await get_tree().physics_frame
		frames += 1
	await _wait(0.05)
	_side()
	await _shot("takeoff")
	await _wait(0.25)
	_side()
	await _shot("rising")
	frames = 0
	while frames < 180 and _e.velocity.y > -3.0 and bool(_e.get("_leaping")):
		await get_tree().physics_frame
		frames += 1
	_side()
	await _shot("falling")
	frames = 0
	while frames < 300 and bool(_e.get("_leaping")):
		await get_tree().physics_frame
		frames += 1
	await get_tree().physics_frame
	_side()
	await _shot("landed")
	await _wait(0.6)
	_e.set_physics_process(false)
	_e.set("_frozen", true)
	await _wait(0.4)
	_side()
	await _shot("assess")
	get_tree().quit()
