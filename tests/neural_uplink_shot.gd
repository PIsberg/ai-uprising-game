extends Node3D
## Windowed visual check for the NEURAL UPLINK chase camera: on Level 01, a
## hijacked android near the spawn is ridden and the frame is captured from the
## uplink camera (green tint, ride HUD, the chassis in front of the crosshair),
## then once more after walking it a few metres. Headless gives black frames.
##   godot --path . res://tests/neural_uplink_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://uplink_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/uplink_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 60:
		await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	player.get_node("Damageable").set("invulnerable", true)
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node3D).visible = false
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var fwd := -player.global_transform.basis.z
	var r: EnemyBase = load("res://scenes/enemies/android.tscn").instantiate()
	add_child(r)
	r.global_position = player.global_position + fwd * 5.0
	r.rotation.y = player.rotation.y
	for i in 10:
		await get_tree().physics_frame
	r.hijack(60.0, player)
	var uplink := player.get_node("NeuralUplink") as NeuralUplink
	uplink.begin(r)
	for i in 30:
		await get_tree().process_frame
	await _shot("ride")
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 10:
		await get_tree().process_frame
	await _shot("walked")
	get_tree().quit()
