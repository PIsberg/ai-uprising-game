extends Node3D
## Probe: the HOWITZER walks on its four legs instead of sliding.
## walking_robot_gun.glb has all four crab legs in one mesh (Legs_Legs_0),
## hips at the top, feet on the floor. Feet are measured once at rest, in that
## mesh's own frame (the lowest 3 cm of each quadrant: left/right of x = 0,
## front/back of z = 0.35), and followed through whichever copy draws that leg
## (PartRig names them Legs_Legs_0_L_F and so on).
## (1) walking toward a target: every foot swings fore and aft at least 0.15 m;
## (2) a trot: diagonal feet together (front-left with back-right, r > 0.6),
##     the two front feet in opposition (r < -0.6);
## (3) stopped: every foot back within 0.03 m of rest.
##   godot --headless --path . --audio-driver Dummy res://tests/howitzer_gait_probe.tscn

const LEGS := "Legs_Legs_0"

var ok := true
var _e: CharacterBody3D
var _feet := {} ## "FL" -> foot in the legs mesh's own frame

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _build_floor() -> void:
	var region := NavigationRegion3D.new()
	add_child(region)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _measure_rest() -> void:
	var mi := _e.find_child(LEGS, true, false) as MeshInstance3D
	var to_local := mi.global_transform.affine_inverse() * _e.global_transform
	for k in ["FL", "FR", "BL", "BR"]:
		var sx: float = -1.0 if k[1] == "L" else 1.0
		var front: bool = k[0] == "F"
		var quad := PackedVector3Array()
		for q in PartRig.body_points(_e, mi):
			if signf(q.x) == sx and (q.z < 0.35) == front:
				quad.append(q)
		var lo := INF
		for q in quad:
			lo = minf(lo, q.y)
		var sel := PackedVector3Array()
		for q in quad:
			if q.y < lo + 0.03:
				sel.append(q)
		_feet[k] = to_local * PartRig.mean(sel)

## Body-frame feet, through the copy that draws each leg (the original before
## the split).
func _paws() -> Dictionary:
	var orig := _e.find_child(LEGS, true, false) as MeshInstance3D
	var out := {}
	for k in _feet:
		var name: String = LEGS + ("_L" if k[1] == "L" else "_R") + ("_F" if k[0] == "F" else "_B")
		var drawn: MeshInstance3D = orig
		for m in orig.get_parent().find_children(name, "MeshInstance3D", false, false):
			drawn = m
		out[k] = _e.global_transform.affine_inverse() * drawn.global_transform * (_feet[k] as Vector3)
	return out

static func _corr(a: Array, b: Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-12))

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -50) # in sight (60 m), past its 32 m preferred range
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0

	_e = (load("res://scenes/enemies/howitzer.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_e.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 4:
		await get_tree().physics_frame
	_measure_rest()
	var rest := _paws()
	print("  rest feet %s" % rest)
	_e.process_mode = Node.PROCESS_MODE_INHERIT
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	var track := {"FL": [], "FR": [], "BL": [], "BR": []}
	var speed := 0.0
	var t := 0.0
	while t < 3.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t < 0.5:
			continue # getting up to speed
		var p := _paws()
		for k in track:
			(track[k] as Array).append((p[k] as Vector3).z)
		speed = maxf(speed, Vector2(_e.velocity.x, _e.velocity.z).length())
	print("  ran at up to %.1f m/s" % speed)
	_check("howitzer actually walked", speed > 1.5, "(%.1f m/s)" % speed)
	for k in track:
		var a: Array = track[k]
		var span: float = a.max() - a.min()
		_check("%s foot swings fore and aft" % k, span >= 0.15, "(%.3f m)" % span)
	var diag := _corr(track["FL"], track["BR"])
	var front := _corr(track["FL"], track["FR"])
	_check("diagonal feet move together (trot)", diag > 0.6, "(r %.2f)" % diag)
	_check("front feet in opposition", front < -0.6, "(r %.2f)" % front)

	# Stop: legs settle back under it.
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.velocity = Vector3.ZERO
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var still := _paws()
	var worst := 0.0
	for k in still:
		worst = maxf(worst, (still[k] as Vector3).distance_to(rest[k]))
	_check("feet back under it when it stops", worst < 0.03, "(%.3f m)" % worst)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
