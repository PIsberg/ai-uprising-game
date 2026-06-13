extends Node
## Dev probe: loads the suburb level, walks the player camera up to a house and
## captures user://suburb_house.png, then quits. Run windowed:
##   godot --path . res://tests/suburb_screenshot.tscn

func _ready() -> void:
	var lv: PackedScene = load("res://scenes/levels/level_suburb.tscn")
	add_child(lv.instantiate())
	await get_tree().create_timer(1.6).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		player.global_position = Vector3(-20, 0.1, -4)
		player.rotation.y = 0.0 # face -Z, toward the house row at z = -15
	await get_tree().create_timer(0.4).timeout
	_snap("suburb_house.png")
	if player:
		player.global_position = Vector3(-20, 1.2, -15) # inside house 1
		player.rotation.y = PI # face +Z, back toward the street
	await get_tree().create_timer(0.3).timeout
	_snap("suburb_inside.png")
	get_tree().quit()

func _snap(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname)
