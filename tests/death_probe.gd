extends Node
## Dev probe: load a level, kill the player, and confirm the fall-over + lockout
## + game-over flow. Run windowed:
##   godot --path . res://tests/death_probe.tscn

func _ready() -> void:
	if has_node("/root/GraphicsSettings"):
		get_node("/root/GraphicsSettings").set_quality(1)
	add_child((load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate())
	await get_tree().create_timer(1.6).timeout
	var pl := get_tree().get_first_node_in_group("player")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await _snap("death_alive.png")
	pl.hp.apply_damage(9999.0, null)
	await get_tree().create_timer(0.5).timeout
	await _snap("death_dying.png")
	await get_tree().create_timer(1.0).timeout
	await _snap("death_dead.png")
	var head := pl.get_node("Head") as Node3D
	var go := GameState.current_state == GameState.State.GAME_OVER
	print("DEATH dead=%s head_roll_deg=%.1f head_y=%.2f state_gameover=%s" % [
		str(pl.get("_dead")), rad_to_deg(head.rotation.z), head.position.y, str(go)])
	get_tree().quit()

func _snap(fname: String) -> void:
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname)
