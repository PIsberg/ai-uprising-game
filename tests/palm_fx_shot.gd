extends Node3D
## Windowed look-check of the PALM Cannon's signature (PalmFx) in the player's
## hands in a real level, firing at a wall stood up 9 m ahead:
##   palm_ready.png   at rest: the iris tight and bright on the muzzle
##   palm_flight.png  0.09 s after a shot: the iris thrown open, the bolt in its
##                    halo with echo rings hanging behind it
##   palm_clap.png    as the bolt lands: the clap ring spreading on the wall
##   palm_print.png   half a second later: the handprint glowing on the wall
## Headless renders black.
##   godot --path . res://tests/palm_fx_shot.tscn -- --out=<abs dir> [--level=res://scenes/levels/level_gpt.tscn]

const GUN := "res://scenes/weapons/salvage_palm.tscn"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("user://palm_fx_shots")
	var level := "res://scenes/levels/level_gpt.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--level="):
			level = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out_dir)
	add_child((load(level) as PackedScene).instantiate())
	for i in 60:
		await get_tree().physics_frame
	GameState.set_state(GameState.State.PLAYING)
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED
	# Let the level-start overlord broadcast (and its screen glitch) play out.
	await get_tree().create_timer(4.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	player.set_physics_process(false)
	(player.get_node("Damageable") as Damageable).invulnerable = true
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	# A wall across the line of fire.
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(8, 5, 0.4)
	var cs := CollisionShape3D.new()
	cs.shape = box
	wall.add_child(cs)
	var bm := BoxMesh.new()
	bm.size = box.size
	var wm_mat := StandardMaterial3D.new()
	wm_mat.albedo_color = Color(0.2, 0.22, 0.24)
	wm_mat.roughness = 0.8
	bm.material = wm_mat
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	wall.add_child(mi)
	add_child(wall)
	wall.global_position = cam.global_position + fwd * 9.0
	wall.look_at(cam.global_position, Vector3.UP)
	var w: Weapon = wm.take_salvage(load(GUN))
	await get_tree().create_timer(0.9).timeout # draw time + settle
	(await _grab()).save_png(out_dir.path_join("palm_ready.png"))
	w._cooldown = 0.0
	w._fire_once(cam, player, false)
	await get_tree().create_timer(0.09).timeout
	(await _grab()).save_png(out_dir.path_join("palm_flight.png"))
	await get_tree().create_timer(0.12).timeout
	(await _grab()).save_png(out_dir.path_join("palm_clap.png"))
	await get_tree().create_timer(0.5).timeout
	(await _grab()).save_png(out_dir.path_join("palm_print.png"))
	var brands := get_tree().current_scene.find_children("PalmBrand*", "Node3D", true, false)
	print("prints %d mag %d" % [brands.size(), w.mag])
	print("RESULT PASS")
	get_tree().quit()

func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()
