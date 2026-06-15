extends Node3D
## Loads campaign levels one at a time and captures an elevated 3/4 view to
## assess layout, graphical detail and obstacle/model fit. Windowed:
##   godot --path . tests/level_shot.tscn
## Saves user://shot_<id>.png for each.

const LEVELS := ["gpt", "gemini", "mistral", "claude", "assembly", "suburb"]

func _ready() -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 70.0
	# Match the player camera's auto-exposure so brightness reads like real play.
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	for id in LEVELS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("skip ", id, " (no scene)")
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		# Keep the probe player alive so the death overlay doesn't cover the shot.
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg:
			pdmg.invulnerable = true
		# Let it build geometry, props, enemies, lighting + a couple navmesh frames.
		await get_tree().create_timer(2.0).timeout
		# Disable the player's camera so OUR framing wins.
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam:
			pcam.current = false
		# Player eye-level view: stand near the spawn, look toward the arena centre
		# — the real in-game read (not a floor-filling overhead).
		var player := lvl.find_child("Player", false, false) as Node3D
		var spawn := player.global_position if player else Vector3(16, 0, 16)
		cam.current = true
		cam.global_position = Vector3(spawn.x * 0.7, 1.7, spawn.z * 0.7)
		cam.look_at(Vector3(0, 1.4, 0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var out := OS.get_user_data_dir() + "/shot_%s.png" % id
		img.save_png(out)
		print("SAVED ", out)
		lvl.queue_free()
		await get_tree().process_frame
	print("DONE")
	get_tree().quit()
