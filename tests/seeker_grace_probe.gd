extends Node3D
## Assertion probe: the opening-seconds attack grace must hold against CONTACT
## damage, not just ranged fire.
##
## Regression: EnemySeeker is a kamikaze — it deals its damage from
## `_check_detonate()` driven by `_physics_process`, entirely outside the
## `_state_attack` path where EnemyBase applies `GameState.attack_grace_active()`.
## So it flew in and detonated on a player who had just loaded the level, before
## they could move. Caught by tests/spawn_safety_probe on lava_world
## (GRACE-LEAK <- enemy_seeker).
##
## Measured off the `damaged` signal, testing `attack_grace_active()` AT THE
## MOMENT OF THE HIT. Sampling health on a timer cannot do this: the seeker
## detonates the instant grace lapses, so any polling loop straddles the boundary
## and blames the grace window for a legitimate hit.
##   godot --headless --path . --audio-driver Dummy res://tests/seeker_grace_probe.tscn

const GRACE := 2.5

var _player: Node3D
var _php: Damageable
var _dmg_in_grace: float = 0.0
var _dmg_after: float = 0.0

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(200, 1, 200)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	_player = load("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 1, 0)
	_php = _player.get_node_or_null("Damageable")

	var seeker: Node3D = load("res://scenes/enemies/seeker.tscn").instantiate()
	add_child(seeker)
	seeker.global_position = Vector3(0, 1.5, 7)

	GameState.set_state(GameState.State.PLAYING)
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	if _php == null:
		print("FAIL no player Damageable"); print("RESULT FAIL"); get_tree().quit(1); return
	_php.damaged.connect(_on_hit)
	GameState.start_attack_grace(GRACE)
	var ok := true

	# Phase 1 — through grace. The seeker may close in; it must not land the blast.
	while GameState.attack_grace_active():
		await get_tree().create_timer(0.1).timeout
	print("during grace: %.1f damage landed (expect 0)" % _dmg_in_grace)
	if _dmg_in_grace > 0.0:
		print("FAIL contact damage landed during grace"); ok = false
	else:
		print("PASS grace held against the kamikaze")

	# Phase 2 — grace is gone. It must still be lethal; the gate defers, not defuses.
	var t := 0.0
	while t < 6.0 and _dmg_after <= 0.0:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	print("after grace: %.1f damage landed within %.1fs (expect > 0)" % [_dmg_after, t])
	if _dmg_after > 0.0:
		print("PASS seeker still detonates once grace lapses")
	else:
		print("FAIL seeker never detonated after grace — defused, not deferred")
		ok = false

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _on_hit(amount: float, _source: Node) -> void:
	if GameState.attack_grace_active():
		_dmg_in_grace += amount
	else:
		_dmg_after += amount
