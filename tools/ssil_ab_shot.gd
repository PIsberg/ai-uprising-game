extends Node3D
## A/B screenshot: level_gpt at HIGH (SSAO, no SSIL) vs ULTRA (SSAO+SSIL) from
## the same eye-level framing, to judge whether dropping SSIL from HIGH reads
## as a visual downgrade. Writes ab_high.png / ab_ultra.png next to SHOT_DIR.
## Run windowed:  godot --path . --quit-after 2000 res://tools/ssil_ab_shot.tscn

const SHOT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad"

var _cam: Camera3D
var _lvl: Node

func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	_cam.attributes = ca
	add_child(_cam)

	_set_tier(GraphicsSettings.Quality.HIGH)
	_lvl = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(_lvl)
	await get_tree().create_timer(2.0).timeout
	var pdmg := _lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.invulnerable = true
	var pcam := _lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var player := _lvl.find_child("Player", false, false) as Node3D
	var spawn := player.global_position if player else Vector3(16, 0, 16)
	_cam.current = true
	_cam.global_position = Vector3(spawn.x * 0.5, 2.3, spawn.z * 0.5)
	_cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)

	await _shoot("ab_high")
	_set_tier(GraphicsSettings.Quality.ULTRA)
	await _shoot("ab_ultra")
	print("AB_DONE")
	get_tree().quit()

## In-memory tier switch (never touches the saved cfg) + live env re-apply.
func _set_tier(q: int) -> void:
	GraphicsSettings.quality = q
	GraphicsSettings._apply_viewport()
	for we in find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env:
			GraphicsSettings.apply_to_environment(env, bool(we.get_meta("open_sky", false)))

func _shoot(name_: String) -> void:
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := "%s/%s.png" % [SHOT_DIR, name_]
	img.save_png(out)
	print("SAVED ", out)
