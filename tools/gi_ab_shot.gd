extends Node3D
## A/B screenshot: level_gpt at HIGH (VoxelGI gated off, reflection probe only)
## vs ULTRA (VoxelGI baked) from the same eye-level framing, to judge whether
## dropping VoxelGI from HIGH reads as a visual downgrade.
## Writes ab_gi_high.png / ab_gi_ultra.png next to SHOT_DIR.
##
## IMPORTANT DIFFERENCE from tools/ssil_ab_shot.gd: GI is decided at LEVEL
## BUILD TIME (LevelBuilder._build_gi reads the tier once, while building the
## scene tree), so each arm needs a *fresh* level instantiation with the tier
## already set BEFORE add_child — flipping the tier under an already-built
## level would not add/remove its VoxelGI node.
##
## Run windowed:  godot --path . --quit-after 2000 res://tools/gi_ab_shot.tscn

const SHOT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad"

var _cam: Camera3D
var _lvl: Node
var _pre_quality: int

func _ready() -> void:
	_pre_quality = GraphicsSettings.quality

	_cam = Camera3D.new()
	_cam.fov = 70.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	_cam.attributes = ca
	add_child(_cam)

	await _run_arm(GraphicsSettings.Quality.HIGH, "ab_gi_high")
	await get_tree().process_frame
	await get_tree().process_frame
	await _run_arm(GraphicsSettings.Quality.ULTRA, "ab_gi_ultra")

	# Restore whatever quality was active before this probe ran (in-memory only
	# — never persisted).
	_set_tier(_pre_quality)
	print("GI_AB_DONE")
	get_tree().quit()

## Sets the tier BEFORE instantiating a fresh level (GI is baked in at
## LevelBuilder._build_gi time), frames the same eye-level shot ssil_ab_shot
## uses, waits for the deferred VoxelGI bake (windowed-only), and shoots.
func _run_arm(q: int, shot_name: String) -> void:
	_set_tier(q)
	_lvl = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(_lvl)

	# Make the player invulnerable and full-health IMMEDIATELY (player HP
	# persists across level loads via GameState, so a fresh instantiation does
	# not mean full HP) — otherwise hostiles chip it down during the bake wait
	# below and the low-health red vignette pollutes the GI comparison shot.
	var pdmg := _lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.invulnerable = true
		if "max_health" in pdmg and pdmg.has_method("heal"):
			pdmg.heal(pdmg.max_health)

	# VoxelGI.bake() is deferred by the builder and only runs in a real
	# (non-headless) window — give it time to bake before we screenshot.
	await get_tree().create_timer(2.5).timeout

	var pcam := _lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var player := _lvl.find_child("Player", false, false) as Node3D
	var spawn := player.global_position if player else Vector3(16, 0, 16)
	_cam.current = true
	_cam.global_position = Vector3(spawn.x * 0.5, 2.3, spawn.z * 0.5)
	_cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)

	await _shoot(shot_name)

	_lvl.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## In-memory tier switch (never touches the saved cfg) + viewport re-apply.
func _set_tier(q: int) -> void:
	GraphicsSettings.quality = q
	GraphicsSettings._apply_viewport()

func _shoot(name_: String) -> void:
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := "%s/%s.png" % [SHOT_DIR, name_]
	img.save_png(out)
	print("SAVED ", out)
