extends Node3D
## Probe: the ENFORCER walks on its legs instead of sliding. mech_police.glb
## keeps both trouser legs in one mesh (Object_8) and the boots in the chest
## plate's mesh (Object_13); EnemyEnforcer._setup_gait cuts both by side and
## _tick_gait swings each leg with its boot about the hip. Boot soles and
## trouser hems are measured once at rest in each copy's own frame and
## followed through its transform, read with the chassis lean taken out.
## (1) walking after a target: each boot swings fore and aft 0.15+ m;
## (2) the two legs in opposition (correlation < -0.6);
## (3) each boot moves with its trouser leg (correlation > 0.9);
## (4) the chest plate (the rest of the boots' mesh) stays put (< 0.03 m);
## (5) stopped: every boot back within 0.03 m of rest.
##   godot --headless --path . --audio-driver Dummy res://tests/enforcer_gait_probe.tscn

var ok := true
var _e: CharacterBody3D
var _marks := {} ## name -> [MeshInstance3D, point in its frame]
var _rest := {}

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

## A part-local point in the body frame with the chassis lean taken out.
func _read(mi: MeshInstance3D, local: Vector3) -> Vector3:
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (mi.global_transform * local))

func _mark(name: String, mi: MeshInstance3D, body_p: Vector3) -> void:
	_marks[name] = [mi, mi.global_transform.affine_inverse() * (_e.global_transform * body_p)]

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

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_e = (load("res://scenes/enemies/enforcer.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 0.1, 0)
	_e.set("_attack_timer", 999.0)
	_e.set("_laser_cd", 999.0)
	var t := 0.0
	while t < 2.0 and not bool(_e.get("_gait_tried")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var parts := {}
	for n in ["Object_8_L", "Object_8_R", "Object_13_BootL", "Object_13_BootR", "Object_13_Plate"]:
		parts[n] = _e.find_child(n, true, false) as MeshInstance3D
	var rigged: bool = not parts.values().has(null) and (_e.get("_legs") as Array).size() == 2
	_check("legs and boots cut by side and rigged", rigged, "(found %s)" % [str(parts.keys().filter(func(k): return parts[k] != null))])
	if not rigged:
		print("RESULT FAIL")
		get_tree().quit()
		return
	# Marks: each boot's sole, each trouser leg's hem, the plate's centre.
	for n in ["Object_8_L", "Object_8_R", "Object_13_BootL", "Object_13_BootR"]:
		var pts := PartRig.body_points(_e, parts[n])
		_mark(n, parts[n], AimedPart.band_mean(pts, Vector3.DOWN, 0.04))
	_mark("plate", parts["Object_13_Plate"], PartRig.mean(PartRig.body_points(_e, parts["Object_13_Plate"])))
	for k in _marks:
		_rest[k] = _at(k)
	print("  rest %s" % _rest)

	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -34)
	player.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE
	var track := {"Object_8_L": [], "Object_8_R": [], "Object_13_BootL": [], "Object_13_BootR": []}
	var plate_dev := 0.0
	var speed := 0.0
	t = 0.0
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_e.set("_attack_timer", 999.0)
		if t < 0.6:
			continue # up to speed
		for k in track:
			(track[k] as Array).append(_at(k).z)
		plate_dev = maxf(plate_dev, _at("plate").distance_to(_rest["plate"]))
		speed = maxf(speed, Vector2(_e.velocity.x, _e.velocity.z).length())
	_check("enforcer actually walked", speed > 2.0, "(%.1f m/s)" % speed)
	for k in ["Object_13_BootL", "Object_13_BootR"]:
		var a: Array = track[k]
		var span: float = a.max() - a.min()
		_check("%s swings fore and aft" % k, span >= 0.15, "(%.3f m)" % span)
	var opp := _corr(track["Object_13_BootL"], track["Object_13_BootR"])
	_check("legs in opposition", opp < -0.6, "(r %.2f)" % opp)
	var same_l := _corr(track["Object_13_BootL"], track["Object_8_L"])
	var same_r := _corr(track["Object_13_BootR"], track["Object_8_R"])
	_check("each boot moves with its trouser leg", same_l > 0.9 and same_r > 0.9, "(r %.2f, %.2f)" % [same_l, same_r])
	_check("the chest plate stays put", plate_dev < 0.03, "(%.3f m)" % plate_dev)

	# Stop: the player out of sight and hearing, or it re-acquires it and walks on.
	player.global_position = Vector3(0, 0.1, -300)
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
	for k in ["Object_13_BootL", "Object_13_BootR", "Object_8_L", "Object_8_R"]:
		worst = maxf(worst, _at(k).distance_to(_rest[k]))
	_check("legs back under it when it stops", worst < 0.03, "(%.3f m)" % worst)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
