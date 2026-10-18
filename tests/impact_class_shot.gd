extends Node3D
## Windowed look-check of wall impacts by damage class: an AR-7, an Arc Coil, a
## Longshot and a Gauss Lance each fire into a lit concrete wall 5 m away (left
## to right), photographed 0.12 s after (sparks, light, fresh glow) and 1.2 s
## after (the rail holes cooling). Headless renders black.
##   godot --path . res://tests/impact_class_shot.tscn -- --out=<abs dir>

const GUNS := ["rifle", "arccoil", "sniper", "gauss"]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_dir := ProjectSettings.globalize_path("user://impact_class_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	GraphicsSettings.quality = GraphicsSettings.Quality.HIGH
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 20, 0)
	sun.light_energy = 0.4
	add_child(sun)
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(12, 5, 0.5)
	cs.shape = bs
	wall.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.55, 0.53)
	mat.roughness = 0.9
	bm.material = mat
	mi.mesh = bm
	wall.add_child(mi)
	add_child(wall)
	wall.global_position = Vector3(0, 1.5, -5)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.5, 0)
	cam.fov = 70.0
	cam.current = true
	var shooter := Node3D.new()
	add_child(shooter)
	for i in 10:
		await get_tree().process_frame
	for i in GUNS.size():
		var w: Weapon = (load("res://scenes/weapons/%s.tscn" % GUNS[i]) as PackedScene).instantiate()
		add_child(w)
		w.visible = false
		w._active_shooter = shooter
		var x := -3.0 + 2.0 * i
		var from := Vector3(x, 1.5, 0)
		w._do_hitscan(from, Vector3(0, 0, -1))
	await get_tree().create_timer(0.12).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("impacts_fresh.png"))
	await get_tree().create_timer(1.1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("impacts_cooling.png"))
	print("RESULT PASS")
	get_tree().quit()
