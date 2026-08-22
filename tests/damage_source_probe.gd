extends Node
## Dev probe: Damageable.apply_damage must survive a FREED `source` (the shooter
## died before its projectile landed) and still apply the damage.
##
## Regression: the guard read `source is Node and is_instance_valid(source)`.
## `and` short-circuits left-to-right, so `is` ran first on the freed instance and
## raised "Left operand of 'is' is a previously freed instance" — which aborts
## apply_damage, so the hit silently dealt ZERO damage. Seen live in
## tests/pacing_sweep (projectile.gd:324 -> damageable.gd:25).
##   godot --headless --path . res://tests/damage_source_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true

	# 1. Freed Node source — the case that regressed. Damage must still land.
	var victim := Node3D.new()
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 100.0
	victim.add_child(hp)
	get_tree().root.add_child(victim)
	await get_tree().physics_frame

	var shooter := Node3D.new()
	get_tree().root.add_child(shooter)
	await get_tree().physics_frame
	shooter.free()   # immediate free -> `source` is now a freed instance

	hp.apply_damage(25.0, shooter)
	var after_freed := hp.current_health
	print("FREED-SOURCE  hp=%.1f (expect 75.0)" % after_freed)
	if not is_equal_approx(after_freed, 75.0):
		ok = false

	# 2. Live non-Node Object source must be demoted to null, not crash the
	#    Node-typed `damaged`/`died` signals.
	var got_src_is_null := [false]
	hp.damaged.connect(func(_a: float, s: Node) -> void: got_src_is_null[0] = (s == null))
	var refc := RefCounted.new()
	hp.apply_damage(10.0, refc)
	print("NONNODE-SRC   hp=%.1f (expect 65.0) demoted_to_null=%s" % [hp.current_health, got_src_is_null[0]])
	if not (is_equal_approx(hp.current_health, 65.0) and got_src_is_null[0]):
		ok = false

	# 3. Plain null source still works.
	hp.apply_damage(5.0, null)
	print("NULL-SRC      hp=%.1f (expect 60.0)" % hp.current_health)
	if not is_equal_approx(hp.current_health, 60.0):
		ok = false

	# 4. A LIVE Node source is preserved (the guard must not over-demote).
	var live := Node3D.new()
	get_tree().root.add_child(live)
	await get_tree().physics_frame
	var seen_src: Array = [null]
	hp.damaged.connect(func(_a: float, s: Node) -> void: seen_src[0] = s)
	hp.apply_damage(5.0, live)
	print("LIVE-SRC      hp=%.1f (expect 55.0) preserved=%s" % [hp.current_health, seen_src[0] == live])
	if not (is_equal_approx(hp.current_health, 55.0) and seen_src[0] == live):
		ok = false

	victim.queue_free()
	live.queue_free()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
