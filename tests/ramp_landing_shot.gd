extends Node3D
## Windowed shot: a def ramp meeting its deck (gpt's vantage deck, the stairs
## up range's overwatch deck). Logic is pinned by tests/ramp_landing_probe.
##   godot --path . res://tests/ramp_landing_shot.tscn
## Saves user://ramp_landing_<id>.png (pass "-- tag=before" to change the suffix).

const CASES := [
	["gpt", Vector3(-31.0, 7.5, 33.0), Vector3(-18.5, 2.0, 24.5)],
	["range", Vector3(-22.0, 6.0, 27.0), Vector3(-12.0, 1.2, 42.0)],
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
		var path := "user://ramp_landing_%s%s.png" % [c[0], tag]
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path))
		lvl.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit(0)
