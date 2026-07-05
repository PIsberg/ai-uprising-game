extends Node3D
## Windowed visual check: loads level_01, waits for it to build, forces the
## player invulnerable off, then applies damage from a marker placed 10m to the
## player's right (relative to camera yaw) — screenshots ~0.2s later to confirm
## the damage-direction arc renders pointing screen-right of the crosshair.
## Run: godot --path . --quit-after 900 res://tests/damage_dir_probe.tscn

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.5).timeout

	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null:
		print("NO PLAYER found")
		get_tree().quit()
		return
	player.hp.invulnerable = false

	# A Node3D 10m to the player's right (the same "right" the game itself uses:
	# the player body's own basis.x, since rotate_y is applied to the player).
	var right: Vector3 = player.global_transform.basis.x
	var src := Node3D.new()
	lvl.add_child(src)
	src.global_position = player.global_position + right.normalized() * 10.0

	player.hp.apply_damage(10.0, src)
	await get_tree().create_timer(0.2).timeout

	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad/damage_dir.png"
	img.save_png(path)
	print("SAVED ", path)
	get_tree().quit()
