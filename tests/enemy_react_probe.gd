extends Node3D
## Headless assertions for the enemy-reaction pass:
##  1) GRENADE SCRAMBLE — a combat-aware android moves AWAY from a live grenade
##     dropped at its feet (an unaware idler must NOT react).
##  2) KILL ROUSES ALLIES — the killing hit's damage-alert (enemy_base
##     _on_damaged, 16 m) turns a nearby IDLE ally onto the killer.
##   godot --headless --path . --quit-after 2000 res://tests/enemy_react_probe.tscn

const ANDROID := preload("res://scenes/enemies/android.tscn")
const GRENADE := preload("res://scenes/weapons/grenade.tscn")

var _fails := 0

func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fails += 1

func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	body.position = Vector3(0, -0.5, 0)
	shape.position = Vector3.ZERO
	body.add_child(shape)
	add_child(body)

func _ready() -> void:
	_floor()
	# Stand-in player far away, so perception doesn't interfere with the setup.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.position = Vector3(60, 1, 60)
	add_child(player)
	await get_tree().create_timer(0.5).timeout # let enemies finish _ready/_sync_stats

	# --- 1) grenade scramble ---
	var aware: Node = ANDROID.instantiate()
	add_child(aware)
	aware.global_position = Vector3(0, 0.5, 0)
	# Outside the 22 m first-contact rally ring, or phase 1's CHASE rouses it.
	var idler: Node = ANDROID.instantiate()
	add_child(idler)
	idler.global_position = Vector3(30, 0.5, 0)
	await get_tree().physics_frame
	aware.target = player
	aware.set_state(aware.State.CHASE)
	aware._has_last_known = true
	aware._last_known_target_pos = player.global_position

	var g: Node = GRENADE.instantiate()
	add_child(g)
	g.global_position = Vector3(1.2, 0.4, 0)
	g.fuse = 60.0 # never detonates during the test
	g.freeze = true

	var d0: float = aware.global_position.distance_to(g.global_position)
	var idler_p0: Vector3 = idler.global_position
	await get_tree().create_timer(1.0).timeout
	var d1: float = aware.global_position.distance_to(g.global_position)
	_check("aware android scrambles away from grenade (%.1f -> %.1f m)" % [d0, d1], d1 > d0 + 1.0)
	_check("unaware idler holds position", idler.global_position.distance_to(idler_p0) < 0.5)
	g.queue_free()
	aware.queue_free()

	# --- 2) death alert ---
	var victim: Node = ANDROID.instantiate()
	add_child(victim)
	victim.global_position = Vector3(36, 0.5, 6) # ~8.5 m from the idler: inside the 16 m damage-alert ring
	await get_tree().physics_frame
	_check("ally starts unaware", idler.state == idler.State.IDLE or idler.state == idler.State.PATROL)
	victim.target = player # it knew about the player; its death shares that
	victim.hp.apply_damage(99999.0, player)
	await get_tree().create_timer(0.3).timeout
	_check("nearby ally roused by the kill", idler.state != idler.State.IDLE and idler.state != idler.State.PATROL)
	_check("roused ally hunts the killer", idler.target == player)

	print("REACT_PROBE_DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)
