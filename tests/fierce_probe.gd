extends Node3D
## Windowed probe: shows the fierce enemy models in-engine with their real
## RobotModel tint/material treatment, then screenshots and quits.
## Run: godot res://tests/fierce_probe.tscn

const RM := preload("res://scripts/enemies/robot_model.gd")
const SHOT := "C:/Users/isber/AppData/Local/Temp/claude/C--dev-private-ai-uprising-game/25ad9bfd-0bcc-44d5-93df-eabbb559e3bc/scratchpad/ingame_fierce.png"

var _specs := [
	{"glb": "res://assets/models/robots/quaternius_bot_fierce.glb",
	 "scale": 5.0, "tint": Color(1, 0.42, 0.4), "menace": Color(1, 0.15, 0.1), "x": -5.0},
	{"glb": "res://assets/models/robots/quaternius_gunner_bladed.glb",
	 "scale": 2.7, "tint": Color(1, 0.72, 0.4), "menace": Color(1, 0.4, 0.1), "x": 0.0},
	{"glb": "res://assets/models/robots/quaternius_flyergun_bladed.glb",
	 "scale": 2.0, "tint": Color(1, 1, 1), "menace": Color(1, 0.2, 0.14), "x": 5.0},
]

func _ready() -> void:
	# lighting + environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.65)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -130, 0); sun.light_energy = 1.4
	add_child(sun)

	for s in _specs:
		var ps := load(s["glb"]) as PackedScene
		var rm := Node3D.new()
		rm.set_script(RM)
		rm.set("anim_idle", "CharacterArmature|Idle")
		rm.set("anim_walk", "")
		rm.set("tint", s["tint"])
		rm.set("menace_color", s["menace"])
		var mesh := ps.instantiate()
		var sc: float = s["scale"]
		mesh.transform = Transform3D(Basis().scaled(Vector3(-sc, sc, -sc)), Vector3.ZERO)
		rm.add_child(mesh)
		rm.position = Vector3(s["x"], 0, 0)
		add_child(rm)
		rm.set_physics_process(false)  # no EnemyBase parent to drive it

	var cam := Camera3D.new()
	var cpos := Vector3(0, 2.8, 9.5)
	cam.look_at_from_position(cpos, Vector3(0, 2.4, 0), Vector3.UP)
	cam.fov = 55.0
	add_child(cam)
	cam.make_current()

	await _shoot()

func _shoot() -> void:
	for i in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	print("SHOT ", SHOT)
	get_tree().quit()
