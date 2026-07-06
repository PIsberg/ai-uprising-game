extends Node3D
## Sweeps every campaign level, stands at the player spawn looking toward the
## arena centre (the real in-game read) and measures mean luminance of the frame
## so under-lit "dark spot" levels can be ranked objectively. Windowed:
##   godot --path . tests/dark_spot_probe.tscn
## Saves user://dark_<id>.png for each and prints a brightness table.

const LEVELS := [
	"01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss", "mistral",
	"overseer", "alien", "uplink", "assembly", "titan", "archon", "range",
	"sublevel", "crucible", "frostbreak", "neon", "lava_world", "water_world",
	"desert",
]

func _ready() -> void:
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 75.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	var rows: Array = []
	for id in LEVELS:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			print("skip ", id, " (no scene)")
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg:
			pdmg.invulnerable = true
		await get_tree().create_timer(2.0).timeout
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam:
			pcam.current = false
		var player := lvl.find_child("Player", false, false) as Node3D
		var spawn: Vector3 = player.global_position if player else Vector3(16, 0, 16)
		cam.current = true
		# Stand a little in from spawn at eye height, look at the arena middle.
		cam.global_position = Vector3(spawn.x * 0.62, 1.7, spawn.z * 0.62)
		cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var out := OS.get_user_data_dir() + "/dark_%s.png" % id
		img.save_png(out)
		# Mean perceptual luminance over a downsampled grid.
		var w := img.get_width()
		var h := img.get_height()
		var step := 8
		var sum := 0.0
		var n := 0
		var dark_px := 0
		for y in range(0, h, step):
			for x in range(0, w, step):
				var c := img.get_pixel(x, y)
				var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				sum += lum
				if lum < 0.06:
					dark_px += 1
				n += 1
		var mean := sum / float(maxi(n, 1))
		var dark_frac := float(dark_px) / float(maxi(n, 1))
		rows.append({"id": id, "mean": mean, "dark": dark_frac})
		print("MEAS %s mean=%.3f dark_frac=%.2f" % [id, mean, dark_frac])
		lvl.queue_free()
		await get_tree().process_frame
	# Sorted brightness table, darkest first.
	rows.sort_custom(func(a, b): return a["mean"] < b["mean"])
	print("\n==== DARK-SPOT RANKING (darkest first) ====")
	for r in rows:
		print("%-14s mean=%.3f  dark_frac=%.2f" % [r["id"], r["mean"], r["dark"]])
	print("DONE")
	get_tree().quit()
