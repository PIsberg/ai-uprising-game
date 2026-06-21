extends Node
## Dev probe: loads the rebuilt level 1, lets it build + bake, then captures an
## overhead layout shot and a player-eye shot toward the nexus tower to
## user://level01_*.png, then quits. Run windowed:
##   godot --path . res://tests/level01_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ps: PackedScene = load("res://scenes/levels/level_01.tscn")
	var lvl := ps.instantiate()
	get_tree().root.add_child(lvl)
	await _wait(1.2) # let the builder finish + navmesh bake

	# Player-eye shot: stand at the spawn, look toward the tower.
	var cam := Camera3D.new()
	cam.fov = 70.0
	lvl.add_child(cam)
	cam.global_position = Vector3(-22, 6.0, -22)
	cam.look_at(Vector3(7, 6.0, 14), Vector3.UP)
	cam.current = true
	await _wait(0.4)
	await _save("level01_eye")

	# Overhead layout shot.
	cam.global_position = Vector3(0, 62, 2)
	cam.look_at(Vector3(0, 0, 2), Vector3.FORWARD)
	cam.fov = 60.0
	await _wait(0.4)
	await _save("level01_top")
	get_tree().quit()

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_user_data_dir() + "/%s.png" % name
	img.save_png(path)
	print("SAVED ", path)
