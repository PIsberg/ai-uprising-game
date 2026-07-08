extends Node3D
## Verifies the MAULER's OVERLOAD "wounded mauler RUNS" sprint is actually applied.
## The bug: _begin_overload bumped _speed_mult (spent once at spawn in _sync_stats,
## never re-read) so the sprint was dead. Fixed to bump live move_speed.
## Expect: after HP drops below overload_at, move_speed ~1.7x its base and
## chase_speed() rises accordingly.
## Run: godot --headless --path . res://tests/mauler_overload_probe.tscn

func _ready() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var pdmg := Damageable.new(); pdmg.name = "Damageable"; pdmg.max_health = 9999.0
	pdmg.invulnerable = true; player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(0, 1, 0)

	var m: EnemyMauler = (load("res://scenes/enemies/mauler.tscn") as PackedScene).instantiate()
	add_child(m)
	m.global_position = Vector3(0, 0.5, 12)
	await get_tree().process_frame
	await get_tree().physics_frame  # let _sync_stats (deferred) land

	m.target = player
	var base_speed: float = m.move_speed
	var base_chase: float = m.chase_speed()

	# Trip overload: drop health below overload_at (0.35).
	m.hp.current_health = m.hp.max_health * 0.20
	# One physics tick runs _physics_process -> _begin_overload.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var od_speed: float = m.move_speed
	var od_chase: float = m.chase_speed()
	var ratio: float = od_speed / maxf(base_speed, 0.01)
	print("MAULER base_speed=%.2f overload_speed=%.2f ratio=%.2f  base_chase=%.2f overload_chase=%.2f  overloading=%s" % [
		base_speed, od_speed, ratio, base_chase, od_chase, m._overloading])

	var ok := m._overloading and ratio > 1.6 and ratio < 1.8 and od_chase > base_chase * 1.5
	print("MAULER_OVERLOAD ", "OK" if ok else "FAIL")
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
