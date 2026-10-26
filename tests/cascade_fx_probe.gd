extends Node
## Probe: the CX-4 Cascade's look (CascadeFx, scripts/weapons/fx/cascade_fx.gd,
## and the prime/chain visuals in scripts/weapons/cascade.gd):
##   - its tracer is the quick cyan dart (1.6 m at 185 m/s);
##   - a round into a robot stamps one hexagonal tag flat on the plating, which
##     snaps down from twice its size and is gone within a second;
##   - a primed robot wears a hex fuse ring (six segments) that spins, and whose
##     blink quickens as the prime runs out; it is hidden once the prime expires;
##   - one kill in a ring of robots draws a link arc from each detonation to each
##     robot it primes (at least one per robot chained), and every arc fades;
##   - an unsigned Cascade (signature cleared) stamps no tag, while its prime
##     still wears the fuse ring (chain-primed robots wear it too).
##   godot --headless --path . --audio-driver Dummy res://tests/cascade_fx_probe.tscn

const ANDROID := "res://scenes/enemies/android.tscn"
const CASCADE := "res://scenes/weapons/cascade.tscn"
const CASCADE_FX := "res://scripts/weapons/fx/cascade_fx.gd"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(400, 1, 400)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 80)

	var gun: Weapon = (load(CASCADE) as PackedScene).instantiate()
	add_child(gun)
	gun._active_shooter = shooter
	var ctl: Weapon = (load(CASCADE) as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl._active_shooter = shooter
	await get_tree().process_frame
	_check("the CX-4 carries the Cascade signature",
			gun._sig != null and gun._sig.get_script() != null and gun._sig.get_script().resource_path == CASCADE_FX)

	# Tracer.
	var t := _spawned(func() -> void: gun._spawn_tracer(Vector3(0, 1.4, 5), Vector3(0, 1, -20)), "")
	_check("the CX-4's tracer is the quick dart (1.6 m at 185 m/s)",
			t.size() == 1 and is_equal_approx(t[0].bolt_length, 1.6) and is_equal_approx(t[0].bolt_speed, 185.0))
	for n in t:
		n.queue_free()

	# Tag + fuse on a tough robot.
	var tough := _robot(Vector3(20, 0, 0))
	await _frames(3)
	_set_hp(tough, 400.0)
	var hit := _spawned(func() -> void:
			gun._do_hitscan(tough.global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1)), "cascade_tag")
	_check("a round into a robot stamps one hex tag", hit.size() == 1, str(hit.size()))
	if hit.size() == 1:
		var tag: MeshInstance3D = hit[0]
		_check("the tag lies flat on the struck face", absf(tag.global_basis.y.normalized().dot(Vector3.BACK)) > 0.95,
				str(tag.global_basis.y))
		_check("the tag is a hexagon", (tag.mesh as TorusMesh).rings == 6)
		_check("the tag snaps down from twice its size", tag.scale.x > 1.5, "%.2f" % tag.scale.x)
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(tag) and Time.get_ticks_msec() - t0 < 1200:
			await get_tree().process_frame
		_check("the tag is gone within a second", not is_instance_valid(tag))
	var charge = tough.get_node_or_null("CascadeCharge")
	_check("the hit primed the robot", Cascade.is_primed(tough))
	var fuse: MeshInstance3D = charge.fuse if charge else null
	_check("a primed robot wears a fuse ring", fuse != null and fuse.visible)
	if fuse:
		_check("the fuse ring is a hexagon", (fuse.mesh as TorusMesh).rings == 6)
		var p_fresh: float = charge.fuse_period()
		var yaw0 := fuse.rotation.y
		for i in 6:
			await get_tree().process_frame
		_check("the fuse ring spins", not is_equal_approx(fuse.rotation.y, yaw0), "%.2f -> %.2f" % [yaw0, fuse.rotation.y])
		charge.expires_ms = Time.get_ticks_msec() + 300
		var p_late: float = charge.fuse_period()
		_check("the blink quickens as the prime runs out", p_late < p_fresh * 0.5, "%.2f -> %.2f s" % [p_fresh, p_late])
		charge.expires_ms = Time.get_ticks_msec() - 1
		for i in 3:
			await get_tree().process_frame
		_check("an expired prime hides its fuse ring", not fuse.visible)

	# Unsigned: no tag, but the prime still wears the ring.
	var tough2 := _robot(Vector3(-20, 0, 0))
	await _frames(3)
	_set_hp(tough2, 400.0)
	var chit := _spawned(func() -> void:
			ctl._do_hitscan(tough2.global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1)), "cascade_tag")
	_check("an unsigned Cascade stamps no tag", chit.is_empty())
	var c2 = tough2.get_node_or_null("CascadeCharge")
	_check("its prime still wears the fuse ring", c2 != null and c2.fuse != null and c2.fuse.visible)

	# A chain: link arcs from each detonation to the robots it primes.
	var ring := _ring(Vector3(0, 0, -40), 5, 2.2)
	await _frames(3)
	for e in ring:
		_set_hp(e, gun.data.cascade_damage * 0.6)
	ring[0].hp.current_health = 1.0
	var links: Array = []
	var watch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") == "cascade_link":
			links.append(n)
	get_tree().node_added.connect(watch)
	gun._do_hitscan(ring[0].global_position + Vector3(0, 1.2, 10), Vector3(0, 0, -1))
	for i in 6:
		await get_tree().create_timer(0.25).timeout
	get_tree().node_added.disconnect(watch)
	var dead := ring.filter(func(e) -> bool: return not is_instance_valid(e) or not e.hp.is_alive()).size()
	_check("the ring chained", dead == ring.size(), "%d / %d" % [dead, ring.size()])
	_check("each chained robot was linked by an arc", links.size() >= ring.size() - 1, "%d arcs" % links.size())
	_check("every link arc has faded", links.all(func(n) -> bool: return not is_instance_valid(n)))
	# Let the wrecks finish dying and free the robots before quitting: a wreck
	# still dissolving at exit makes the dummy renderer log null-material errors.
	for i in 12:
		await get_tree().create_timer(0.25).timeout
	for c in get_children():
		if c is EnemyBase:
			c.queue_free()
	await _frames(2)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _spawned(action: Callable, tag: String) -> Array:
	var root := get_tree().current_scene
	var before := root.get_children()
	action.call()
	var out: Array = []
	for n in root.get_children():
		if n in before:
			continue
		if tag == "" or n.get_meta("sig_fx", "") == tag:
			out.append(n)
	return out

func _ring(center: Vector3, n: int, r: float) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * i / n
		out.append(_robot(center + Vector3(cos(a), 0, sin(a)) * r))
	return out

func _set_hp(e: EnemyBase, health: float) -> void:
	e.hp.max_health = health
	e.hp.current_health = health

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(e)
	e.global_position = pos
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set_physics_process(false)
	return e
