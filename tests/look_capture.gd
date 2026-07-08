extends Node3D
## Visual-audit capture: loads campaign levels one at a time and saves an
## eye-level, forward-looking screenshot of each to an absolute OUT_DIR so the
## environment/models/lighting can be reviewed. Run WINDOWED (needs a GPU):
##   godot --path . -- res://tests/look_capture.tscn  (OUT_DIR/level set via consts)
## Not headless — headless produces black frames.

# Absolute output dir (scratchpad). Overwrite per run.
const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/0fc2ad91-24b1-454b-a19d-915b39dd00b0/scratchpad/looks"

# Which levels to shoot. Full campaign order.
const LEVELS := ["01", "gpt", "gemini", "mistral", "suburb", "suburb_boss", "convoy",
	"claude", "grok", "uplink", "overseer", "alien", "assembly", "sublevel",
	"frostbreak", "water_world", "desert", "neon", "guardrails", "hivemind",
	"crucible", "lava_world", "titan", "archon"]

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 72.0
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
			print("skip ", id); continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		var pdmg := lvl.find_child("Damageable", true, false)
		if pdmg: pdmg.invulnerable = true
		await get_tree().create_timer(2.2).timeout
		var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
		if pcam: pcam.current = false
		var player := lvl.find_child("Player", false, false) as Node3D
		var spawn: Vector3 = player.global_position if player else Vector3(16, 2, 16)
		# Stand at the spawn (eye height), look toward the arena centre — the real
		# player's-eye first impression.
		cam.current = true
		var eye := Vector3(spawn.x * 0.82, maxf(spawn.y, 0.0) + 1.7, spawn.z * 0.82)
		cam.global_position = eye
		cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [OUT_DIR, id])
		print("SAVED ", id)
		lvl.queue_free()
		await get_tree().process_frame
	print("LOOK_CAPTURE_DONE")
	get_tree().quit()
