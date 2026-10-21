extends Node3D
## Regression probe for the WARBOT cross-fire geometry: enemy_warbot.gd fired
## its two arm-cannons in a fixed 6-degree V, which put each stream 1.15 m off
## the aim line at its 11 m preferred range - three times the player's 0.35 m
## capsule radius - so BOTH barrels missed a still target every time. The
## threat sweep measured 0.4 DPS against 13.5 for the android AI it reuses.
## The V is now a half-width in metres at the target (0.45 m; furious 0.15 m),
## so bracketing the body works at every range and base scatter decides hits.
## Asserts a warbot at its own preferred range lands materially more than the
## old geometry's ~10 damage in 12 s (fix measures ~115-135; android ~170).
##   godot --headless --path . --audio-driver Dummy res://tests/warbot_crossfire_probe.tscn

const WINDOW := 12.0
const MIN_DAMAGE := 40.0 ## old 6-degree V: ~10 in 12 s; fixed: ~115-135

var _player: Node3D
var _taken: float = 0.0
var _hits: int = 0

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
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	region.add_child(body)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	region.navigation_mesh = nm
	region.bake_navigation_mesh()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_build_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector3.ZERO
	_player.set_physics_process(false)
	await get_tree().physics_frame
	var hp: Node = _player.get_node_or_null("Damageable")
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src):
		_taken += amount
		_hits += 1)
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	var e: Node3D = (load("res://scenes/enemies/warbot.tscn") as PackedScene).instantiate()
	add_child(e)
	var pref: float = float(e.get("preferred_range"))
	e.global_position = Vector3(0, 0, -pref)
	e.rotation = Vector3(0, PI, 0) # face the player: sight forward is -Z (see threat_probe)
	for i in 3:
		await get_tree().physics_frame
	e.set("target", _player)
	if e.has_method("set_state"):
		e.call("set_state", 4) # State.ATTACK

	var t := 0.0
	while t < WINDOW:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if is_instance_valid(_player):
			var php: Node = _player.get_node_or_null("Damageable")
			if php:
				php.current_health = 1000000.0

	print("WARBOT: %d bolts landed, %.1f damage in %.1fs at preferred_range=%.1f (need >= %.0f)" % [_hits, _taken, WINDOW, pref, MIN_DAMAGE])
	if _taken >= MIN_DAMAGE:
		print("RESULT PASS")
	else:
		print("RESULT FAIL")
	get_tree().quit()
