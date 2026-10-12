extends Node3D
## Windowed visual check for a level's floor saws (the Assembly's north gap by
## default): both slots from the approach, at two moments of the blades' runs,
## and a low close-up of one blade. Headless gives black frames.
##   godot --path . res://tests/floor_saw_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "assembly"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://floor_saw_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/saw_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

## Keep every robot (late spawns too) out of the frame and out of the fight.
func _still() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

func _wait(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		_still()

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	_still()
	var saws := lvl.find_children("*", "FloorSaw", true, false)
	var a := saws[0] as FloorSaw
	var b := saws[min(1, saws.size() - 1)] as FloorSaw
	var span: Vector3 = a.span
	var mid := (a.global_position + b.global_position) * 0.5 + span * 0.5
	var across := span.normalized().cross(Vector3.UP)
	# Stand the player in the second slot's lane so its warning fires in frame.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.get_node("Damageable").set("invulnerable", true)
	player.global_position = b.global_position + span * 0.5 + Vector3.UP * 0.1
	player.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var side := signf((mid - b.global_position).dot(across))
	cam.global_position = mid - across * side * 8.0 + Vector3.UP * 2.2
	cam.look_at(mid + Vector3.UP * 0.3)
	await _wait(0.6)
	await _shot("approach_0")
	await _wait(1.3)
	await _shot("approach_1")
	var blade := a.blade_position()
	cam.global_position = blade + across * 2.6 + Vector3.UP * 0.9 - span.normalized() * 1.2
	cam.look_at(blade + Vector3.UP * 0.2)
	await RenderingServer.frame_post_draw
	await _shot("blade")
	print("RESULT PASS")
	get_tree().quit()
