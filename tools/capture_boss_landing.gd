extends Node3D
## Captures the GOLIATH-IX (colossus) sky-drop entrance as a PNG frame sequence
## into docs/screenshots/boss_landing/frame_###.png — the retro-rocket planetfall
## and touchdown. Frames are grabbed once the boss drops into view and for a beat
## after it lands, so the foot-thruster flames and impact ring are captured.
##
## Run (needs a window/GPU): godot --path . tools/capture_boss_landing.tscn

const OUT_DIR := "res://docs/screenshots/boss_landing"
const START_CAPTURE_Y := 16.0
const POST_LAND_FRAMES := 36     # keep rolling after touchdown for the impact ring

var _cam: Camera3D
var _boss: Node3D
var _frame := 0
var _post := -1
var _capturing := false


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# Slow-mo so the fast retro-burn descent is captured across many smooth frames
	# (capture-only; does not affect the game).
	Engine.time_scale = 0.12

	_cam = Camera3D.new()
	_cam.fov = 62.0
	add_child(_cam)
	_cam.make_current()
	# Low 3/4 angle looking up at the landing mark so the boss reads big and the
	# foot-thrusters are dead centre as it drops in.
	_cam.global_position = Vector3(9, 6.0, 18)
	_cam.look_at(Vector3(0, 9, 0), Vector3.UP)

	# Moody dusk arena, like Maple Grove Plaza at night.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(30), 0)
	sun.light_energy = 0.8
	sun.light_color = Color(0.7, 0.75, 0.95)
	add_child(sun)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.11)
	env.ambient_light_color = Color(0.4, 0.45, 0.6)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	we.environment = env
	add_child(we)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-8, 4, 8)
	fill.light_color = Color(0.5, 0.6, 1.0)
	fill.light_energy = 2.0
	fill.omni_range = 30.0
	add_child(fill)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.13, 0.13, 0.16)
	pm.material = gmat
	ground.mesh = pm
	add_child(ground)
	# A faint landing ring so the touchdown mark reads.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.0
	tm.outer_radius = 3.3
	var rmat := StandardMaterial3D.new()
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.4, 0.2)
	rmat.albedo_color = Color(1.0, 0.4, 0.2)
	tm.material = rmat
	ring.mesh = tm
	ring.position = Vector3(0, 0.05, 0)
	add_child(ring)

	# The boss itself — preview stays false so it runs the full sky-drop.
	_boss = load("res://scenes/enemies/colossus.tscn").instantiate()
	add_child(_boss)
	_boss.global_position = Vector3.ZERO


func _process(_delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		return
	var y := _boss.global_position.y
	if not _capturing and y <= START_CAPTURE_Y:
		_capturing = true
	if _capturing:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%03d.png" % [OUT_DIR, _frame])
		_frame += 1
		# Once it has effectively landed (near its mark), count down a tail then stop.
		if _post < 0 and y <= 0.2:
			_post = POST_LAND_FRAMES
		if _post >= 0:
			_post -= 1
			if _post <= 0:
				print("BOSS LANDING CAPTURED frames=", _frame)
				get_tree().quit()
	# Safety: never hang forever.
	if _frame > 400:
		get_tree().quit()
