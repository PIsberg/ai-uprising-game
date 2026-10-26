extends Node3D
## Windowed visual check for the RIPPER's minigun rig: close on the gun at
## rest, the barrel cluster and the housing alone (the model's two gun
## meshes), the gun turned onto a player off to its side with the saw
## running (tracers from the cluster's tip), and that from the player's eye.
## Headless gives black frames.
##   godot --path . res://tests/ripper_rig_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _e: CharacterBody3D
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://ripper_rig_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	for i in 3: # a visibility change lands a couple of draws on
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(960, 540)
	img.save_png("%s/ripper_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _part(which: String) -> MeshInstance3D:
	return _e.find_child(String(_e.get(which)), true, false) as MeshInstance3D

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
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.32, 0.34)
	pm.material = fm
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
	_e = (load("res://scenes/enemies/ripper.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.05, 0)
	_e.set("sight_range", 0.0)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()
	var frames := 0
	while frames < 240 and not bool(_e.get("_rig_ready")):
		await get_tree().process_frame
		frames += 1
	await _wait(0.2)
	_aim(Vector3(-1.6, 1.3, -2.2), Vector3(0, 0.8, 0))
	await _shot("rest")
	_aim(Vector3(-0.9, 0.9, -0.9), Vector3(0, 0.64, -0.2))
	await _shot("gun")
	_e.set_physics_process(false) # hold it still (idle turns it) for the parts
	_part("HOUSING_NAME").visible = false
	await _shot("barrels")
	_part("HOUSING_NAME").visible = true
	_part("BARREL_NAME").visible = false
	await _shot("housing")
	_part("BARREL_NAME").visible = true
	_e.set_physics_process(true)
	# A player 30 deg off the nose at 8 m: the spin-up, then the saw.
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(-2.5, 0.05, -4.3)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	(player.get_node("Head/Camera3D/WeaponHolder") as Node3D).visible = false
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("sight_range", 40.0)
	_e.set("target", player)
	_e.set("turn_speed", 0.0)
	_e.set("move_speed", 0.0) # no grinding advance: hold the frame
	_e.call("set_state", 4) # ATTACK
	_e.set("_attack_timer", 999.0)
	_e.call("_start_burst")
	var t := 0.0
	while t < 2.0 and int(_e.get("_burst_remaining")) == 0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_e.set("_attack_timer", 999.0)
	await _wait(0.2)
	_e.set("_attack_timer", 999.0)
	_aim(_e.global_position + Vector3(-1.0, 0.95, -1.1), _e.global_position + Vector3(0, 0.64, -0.2))
	await _shot("saw")
	_aim(player.global_position + Vector3.UP * 1.6, _e.global_position + Vector3.UP * 0.7)
	await _shot("saw_from_player")
	get_tree().quit()
