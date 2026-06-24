extends Node
## Promo: the first sky-drop boss — GOLIATH-IX (Colossus) making planetfall on its
## retro-rockets over Maple Grove Plaza. Saves docs/screenshots/sky_boss.png
func _ready() -> void:
	add_child((load("res://scenes/levels/level_suburb_boss.tscn") as PackedScene).instantiate())
	_run.call_deferred()

func _run() -> void:
	await get_tree().create_timer(1.2).timeout
	var land := Vector3(22, 0.5, 22)
	var boss: Node3D = (load("res://scenes/enemies/colossus.tscn") as PackedScene).instantiate()
	boss.position = land                 # set BEFORE add_child so _ready bumps it +44 m up
	add_child(boss)
	var cam := Camera3D.new()
	cam.fov = 64.0
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 4.0, 44)
	await get_tree().create_timer(0.95).timeout   # mid-descent, thrusters blazing
	cam.look_at(boss.global_position + Vector3(0, 0.5, 0), Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var th := int(round(1600.0 * img.get_height() / float(img.get_width())))
	img.resize(1600, th, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://docs/screenshots/sky_boss.png")
	print("SAVED sky_boss boss_y=%.1f 1600x%d" % [boss.global_position.y, th])
	get_tree().quit()
