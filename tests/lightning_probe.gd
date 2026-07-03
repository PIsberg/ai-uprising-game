extends Node3D
## Windowed screenshot of the storm-lightning bolt: spawns strikes at the real
## in-game distance (just past the arena wall) and captures them at full
## brightness, with fog/exposure exactly as in play.
##   godot --path . res://tests/lightning_probe.tscn --quit-after 600

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/95a1d0e0-6d29-460c-8157-97f2f1fe8e7d/scratchpad/lightning_shot.png"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.set("invulnerable", true)
	var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var cam := Camera3D.new()
	cam.fov = 75.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	cam.global_position = Vector3(-13, 3.5, 16)
	cam.look_at(Vector3(-22, 26, -30), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(0.5).timeout
	# Two strikes at the real in-game range (arena base 24 + 5..20).
	lvl.call("_spawn_bolt", Vector3(-30, 0, -13))
	lvl.call("_spawn_bolt", Vector3(-8, 0, -38))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	get_tree().quit()
