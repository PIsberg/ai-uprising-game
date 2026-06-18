extends Node
## Dev probe: load a campaign level and capture eye-level views to judge (and
## iterate on) environmental detail. Pass the level scene + a tag after `--`:
##   godot --path . res://tests/level_detail_probe.tscn -- res://scenes/levels/level_gpt.tscn gpt

func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var scene_path := "res://scenes/levels/level_gpt.tscn"
	var tag := "lvl"
	if argv.size() >= 1: scene_path = argv[0]
	if argv.size() >= 2: tag = argv[1]
	# Force max detail so density-gated dressing (incl. the facility pass) builds.
	if has_node("/root/GraphicsSettings"):
		get_node("/root/GraphicsSettings").set_quality(2) # HIGH
	var level: Node = (load(scene_path) as PackedScene).instantiate()
	add_child(level)
	await get_tree().create_timer(2.0).timeout
	var pl := get_tree().get_first_node_in_group("player")
	if pl and pl.has_node("Damageable"):
		pl.get_node("Damageable").invulnerable = true

	var def: Dictionary = LevelDefs.get_def(level.level_id) if "level_id" in level else {}
	var fs: Vector2 = def.get("floor_size", Vector2(50, 50))
	var hx: float = fs.x * 0.5
	var hz: float = fs.y * 0.5

	# Corner, eye level, looking diagonally across the room.
	_pose(Vector3(-hx + 4, 1.8, -hz + 4), deg_to_rad(-135))
	await get_tree().create_timer(0.4).timeout
	await _snap(tag + "_corner.png")
	# Mid-room, looking toward a side wall (shows wall + ceiling + floor detail).
	_pose(Vector3(0, 1.8, hz * 0.3), deg_to_rad(180))
	await get_tree().create_timer(0.3).timeout
	await _snap(tag + "_room.png")
	# Low angle near floor, catches floor + low-prop detail.
	_pose(Vector3(hx * 0.4, 1.2, hz * 0.4), deg_to_rad(200))
	await get_tree().create_timer(0.3).timeout
	await _snap(tag + "_floor.png")
	# Close on a wall: shows wall fittings (vents/boxes/panels/conduit) + the floor
	# hazard chevrons inset from it.
	_pose(Vector3(0, 1.8, -hz + 7), deg_to_rad(0))
	await get_tree().create_timer(0.3).timeout
	await _snap(tag + "_wall.png")
	# Top-down ortho to verify floor + perimeter detail (chevrons) read.
	_clear_enemies()
	var topcam := Camera3D.new()
	topcam.projection = Camera3D.PROJECTION_ORTHOGONAL
	topcam.size = maxf(fs.x, fs.y) * 1.05
	add_child(topcam)
	topcam.look_at_from_position(Vector3(0, 70, 0.01), Vector3.ZERO, Vector3.FORWARD)
	topcam.current = true
	await get_tree().create_timer(0.3).timeout
	await _snap(tag + "_top.png")
	get_tree().quit()

func _clear_enemies() -> void:
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
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/" + fname)
	print("SAVED ", fname)
