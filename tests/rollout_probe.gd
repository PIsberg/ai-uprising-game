extends Node
## Dev probe: loads several rolled-out levels in turn and captures one framed
## centre/hero shot of each. Run WINDOWED (headless renders black):
##   godot --path . res://tests/rollout_probe.tscn

# scene id -> camera pos (world space, post WORLD_SCALE) + yaw facing the centre
const SHOTS := [
	{"id": "gpt", "pos": Vector3(-16, 5, -16), "yaw": -135.0},
	{"id": "mistral", "pos": Vector3(-17, 5, -17), "yaw": -135.0},
	{"id": "gemini", "pos": Vector3(-18, 6, -18), "yaw": -135.0},
	{"id": "titan", "pos": Vector3(-22, 7, -22), "yaw": -135.0},
	{"id": "grok", "pos": Vector3(-20, 6, -20), "yaw": -135.0},
]

func _ready() -> void:
	for shot in SHOTS:
		var lv: PackedScene = load("res://scenes/levels/level_%s.tscn" % shot["id"])
		var inst := lv.instantiate()
		add_child(inst)
		await get_tree().create_timer(1.8).timeout
		_clear_enemies()
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_node("Damageable"):
			pl.get_node("Damageable").invulnerable = true
		if pl:
			(pl as Node3D).global_position = shot["pos"]
			(pl as Node3D).rotation.y = deg_to_rad(shot["yaw"])
		await get_tree().create_timer(0.4).timeout
		_clear_enemies()
		await get_tree().create_timer(0.15).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/rollout_%s.png" % shot["id"])
		print("SAVED rollout_%s.png" % shot["id"])
		inst.queue_free()
		await get_tree().process_frame
	get_tree().quit()

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
