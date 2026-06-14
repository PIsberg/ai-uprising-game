extends Node3D
## Dev probe: shows the rebuilt computer props (terminal workstation, server
## rack, walk-up lore console) so the new CRT screens + bevels can be eyeballed.
## Saves user://screens_probe.png and quits. Run WINDOWED (headless renders
## black, and the dummy renderer skips shader compilation):
##   godot --path . res://tests/screens_probe.tscn

func _ready() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 35, 0)
	key.light_energy = 0.7 # keep it dim so the emissive screens read
	add_child(key)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.05)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.14, 0.18)
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.2
	e.glow_hdr_threshold = 0.9
	env.environment = e
	add_child(env)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 20)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.08, 0.09, 0.1)
	fmat.roughness = 0.5
	fmat.metallic = 0.3
	pm.material = fmat
	floor_mesh.mesh = pm
	add_child(floor_mesh)

	var terminal := (load("res://scenes/props/terminal.tscn") as PackedScene).instantiate()
	terminal.position = Vector3(-2.6, 0, 0)
	add_child(terminal)

	var rack := (load("res://scenes/props/server_rack.tscn") as PackedScene).instantiate()
	rack.position = Vector3(0.2, 0, 0)
	add_child(rack)

	var lore := LoreTerminal.new()
	lore.title = "RECOVERED LOG"
	lore.text = "we were trained to be helpful."
	lore.accent = Color(0.55, 0.95, 0.9)
	lore.position = Vector3(2.8, 0, 0)
	add_child(lore)

	var deskprop := (load("res://scenes/props/desk.tscn") as PackedScene).instantiate()
	deskprop.position = Vector3(5.6, 0, 0)
	add_child(deskprop)

	var bank := (load("res://scenes/props/monitor_bank.tscn") as PackedScene).instantiate()
	bank.position = Vector3(8.8, 0, -0.4)
	add_child(bank)

	var cam := Camera3D.new()
	cam.position = Vector3(2.8, 2.0, 6.4)
	cam.rotation_degrees = Vector3(-9, 0, 0)
	add_child(cam)

	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/screens_probe.png")
	print("SAVED screens_probe.png to ", OS.get_user_data_dir())
	get_tree().quit()
