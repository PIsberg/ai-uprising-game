extends Node3D
## Windowed visual check for a level's hidden transmitter (the Hollow's cloak
## emitter by default): from 9 m at eye height while hidden (a dark box among
## the dressing, LED mid-ping), then revealed (aerial up, red beacon).
## Headless gives black frames.
##   godot --path . res://tests/signal_hunt_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "alien"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://signal_hunt_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/signal_hunt_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 40:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.global_position = Vector3(0, 10, 0)
	var st := lvl.find_children("*", "SignalTransmitter", true, false)[0] as SignalTransmitter
	st.set_physics_process(false)
	var at := st.global_position
	var toward := (Vector3.ZERO - at)
	toward.y = 0.0
	toward = toward.normalized()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 60.0
	cam.global_position = at + toward * 9.0 + Vector3.UP * 1.6
	cam.look_at(at + Vector3.UP * 0.6)
	for i in 10:
		await get_tree().process_frame
	st._ping(3)
	await get_tree().process_frame
	await _shot("hidden")
	st.reveal()
	for i in 40:
		await get_tree().process_frame
	await _shot("revealed")
	print("RESULT PASS")
	get_tree().quit()
