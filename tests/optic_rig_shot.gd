extends Node3D
## Windowed visual check for the OPTIC's rig: front-left view at rest, through
## the cutting beam's charge (both torches raised onto the player) and while
## it burns (a beam from each tip), plus the wheels alone at rest and a quarter
## turn on, to see that nothing static turns with them.
## Headless gives black frames.
##   godot --path . res://tests/optic_rig_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://optic_rig_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/optic_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _part(name: String) -> MeshInstance3D:
	return _e.find_child(name, true, false) as MeshInstance3D

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
	env.background_color = Color(0.25, 0.28, 0.32)
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
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	_e = (load("res://scenes/enemies/optic.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.05, 0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	for i in 8:
		await get_tree().physics_frame
	_aim(Vector3(-2.2, 1.4, -2.6), Vector3(0, 0.8, 0))
	await _shot("rest")
	# Wheels alone, at rest and a quarter turn on.
	for n in ["Body", "TorchL", "TorchR"]:
		_part(n).visible = false
	_aim(Vector3(-1.15, 0.42, -0.75), Vector3(-0.3, 0.12, -0.07))
	await _shot("wheels_rest")
	_e.set("_wheel_spin", PI * 0.5)
	await get_tree().physics_frame
	await _shot("wheels_quarter")
	_e.set("_wheel_spin", 0.0)
	for n in ["Body", "TorchL", "TorchR"]:
		_part(n).visible = true
	# A player at 9 m: the attack starts the beam; the torches rise through
	# the charge, then both tips burn.
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
	_e.set("_beam_cd", 0.0)
	_e.call("set_state", 4) # ATTACK
	var t := 0.0
	while t < 1.0 and not bool(_e.call("_beaming")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _wait(0.45)
	_aim(Vector3(-2.2, 1.4, -2.6), Vector3(0, 0.8, 0))
	await _shot("charge")
	_aim(Vector3(-2.6, 1.0, 1.2), Vector3(0, 0.8, -3.0))
	await _shot("charge_behind")
	await _wait(0.45)
	_aim(Vector3(-2.6, 1.0, 1.2), Vector3(0, 0.8, -3.0))
	await _shot("fire")
	get_tree().quit()
