extends Node3D
## Jam-shielded objective cores (ObjectiveCore.jam_shielded, hivemind's mesh
## relays): the core shrugs off damage until a jam zone covers it, takes damage
## while one does, closes again when the zone expires, and a zone out of range
## does nothing; an unshielded core is the control that proves the damage path
## fires. Then every campaign core authored jam_shielded sits on a level that
## grants the jammer (else it can never die). Live: hivemind builds, both relays
## are shielded, the HIVE PRIME stays staged until both fall and goes live after.
##   godot --headless --path . --audio-driver Dummy res://tests/jam_relay_probe.tscn

var _fails: Array[String] = []

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	_campaign()
	await _live()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _wait(secs: float) -> void:
	await _frames(int(ceil(secs * Engine.physics_ticks_per_second)) + 2)

func _jam(at: Vector3, radius: float, lifetime: float) -> JamZone:
	var z := JamZone.new()
	z.radius = radius
	z.lifetime = lifetime
	z.position = at
	add_child(z)
	return z

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("relay", "Relay", 0.0)
	var core := ObjectiveCore.new()
	core.task_id = "relay"
	core.max_health = 100.0
	core.jam_shielded = true
	core.position = Vector3(0, 0, 0)
	add_child(core)
	var plain := ObjectiveCore.new()
	plain.task_id = "plain_never_registered"
	plain.max_health = 100.0
	plain.position = Vector3(30, 0, 0)
	add_child(plain)
	await _frames(3)
	core.hp.apply_damage(40.0)
	plain.hp.apply_damage(40.0)
	_check(is_equal_approx(core.hp.current_health, 100.0), "a shielded core shrugs off damage with no jam zone")
	_check(is_equal_approx(plain.hp.current_health, 60.0), "control: an unshielded core takes the same hit")
	var far := _jam(Vector3(12, 0, 0), 5.0, 5.0)
	await _frames(3)
	core.hp.apply_damage(40.0)
	_check(not core.exposed and is_equal_approx(core.hp.current_health, 100.0), "a jam zone out of range leaves the shield up")
	far.queue_free()
	_jam(Vector3(2, 0, 0), 5.0, 0.8)
	await _frames(3)
	core.hp.apply_damage(40.0)
	_check(core.exposed and is_equal_approx(core.hp.current_health, 60.0), "inside a jam zone the core takes damage (%.0f)" % core.hp.current_health)
	await _wait(1.2)
	core.hp.apply_damage(40.0)
	_check(not core.exposed and is_equal_approx(core.hp.current_health, 60.0), "the shield closes again when the zone expires")
	_jam(Vector3(0, 0, 2), 5.0, 3.0)
	await _frames(3)
	core.hp.apply_damage(80.0)
	await _frames(3)
	_check(GameState.is_task_done("relay"), "a jammed core can be destroyed and completes its task")
	if is_instance_valid(plain):
		plain.queue_free()
	for z in get_tree().get_nodes_in_group("jam_zone"):
		z.queue_free()
	GameState.reset_tasks()
	await _frames(3)

func _campaign() -> void:
	print("campaign:")
	var n := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for t in def.get("tasks", []):
			if t.get("type", "") == "destroy_core" and t.get("jam_shielded", false):
				n += 1
				_check(def.get("jammer", null) != null, "%s: jam-shielded core '%s' is on a level that grants the jammer" % [id, t.get("id", "core")])
	_check(n >= 2, "campaign authors jam-shielded relays (%d)" % n)

func _staged(id: String) -> bool:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return bool(t.get("staged", false))
	return false

func _live() -> void:
	print("live:")
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	for i in 10:
		await get_tree().create_timer(0.25).timeout
	GameState.current_state = GameState.State.PLAYING
	var relays: Array = []
	for c in get_tree().get_nodes_in_group("objective_core"):
		if (c as ObjectiveCore).jam_shielded:
			relays.append(c)
	_check(relays.size() == 2, "hivemind builds two jam-shielded relays (%d)" % relays.size())
	_check(_staged("hvt"), "the HIVE PRIME waits, staged, while the relays stand")
	for r in relays:
		(r as ObjectiveCore).hp.apply_damage(500.0)
	await _frames(3)
	_check(relays.all(func(r): return is_instance_valid(r)), "unjammed relays survive a 500 damage hit")
	_check(_staged("hvt"), "the PRIME is still staged after the shrugged-off hits")
	for r in relays:
		var rc := r as ObjectiveCore
		_jam(rc.global_position + Vector3(1, 0, 0), 6.5, 2.0)
	await _frames(3)
	for r in relays:
		if is_instance_valid(r):
			(r as ObjectiveCore).hp.apply_damage(500.0)
	await _frames(6)
	_check(GameState.is_task_done("relay_w") and GameState.is_task_done("relay_e"), "jammed relays fall and complete their tasks")
	_check(not _staged("hvt"), "with both relays down the PRIME goes live")
	lvl.queue_free()
	await _frames(3)
