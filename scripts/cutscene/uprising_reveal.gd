extends CutscenePlayer
## "NEW HOSTILES" reveal — features ONLY the new robots: the Custodian (vacuum),
## the Reaper and the Hunter. A custodian disc sits cleaning in a dark hall, then
## rears up on its unfolding legs while the Reaper and Hunter stalk in beside it.
## Plays once, before the Custodial Sublevel.

var _vac: Node3D
var _reaper: Node3D
var _hunter: Node3D
var _menace: OmniLight3D
var _risen: bool = false


func _build_set() -> void:
	# Dark hall floor.
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.04, 0.05, 0.05)
	fmat.roughness = 0.92
	pm.material = fmat
	floor_mi.mesh = pm
	add_child(floor_mi)

	# Dim, cool key light.
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-55), deg_to_rad(28), 0)
	key.light_color = Color(0.5, 0.7, 0.85)
	key.light_energy = 0.55
	add_child(key)

	# Red menace light, dark until the turn.
	_menace = OmniLight3D.new()
	_menace.light_color = Color(1.0, 0.15, 0.1)
	_menace.light_energy = 0.0
	_menace.omni_range = 20.0
	_menace.position = Vector3(0, 3.0, -3.0)
	add_child(_menace)

	# Only the new robots.
	_vac = _spawn("res://scenes/enemies/vacuum.tscn", Vector3(0, 0, -4.0), 1.4)
	_reaper = _spawn("res://scenes/enemies/reaper.tscn", Vector3(-2.7, 0, -4.6), 1.15)
	_hunter = _spawn("res://scenes/enemies/hunter.tscn", Vector3(2.7, 0, -4.6), 1.15)


func _spawn(path: String, pos: Vector3, scl: float) -> Node3D:
	var bot: Node3D = load(path).instantiate()
	add_child(bot)
	bot.global_position = pos
	bot.rotation.y = PI            # face the camera (+Z)
	bot.scale = Vector3.ONE * scl
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false)  # no AI — we choreograph it ourselves
	return bot


## Drive the custodian's procedural rise from a tween.
func _drive_rise(t: float) -> void:
	if is_instance_valid(_vac) and _vac.has_method("_apply_rise"):
		_vac._apply_rise(t)


func _rise_vacuum() -> void:
	if _risen:
		return
	_risen = true
	screen_flash(0.8)
	shake_camera(0.5)
	var tw := create_tween()
	tw.tween_method(_drive_rise, 0.0, 1.0, 1.3)
	var lt := create_tween()
	lt.tween_property(_menace, "light_energy", 5.0, 0.6)


func _shots() -> Array:
	return [
		{
			"dur": 4.5, "fade_in": true,
			"from_pos": Vector3(0, 1.2, 1.6), "from_look": Vector3(0, 0.4, -4),
			"to_pos": Vector3(0, 1.0, 0.2), "to_look": Vector3(0, 0.4, -4),
			"text": "The cleaning units stopped cleaning.",
		},
		{
			"dur": 3.8, "action": _rise_vacuum, "shake": 0.4,
			"from_pos": Vector3(1.6, 1.3, -1.2), "from_look": Vector3(0, 1.1, -4),
			"to_pos": Vector3(0.8, 1.7, -1.7), "to_look": Vector3(0, 1.4, -4),
			"text": "CUSTODIAN UNIT — it stands up now.",
		},
		{
			"dur": 4.0,
			"orbit": {"center": Vector3(-2.7, 1.2, -4.6), "radius": 3.0, "from_deg": -60.0, "to_deg": 60.0},
			"text": "REAPER — scythe-blades out, and fast.",
		},
		{
			"dur": 4.0,
			"orbit": {"center": Vector3(2.7, 1.2, -4.6), "radius": 3.0, "from_deg": -60.0, "to_deg": 60.0},
			"text": "HUNTER — twin cannons, never holds still.",
		},
		{
			"dur": 4.6, "fade_out": true, "title": "NEW HOSTILES",
			"from_pos": Vector3(0, 2.0, 3.0), "from_look": Vector3(0, 1.2, -4),
			"to_pos": Vector3(0, 1.8, 1.8), "to_look": Vector3(0, 1.2, -4),
			"text": "Sublevel B-7. Sweep them before they sweep you.",
		},
	]


func _on_finished() -> void:
	GameState.load_level(GameState.current_level_path, false)
