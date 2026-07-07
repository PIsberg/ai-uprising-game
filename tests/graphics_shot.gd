extends Node3D
## Clean first-person gameplay captures at ULTRA, from the player's own camera,
## across a few visually distinct levels — a baseline to judge graphics against.
## Run windowed: godot --path . --quit-after 100000 res://tests/graphics_shot.tscn

# level id -> a scenic vantage {pos, look_at} to frame architecture + enemies.
const SHOTS := [
	{"id": "sublevel","pos": Vector3(-9, 1.7, -9),   "look": Vector3(9, 1.6, 10)},
	{"id": "neon",    "pos": Vector3(-8, 1.7, -6),   "look": Vector3(10, 1.5, 10)},
]

func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs:
		gs.set_quality(gs.Quality.HIGH) # the default gameplay tier — what players actually see (applies viewport internally)
		gs.set_render_scale(1.0)
	var tag := str(OS.get_environment("SHOT_TAG"))
	if tag == "": tag = "base"
	print("PROBE: gs applied, starting")
	for s in SHOTS:
		var id: String = s["id"]
		print("PROBE: loading ", id)
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		print("PROBE: added ", id, " waiting")
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg: pdmg.invulnerable = true
		await get_tree().create_timer(2.0).timeout # build + navmesh + GI bake + auto-exposure settle
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var cam := lvl.find_child("Camera3D", true, false) as Camera3D
		if player:
			player.global_position = s["pos"] + Vector3(0, 0.2, 0)
		if cam:
			cam.current = true
			cam.global_position = s["pos"]
			cam.look_at(s["look"], Vector3.UP)
		for i in range(30): # let auto-exposure adapt to the new view
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/gfx_%s_%s.png" % [id, tag])
		print("SHOT ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("GRAPHICS_SHOT_DONE dir=", OS.get_user_data_dir(), " tag=", tag)
	get_tree().quit()
