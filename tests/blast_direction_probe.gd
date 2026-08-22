extends Node3D
## Assertion probe: a BRUTE's frontal shield must judge an explosion by where the
## BLAST went off, not by where the player happens to be standing.
##
## Regression (issue #63): EnemyBrute.modify_incoming_damage took its direction
## from `source`, and every splash path passes the SHOOTER as source (deliberately,
## so kills pay score). So the shield asked "is the player in front of me?" instead
## of "did the blast come from in front of me?" — and a grenade landing BEHIND a
## brute was still blocked at 90% because the thrower stood in front. That inverts
## the brute's whole counter-play: positioning the explosive did nothing.
##
## Both cases keep the player in FRONT of the brute. Only the grenade moves.
##   godot --headless --path . --audio-driver Dummy res://tests/blast_direction_probe.tscn

const GRENADE := "res://scenes/weapons/grenade.tscn"

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(120, 1, 120)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	_run.call_deferred()

func _run() -> void:
	var ok := true
	# A brute at rotation 0 faces -Z (fwd = -basis.z). The player stands in front
	# of it for BOTH cases — it is the grenade that moves.
	var front := Vector3(0, 1.0, -2.0)
	var behind := Vector3(0, 1.0, 2.0)

	var d_behind := await _blast_damage(behind, front)
	var d_front := await _blast_damage(front, front)
	print("blast BEHIND brute (player in front): %.1f damage" % d_behind)
	print("blast IN FRONT of brute            : %.1f damage" % d_front)

	# Behind: the shield does not cover the back, so the blast must land properly.
	# Front: the shield is doing its job and must still cut it down.
	if d_behind <= 0.0:
		print("FAIL blast behind the brute dealt nothing at all"); ok = false
	elif d_front <= 0.0:
		print("FAIL blast in front dealt nothing — cannot tell blocking from a miss"); ok = false
	elif d_behind <= d_front * 2.0:
		print("FAIL flanking gains nothing: behind=%.1f front=%.1f (want behind >> front)" % [d_behind, d_front])
		ok = false
	else:
		print("PASS flanking works: behind %.1f vs front %.1f (%.1fx)" % [
			d_behind, d_front, d_behind / maxf(d_front, 0.01)])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Detonates one grenade at `blast_pos`, thrown by a player standing at
## `player_pos`, and returns how much health the brute actually lost.
func _blast_damage(blast_pos: Vector3, player_pos: Vector3) -> float:
	var brute: Node3D = load("res://scenes/enemies/brute.tscn").instantiate()
	add_child(brute)
	brute.global_position = Vector3.ZERO
	brute.rotation = Vector3.ZERO # faces -Z

	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	add_child(player)
	player.global_position = player_pos

	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp: Damageable = brute.get_node("Damageable")
	# Neutralise the wake/entrance grace so the shield logic is what we measure.
	GameState.set_state(GameState.State.PLAYING)
	var before: float = hp.current_health

	var g: Node3D = load(GRENADE).instantiate()
	add_child(g)
	g.global_position = blast_pos
	g.set("_shooter", player)
	await get_tree().physics_frame
	g.call("_explode")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lost: float = before - hp.current_health

	brute.queue_free()
	player.queue_free()
	if is_instance_valid(g):
		g.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return lost
