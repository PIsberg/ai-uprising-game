extends Node3D
## Probe: static bipeds walk on their legs (BipedGait) instead of sliding.
## ENFORCER: mech_police.glb keeps both trouser legs in one mesh and the boots
## in the chest plate's mesh; both are cut by side at spawn. GUNSLINGER and
## WARBOT: their GLBs are cut offline into Body, LegL and LegR. RONIN: the
## shins, ankles and feet under its cloak are a dozen small meshes, each cut
## by side at spawn. For each,
## the sole of every leg part (its lowest band at rest, in the copy's own
## frame) is followed through the copy's transform, read with the chassis
## lean taken out.
## (1) walking after a target: each foot swings fore and aft 0.15+ m (the
##     WARBOT's stubby legs 0.10+);
## (2) the two legs in opposition (correlation < -0.6);
## (3) a leg's extra parts (the ENFORCER's boots) move with it (r > 0.9);
## (4) the parts that must not swing (chest plate, Body) stay put (< 0.03 m);
## (5) stopped out of the player's sight: every foot back within 0.03 m.
##   godot --headless --path . --audio-driver Dummy res://tests/biped_gait_probe.tscn

const SPECS := [
	{"name": "ENFORCER", "scene": "res://scenes/enemies/enforcer.tscn",
		"legs": [["Object_8_L", "Object_13_BootL"], ["Object_8_R", "Object_13_BootR"]],
		"still": ["Object_13_Plate"], "quiet": ["_attack_timer", "_laser_cd"], "walk": 2.0},
	{"name": "GUNSLINGER", "scene": "res://scenes/enemies/gunslinger.tscn",
		"legs": [["LegL"], ["LegR"]], "still": ["Body"], "quiet": ["_attack_timer"], "walk": 3.0},
	{"name": "WARBOT", "scene": "res://scenes/enemies/warbot.tscn",
		"legs": [["LegL"], ["LegR"]], "still": ["Body"], "quiet": ["_attack_timer"], "walk": 2.0, "swing": 0.10},
	{"name": "RONIN", "scene": "res://scenes/enemies/ronin.tscn",
		"legs": [["Cube_007_Material_006_0_L", "Cube_003_Material_005_0_L"], ["Cube_007_Material_006_0_R", "Cube_003_Material_005_0_R"]],
		"still": ["Plane_017_Material_048_0"], "quiet": ["_attack_timer", "_slug_cd", "_dash_cd"], "walk": 3.0, "swing": 0.10},
]

var ok := true
var _failed: Array = [] ## labels of the failed checks, listed before the verdict (CI keeps only the last lines)
var _e: CharacterBody3D
var _player: CharacterBody3D
var _marks := {} ## name -> [MeshInstance3D, point in its frame]
var _rest := {}

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false
		_failed.append("%s %s" % [label, detail])

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

## A part-local point in the body frame with the chassis lean taken out.
func _read(mi: MeshInstance3D, local: Vector3) -> Vector3:
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * local))

func _mark(name: String, mi: MeshInstance3D, body_p: Vector3) -> void:
	_marks[name] = [mi, mi.global_transform.affine_inverse() * ((_e.call("rig_frame") as Transform3D) * body_p)]

func _at(name: String) -> Vector3:
	var m: Array = _marks[name]
	return _read(m[0], m[1])

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

func _quiet(spec: Dictionary) -> void:
	for k in spec["quiet"]:
		_e.set(k, 999.0)

func _test(spec: Dictionary) -> void:
	var tag: String = spec["name"]
	_marks.clear()
	_rest.clear()
	_e = (load(spec["scene"]) as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_quiet(spec)
	# The rig sets itself up on the tick after RobotModel's deferred fit lands,
	# and deferred calls run on PROCESS frames: a loaded CI runner packs up to
	# 8 physics steps into one frame, so a physics-time wait ran out before
	# the fit had had a frame. Count process frames (up to about 4 s), then
	# step back onto the physics clock the rig poses on.
	var t := 0.0
	var frames := 0
	while frames < 240 and not bool(_e.get("_gait_tried")):
		await get_tree().process_frame
		frames += 1
	await get_tree().physics_frame
	var names: Array = []
	for side in spec["legs"]:
		names.append_array(side)
	names.append_array(spec["still"])
	var parts := {}
	for n in names:
		parts[n] = _e.find_child(n, true, false) as MeshInstance3D
	var gait = _e.get("_gait")
	var rigged: bool = not parts.values().has(null) and gait != null and not gait.is_empty()
	_check("%s: leg parts found and rigged" % tag, rigged, "(found %s)" % [str(parts.keys().filter(func(k): return parts[k] != null))])
	if not rigged:
		_e.queue_free()
		return
	for side in spec["legs"]:
		for n in side:
			_mark(n, parts[n], AimedPart.band_mean(PartRig.body_points(_e, parts[n]), Vector3.DOWN, 0.04))
	for n in spec["still"]:
		_mark(n, parts[n], PartRig.mean(PartRig.body_points(_e, parts[n])))
	for k in _marks:
		_rest[k] = _at(k)

	_player.global_position = Vector3(0, 0.1, -34)
	_e.set("sight_range", 60.0)
	_e.set("target", _player)
	_e.call("set_state", 3) # CHASE
	var track := {}
	for k in _marks:
		track[k] = []
	var still_dev := 0.0
	var speed := 0.0
	t = 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_quiet(spec)
		if t < 0.6:
			continue # up to speed
		for k in track:
			(track[k] as Array).append(_at(k).z)
		for n in spec["still"]:
			still_dev = maxf(still_dev, _at(n).distance_to(_rest[n]))
		speed = maxf(speed, Vector2(_e.velocity.x, _e.velocity.z).length())
	_check("%s actually walked" % tag, speed > float(spec["walk"]), "(%.1f m/s)" % speed)
	var feet: Array = []
	for side in spec["legs"]:
		var foot: String = side[0]
		feet.append(foot)
		var a: Array = track[foot]
		var span: float = a.max() - a.min()
		_check("%s: %s swings fore and aft" % [tag, foot], span >= float(spec.get("swing", 0.15)), "(%.3f m)" % span)
		for extra in side.slice(1):
			var r := _corr(track[foot], track[extra])
			_check("%s: %s moves with %s" % [tag, extra, foot], r > 0.9, "(r %.2f)" % r)
	var opp := _corr(track[feet[0]], track[feet[1]])
	_check("%s: legs in opposition" % tag, opp < -0.6, "(r %.2f)" % opp)
	_check("%s: %s stay put" % [tag, str(spec["still"])], still_dev < 0.03, "(%.3f m)" % still_dev)

	# Stop: the player out of sight and hearing, or it re-acquires it and walks on.
	_player.global_position = Vector3(0, 0.1, -300)
	_e.set("sight_range", 0.0)
	_e.set("hearing_range", 0.0)
	_e.set("target", null)
	_e.call("set_state", 0) # IDLE
	_e.set("move_speed", 0.0)
	_e.velocity = Vector3.ZERO
	t = 0.0
	while t < 1.2:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var worst := 0.0
	for side in spec["legs"]:
		for n in side:
			worst = maxf(worst, _at(n).distance_to(_rest[n]))
	_check("%s: legs back under it when it stops" % tag, worst < 0.03, "(%.3f m)" % worst)
	_e.queue_free()
	await get_tree().physics_frame

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.1, -300)
	_player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = _player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	for spec in SPECS:
		await _test(spec)
	for f in _failed:
		print("FAILED: %s" % f)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
