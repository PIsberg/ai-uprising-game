extends Node
const TYPES := ["skitter", "android", "skitter", "raptor", "skitter"]
func _ready() -> void:
	GameState.unlock_all_weapons()
	add_child((load("res://scenes/levels/level_suburb.tscn") as PackedScene).instantiate())
	_run.call_deferred()
func _run() -> void:
	await get_tree().create_timer(1.3).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		if player.hp: player.hp.invulnerable = true
		var fwd := -player.global_transform.basis.z
		var right := player.global_transform.basis.x
		for i in TYPES.size():
			var scn: PackedScene = LevelBuilder.ENEMY_SCENES.get(TYPES[i])
			if scn == null: continue
			var e: Node3D = scn.instantiate(); add_child(e)
			e.global_position = player.global_position + fwd * (9.0 + i * 1.5) \
				+ right * float(i - 2) * 2.6 + Vector3(0, 0.5, 0)
	await get_tree().create_timer(1.7).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var th := int(round(1600.0 * img.get_height() / float(img.get_width())))
	img.resize(1600, th, Image.INTERPOLATE_LANCZOS)
	img.save_png("res://docs/screenshots/ingame_suburb.png")
	print("SAVED ingame_suburb 1600x", th)
	get_tree().quit()
