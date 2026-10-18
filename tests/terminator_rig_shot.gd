extends Node3D
## Windowed visual check for APEX ENDOFRAME's rig: a side view at four points
## of its stride, a front view mid-strafe, and the cannons aimed up and down
## at a marker. Driven off the rig's own state (preview mode, physics off).
## Headless gives black frames.
##   godot --path . res://tests/terminator_rig_shot.tscn -- --out=<abs dir>

var _out_dir := ""
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://terminator_rig_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String, cam: Vector3) -> void:
	_cam.global_position = cam
	_cam.look_at(Vector3(0, 1.1, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/terminator_%s.png" % [_out_dir, name])
	print("SHOT ", name)

## Holds the boss at `vel` for a few frames, its stride parked at `phase`.
func _hold(b: CharacterBody3D, vel: Vector3, phase: float) -> void:
	for f in 30:
		b.velocity = vel
		b.set("_stride_phase", phase)
		await get_tree().process_frame

func _run() -> void:
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
	key.light_energy = 1.4
	add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	add_child(_cam)
	_cam.make_current()

	var b := (load("res://scenes/enemies/terminator.tscn") as PackedScene).instantiate() as CharacterBody3D
	b.set("preview", true)
	add_child(b)
	await get_tree().create_timer(0.5).timeout
	for i in 4:
		await _hold(b, Vector3(0, 0, -6), i * TAU / 4.0 + 0.3)
		await _shot("stride_%d" % i, Vector3(6, 1.6, -0.5))
	await _hold(b, Vector3(5, 0, 0), 1.2)
	await _shot("strafe", Vector3(0.8, 1.8, -6))
	b.velocity = Vector3.ZERO
	await _hold(b, Vector3.ZERO, 0.0)
	var mark := Node3D.new()
	add_child(mark)
	b.set("target", mark)
	b.call("set_state", 4) # ATTACK (physics off: it neither moves nor fires)
	for aim in [["aim_up", Vector3(0, 8, -8)], ["aim_down", Vector3(0, -4.5, -8)]]:
		mark.global_position = aim[1]
		await get_tree().create_timer(1.0).timeout
		await _shot(aim[0], Vector3(5, 1.8, -2.5))
	get_tree().quit()
