extends Node3D
## Stands every enemy on a flat lit floor and screenshots the lineup at eye
## level — any model resting below the floor plane is immediately visible.
##   godot --path . --quit-after 1200 res://tools/roster_floor_shot.tscn

const SHOT_DIR := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/df4a3e78-e161-445d-96b9-6124bf321864/scratchpad"
const ROW1 := ["android", "drone", "spider", "dog", "skitter", "vacuum", "roller", "optic", "hunter"]
const ROW2 := ["mauler", "sentinel", "reaper", "seeker", "breaker", "mender", "gunner", "gunslinger"]

func _ready() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	body.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.35, 0.37, 0.42)
	pm.material = fmat
	fl.mesh = pm
	add_child(fl)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.85)
	env.ambient_light_energy = 0.8
	we.environment = env
	add_child(we)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(0, 1, 90)
	add_child(player)

	for i in ROW1.size():
		_spawn(ROW1[i], Vector3((i - 4) * 3.2, 0.6, 0))
	for i in ROW2.size():
		_spawn(ROW2[i], Vector3((i - 4) * 3.2, 0.6, -5.5))
	await get_tree().create_timer(1.5).timeout # settle onto the floor

	var cam := Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.6, 13), Vector3(0, 0.9, -2), Vector3.UP)
	cam.make_current()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/roster_floor.png")
	print("SAVED roster_floor.png")
	get_tree().quit()

func _spawn(id: String, pos: Vector3) -> void:
	var b: Node3D = (load("res://scenes/enemies/%s.tscn" % id) as PackedScene).instantiate()
	add_child(b)
	b.global_position = pos
	b.rotation.y = PI
	if b.has_method("set_process"):
		b.set_process(false)
