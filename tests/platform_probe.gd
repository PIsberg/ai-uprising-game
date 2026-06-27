extends Node3D
## Frames the new vantage platform + ramp corner of a couple levels to confirm
## they built, sit on the floor, and have a reachable ramp + nearby holo signs.
## Run windowed: godot --path . --quit-after 1200 res://tests/platform_probe.tscn

const CASES := [
	["gpt", Vector3(-13.2, 3, 13)],
	["neon", Vector3(-13.2, 3, 13)],
]
var _cam: Camera3D

func _ready() -> void:
	_cam = Camera3D.new(); _cam.current = true; _cam.fov = 70.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true; ca.auto_exposure_scale = 0.4
	_cam.attributes = ca
	add_child(_cam)
	for c in CASES:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % c[0]) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg: pdmg.invulnerable = true
		await get_tree().create_timer(2.2).timeout
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam: pcam.current = false
		_cam.current = true
		var tgt: Vector3 = c[1]
		# stand back from the platform corner, slightly above, looking at it
		_cam.global_position = tgt + Vector3(9, 4, -9)
		_cam.look_at(tgt, Vector3.UP)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/plat_%s.png" % c[0])
		print("SHOT ", c[0])
		lvl.queue_free()
		await get_tree().process_frame
	print("PLATFORM_PROBE_DONE")
	get_tree().quit()
