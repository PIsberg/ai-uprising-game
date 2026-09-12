extends Node3D
## Regression probe for the HOWITZER ballistic-lead bug: enemy_howitzer.gd's
## _fire_shell() lofted its shot assuming g=9.8, but the shell itself falls
## under the PROJECT's actual gravity (project.godot physics/3d/default_gravity
## = 24.0) via projectile.gd's own ProjectSettings lookup. The stale constant
## under-lofted every shell by 2.45x, so it hit the floor ~9 m short of a
## target at the howitzer's own preferred range (32 m) and never landed a hit.
## Found via tests/silent_robot_probe.gd. Asserts the player actually takes
## damage from a howitzer firing at its own preferred range.
##   godot --headless --path . res://tests/howitzer_hit_probe.tscn

const WINDOW := 16.0 # first shell lands ~4.6s in (reaction+windup+~1s flight); leave room for a second volley

var _player: Node3D
var _taken: float = 0.0

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
	hp.damaged.connect(func(amount: float, _src): _taken += amount)
	while GameState.attack_grace_active():
		await get_tree().physics_frame

	var e: Node3D = (load("res://scenes/enemies/howitzer.tscn") as PackedScene).instantiate()
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

	print("HOWITZER: damage taken by player in %.1fs at preferred_range=%.1f: %.1f" % [WINDOW, pref, _taken])
	if _taken > 0.0:
		print("RESULT PASS")
	else:
		print("RESULT FAIL")
	get_tree().quit()
