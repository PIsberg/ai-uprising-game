extends Node3D
## Windowed visual check for a level's pendulum gantry (LAVA WORLD's first,
## on the west walkway, by default): the gantry from 6 m up its walkway while
## the sign reads WAIT (the blade swinging through) and while it reads GO.
## Headless gives black frames.
##   godot --path . res://tests/pendulum_blade_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "lava_world"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://pendulum_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/pendulum_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep every robot (late spawns too) out of the frame and out of the fight.
func _still() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

## Step physics until `cond` holds.
func _until(cond: Callable) -> void:
	while not cond.call():
		await get_tree().physics_frame
		_still()

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	_still()
	var pb := lvl.find_children("*", "PendulumBlade", true, false)[0] as PendulumBlade
	var path := Vector3.BACK if pb.path_axis == "z" else Vector3.RIGHT
	# The player stands short of the cut on the walkway, so the sign reads for them.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = pb.global_position - path * 3.0 + Vector3.UP * 0.1
	player.set_physics_process(false)
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = pb.global_position - path * 6.0 + Vector3.UP * 1.8
	cam.look_at(pb.global_position + Vector3.UP * 1.6)
	await _until(func() -> bool: return pb.sign_text() == "WAIT" and absf(pb.angle_at(pb.get("_t"))) < 15.0)
	await _shot("wait")
	await _until(func() -> bool: return pb.sign_text() == "GO")
	await _shot("go")
	print("RESULT PASS")
	get_tree().quit()
