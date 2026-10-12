extends Node3D
## Probe: the MAITRE-D' (SERVER) whirls its trays when it attacks.
## serving_bot.glb is one mesh (a tiered column of serving trays under a face
## screen), so the attack is the whole model spinning: around every tray-bash
## and every cleaver throw the model's yaw relative to the body must sweep at
## least 300 degrees inside 0.6 s, and it must face forward again (within 5
## degrees) once the spin is over. Measured off the Model node's basis
## against the body's, accumulated frame to frame.
##   godot --headless --path . --audio-driver Dummy res://tests/server_spin_probe.tscn

var ok := true
var _e: Node3D

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
	pm.size = Vector2(80, 80)
	mi.mesh = pm
	region.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 1, 120)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

## The model's yaw relative to the body (radians).
func _yaw() -> float:
	var model := _e.get_node("Model") as Node3D
	var rel := _e.global_transform.basis.inverse() * model.global_transform.basis
	var f := rel * Vector3.FORWARD
	return atan2(-f.x, -f.z)

## Watch `secs`: [largest yaw swept inside any 0.6 s window, final yaw (deg)].
func _watch(secs: float) -> Array:
	var swept: Array[float] = [0.0]
	var times: Array[float] = [0.0]
	var prev := _yaw()
	var acc := 0.0
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var y := _yaw()
		acc += absf(wrapf(y - prev, -PI, PI))
		prev = y
		swept.append(acc)
		times.append(t)
	var best := 0.0
	var j := 0
	for i in swept.size():
		while times[i] - times[j] > 0.6:
			j += 1
		best = maxf(best, swept[i] - swept[j])
	return [rad_to_deg(best), rad_to_deg(absf(prev))]

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -9)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0
	while GameState.attack_grace_active():
		await get_tree().physics_frame
	_e = (load("res://scenes/enemies/server.tscn") as PackedScene).instantiate()
	add_child(_e)
	_e.global_position = Vector3.ZERO
	for i in 6:
		await get_tree().physics_frame
	_e.set("move_speed", 0.0)
	_e.set("target", player)
	_e.call("set_state", 3) # CHASE: 9 m out, it throws cleavers
	var thrown: Array = await _watch(3.0)
	print("  cleaver throws: swept %.0f deg in 0.6 s, ends at %.1f deg" % [thrown[0], thrown[1]])
	_check("whirls on a cleaver throw", thrown[0] >= 300.0, "(%.0f deg)" % thrown[0])

	# Up close: the tray-bash.
	player.global_position = _e.global_position + Vector3(0, 0.1, -2.0)
	_e.set("_cleaver_cd", 999.0)
	_e.call("set_state", 4) # ATTACK
	var bash: Array = await _watch(3.0)
	print("  tray-bash: swept %.0f deg in 0.6 s, ends at %.1f deg" % [bash[0], bash[1]])
	_check("whirls on a tray-bash", bash[0] >= 300.0, "(%.0f deg)" % bash[0])

	# Settles facing forward.
	_e.set("target", null)
	_e.call("set_state", 0)
	var rest: Array = await _watch(1.0)
	_check("faces forward again after", rest[1] < 5.0, "(%.1f deg)" % rest[1])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
