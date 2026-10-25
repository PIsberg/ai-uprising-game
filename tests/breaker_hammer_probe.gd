extends Node3D
## Probe: the BREAKER swings its piston hammer. combat_steampunk.glb's hammer
## (`Object_7`) is its own mesh hanging from a root at the top of the chassis;
## EnemyBreaker._tick_hammer swings it about that root. The head is the
## part's vertices farthest from the root, measured once at rest in the
## part's own frame and followed through its transform, read with the
## chassis bank taken out (the hammer alone, not the flyer's lean).
## (1) the root sits where the arm leaves the chassis (within 0.06 m of the
##     part's topmost vertices, read headless);
## (2) hovering in place the head only sways (under 0.15 m);
## (3) an attack: the head draws back 0.15+ m within the wind-up, then whips
##     0.3+ m forward of rest by the end of the stroke; the player is hurt by
##     the stroke, not when the attack is decided;
## (4) a second later the head hangs back within 0.06 m of rest.
##   godot --headless --path . --audio-driver Dummy res://tests/breaker_hammer_probe.tscn

var ok := true
var _e: CharacterBody3D
var _mi: MeshInstance3D
var _head_local := Vector3.ZERO
var _rest := Vector3.ZERO

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## The head in the body frame with the chassis lean taken out: RobotModel
## banks the `Mesh` node the parts hang under, so the head is read in that
## node's frame and put back through the fitted base it banks from.
func _head() -> Vector3:
	var mesh_node: Node3D = _e.get_node("Model/Mesh")
	var base: Transform3D = _e.get_node("Model").get("_mesh_base")
	return base * (mesh_node.global_transform.affine_inverse() * (_mi.global_transform * _head_local))

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -2.5)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000.0
	php.current_health = 1000.0

	_e = (load("res://scenes/enemies/breaker.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3(0, 2.0, 0)
	var t := 0.0
	while t < 2.0 and not bool(_e.get("_hammer_tried")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_mi = _e.find_child("Object_7", true, false) as MeshInstance3D
	var rigged: bool = _mi != null and not (_e.get("_hammer_e") as Array).is_empty()
	_check("hammer found and rigged", rigged, "(tried %s)" % _e.get("_hammer_tried"))
	if not rigged:
		print("RESULT FAIL")
		get_tree().quit()
		return
	var pts := PartRig.body_points(_e, _mi)
	var top := AimedPart.band_mean(pts, Vector3.UP, 0.04)
	var root: Vector3 = _e.get("_hammer_root")
	_check("root sits where the arm leaves the chassis", root.distance_to(top) < 0.06, "(root %s, topmost %s, %.3f m)" % [root, top, root.distance_to(top)])
	var head_body := AimedPart.far_mean(pts, root, 0.06)
	_head_local = _mi.global_transform.affine_inverse() * (_e.global_transform * head_body)
	_rest = _head()
	print("  head at rest %s" % _rest)

	# (2) Hover in place: pendulum sway only. Hold it still above the player,
	# its own attack clock parked so only the probe's attack swings.
	_e.set("target", player)
	_e.set("move_speed", 0.0)
	_e.set("_attack_timer", 999.0)
	_e.call("set_state", 4) # ATTACK
	var sway := 0.0
	t = 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		sway = maxf(sway, _head().distance_to(_rest))
	_check("hovering, the hammer only sways", sway < 0.15, "(%.3f m)" % sway)

	# (3) An attack: wind back, strike forward, hit on the stroke.
	var hp0: float = php.current_health
	_e.set("_attack_timer", 999.0)
	_e.call("_perform_attack")
	await get_tree().physics_frame
	_check("no damage when the attack is decided", php.current_health == hp0, "(%.0f -> %.0f)" % [hp0, php.current_health])
	var back := 0.0
	var fwd := 0.0
	var hit_at := -1.0
	t = 0.0
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var dz := _head().z - _rest.z
		if t <= 0.2:
			back = maxf(back, dz)
		fwd = minf(fwd, dz)
		if hit_at < 0.0 and php.current_health < hp0:
			hit_at = t
	_check("the head draws back in the wind-up", back >= 0.15, "(%.3f m)" % back)
	_check("the head whips forward through the stroke", fwd <= -0.3, "(%.3f m)" % fwd)
	_check("the hit lands at the end of the stroke", hit_at >= 0.18 and hit_at <= 0.34, "(at %.2f s; wind %.2f + stroke %.2f)" % [hit_at, EnemyBreaker.WIND_T, EnemyBreaker.STRIKE_T])
	_check("the stroke hurts for smash_damage", is_equal_approx(hp0 - php.current_health, float(_e.get("smash_damage"))), "(%.0f)" % (hp0 - php.current_health))

	# (4) Settle.
	t = 0.0
	while t < 1.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var off := _head().distance_to(_rest)
	_check("a second later the hammer hangs at rest", off < 0.06, "(%.3f m)" % off)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
