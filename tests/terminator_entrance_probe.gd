extends Node3D
## Dev probe: watch the TERMINATOR's eruption entrance play out — buried rumble,
## floor breach, rise, settle — capturing frames through it. Run windowed:
##   godot --path . res://tests/terminator_entrance_probe.tscn

const SHOTS := {0.45: "telegraph", 0.85: "breach", 1.15: "rising", 1.55: "clearing", 2.3: "settled"}

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0); sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.4, 0.42, 0.5)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.05, 0.05, 0.08)
	env.environment.glow_enabled = true
	add_child(env)
	# Floor (deck) the boss erupts through.
	var sb := StaticBody3D.new(); sb.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(40, 1, 40)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0); sb.add_child(cs)
	var fmi := MeshInstance3D.new()
	var fbox := BoxMesh.new(); fbox.size = Vector3(40, 1, 40)
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.2, 0.2, 0.23); fmat.roughness = 0.95
	fbox.material = fmat; fmi.mesh = fbox; fmi.position = Vector3(0, -0.5, 0)
	sb.add_child(fmi); add_child(sb)
	# Dummy player (target + shake target; has no shake() so shakes are skipped).
	var player := CharacterBody3D.new(); player.add_to_group("player")
	var pd := Damageable.new(); pd.name = "Damageable"; player.add_child(pd)
	add_child(player); player.global_position = Vector3(0, 1.2, 12)

	# Spawn the terminator. Position MUST be set before add_child so its _ready
	# buries itself relative to the right floor height (EnemySpawner does the same).
	var boss: Node3D = (load("res://scenes/enemies/terminator.tscn") as PackedScene).instantiate()
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)

	var cam := Camera3D.new()
	add_child(cam)
	cam.look_at_from_position(Vector3(7, 3.2, 9), Vector3(0, 1.6, 0), Vector3.UP)
	cam.current = true

	var times := SHOTS.keys()
	times.sort()
	var prev := 0.0
	for tm in times:
		await get_tree().create_timer(tm - prev).timeout
		prev = tm
		var img := get_viewport().get_texture().get_image()
		img.save_png(OS.get_user_data_dir() + "/term_ent_" + str(SHOTS[tm]) + ".png")
		print("SAVED term_ent_", SHOTS[tm], "  body_y=%.2f rising=%s" % [boss.global_position.y, str(boss.get("_rising"))])
	get_tree().quit()
