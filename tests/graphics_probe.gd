extends Node3D
## Windowed screenshot of the graphics pass: rain-slick clearcoat ground on
## level 01 plus explosion scorch decals, at player eye level, ULTRA tier.
##   godot --path . res://tests/graphics_probe.tscn --quit-after 900

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/95a1d0e0-6d29-460c-8157-97f2f1fe8e7d/scratchpad/graphics_shot.png"

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GraphicsSettings.quality = GraphicsSettings.Quality.ULTRA
	var lvl := (load("res://scenes/levels/level_01.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.set("invulnerable", true)
	# One cooled mark (spawned early, embers die), then two fresh ember-hot ones.
	ScorchDecal.spawn(lvl, Vector3(-4, 0.2, -4), 2.4)
	await get_tree().create_timer(4.0).timeout
	ScorchDecal.spawn(lvl, Vector3(-1, 0.2, -8), 1.6)
	ScorchDecal.spawn(lvl, Vector3(2, 0.2, -3), 2.0)
	var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var cam := Camera3D.new()
	cam.fov = 72.0
	# Match the player camera's auto-exposure so brightness reads like play.
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	cam.global_position = Vector3(-9, 1.9, -12)
	cam.look_at(Vector3(4, 0.6, 2), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	get_tree().quit()
