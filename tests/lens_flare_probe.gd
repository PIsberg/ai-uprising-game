extends Node3D
## Probe: the camera lens flare (scripts/fx/lens_flare.gd, shaders/lens_flare.gdshader).
## (1) source_for: an open-sky level's sun is the brightest DirectionalLight3D
##     (pointing back along its +Z); a night_sky level flares off its moon_dir,
##     weaker; an HDRI sky (sun position unknown) and an interior get none;
## (2) looking straight at the sun the flare comes up to the source's power,
##     centred on screen, over the whole screen; a wall between camera and sun
##     fades it out and hides the node, and so does a skyline tower, which has
##     no collision (its boxes are tested instead); looking away it is off;
## (3) the advanced post-process setting turns it off;
## (4) the player carries one under PostFX, drawn before the post overlay.
##   godot --headless --path . --audio-driver Dummy res://tests/lens_flare_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	for i in int(ceil(sec / 0.25)):
		await get_tree().create_timer(0.25).timeout

func _ready() -> void:
	_run.call_deferred()

func _level(sky_mat: Material, open_sky: bool) -> Node3D:
	var root := Node3D.new()
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_mat
	we.environment = env
	we.set_meta("open_sky", open_sky)
	root.add_child(we)
	var fill := DirectionalLight3D.new() # a weak second light must not win
	fill.light_energy = 0.2
	fill.rotation_degrees = Vector3(-80, 0, 0)
	root.add_child(fill)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.1
	sun.rotation_degrees = Vector3(-25, 140, 0)
	root.add_child(sun)
	return root

func _run() -> void:
	# 1. Sources.
	var day := _level(ProceduralSkyMaterial.new(), true)
	add_child(day)
	var sun := day.get_node("Sun") as DirectionalLight3D
	var src := LensFlare.source_for(day)
	_check("day: flares off the sun", not src.is_empty()
		and (src["dir"] as Vector3).angle_to(sun.global_transform.basis.z) < 0.01,
		str(src))
	var day_power: float = src.get("power", 0.0)
	_check("day: has power", day_power > 0.5, "%.2f" % day_power)
	var night_mat := ShaderMaterial.new()
	night_mat.shader = load("res://shaders/night_sky.gdshader")
	var moon := Vector3(0.3, 0.4, -0.8)
	night_mat.set_shader_parameter("moon_dir", moon)
	var night := _level(night_mat, true)
	add_child(night)
	src = LensFlare.source_for(night)
	_check("night: flares off the moon", not src.is_empty()
		and (src["dir"] as Vector3).angle_to(moon.normalized()) < 0.01, str(src))
	_check("night: weaker than day", float(src.get("power", 9.0)) < day_power * 0.6)
	night.queue_free()
	var hdri := _level(PanoramaSkyMaterial.new(), true)
	add_child(hdri)
	_check("hdri: no flare", LensFlare.source_for(hdri).is_empty())
	hdri.queue_free()
	var inside := _level(ProceduralSkyMaterial.new(), false)
	add_child(inside)
	_check("interior: no flare", LensFlare.source_for(inside).is_empty())
	inside.queue_free()

	# 2. Live flare in the day level.
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 2, 0)
	var to_sun: Vector3 = sun.global_transform.basis.z
	cam.look_at(cam.global_position + to_sun, Vector3.UP)
	var layer := CanvasLayer.new()
	add_child(layer)
	var flare := LensFlare.new()
	flare.camera = cam
	flare.source_root = day
	layer.add_child(flare)
	await _wait(1.0)
	var uv: Vector2 = flare.light_uv
	_check("facing the sun: flare up", flare.strength > day_power * 0.8 and flare.visible,
		"strength %.2f" % flare.strength)
	_check("covers the screen", flare.size == flare.get_viewport_rect().size and flare.size.x > 0.0,
		"%s vs %s" % [flare.size, flare.get_viewport_rect().size])
	_check("facing the sun: centred", uv.distance_to(Vector2(0.5, 0.5)) < 0.02, str(uv))
	var sm := flare.material as ShaderMaterial
	_check("shader is fed", sm != null and is_equal_approx(float(sm.get_shader_parameter("strength")), flare.strength))

	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 30, 1)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = cam.global_position + to_sun * 12.0
	wall.look_at(cam.global_position, Vector3.UP)
	await _wait(1.0)
	_check("wall in the way: faded out", flare.strength < 0.03 and not flare.visible,
		"strength %.3f" % flare.strength)
	wall.queue_free()
	await _wait(1.0)
	_check("wall gone: back", flare.strength > day_power * 0.8)
	# A skyline tower has no collision (MultiMesh only): it occludes through
	# its published boxes (group flare_occluder), not the physics rays.
	var sky := Skyline.new()
	day.add_child(sky)
	var tower_at := cam.global_position + to_sun * 60.0
	sky._build({"towers": [{"pos": tower_at, "size": Vector3(24, 120, 24), "yaw": 0.4, "lit": true,
		"base": true, "far": false, "seed": 0.5, "dens": 0.5}], "beacons": [], "signs": []},
		Color.WHITE, false, false)
	_check("skyline publishes its towers", sky.is_in_group("flare_occluder") and sky.flare_boxes().size() == 1)
	await _wait(1.0)
	_check("skyline tower in the way: faded out", flare.strength < 0.03 and not flare.visible,
		"strength %.3f" % flare.strength)
	sky.queue_free()
	await _wait(1.0)
	_check("tower gone: back", flare.strength > day_power * 0.8, "strength %.3f" % flare.strength)
	cam.look_at(cam.global_position - to_sun, Vector3.UP)
	await _wait(1.0)
	_check("looking away: off", flare.strength < 0.03 and not flare.visible,
		"strength %.3f" % flare.strength)

	# 3. Setting.
	cam.look_at(cam.global_position + to_sun, Vector3.UP)
	var was: bool = GraphicsSettings.advanced_post_process_enabled
	GraphicsSettings.advanced_post_process_enabled = false
	await _wait(1.0)
	_check("advanced post off: no flare", flare.strength < 0.03 and not flare.visible)
	GraphicsSettings.advanced_post_process_enabled = was
	flare.queue_free()

	# 4. Player wiring.
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	await _wait(0.5)
	var post := player.get_node("PostFX")
	var flares := post.find_children("*", "LensFlare", false, false)
	_check("player has a LensFlare under PostFX", flares.size() == 1, "found %d" % flares.size())
	if flares.size() == 1:
		_check("drawn before the post overlay",
			(flares[0] as Node).get_index() < post.get_node("Overlay").get_index())
	player.queue_free()

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
