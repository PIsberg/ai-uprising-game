extends Node3D
## Dev probe: renders the Warbot enemy (happy idle face + weapons, then angry
## combat face) so I can tune the procedural face/cannon offsets.
##   godot --path . res://tests/warbot_view_probe.tscn

const OUT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private/4fbdff7a-4323-435c-af31-9542c7153dc8/scratchpad/"

var _bot: Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	e.ambient_light_color = Color(0.55, 0.58, 0.68)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.7
	add_child(sun)

	_bot = load("res://scenes/enemies/warbot.tscn").instantiate()
	add_child(_bot)
	_bot.set_physics_process(false) # freeze AI; we drive the face manually
	# Face the camera: enemy forward is -Z, camera sits at +Z, so spin 180.
	_bot.rotation.y = PI

	for mi in _bot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh and m.name == "Mesh":
			pass
	# Report the imported body's world-space height so I can place the face.
	for c in _bot.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh:
			var ab: AABB = mi.global_transform * mi.mesh.get_aabb()
			print("BODY AABB world: pos=", ab.position, " end=", ab.end, " size=", ab.size)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.0, 3.0)
	cam.look_at_from_position(Vector3(0, 1.0, 3.0), Vector3(0, 1.0, 0), Vector3.UP)
	add_child(cam)
	_shoot.call_deferred()

func _shoot() -> void:
	await get_tree().create_timer(0.5).timeout
	# Happy (idle) — built that way by default.
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "warbot_happy.png")
	print("SAVED happy")
	# Angry (combat): toggle the faces directly.
	var happy: Node3D = _bot.get("_happy")
	var angry: Node3D = _bot.get("_angry")
	if happy:
		happy.visible = false
	if angry:
		angry.visible = true
	await get_tree().create_timer(0.1).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + "warbot_angry.png")
	print("SAVED angry")
	get_tree().quit()
