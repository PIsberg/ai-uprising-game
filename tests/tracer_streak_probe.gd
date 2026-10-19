extends Node3D
## Probe: a shot's tracer (scripts/fx/tracer.gd) is a soft glowing streak that
## turns to face the camera, not a solid six-sided rod, and its spill light
## stays inside the FX light budget.
##   - the player's rifle bolt and an enemy's red bolt each draw one flat card
##     whose face turns toward the camera on every frame of the flight (within
##     MAX_FACE_DEG), from two different camera positions;
##   - the bolt's nose leaves the muzzle and runs down the line of fire toward
##     the hit point, then the tracer frees itself;
##   - it is drawn in the gun's shot colour (an enemy tracer in its override);
##   - with the FX light budget full a tracer brings no light; with room it
##     takes one slot and gives it back when it is gone.
##   godot --headless --path . --audio-driver Dummy res://tests/tracer_streak_probe.tscn

const MAX_FACE_DEG := 10.0

var ok := true
var cam: Camera3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	var w: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(w)
	await get_tree().process_frame
	var from := Vector3(0.3, 1.4, 0)
	var to := Vector3(0.0, 1.0, -30.0)
	for eye: Vector3 in [Vector3(0, 1.6, 0.4), Vector3(4, 3, -10)]:
		cam.look_at_from_position(eye, to, Vector3.UP)
		var before := _tracers()
		w._spawn_tracer(from, to)
		var mine: Array = _tracers().filter(func(n: Node) -> bool: return not n in before)
		_check("rifle shot spawns one tracer (eye %s)" % eye, mine.size() == 1)
		if mine.size() == 1:
			await _fly("rifle (eye %s)" % eye, mine[0], from, to, w.shot_color())
	# An enemy bolt: the shared red tracer with its colour override.
	cam.look_at_from_position(Vector3(0, 1.6, 0.4), Vector3(0, 1.0, -30), Vector3.UP)
	var red: Node3D = (load("res://scenes/fx/tracer_red.tscn") as PackedScene).instantiate()
	add_child(red)
	var efrom := Vector3(-2, 1.5, -25)
	var eto := Vector3(0, 1.6, 0.2)
	red.setup(efrom, eto)
	await _fly("enemy red bolt", red, efrom, eto, red.color_override)
	# FX light budget.
	var live0: int = FXLights._live
	FXLights._live = FXLights._budget()
	var starved := _spawn(w, from, to)
	_check("over the FX light budget a tracer brings no light",
			starved.find_children("*", "OmniLight3D", true, false).is_empty())
	FXLights._live = live0
	starved.queue_free()
	await get_tree().process_frame
	var lit := _spawn(w, from, to)
	_check("with room a tracer takes one light slot",
			lit.find_children("*", "OmniLight3D", true, false).size() == 1 and FXLights._live == live0 + 1,
			"live %d -> %d" % [live0, FXLights._live])
	lit.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("a freed tracer gives its light slot back", FXLights._live == live0, str(FXLights._live))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _spawn(w: Weapon, from: Vector3, to: Vector3) -> Node3D:
	var before := _tracers()
	w._spawn_tracer(from, to)
	return _tracers().filter(func(n: Node) -> bool: return not n in before)[0]

## Follow one tracer to its end: card faces the camera, nose runs muzzle -> hit.
func _fly(label: String, t: Node3D, from: Vector3, to: Vector3, col: Color) -> void:
	var cards := t.find_children("*", "MeshInstance3D", true, false)
	_check("%s is one flat card" % label, cards.size() == 1 and (cards[0] as MeshInstance3D).mesh is PlaneMesh)
	if cards.size() != 1:
		return
	var card := cards[0] as MeshInstance3D
	var mat := card.material_override as ShaderMaterial
	var tint: Color = mat.get_shader_parameter("tint") if mat else Color.BLACK
	_check("%s is drawn in its colour" % label, mat != null and tint.is_equal_approx(col), str(tint))
	var line := (to - from).normalized()
	var worst := 0.0
	var first_nose := -1.0
	var last_nose := 0.0
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(t) and Time.get_ticks_msec() - t0 < 2000:
		# The card's face normal (local +Y) against the camera, both taken
		# perpendicular to the line of fire (the only freedom a streak has).
		var n := card.global_basis.y.normalized()
		var to_cam := cam.global_position - card.global_position
		to_cam = (to_cam - line * to_cam.dot(line)).normalized()
		worst = maxf(worst, rad_to_deg(acos(clampf(absf(n.dot(to_cam)), -1.0, 1.0))))
		var nose: float = (card.global_position - card.global_basis.z * 0.5 - from).dot(line)
		if first_nose < 0.0:
			first_nose = nose
		last_nose = nose
		frames += 1
		await get_tree().process_frame
	var dist := from.distance_to(to)
	print("   %s: %d frames, face off by at most %.1f deg, nose %.1f -> %.1f of %.1f m" % [label, frames, worst, first_nose, last_nose, dist])
	_check("%s turns its face to the camera" % label, worst < MAX_FACE_DEG, "%.1f deg" % worst)
	_check("%s leaves from the muzzle" % label, first_nose < dist * 0.5, "%.1f m" % first_nose)
	# A slow headless frame can carry the 150 m/s bolt most of the way in one
	# step, so ask for real travel down the line, not a sample at the end.
	_check("%s runs down the line of fire" % label, last_nose - first_nose > dist * 0.4,
			"%.1f -> %.1f of %.1f m" % [first_nose, last_nose, dist])
	_check("%s frees itself" % label, not is_instance_valid(t))

func _tracers() -> Array:
	return get_tree().root.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.get_script() == preload("res://scripts/fx/tracer.gd"))
