extends Node3D
## Windowed visual check for the RETURNER elite: a real android elite in a lit
## room, first idle (magenta ring marker), then mid-wind-up holding a caught
## frag (the glowing magenta charge). Headless gives black frames.
##   godot --path . res://tests/returner_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://returner_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/returner_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
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
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	var player := Node3D.new()
	player.add_to_group("player")
	player.position = Vector3(0, 0, 12)
	add_child(player)
	var e := (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate() as EnemyBase
	Elite.apply(e, "returner")
	add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 50.0
	cam.global_position = Vector3(0, 1.8, 5.0)
	cam.look_at(Vector3(0, 1.5, 0))
	for i in 20:
		await get_tree().process_frame
	await _shot("idle")
	var r := e.get_node("GrenadeReturner") as GrenadeReturner
	r.set_physics_process(false)
	var g := (load("res://scenes/weapons/grenade.tscn") as PackedScene).instantiate() as Grenade
	add_child(g)
	g.global_position = Vector3(1, 0.4, 2)
	r._catch(g)
	r._t = GrenadeReturner.WINDUP * 0.6
	r.set_physics_process(true)
	await get_tree().physics_frame
	r.set_physics_process(false)
	for i in 3:
		await get_tree().process_frame
	await _shot("windup")
	print("RESULT PASS")
	get_tree().quit()
