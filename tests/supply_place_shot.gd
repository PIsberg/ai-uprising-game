extends Node3D
## Windowed shot: supplies the pickup sweep moved (the range's gun rack with the
## Cascade and the OMEGA inside the room, lava_world's dais medkit, desert's
## tower-foot medkit). Logic is pinned by tests/task_reach_probe.
##   godot --path . res://tests/supply_place_shot.tscn
## Saves user://supply_place_<id>.png (pass "-- tag=before" to change the suffix).

const CASES := [
	["range", Vector3(-24.0, 3.2, 32.5), Vector3(8.0, 0.4, 29.4)],
	["lava_world", Vector3(9.0, 6.5, 10.0), Vector3(1.5, 1.8, 1.5)],
	["desert", Vector3(-8.5, 2.2, 9.5), Vector3(-2.8, 1.0, 12.6)],
]

func _ready() -> void:
	var tag := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("tag="):
			tag = "_" + a.substr(4)
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	for c: Array in CASES:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % c[0]) as PackedScene).instantiate()
		add_child(lvl)
		var hp := lvl.find_child("Damageable", true, false)
		if hp:
			hp.set("invulnerable", true)
		for i in 120:
			await get_tree().process_frame
		cam.global_position = c[1]
		cam.look_at(c[2], Vector3.UP)
		cam.make_current()
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "user://supply_place_%s%s.png" % [c[0], tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit(0)
