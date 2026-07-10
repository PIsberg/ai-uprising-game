extends Node
## Dev probe: validates the HIJACK counter-move end to end.
## (1) hijack() flips a unit to the player's side (flag, group, player collision
##     layer) and it zaps a nearby hostile robot (cross-side damage lands);
## (2) the hostile retargets the traitor (traitor priority in _perceive);
## (3) at burnout the stolen unit dies and its bookkeeping is cleaned up;
## (4) the HIJACK grenade bursts and converts the nearest robot in radius;
## (5) a boss-fat chassis resists conversion and gets EMP'd instead.
##   godot --headless --path . res://tests/hijack_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var ENEMY := "res://scenes/enemies/android.tscn"

	# 1+2. Direct hijack: traitor fights, hostile retargets it.
	var a: Node3D = load(ENEMY).instantiate()
	var b: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(a)
	get_tree().root.add_child(b)
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(6.0, 0.0, 0.0)
	await get_tree().physics_frame
	var converted: bool = a.hijack(1.4, null)
	var flags_ok: bool = converted and a.hijacked and a.is_in_group("hijacked") and a.collision_layer == 2
	print("HIJACK flags: converted=%s flag=%s group=%s layer=%d" % [converted, a.hijacked, a.is_in_group("hijacked"), a.collision_layer])
	if not flags_ok:
		ok = false
	for i in 45: # ~0.75s: at least one zap should land, hostile should retarget
		await get_tree().physics_frame
	var b_hp: float = b.hp.current_health
	var zapped: bool = b_hp < b.hp.max_health
	var traitor_targeted: bool = b.target == a
	print("HIJACK combat: foe=%s b_hp=%.0f/%.0f zapped=%s traitor_targeted=%s" % [a.target, b_hp, b.hp.max_health, zapped, traitor_targeted])
	if not (a.target == b and zapped and traitor_targeted):
		ok = false

	# 3. Burnout: past hijack_time the stolen chassis dies and cleans up.
	for i in 70: # push total elapsed past 1.4s
		await get_tree().physics_frame
	var burned: bool = is_instance_valid(a) and not a.hp.is_alive()
	var cleaned: bool = is_instance_valid(a) and not a.hijacked and not a.is_in_group("hijacked")
	print("BURNOUT: dead=%s cleaned=%s" % [burned, cleaned])
	if not (burned and cleaned):
		ok = false
	if is_instance_valid(a):
		a.queue_free()
	if is_instance_valid(b):
		b.queue_free()

	# 4. Grenade burst converts the nearest robot in radius.
	var c: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(c)
	c.global_position = Vector3(0.0, 0.0, 40.0) # away from test-1 corpses
	await get_tree().physics_frame
	var g: Node3D = load("res://scenes/weapons/grenade_hijack.tscn").instantiate()
	get_tree().root.add_child(g)
	g.global_position = Vector3(1.0, 0.2, 40.0)
	g.throw_grenade(Vector3.ZERO, null)
	for i in 80: # > fuse, so it bursts
		await get_tree().physics_frame
	var converted2: bool = is_instance_valid(c) and c.hijacked
	var grenade_gone: bool = not is_instance_valid(g)
	print("GRENADE burst: converted=%s grenade_freed=%s" % [converted2, grenade_gone])
	if not (converted2 and grenade_gone):
		ok = false
	if is_instance_valid(c):
		c.queue_free()

	# 5. Boss-fat chassis resists: no conversion, short EMP fallback instead.
	var d: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(d)
	d.global_position = Vector3(0.0, 0.0, 80.0)
	await get_tree().physics_frame
	d.max_health = 900.0 # boss-sized pool
	var stole: bool = d.hijack(12.0, null)
	var resisted: bool = (not stole) and (not d.hijacked) and float(d._emp_t) > 0.0
	print("BOSS resist: stole=%s hijacked=%s emp_t=%.1f" % [stole, d.hijacked, d._emp_t])
	if not resisted:
		ok = false
	d.queue_free()

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
