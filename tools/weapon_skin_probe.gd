extends Node3D
## Windowed probe: a few player weapons under a real sky so the new worn-gunmetal
## skin shows its metallic reflections / clearcoat sheen. Screenshots then quits.
## Run: godot res://tools/weapon_skin_probe.tscn

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/25ad9bfd-0bcc-44d5-93df-eabbb559e3bc/scratchpad/weapon_skin.png"
const WEAPONS := ["rifle", "sniper", "gauss", "plasma", "omega"]

func _ready() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.45, 0.62)
	sky_mat.sky_horizon_color = Color(0.7, 0.74, 0.8)
	sky_mat.ground_bottom_color = Color(0.18, 0.19, 0.22)
	sky_mat.ground_horizon_color = Color(0.5, 0.52, 0.56)
	var sky := Sky.new(); sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)

	for i in WEAPONS.size():
		var ps := load("res://scenes/weapons/%s.tscn" % WEAPONS[i]) as PackedScene
		if ps == null:
			continue
		var w := ps.instantiate() as Node3D
		w.position = Vector3(0, 1.16 - i * 0.58, 0)
		w.rotation.y = PI * 0.5  # muzzle (-Z) to screen-left
		add_child(w)
		var lbl := Label3D.new()
		lbl.text = WEAPONS[i]
		lbl.font_size = 22
		lbl.position = w.position + Vector3(0.95, 0.16, 0)
		lbl.modulate = Color(0.9, 0.92, 1.0)
		add_child(lbl)

	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(0.1, 0.0, 4.0), Vector3(0, 0.0, 0), Vector3.UP)
	cam.fov = 42.0
	add_child(cam); cam.make_current()
	await _shoot()

func _shoot() -> void:
	for i in 24:  # let the noise roughness texture finish baking
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SHOT ", SHOT)
	get_tree().quit()
