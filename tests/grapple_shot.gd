extends Node3D
## Windowed visual check for the grapple tether: attach to a high wall and
## screenshot both the first-person view (beam converging on the anchor) and
## a third-person side view (full tether span) mid-pull.
## Run: godot --path . --quit-after 800 res://tests/grapple_shot.tscn
## Saves user://grapple_fp.png and user://grapple_side.png.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

func _make_box(pos: Vector3, size: Vector3, col: Color) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new(); sh.size = size
	cs.shape = sh
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	var m := StandardMaterial3D.new(); m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	b.add_child(mi)
	add_child(b)
	b.global_position = pos

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.05, 0.06, 0.1)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.4, 0.45, 0.55)
	we.environment.glow_enabled = true
	add_child(we)
	_make_box(Vector3(0, -0.5, 0), Vector3(60, 1, 60), Color(0.15, 0.16, 0.2))
	_make_box(Vector3(0, 12, -22), Vector3(30, 24, 1), Color(0.22, 0.24, 0.3))

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	(player.get_node("Head") as Node3D).rotation.x = deg_to_rad(22)
	await get_tree().create_timer(0.5).timeout

	Input.action_press("grapple")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("grapple")
	# A few frames into the pull: tether taut, player airborne.
	for i in 10:
		await get_tree().physics_frame
	print("STATE grappling=%s player=%s beam_xform=%s" % [
		player._grappling, player.global_position,
		player._tether_beam.global_transform if is_instance_valid(player._tether_beam) else "GONE"])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/grapple_fp.png")
	print("SAVED grapple_fp.png")

	# Third-person side view of the full tether span.
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = player.global_position + Vector3(10, 1.5, 2)
	cam.look_at((player.global_position + player._grapple_point) * 0.5, Vector3.UP)
	cam.make_current()
	await get_tree().physics_frame
	print("STATE2 grappling=%s player=%s" % [player._grappling, player.global_position])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/grapple_side.png")
	print("SAVED grapple_side.png")
	print("GRAPPLE_SHOT_DONE")
	get_tree().quit()
