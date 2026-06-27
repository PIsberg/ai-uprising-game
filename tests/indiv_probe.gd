extends Node3D
## Visual check for the individual-improvement pass:
##  - BRUTE: shield held in the left hand, right arm free (capture idle + a punch).
##  - VACUUM: rises in the codex (preview tween), capture mid-rise + reared up.
## Run windowed: godot --path . --quit-after 700 res://tests/indiv_probe.tscn

func _ready() -> void:
	var we := WorldEnvironment.new(); we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.1, 0.11, 0.14)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.5, 0.55, 0.65)
	we.environment.ambient_light_energy = 1.0
	add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, 25, 0); sun.light_energy = 2.0
	add_child(sun)
	var cam := Camera3D.new(); cam.current = true; add_child(cam)

	# --- BRUTE ---
	var brute: Node3D = (load("res://scenes/enemies/brute.tscn") as PackedScene).instantiate()
	add_child(brute)
	await get_tree().process_frame
	brute.global_position = Vector3.ZERO
	brute.set_physics_process(false) # no floor in this probe; freeze it so gravity doesn't drop it (RobotModel still animates)
	cam.global_position = Vector3(0, 1.9, 4.6)
	cam.look_at(Vector3(0, 1.3, 0), Vector3.UP)
	await get_tree().create_timer(0.6).timeout
	await _grab("indiv_brute_idle")
	# Trigger the punch clip (RobotModel plays anim_attack on the recoil spike).
	if "recoil" in brute:
		brute.recoil = 1.0
	await get_tree().create_timer(0.35).timeout
	await _grab("indiv_brute_punch")
	brute.queue_free()
	await get_tree().process_frame

	# --- VACUUM (codex preview) ---
	var vac: Node3D = (load("res://scenes/enemies/vacuum.tscn") as PackedScene).instantiate()
	if "preview" in vac:
		vac.preview = true
	add_child(vac)
	vac.global_position = Vector3.ZERO
	vac.set_physics_process(false) # mirror the codex
	cam.global_position = Vector3(0, 1.4, 4.0)
	cam.look_at(Vector3(0, 0.7, 0), Vector3.UP)
	await get_tree().create_timer(0.9).timeout
	await _grab("indiv_vacuum_folded")
	await get_tree().create_timer(1.4).timeout # let the rise tween play
	await _grab("indiv_vacuum_risen")
	print("INDIV_DONE")
	get_tree().quit()

func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/" + name + ".png")
	print("shot ", name)
