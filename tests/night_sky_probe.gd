extends Node3D
## Dev probe: renders the night_sky shader in a few faction palettes so the
## starfield / Milky-Way / moon can be eyeballed. Saves user://night_sky_*.png
## and quits. Run WINDOWED (headless renders black, no shader compile):
##   godot --path . res://tests/night_sky_probe.tscn

const SHADER := preload("res://shaders/night_sky.gdshader")

const THEMES := [
	{"name": "blue", "zen": Color(0.04, 0.04, 0.1), "hor": Color(0.3, 0.12, 0.16),
		"star": Color(0.85, 0.92, 1.0), "mw": 0.4, "mwt": Color(0.5, 0.55, 0.85), "moon": Color(0.85, 0.9, 1.0)},
	{"name": "green", "zen": Color(0.02, 0.06, 0.04), "hor": Color(0.08, 0.16, 0.1),
		"star": Color(0.75, 1.0, 0.8), "mw": 0.5, "mwt": Color(0.4, 0.8, 0.5), "moon": Color(0.7, 1.0, 0.75)},
	{"name": "red", "zen": Color(0.08, 0.02, 0.03), "hor": Color(0.28, 0.07, 0.07),
		"star": Color(1.0, 0.7, 0.65), "mw": 0.4, "mwt": Color(0.7, 0.3, 0.3), "moon": Color(1.0, 0.65, 0.55)},
]

var _we: WorldEnvironment

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 0)
	cam.rotation_degrees = Vector3(22, 0, 0) # look up into the dome
	cam.fov = 80.0
	add_child(cam)
	_we = WorldEnvironment.new()
	add_child(_we)
	for t in THEMES:
		await _shoot(t)
	get_tree().quit()

func _shoot(t: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("zenith_color", t["zen"])
	mat.set_shader_parameter("horizon_color", t["hor"])
	mat.set_shader_parameter("star_tint", t["star"])
	mat.set_shader_parameter("star_brightness", 2.2)
	mat.set_shader_parameter("milkyway", t["mw"])
	mat.set_shader_parameter("milkyway_tint", t["mwt"])
	mat.set_shader_parameter("moon_color", t["moon"])
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.8
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.25
	_we.environment = env
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/night_sky_%s.png" % t["name"])
	print("SAVED night_sky_%s.png" % t["name"])
