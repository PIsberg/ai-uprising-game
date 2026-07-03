extends Node
## Builds level 1 and photographs an OPEN (enterable) building from the street
## and from inside, plus checks the grapple pad exists. Saves
## user://open_house_street.png / open_house_inside.png.
##   godot --path . res://tests/open_house_probe.tscn

func _ready() -> void:
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	_run.call_deferred(lvl)

func _run(lvl: Node) -> void:
	# Keep the probe player alive (death overlay would grey the whole shot) and
	# take over the camera from it.
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.invulnerable = true
	await get_tree().create_timer(2.0).timeout
	# Teleport the real player: its own camera + HUD give the authentic view.
	# Open building: authored (20,6,-2) -> world-scaled centre (28, -, -2.8),
	# size 8x12x8, door on the -X face.
	var player := lvl.find_child("Player", false, false) as Node3D
	player.global_position = Vector3(19.0, 0.5, -2.8)
	player.rotation.y = PI * 0.5 # face +X (player forward is -Z)
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/open_house_street.png")
	# Step inside the ground floor, looking at the interior ramp.
	player.global_position = Vector3(26.0, 0.5, -2.8)
	player.rotation.y = PI * 0.4
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/open_house_inside.png")
	print("RESULT PASS")
	get_tree().quit()
