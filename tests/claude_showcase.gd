extends Node
## Dev probe: loads the Claude vault showcase, captures a few framed views of
## the new centrepiece / lighting, then quits. Run WINDOWED (headless renders
## black):
##   godot --path . res://tests/claude_showcase.tscn

func _ready() -> void:
	var lv: PackedScene = load("res://scenes/levels/level_claude.tscn")
	add_child(lv.instantiate())
	# Let the VoxelGI bake, reflection probe capture and emissive tweens settle.
	await get_tree().create_timer(2.0).timeout
	# Make the camera-stand-in immortal so no damage vignette taints the shots.
	var pl := get_tree().get_first_node_in_group("player")
	if pl and pl.has_node("Damageable"):
		pl.get_node("Damageable").invulnerable = true

	# Wide establishing shot from the entry corner toward the lit core.
	_pose(Vector3(-18, 4.0, -18), deg_to_rad(-135))
	await get_tree().create_timer(0.4).timeout
	await _snap("claude_overview.png")

	# Close on the constitution-core monolith from the -Z axis (its broad face).
	_pose(Vector3(0.5, 2.2, -9), deg_to_rad(180))
	await get_tree().create_timer(0.3).timeout
	await _snap("claude_core.png")

	# Reverse establishing shot from the exit corner: the whole arena's density.
	_pose(Vector3(16, 4.0, 16), deg_to_rad(45))
	await get_tree().create_timer(0.3).timeout
	await _snap("claude_arena.png")

	get_tree().quit()

func _clear_enemies() -> void:
	# Trigger-spawned robots keep appearing as the camera moves; clearing right
	# before each frame keeps damage vignettes out of the architecture shots.
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()

func _pose(pos: Vector3, yaw: float) -> void:
	_clear_enemies()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		player.global_position = pos
		player.rotation.y = yaw

func _snap(fname: String) -> void:
	_clear_enemies()
	await get_tree().create_timer(0.1).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname)
