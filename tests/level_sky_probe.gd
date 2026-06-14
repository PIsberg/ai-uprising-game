extends Node
## Dev probe: loads a real open-sky night level and captures the horizon/sky so
## the in-context night "heaven" (gradient + stars + moon) can be verified. Run
## WINDOWED (headless renders black):
##   godot --path . res://tests/level_sky_probe.tscn

const LEVEL := "res://scenes/levels/level_titan.tscn"

func _ready() -> void:
	add_child((load(LEVEL) as PackedScene).instantiate())
	await get_tree().create_timer(2.0).timeout
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl and pl.has_node("Damageable"):
		pl.get_node("Damageable").invulnerable = true
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	if pl:
		# Stand tall and tilt the view up so the dome fills the frame.
		pl.global_position = Vector3(0, 8, 0)
		pl.rotation.y = 0.6
		var cam := pl.get_viewport().get_camera_3d()
		if cam:
			cam.rotation_degrees.x = 18.0
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/level_sky_titan.png")
	print("SAVED level_sky_titan.png")
	get_tree().quit()
