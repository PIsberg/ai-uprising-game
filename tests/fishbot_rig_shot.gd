extends Node3D
## Windowed visual check for the FISHBOT's swim rig: side-on, front-left,
## from behind and from above at rest (the fins on the chassis, the legs
## trailing), mid-swim from behind and the side (the tail mid-stroke, the
## legs kicking), a spit from a player's eye and the dart that follows it.
## Headless gives black frames.
##   godot --path . res://tests/fishbot_rig_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://fishbot_rig_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/fishbot_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _aim(from: Vector3, at: Vector3) -> void:
	_cam.make_current() # the player's own camera takes over when it spawns
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
	env.background_color = Color(0.18, 0.24, 0.32)
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
	pm.size = Vector2(60, 60)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.26, 0.3, 0.34)
	pm.material = fm
	floor_mi.mesh = pm
	add_child(floor_mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(80, 1, 80)
	cs.shape = bx
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	_e = (load("res://scenes/enemies/fishbot.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 2.0, 0)
	_e.set("sight_range", 0.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	var frames := 0
	while frames < 240 and _e.get("_rig_ready") != true:
		await get_tree().process_frame
		frames += 1
	await _wait(0.5)
	var c := _e.global_position
	_aim(c + Vector3(-2.8, 0.6, 0.0), c + Vector3.UP * 0.4)
	await _shot("side")
	_aim(c + Vector3(-1.8, 1.0, -2.0), c + Vector3.UP * 0.4)
	await _shot("rest")
	_aim(c + Vector3(0.0, 1.0, 2.8), c + Vector3.UP * 0.4)
	await _shot("behind")
	_aim(c + Vector3(0.0, 2.8, 0.01), c + Vector3.UP * 0.4)
	await _shot("top")
	# A player 40 m off: it chases at full speed, the tail beating, the legs
	# kicking; the camera rides along.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.05, -40)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	(player.get_node("Head/Camera3D/WeaponHolder") as Node3D).visible = false # its gun would fill the eye-level shots
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("sight_range", 60.0)
	_e.set("target", player)
	_e.set("_dive_timer", 999.0)
	_e.global_rotation = Vector3.ZERO
	_e.call("set_state", 3) # CHASE
	await _wait(1.3)
	c = _e.global_position
	_aim(c + Vector3(0.0, 0.9, 3.0), c + Vector3.UP * 0.4)
	await _shot("swim_behind")
	await _wait(0.1)
	c = _e.global_position
	_aim(c + Vector3(-3.0, 0.7, 0.4), c + Vector3.UP * 0.4)
	await _shot("swim_side")
	# The player 8 m ahead of it: a spit from the eye, then the dart.
	player.global_position = Vector3(_e.global_position.x, 0.05, _e.global_position.z - 8.0)
	_e.set("_attack_timer", 999.0)
	frames = 0
	while frames < 210 and not (int(_e.get("state")) == 4 and bool(_e.call("_can_see", player)) and frames > 30):
		await get_tree().physics_frame
		_e.set("_attack_timer", 999.0)
		frames += 1
	var eye := player.global_position + Vector3.UP * 1.6
	_aim(eye, _e.global_position + Vector3.UP * 0.5)
	await _shot("engaged_from_player")
	_e.set("_attack_timer", 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	eye = player.global_position + Vector3.UP * 1.6
	_aim(eye, _e.global_position + Vector3.UP * 0.5)
	await _shot("spit_from_player")
	_e.set("_attack_timer", 999.0)
	await _wait(0.25)
	eye = player.global_position + Vector3.UP * 1.6
	_aim(eye, _e.global_position + Vector3.UP * 0.5)
	await _shot("dart_from_player")
	get_tree().quit()
