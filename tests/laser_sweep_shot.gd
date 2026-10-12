extends Node3D
## Windowed visual check for a level's laser sweep (GROK's mainframe by
## default, or `--level=claude` for the vault's decrypt zone): the two beams
## (knee and chest height) spinning, from the room and from above.
## Headless gives black frames.
##   godot --path . res://tests/laser_sweep_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "grok"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://laser_sweep_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/sweep_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep every robot (late spawns too) out of the frame and out of the fight.
func _still() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var sweep := lvl.find_children("*", "LaserSweep", true, false)[0] as LaserSweep
	sweep.wakes_on = "" # as if its wake task were done
	sweep.call("_check_tasks")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = sweep.global_position + Vector3(0, 0, -30)
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var at := sweep.global_position
	cam.global_position = at + Vector3(6.5, 1.1, -6.5)
	cam.look_at(at + Vector3(0, 0.8, 0))
	for k in 2:
		var t := 0.0
		while t < 1.1:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			_still()
		await _shot("room_%d" % k)
	cam.global_position = at + Vector3(0.01, 5.5, 0) # under an indoor ceiling too
	cam.look_at(at)
	await _shot("above")
	print("RESULT PASS")
	get_tree().quit()
