extends Node3D
## Windowed visual check for the MIXTURE OF EXPERTS: two of them, one routed to
## SNIPER and one to SHIELD (blue shell); then a pod shot off the first and
## every pod shot off the second (router collapsed). Headless gives black frames.
##   godot --path . res://tests/moe_shot.tscn -- --out=<abs dir>

func _ready() -> void:
	var out_dir := ProjectSettings.globalize_path("user://moe_shots")
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
	sun.light_energy = 0.9
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
	pm.material = fmat
	fm.mesh = pm
	floor_body.add_child(fm)
	add_child(floor_body)
	var cam := Camera3D.new()
	cam.fov = 60.0
	add_child(cam)
	cam.global_position = Vector3(0, 2.4, 7.5)
	cam.look_at(Vector3(0, 1.8, 0), Vector3.UP)
	cam.current = true
	var bots: Array[EnemyMoE] = []
	for x in [-2.6, 2.6]:
		var e: EnemyMoE = (load("res://scenes/enemies/moe.tscn") as PackedScene).instantiate()
		add_child(e)
		e.set_physics_process(false) # posed; the orbit still turns
		e.global_position = Vector3(x, 0, 0)
		e.look_at(Vector3(x, 0, 9), Vector3.UP)
		bots.append(e)
	bots[0].route_to(EnemyMoE.SNIPER)
	bots[1].route_to(EnemyMoE.SHIELD)
	for i in 8:
		await get_tree().create_timer(0.2).timeout
	await _snap(out_dir, "moe_0_sniper_shield")
	(bots[0].pods()[EnemyMoE.SCATTER].get_node("Damageable") as Damageable).apply_damage(999.0, null)
	await get_tree().create_timer(0.15).timeout
	await _snap(out_dir, "moe_1_pod_shot")
	for k in 4:
		var p = bots[1].pods()[k]
		if is_instance_valid(p):
			(p.get_node("Damageable") as Damageable).apply_damage(999.0, null)
	await get_tree().create_timer(0.6).timeout
	await _snap(out_dir, "moe_2_collapsed")
	print("RESULT PASS")
	get_tree().quit()

func _snap(dir: String, stem: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(stem + ".png"))
