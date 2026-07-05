extends Node3D
## Damages a mech to ~45% health (past its first armour shed) and photographs
## it to verify the exposed weak-point core reads as a glowing "shoot me" spot
## on the chassis at combat distance.
##   godot --path . --quit-after 900 res://tools/weakcore_shot.tscn

const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad/weakcore.png"

func _ready() -> void:
	# Game-like dark interior: AGX + low ambient + glow, so the core reads.
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.8
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.62
	env.glow_hdr_threshold = 1.25
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 0.8
	add_child(sun)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.16, 0.17, 0.2)
	pm.material = fmat
	fl.mesh = pm
	add_child(fl)

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(30, 1, 30)
	add_child(player)

	var mech: Node = load("res://scenes/enemies/mech.tscn").instantiate()
	add_child(mech)
	mech.global_position = Vector3(0, 0.5, 0)
	mech.rotation.y = PI # face the camera
	if mech.has_method("set_physics_process"):
		mech.set_physics_process(false) # no AI — hold still for the shot
	await get_tree().create_timer(0.6).timeout

	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	# Pulled back enough to fit the whole (tall) mech chassis in frame, eye level.
	cam.look_at_from_position(Vector3(0, 1.9, 5.5), Vector3(0, 1.7, 0), Vector3.UP)
	cam.make_current()

	# Bite it down to ~45% health (past the 0.66 threshold, short of 0.33) so
	# exactly one panel has shed and the core is exposed.
	var target_frac := 0.45
	var dmg: float = mech.hp.max_health * (1.0 - target_frac)
	mech.hp.apply_damage(dmg, player)
	await get_tree().create_timer(1.4).timeout # let the damage number fade + pulse settle

	get_viewport().get_texture().get_image().save_png(SHOT)
	print("SAVED ", SHOT)
	print("shed_stage=", mech._shed_stage, " hp_frac=%.2f" % (mech.hp.current_health / mech.hp.max_health))
	get_tree().quit()
