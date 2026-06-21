extends Node3D
## In-game playtest of the new content: loads the real Custodial Sublevel,
## captures the player view, switches to the new weapons, and forces a Custodian
## to rise in front of the camera. Screenshots each step, then quits.
## Run (windowed): godot --path . tools/playtest.tscn

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/%s.png" % name)
	print("SHOT ", name)


func _ready() -> void:
	var lvl: Node = load("res://scenes/levels/level_sublevel.tscn").instantiate()
	add_child(lvl)
	# Let LevelBuilder construct geometry, spawn enemies, bake navmesh.
	await get_tree().create_timer(2.5).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_shot("pt1_level")

	var cam := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player")
	var wm: Node = null
	if player:
		wm = player.find_child("WeaponHolder", true, false)

	# Show the two new weapons in hand.
	if wm and "weapons" in wm:
		var names := []
		for w in wm.weapons:
			names.append(w.name)
		print("LOADOUT: ", names)
		if wm.has_method("_equip"):
			wm._equip(2) # magnum
			await get_tree().create_timer(0.6).timeout
			_shot("pt2_magnum")
			wm._equip(1) # sniper
			await get_tree().create_timer(0.6).timeout
			_shot("pt3_sniper")

	# Drop a Custodian right in front of the camera and make it stand up.
	var enemies := []
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		if n.is_in_group("enemy"):
			enemies.append(n.name)
	print("ENEMIES PRESENT: ", enemies)
	var vac := _find_enemy(get_tree().root, "Vacuum")
	if vac and cam:
		vac.global_position = cam.global_position - cam.global_transform.basis.z * 6.0
		vac.global_position.y = 0.0
		await get_tree().create_timer(0.3).timeout
		_shot("pt4_custodian_disc")
		if vac.has_method("_begin_rise"):
			vac._begin_rise()
		await get_tree().create_timer(1.8).timeout
		_shot("pt5_custodian_risen")
	else:
		print("no vacuum found")

	get_tree().quit()


func _find_enemy(root: Node, cls: String) -> Node:
	for n in root.find_children("*", "CharacterBody3D", true, false):
		if n.name.begins_with(cls):
			return n
	return null
