extends Node3D
## Windowed visual check for the ORBITAL STRIKE event on a level (GPT's
## foundry by default): the amber circle tracking the player, the circle
## locked red, and the column of light firing, from beside the player.
## Headless gives black frames.
##   godot --path . res://tests/orbital_strike_shot.tscn -- --out=<abs dir> [--level=<id>]

var _out_dir := ""
var _level := "gpt"

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://orbital_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--level="):
			_level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node3D).visible = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/orbital_%s_%s.png" % [_out_dir, _level, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % _level) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.get_node("Damageable").set("invulnerable", true)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var s := OrbitalStrike.new()
	lvl.add_child(s)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	cam.global_position = player.global_position + Vector3(6.0, 3.5, 6.0)
	cam.look_at(player.global_position + Vector3.UP * 1.0)
	for i in 120:
		await get_tree().physics_frame
	await _shot("tracking")
	while s.phase != OrbitalStrike.Phase.LOCK or s._t < OrbitalStrike.LOCK_TIME * 0.6:
		await get_tree().physics_frame
	await _shot("locked")
	while s.phase != OrbitalStrike.Phase.FIRE:
		await get_tree().physics_frame
	for i in 4:
		await get_tree().physics_frame
	await _shot("fire")
	print("RESULT PASS")
	get_tree().quit()
