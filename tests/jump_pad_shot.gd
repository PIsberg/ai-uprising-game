extends Node3D
## Windowed visual check for NEON ARCADE's jump pads: the pad under the tower,
## then the player mid-throw onto the tower roof from the side. Headless gives
## black frames.
##   godot --path . res://tests/jump_pad_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://jump_pad_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/pad_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_neon.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var pads := lvl.find_children("*", "JumpPad", true, false)
	var tower_pad: JumpPad = pads[0]
	for p in pads:
		if (p as JumpPad).to.y > tower_pad.to.y:
			tower_pad = p
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 70.0
	var at := tower_pad.global_position
	cam.global_position = at + Vector3(-7.0, 2.5, 6.0)
	cam.look_at(at + Vector3(0, 2.0, -6.0))
	await _shot("pad")
	cam.global_position = at + Vector3(-14.0, 6.0, -6.0)
	cam.look_at(at + Vector3(0, 5.0, -8.0))
	player.global_position = at + Vector3.UP * 0.2
	var t := 0.0
	while t < 0.55:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _shot("flight")
	while t < 1.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	await _shot("landed")
	print("RESULT PASS")
	get_tree().quit()
