extends Node3D
## Assertion probe for the opening-seconds attack grace (GameState.start_attack_grace):
## for ~2.5s after a level/respawn starts, enemies should still close in but must
## NOT land any damage; after grace lapses, fire should resume.
##   godot --headless --path . --quit-after 2000 res://tests/grace_probe.tscn

var _player: Node3D
var _php  # player Damageable
var _bot: Node3D

func _ready() -> void:
	# Floor so the enemy can stand + path with the straight-line fallback (no baked navmesh here).
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(200, 1, 200)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)

	_player = load("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 1, 0)
	_php = _player.get_node_or_null("Damageable")

	_bot = load("res://scenes/enemies/android.tscn").instantiate()
	add_child(_bot)
	_bot.global_position = Vector3(0, 0.5, 6)
	_bot.look_at(_player.global_position, Vector3.UP)

	GameState.set_state(GameState.State.PLAYING)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	if _php == null:
		print("FAIL no player Damageable found")
		get_tree().quit(1)
		return
	# Simulate the level-start / checkpoint-respawn grace kicking in right now.
	GameState.start_attack_grace(2.5)
	var hp0: float = _php.current_health
	print("t=0.0 hp=", hp0)

	var all_ok := true

	# t=2.0: grace should still be holding — no damage yet.
	await get_tree().create_timer(2.0).timeout
	var hp2: float = _php.current_health
	print("t=2.0 hp=", hp2)
	if hp2 != hp0:
		print("FAIL grace did not hold: hp dropped from ", hp0, " to ", hp2, " before t=2.0")
		all_ok = false
	else:
		print("PASS grace held through t=2.0 (hp unchanged)")

	# t=8.0: grace has lapsed — fire should have resumed and hp should have dropped.
	await get_tree().create_timer(6.0).timeout
	var hp8: float = _php.current_health
	print("t=8.0 hp=", hp8)
	if hp8 < hp2:
		print("PASS fire resumed after grace: hp dropped from ", hp2, " to ", hp8)
	else:
		print("FAIL fire did not resume after grace lapsed: hp still ", hp8)
		all_ok = false

	print("RESULT ", "PASS" if all_ok else "FAIL")
	get_tree().quit(0 if all_ok else 1)
