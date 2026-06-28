extends Node
## Dev probe: validates the EMP counter-move. (1) emp_disable() on an enemy sets a
## decrementing disable timer and keeps it inert; (2) the EMP grenade bursts on its
## fuse and disables a nearby enemy via radius detection — with no errors.
##   godot --headless --path . res://tests/emp_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var ENEMY := "res://scenes/enemies/android.tscn"

	# 1. Direct emp_disable.
	var e: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(e)
	await get_tree().physics_frame
	e.emp_disable(2.0)
	var t0: float = e._emp_t
	for i in 30:
		await get_tree().physics_frame
	var t1: float = e._emp_t
	var inert := Vector2(e.velocity.x, e.velocity.z).length() < 0.5
	print("DIRECT emp t0=%.2f t1=%.2f (decremented=%s) inert=%s" % [t0, t1, t1 < t0, inert])
	if not (t0 > 1.5 and t1 > 0.0 and t1 < t0 and inert):
		ok = false
	e.queue_free()

	# 2. EMP grenade burst disables a nearby enemy.
	var a2: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(a2)
	a2.global_position = Vector3.ZERO
	await get_tree().physics_frame
	var g: Node3D = load("res://scenes/weapons/grenade_emp.tscn").instantiate()
	get_tree().root.add_child(g)
	g.global_position = Vector3(1.0, 0.2, 0.0)
	g.throw_grenade(Vector3.ZERO, null)
	for i in 80: # > fuse, so it bursts
		await get_tree().physics_frame
	var disabled: bool = is_instance_valid(a2) and float(a2._emp_t) > 0.0
	var grenade_gone: bool = not is_instance_valid(g)
	print("GRENADE burst: nearby_disabled=%s grenade_freed=%s" % [disabled, grenade_gone])
	if not (disabled and grenade_gone):
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
