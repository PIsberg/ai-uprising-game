extends Node3D
## Same eye-level screenshot flow as tools/eye_shot.gd, but forces
## GraphicsSettings to HIGH quality (detail_scale() == 1.0) and GPU particles
## on IN MEMORY ONLY before the level loads — this machine's persisted cfg may
## currently be LOW/MEDIUM from prior benchmark/testing runs, which would
## silently skip ambient weather/ash FX (detail_scale() <= 0.0 early-outs).
## Does not call set_quality()/_save_settings(), so nothing is persisted.
## Level id via EYE_LEVEL env var (default suburb).
##   godot --path . --quit-after 1800 res://tools/weather_shot.tscn

const SHOT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad"

func _ready() -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs:
		gs.quality = 2 # Quality.HIGH — direct property set, bypasses _save_settings()
		gs.gpu_particles_enabled = true
	var id := OS.get_environment("EYE_LEVEL")
	if id == "":
		id = "suburb"
	var cam := Camera3D.new()
	cam.fov = 85.0
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_min_sensitivity = 50.0
	ca.auto_exposure_max_sensitivity = 400.0
	ca.auto_exposure_scale = 0.38
	cam.attributes = ca
	add_child(cam)
	var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	var pdmg := lvl.find_child("Damageable", true, false)
	if pdmg:
		pdmg.set("invulnerable", true)
	var pcam := lvl.find_child("Camera3D", true, false) as Camera3D
	if pcam:
		pcam.current = false
	var player := lvl.find_child("Player", false, false) as Node3D
	var spawn := player.global_position if player else Vector3(-20, 0.6, -20)
	cam.current = true
	cam.global_position = Vector3(spawn.x, spawn.y + 1.1, spawn.z)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	var cps := lvl.find_children("*", "CPUParticles3D", true, false)
	var gps := lvl.find_children("*", "GPUParticles3D", true, false)
	print("CPUParticles3D count=", cps.size())
	for c in cps:
		print("  ", c.name, " amount=", c.amount, " emitting=", c.emitting, " pos=", c.global_position)
	print("GPUParticles3D count=", gps.size())
	for c in gps:
		print("  ", c.name, " amount=", c.amount, " emitting=", c.emitting, " pos=", c.global_position)
	print("spawn=", spawn)
	var gs2 := get_node_or_null("/root/GraphicsSettings")
	if gs2:
		print("detail_scale=", gs2.detail_scale(), " quality=", gs2.quality)
	for i in 30:
		await get_tree().process_frame
	var out := "%s/eye_%s.png" % [SHOT_DIR, id]
	get_viewport().get_texture().get_image().save_png(out)
	print("SAVED ", out)
	# Second frame: pitched down at the near ground — diagnoses what the
	# bottom-of-frame black region actually is in the horizon shot.
	var fwd := (Vector3(0, 0, 0) - spawn).normalized()
	cam.look_at(spawn + fwd * 4.0 + Vector3(0, -1.4, 0), Vector3.UP)
	for i in 30:
		await get_tree().process_frame
	var out2 := "%s/eye_%s_down.png" % [SHOT_DIR, id]
	get_viewport().get_texture().get_image().save_png(out2)
	print("SAVED ", out2)
	get_tree().quit()
