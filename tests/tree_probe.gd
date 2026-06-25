extends Node3D
## Capture the suburb level (now with scattered volumetric trees) from eye level
## to judge the trees in-context. Windowed:  godot --path . tests/tree_probe.tscn

func _ready() -> void:
	var lvl := preload("res://scenes/levels/level_suburb.tscn").instantiate()
	add_child(lvl)
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.set("invulnerable", true)
	await get_tree().create_timer(2.5).timeout
	var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var cam := Camera3D.new()
	cam.fov = 75.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.4
	cam.attributes = ca
	add_child(cam)
	cam.global_position = Vector3(-14, 2.0, -14)
	cam.current = true
	cam.look_at(Vector3(8, 1.0, 8), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/tree_scene.png")
	print("SAVED tree_scene")
	get_tree().quit()
