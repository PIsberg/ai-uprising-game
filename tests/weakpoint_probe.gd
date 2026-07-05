extends Node3D
## Headless probe for weak-point cores (enemy_base.gd _expose_weak_core /
## weakpoint_multiplier): a shot-up android should bare a glowing crit core the
## instant its first armour panel sheds, hits near the core should read as the
## bonus multiplier, and the core must not survive the wreck.
##   godot --headless --path . --quit-after 3000 res://tests/weakpoint_probe.tscn

var _fail := false

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	# Player dummy, far away — just a valid Node3D "source" for _on_damaged's
	# knockback/shed-direction math, not meant to interact with the android.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(50, 0, 50)
	add_child(player)

	var android: Node = load("res://scenes/enemies/android.tscn").instantiate()
	add_child(android)
	android.global_position = Vector3.ZERO
	if android.has_method("set_physics_process"):
		android.set_physics_process(false) # no AI — just the damage reactions
	await get_tree().process_frame
	await get_tree().process_frame

	# Bite it down in small steps until the first panel sheds (stage >= 1),
	# stopping well short of death (android max_health = 110).
	var steps := 0
	while android._shed_stage < 1 and steps < 20 and android.hp.current_health > 10.0:
		android.hp.apply_damage(20.0, player)
		steps += 1

	_check("shed_stage reached 1 (hp=%.1f)" % android.hp.current_health, android._shed_stage >= 1)
	var core_valid: bool = android._weak_core != null and is_instance_valid(android._weak_core)
	_check("weak core exists after first shed", core_valid)

	if core_valid:
		var core_pos: Vector3 = android._weak_core.global_position
		var at_core: float = android.weakpoint_multiplier(core_pos)
		var away: float = android.weakpoint_multiplier(core_pos + Vector3(2, 0, 0))
		_check("weakpoint_multiplier at core == 1.6 (got %.2f)" % at_core, is_equal_approx(at_core, 1.6))
		_check("weakpoint_multiplier away from core == 1.0 (got %.2f)" % away, is_equal_approx(away, 1.0))
	else:
		_check("weakpoint_multiplier at core == 1.6", false)
		_check("weakpoint_multiplier away from core == 1.0", false)

	# Kill it — the core must not linger pulsing on the wreck.
	android.hp.apply_damage(99999.0, player)
	await get_tree().process_frame
	_check("weak core freed on death", android._weak_core == null or not is_instance_valid(android._weak_core))

	print("RESULT: ", "FAIL" if _fail else "PASS")
	get_tree().quit(1 if _fail else 0)

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		_fail = true
