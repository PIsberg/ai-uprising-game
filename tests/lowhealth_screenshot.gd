extends Node3D
## Dev probe: renders a scene through the post shader with low_health forced
## high, saves user://lowhealth_screenshot.png. Run windowed:
##   godot --path . res://tests/lowhealth_screenshot.tscn

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.6, 5)
	add_child(cam)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.28, 0.34)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.45, 0.47, 0.5)
	floor_mi.material_override = fmat
	add_child(floor_mi)
	for x in [-2.0, 0.0, 2.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 1.5, 1)
		b.mesh = bm
		b.position = Vector3(x, 0.75, -2)
		add_child(b)
	var layer := CanvasLayer.new()
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/post_process.gdshader")
	mat.set_shader_parameter("low_health", 0.85)
	rect.material = mat
	layer.add_child(rect)
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/lowhealth_screenshot.png")
	print("SAVED ", OS.get_user_data_dir() + "/lowhealth_screenshot.png")
	get_tree().quit()
