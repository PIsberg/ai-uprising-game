extends Node3D
## Windowed visual check for TITAN's zipline: the cable from the south-west
## deck up to the east tower, the tower-top station, and the view down the
## cable from the tower. Headless gives black frames.
##   godot --path . res://tests/zipline_shot.tscn -- --out=<abs dir>

var _out_dir := ""

func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("user://zipline_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run.call_deferred()

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/zip_%s.png" % [_out_dir, name])
	print("SHOT ", name)

func _run() -> void:
	var lvl: Node3D = (load("res://scenes/levels/level_titan.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().process_frame
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
		(e as Node3D).visible = false
	var zl := lvl.find_children("*", "ZipLine", true, false)[0] as ZipLine
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.get_node("Damageable").set("invulnerable", true)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 65.0
	var flat := Vector3(zl.a.x - zl.b.x, 0, zl.a.z - zl.b.z).normalized()
	cam.global_position = zl.b - flat * 3.0 + Vector3.UP * 2.0 + flat.cross(Vector3.UP) * 2.5
	cam.look_at(zl.a + Vector3.UP * 2.0)
	await _shot("from_deck")
	cam.global_position = zl.a + flat * 3.0 + Vector3.UP * 2.2
	cam.look_at(zl.a + Vector3.UP * 1.5)
	await _shot("tower_station")
	cam.global_position = zl.a + Vector3.UP * 1.7 - flat * 0.5
	cam.look_at(zl.b + Vector3.UP * 1.0)
	await _shot("down_the_cable")
	print("RESULT PASS")
	get_tree().quit()
