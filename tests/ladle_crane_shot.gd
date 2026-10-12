extends Node3D
## Windowed visual check for The Crucible's ladle crane: the crane over the
## foundry floor, the ladle tilting over the warning ring on the player, the
## pour, and the molten pool it leaves. Headless gives black frames.
##   godot --path . res://tests/ladle_crane_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://ladle_crane_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	_still()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/ladle_%s.png" % [_out_dir, name])
	print("SHOT ", name)

## Keep every robot (late spawns too) out of the frame's action.
func _still() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_crucible.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var crane := lvl.find_children("*", "LadleCrane", true, false)[0] as LadleCrane
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.global_position = Vector3(18.0, 0.2, 8.0)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var hp: Node = player.get_node("Damageable")
	hp.set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = Vector3(30.0, 8.6, -4.0)
	cam.look_at(Vector3(18.0, 2.0, 8.0))
	await _shot("crane")
	var t := 0.0
	while t < 12.0 and not crane.aiming:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_still()
	t = 0.0
	while t < 0.9:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_still()
	await _shot("aim")
	while crane.aiming:
		await get_tree().physics_frame
	await get_tree().physics_frame
	await _shot("pour")
	t = 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_still()
	await _shot("pool")
	cam.global_position = Vector3(25.0, 3.5, 2.0)
	cam.look_at(Vector3(18.0, 0.0, 8.0))
	await _shot("pool_close")
	print("RESULT PASS")
	get_tree().quit()
