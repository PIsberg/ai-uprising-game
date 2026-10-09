extends Node3D
## Windowed visual check for leaked robot reasoning: an android spots the camera
## at 9 m and a second one at 20 m gets an EMP; frames once both are typed out.
## Headless gives black frames.
##   godot --path . res://tests/reasoning_trace_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://reasoning_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(80, 1, 80)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.7, 0)
	cam.look_at(Vector3(0, 1.4, -10), Vector3.UP)
	cam.current = true
	var near: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(near)
	near.global_position = Vector3(-1.5, 0, -9)
	var far: EnemyBase = (load("res://scenes/enemies/mech.tscn") as PackedScene).instantiate()
	add_child(far)
	far.global_position = Vector3(4, 0, -20)
	for i in 6:
		await get_tree().create_timer(0.2).timeout
	near.set_state(EnemyBase.State.CHASE)
	far.emp_disable(3.0)
	for i in 5:
		await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("reasoning_trace.png"))
	print("RESULT PASS")
	get_tree().quit()
