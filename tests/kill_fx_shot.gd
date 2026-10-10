extends Node3D
## Windowed visual check for KillFx: six androids side by side, killed at the
## same instant by a DISINTEGRATE hit, an ELECTROCUTE hit, an untagged hit (the
## classic blast), a SHRED hit (thrown back away from the camera), a DECAPITATE
## headshot (the head flies, the neck fountains) and a BLAST (far right: blown
## apart, lofted).
## Saves frames through the deaths.
## Headless gives black frames.
##   godot --path . res://tests/kill_fx_shot.tscn -- --out=<abs dir>

const ANDROID := "res://scenes/enemies/android.tscn"

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://kill_fx_shots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.19)
	fmat.roughness = 0.8
	pm.material = fmat
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)

	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.global_position = Vector3(0, 2.2, 12.5)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true

	var bots: Array[EnemyBase] = []
	for x in [-6.0, -3.6, -1.2, 1.2, 3.6, 6.0]:
		var e: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
		e.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(e)
		e.global_position = Vector3(x, 0, 0)
		e.look_at(Vector3(x, 0, 10), Vector3.UP)
		bots.append(e)
	for i in 10:
		await get_tree().create_timer(0.2).timeout
	await _snap(out_dir, "kill_fx_0_alive")
	var styles := [KillFx.DISINTEGRATE, KillFx.ELECTROCUTE, KillFx.NONE, KillFx.SHRED, KillFx.DECAPITATE, KillFx.BLAST]
	for i in styles.size():
		bots[i].process_mode = Node.PROCESS_MODE_INHERIT
		KillFx.tag(bots[i].hp, styles[i])
		bots[i].hp.apply_damage(99999.0, null)
		KillFx.untag(bots[i].hp)
	var t0 := Time.get_ticks_msec()
	for at_ms in [120, 250, 400, 650, 950]:
		while Time.get_ticks_msec() - t0 < at_ms:
			await get_tree().process_frame
		await _snap(out_dir, "kill_fx_%d_ms" % at_ms)
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(stem + ".png")
	img.save_png(path)
	print("saved ", path)
