extends Node3D
## Dev probe: instantiate a real boss scene, cancel its sky-drop, and screenshot
## it both idle and walking so its in-game (animated) pose can be judged. Lists
## the model's available animation clips too. Pass scene path + tag after `--`:
##   godot --path . res://tests/boss_ingame_probe.tscn -- res://scenes/enemies/colossus.tscn goliath

func _ready() -> void:
	var argv := OS.get_cmdline_user_args()
	var scene_path := "res://scenes/enemies/colossus.tscn"
	var tag := "boss"
	if argv.size() >= 1: scene_path = argv[0]
	if argv.size() >= 2: tag = argv[1]

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0); sun.light_energy = 1.4
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.62)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.07, 0.08, 0.11)
	add_child(env)
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(60, 1, 60)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); add_child(sb)
	var player := CharacterBody3D.new(); player.add_to_group("player")
	add_child(player); player.global_position = Vector3(0, 1.2, 14)

	var boss: Node3D = (load(scene_path) as PackedScene).instantiate()
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)
	await get_tree().physics_frame
	if "_descending" in boss:
		boss._descending = false
		boss._entrance = 0.0
		boss.global_position = Vector3(0, 0.5, 0)
		boss.velocity = Vector3.ZERO
	if boss.hp: boss.hp.invulnerable = false
	# Freeze the boss AI so it stays planted at origin (RobotModel child keeps
	# animating idle + running the arm modifier).
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.global_position = Vector3(0, 0.5, 0)

	var ap := boss.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("ANIMS ", tag, ": ", ap.get_animation_list() if ap else "<none>")

	var cam := Camera3D.new()
	add_child(cam)
	# Let the idle clip + modifier settle, then frame off the real bounds.
	await get_tree().create_timer(0.8).timeout
	var aabb := _boss_aabb(boss)
	var ctr := aabb.get_center()
	var h: float = maxf(aabb.size.y, 1.0)
	for shot in [["front", Vector3(0, 0.15, 1)], ["side", Vector3(1, 0.15, 0.05)], ["q3", Vector3(0.8, 0.3, 0.8)]]:
		var dir := (shot[1] as Vector3).normalized()
		cam.global_position = ctr + dir * (h * 1.15)
		cam.look_at(ctr, Vector3.UP)
		await get_tree().create_timer(0.2).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/" + tag + "_" + str(shot[0]) + ".png")
		print("SAVED ", tag, "_", shot[0], ".png")
	get_tree().quit()

func _boss_aabb(boss: Node) -> AABB:
	var out := AABB(); var first := true
	for mi in _meshes(boss):
		if mi.mesh == null: continue
		var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first: out = ab; first = false
		else: out = out.merge(ab)
	return out

func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D: out.append(n)
	for c in n.get_children(): out.append_array(_meshes(c))
	return out
