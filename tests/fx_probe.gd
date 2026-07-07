extends Node3D
## Captures (1) the HUD showing the new HP / STA bar captions, and (2) the beefed
## grenade explosion mid-blast (fireball + fire column + double shockwave + sparks
## + debris + smoke).

const GREN_EXPLOSION := preload("res://scenes/fx/grenade_explosion.tscn")

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_neon.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var cam := player.find_child("Camera3D", true, false) as Camera3D

	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/fx_hud.png")
	print("HUD shot saved")

	var at := player.global_position + Vector3(2, 0.4, 7)
	cam.global_position = player.global_position + Vector3(-6, 2.6, -1)
	cam.look_at(at + Vector3(0, 1.2, 0), Vector3.UP)
	var fx := GREN_EXPLOSION.instantiate()
	lvl.add_child(fx)
	(fx as Node3D).global_position = at
	for i in 9: # peak fireball/column is ~0.15 s in
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/fx_explosion.png")
	print("EXPLOSION shot saved")
	print("FX_PROBE_DONE")
	get_tree().quit()
