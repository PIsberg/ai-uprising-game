extends Node3D
## Windowed visual check for BEHEMOTH-X's limbs: a side view at four points of
## its stride, then a front three-quarter view of each attack beat (smash
## reared and struck, slam overhead and pounded, rake cocked and swept). The
## beats are held by setting their timers each frame, so physics stays off.
## Headless gives black frames.
##   godot --path . res://tests/smasher_pose_shot.tscn -- --out=<abs dir>

const BEATS := [
	["smash_up", "_smash_windup_t", ""], ["smash_down", "_strike_t", "smash"],
	["slam_up", "_slam_windup_t", ""], ["slam_down", "_strike_t", "slam"],
	["rake_back", "_rake_windup_t", ""], ["rake_sweep", "_rake_lunge_t", ""],
]

var _out_dir := ""
var _cam: Camera3D

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://smasher_pose_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String, cam: Vector3) -> void:
	_cam.global_position = cam
	_cam.look_at(Vector3(0, 5.5, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/smasher_%s.png" % [_out_dir, name])
	print("SHOT ", name)

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
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 1.4
	add_child(key)
	var floor_mesh := MeshInstance3D.new() # visual only: no collision to land on
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 60.0
	add_child(_cam)
	_cam.make_current()

	var b := (load("res://scenes/enemies/smasher.tscn") as PackedScene).instantiate() as CharacterBody3D
	b.set("preview", true) # no entrance, no AI, physics off
	add_child(b)
	await get_tree().create_timer(0.5).timeout
	# The stride, driven straight off its phase at full amplitude.
	for i in 4:
		b.set("_gait_phase", i * TAU / 4.0 + 0.2)
		b.set("_gait_amp", 1.0)
		await get_tree().process_frame
		await _shot("stride_%d" % i, Vector3(16, 6, -4))
	b.set("_gait_amp", 0.0)
	for beat in BEATS:
		for f in 40:
			b.set(beat[1], 0.3)
			b.set("_strike_kind", beat[2])
			await get_tree().process_frame
		await _shot(beat[0], Vector3(12, 7, -14))
		b.set(beat[1], 0.0)
		for f in 40:
			await get_tree().process_frame
	get_tree().quit()
