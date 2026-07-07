extends Node3D
## Eye-level + overhead screenshots of the gated levels, to eyeball that the
## bulkhead gates / tunnel mouths / guide beacons read well and don't clip
## existing towers or props. Run windowed.

const IDS := ["sublevel", "uplink", "claude", "gemini", "neon"]

func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 78.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 40.0
	ca.auto_exposure_max_sensitivity = 800.0
	add_child(cam)
	for id in IDS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg: pdmg.invulnerable = true
		await get_tree().create_timer(2.4).timeout
		var def: Dictionary = LevelDefs.get_def(id)
		var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		# Strip the ceiling cap and add a bright key light so the route reads.
		for c in get_tree().get_nodes_in_group("level_ceiling"):
			c.visible = false
		var sun := DirectionalLight3D.new()
		sun.rotation = Vector3(deg_to_rad(-58), deg_to_rad(35), 0)
		sun.light_energy = 1.4
		add_child(sun)
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam: pcam.current = false
		cam.current = true
		# Angled aerial from over the spawn corner, looking down the diagonal to
		# the exit — shows the gate walls' faces, their gaps and tunnel mouths.
		cam.global_position = Vector3(spawn.x * 1.25, maxf(fs.x, fs.y) * 0.62, spawn.z * 1.25)
		cam.look_at(Vector3(-spawn.x * 0.15, 1.0, -spawn.z * 0.15), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/gate_%s_top.png" % id)
		sun.queue_free()
		print("SHOT ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("GATE_SHOT_DONE  dir=", OS.get_user_data_dir())
	get_tree().quit()
