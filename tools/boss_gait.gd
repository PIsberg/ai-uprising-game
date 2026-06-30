extends Node3D
## Spawns a boss in preview mode, forces it to "walk" (steady forward velocity),
## and captures side-view frames across a stride so the procedural gait can be
## judged. Run windowed: godot --path . tools/boss_gait.tscn
const OUT := "res://docs/screenshots/boss"
const BOSS := "titan"
const FRAMES := 10
const STEP := 0.12   # seconds between captures

var _boss: Node3D
var _cam: Camera3D
var _t := 0.0
var _f := 0
var _ready_done := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 28, 0); sun.light_energy = 1.5
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.55, 0.62)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.07, 0.08, 0.11)
	add_child(env)
	var scn: Node3D = load("res://scenes/enemies/%s.tscn" % BOSS).instantiate()
	scn.set("preview", true)   # skip entrance/AI; gait still builds + runs in _process
	add_child(scn)
	_boss = scn
	_cam = Camera3D.new()
	add_child(_cam)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	# Frame the model from the side.
	_cam.global_position = Vector3(5.5, 2.2, 1.2)
	_cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	_ready_done = true

func _process(delta: float) -> void:
	if not _ready_done or _boss == null:
		return
	_boss.velocity = Vector3(0, 0, -_boss.move_speed)  # steady forward "walk"
	_t += delta
	if _t < STEP:
		return
	_t = 0.0
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/gait_%s_%02d.png" % [OUT, BOSS, _f])
	_f += 1
	if _f >= FRAMES:
		print("BOSS GAIT CAPTURED boss=%s frames=%d" % [BOSS, _f])
		get_tree().quit()
