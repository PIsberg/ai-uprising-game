extends Node3D
## Windowed visual check for the MENDER's eye rig: at rest, mending a
## wounded SPIDER below it (the eye pitched down, the beam from the lens,
## the iris narrowed), mid back-flip as the player closes in, and the mend
## from the player's eye. Headless gives black frames.
##   godot --path . res://tests/mender_eye_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://mender_eye_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/mender_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _aim(from: Vector3, at: Vector3) -> void:
	_cam.make_current()
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.28)
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
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.05, 30)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	(player.get_node("Head/Camera3D/WeaponHolder") as Node3D).visible = false
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	var ally: CharacterBody3D = (load("res://scenes/enemies/spider.tscn") as PackedScene).instantiate()
	add_child(ally)
	ally.global_position = Vector3(0, 0.1, -6)
	ally.set("sight_range", 0.0)
	ally.set("_leap_cd", 999.0)
	_e = (load("res://scenes/enemies/mender.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 3.3, 0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	await _wait(0.5)
	_aim(_e.global_position + Vector3(-3.0, 0.6, -2.5), _e.global_position)
	await _shot("rest")
	var ahp: Node = ally.get_node("Damageable")
	ahp.max_health = 400.0
	ahp.current_health = 100.0
	await _wait(1.5)
	_aim(_e.global_position + Vector3(-3.0, 0.4, -2.0), _e.global_position + Vector3(0, -0.6, -1.5))
	await _shot("mending")
	_aim(_e.global_position + Vector3(0.0, -0.4, -2.6), _e.global_position)
	await _shot("mending_lens")
	player.global_position = _e.global_position + Vector3(0, -3.2, 5.0)
	await _wait(0.35)
	_aim(_e.global_position + Vector3(-3.2, 0.5, 0.0), _e.global_position)
	await _shot("backflip")
	await _wait(0.4)
	_aim(_e.global_position + Vector3(-3.2, 0.5, 0.0), _e.global_position)
	await _shot("backflip_late")
	player.global_position = Vector3(2.0, 0.05, 6.0)
	ahp.current_health = 100.0
	await _wait(2.0)
	var eye := player.global_position + Vector3.UP * 1.6
	_aim(eye, _e.global_position)
	await _shot("mend_from_player")
	get_tree().quit()
