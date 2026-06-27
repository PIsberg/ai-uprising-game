extends Node3D
## High-angle look at the new themed rivers to confirm the serpentine + the gap.
## Run windowed: godot --path . --quit-after 1400 res://tests/river_view.tscn

const IDS := ["grok", "alien", "neon"]
var _cam: Camera3D

func _ready() -> void:
	_cam = Camera3D.new(); _cam.current = true; _cam.fov = 60.0
	add_child(_cam)
	for id in IDS:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		var pd := lvl.find_child("Damageable", true, false)
		if pd: pd.invulnerable = true
		await get_tree().create_timer(2.2).timeout
		var pc := lvl.find_child("Camera3D", true, false) as Camera3D
		if pc: pc.current = false
		_cam.current = true
		_cam.global_position = Vector3(0, 34, 30)
		_cam.look_at(Vector3(0, 0, 0), Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/river_%s.png" % id)
		print("SHOT ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("RIVER_VIEW_DONE")
	get_tree().quit()
