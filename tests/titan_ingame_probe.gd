extends Node3D
## Dev probe: instantiate the real titan.tscn so the ModelPoser path in
## enemy_titan.gd is exercised end-to-end, cancel its sky-drop, and screenshot
## the planted boss. Run windowed:
##   godot --path . res://tests/titan_ingame_probe.tscn

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.62)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.07, 0.08, 0.11)
	add_child(env)
	# Floor so the boss has something under it.
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(60, 1, 60)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs); add_child(sb)
	# A dummy player so the boss has a target / the announce doesn't choke.
	var player := CharacterBody3D.new(); player.add_to_group("player")
	add_child(player); player.global_position = Vector3(0, 1.2, 12)

	var boss: Node3D = (load("res://scenes/enemies/titan.tscn") as PackedScene).instantiate()
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)
	await get_tree().physics_frame
	# Cancel the cinematic sky-drop so it stands planted for the shot.
	if "_descending" in boss:
		boss._descending = false
		boss._entrance = 0.0
		boss.global_position = Vector3(0, 0.5, 0)
		boss.velocity = Vector3.ZERO
	boss.set_physics_process(false)
	boss.set_process(false)

	var cam := Camera3D.new()
	add_child(cam)
	for shot in [["ig_front", Vector3(0, 5.5, 13)], ["ig_q3", Vector3(9, 6, 10)], ["ig_side", Vector3(13, 5.5, 1)]]:
		cam.global_position = shot[1]
		cam.look_at(Vector3(0, 4.0, 0), Vector3.UP)
		await get_tree().create_timer(0.4).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/titan_" + str(shot[0]) + ".png")
		print("SAVED titan_", shot[0], ".png  pivots=", _count_pivots(boss))
	get_tree().quit()

func _count_pivots(n: Node) -> int:
	var c := 0
	if str(n.name).begins_with("ArmPivot"):
		c += 1
	for ch in n.get_children():
		c += _count_pivots(ch)
	return c
