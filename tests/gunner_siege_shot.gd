extends Node3D
## Windowed look-check for the GUNNER siege fork: one unit mid-burst (front 3/4, rotor
## spinning, barrels glowing, rounds in the air) beside an idle one turned away to show
## the ammo drum, feed chute, cooling fins and recoil spades. The camera looks down +Z,
## so the idle unit (world +X) is on the LEFT of the frame.
## Everything stands on a stage node 50 m from the scene root: impact explosions emit their
## first frame of particles at the current scene's origin, not at the impact, which
## otherwise lands a smoke cloud between the two units.
## Saves user://gunner_siege.png. Run: godot --path . res://tests/gunner_siege_shot.tscn

const GUNNER := preload("res://scenes/enemies/gunner.tscn")

func _ready() -> void:
	var stage := Node3D.new()
	stage.position = Vector3(50, 0, 50)
	add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 150, 0)
	sun.light_energy = 1.4
	add_child(sun)

	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	floor_body.add_child(cs)
	var fm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	fm.mesh = bm
	floor_body.add_child(fm)
	floor_body.position = Vector3(0, -0.5, 0)
	stage.add_child(floor_body)

	# The firing unit aims at this; off-frame, past the camera's right shoulder.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	pcs.shape = cap
	player.add_child(pcs)
	stage.add_child(player)
	player.position = Vector3(-17, 0.9, -37)

	var firing := GUNNER.instantiate() as Node3D
	stage.add_child(firing)
	firing.position = Vector3(-2.3, 0.1, 0)
	firing.look_at(Vector3(33, 0.1, 13), Vector3.UP)
	var idle := GUNNER.instantiate() as Node3D
	stage.add_child(idle)
	idle.position = Vector3(2.6, 0.1, 0.5)
	idle.rotation_degrees.y = -128.0
	idle.set_physics_process(false) # keep it turned away: its AI would swing round on the player

	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(50, 2.3, 42.4), Vector3(50, 1.5, 50), Vector3.UP)
	cam.fov = 50.0
	cam.make_current()

	for i in 10:
		await get_tree().physics_frame
	firing.set("target", player)
	firing.call("_perform_attack")
	# Windup + most of the burst: rotor at speed, barrels near peak heat.
	var frames := int((float(firing.get("windup")) + 1.0) * Engine.physics_ticks_per_second)
	for i in frames:
		await get_tree().physics_frame
	print("SHOT spin=%.1f heat=%.2f" % [firing.call("rotor_spin"), firing.call("barrel_heat")])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, int(1280.0 * img.get_height() / img.get_width()))
	img.save_png("user://gunner_siege.png")
	print("SHOT ", ProjectSettings.globalize_path("user://gunner_siege.png"))
	get_tree().quit()
