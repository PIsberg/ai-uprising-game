extends Node3D
## Probe: the CL-3 Arc Coil's signature (ArcCoilFx, scripts/weapons/fx/arc_coil_fx.gd):
##   - three coil rings sit round the bore behind the muzzle, all lit when fresh;
##   - each round of a burst drains one ring (3 lit, then 2, 1, 0 across a
##     burst), the drained rings darker than the lit ones;
##   - through the cooldown they recharge one by one (0, 1, 2, 3), all three
##     within 1 s (driven in fixed steps);
##   - a round into a wall throws SURFACE_ARCS arcs that lie along the wall
##     (not out of it) and fade within 0.5 s;
##   - a round into a robot with another robot 3 m off throws one arc on to the
##     other robot; with the other robot 12 m off, none;
##   - an unsigned Arc Coil has no rings and throws no arcs.
##   godot --headless --path . --audio-driver Dummy res://tests/arccoil_fx_probe.tscn

const ARC_COIL_FX := "res://scripts/weapons/fx/arc_coil_fx.gd"

var ok := true
var cam: Camera3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 1.5, 0.3), Vector3(0, 1.5, -30), Vector3.UP)
	var wall := _wall(Vector3(-5, 1.5, -10))
	var robot := _robot(Vector3(4, 0, -8))
	var buddy := _robot(Vector3(7, 0, -8))
	var w: Weapon = (load("res://scenes/weapons/arccoil.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var ctl: Weapon = (load("res://scenes/weapons/arccoil.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, 0)
	await get_tree().process_frame
	await get_tree().physics_frame
	var sig: ArcCoilFx = w._sig as ArcCoilFx
	_check("the CL-3 carries the Arc Coil signature",
			sig != null and sig.get_script().resource_path == ARC_COIL_FX)
	# Rings found on the muzzle (not through the signature), so an unwired gun
	# fails the look checks below instead of skipping them.
	if sig:
		sig.on_process(0.0)
	var rings: Array = w.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "coil_ring")
	_check("three coil rings sit round the bore", rings.size() == 3, str(rings.size()))
	if rings.size() == 3:
		var bore := -w.muzzle.global_basis.z.normalized()
		var round_bore := true
		for r: Node3D in rings:
			round_bore = round_bore and absf(r.global_basis.y.normalized().dot(bore)) > 0.95 and (r.global_position - w.muzzle.global_position).dot(bore) < 0.0
		_check("the rings wrap the bore, behind the muzzle", round_bore)
	_check("all three lit when fresh", sig != null and sig.lit_rings() == 3)

	# A burst drains them.
	w._active_camera = cam
	w._active_shooter = null
	w.mag = maxi(w.mag, 20)
	if sig == null:
		_check("each round of the burst drains one ring (2, 1, 0)", false, "no signature")
	else:
		_burst_and_refill(w, sig, rings)

	# Surface discharge on a wall.
	var origin := Vector3(0, 1.5, 0)
	var wdir := (wall.global_position + Vector3(0, 0, 0.25) - origin).normalized()
	await get_tree().process_frame
	var whits := _spawned(func() -> void: w._do_hitscan(origin, wdir), "surface_arc")
	_check("a round into a wall throws SURFACE_ARCS arcs", whits.size() == ArcCoilFx.SURFACE_ARCS, str(whits.size()))
	if not whits.is_empty():
		var flat := true
		for b: ArcBolt in whits:
			for p in b.points():
				flat = flat and absf(p.z - (-10 + 0.25)) < 0.12
		_check("the arcs lie along the wall", flat)
		await _wait(0.5)
		_check("the arcs fade within 0.5 s", whits.all(func(b) -> bool: return not is_instance_valid(b)))

	# Arc jump to a nearby robot.
	await get_tree().process_frame
	var rdir := (robot.global_position + Vector3(0, 1.2, 0.4) - origin).normalized()
	var jumps := _spawned(func() -> void: w._do_hitscan(origin, rdir), "arc_jump")
	_check("a round into a robot throws one arc on to a robot 3 m off", jumps.size() == 1, str(jumps.size()))
	if jumps.size() == 1:
		var pts: PackedVector3Array = (jumps[0] as ArcBolt).points()
		var end := pts[pts.size() - 1]
		_check("the arc lands on the other robot", Vector2(end.x - buddy.global_position.x, end.z - buddy.global_position.z).length() < 0.3,
				str(end))
	buddy.global_position = Vector3(16, 0, -8)
	await get_tree().physics_frame
	await get_tree().process_frame
	var none := _spawned(func() -> void: w._do_hitscan(origin, rdir), "arc_jump")
	_check("with the other robot 12 m off, no arc", none.is_empty(), str(none.size()))

	# Unsigned.
	ctl._active_camera = cam
	ctl.mag = maxi(ctl.mag, 6)
	buddy.global_position = Vector3(7, 0, -8)
	await get_tree().physics_frame
	var c := _spawned(func() -> void:
			ctl._do_shot()
			ctl._do_hitscan(origin, wdir)
			ctl._do_hitscan(origin, rdir), "")
	var tagged := c.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") in ["surface_arc", "arc_jump"])
	var crings := ctl.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "coil_ring")
	_check("an unsigned Arc Coil has no rings and throws no arcs", tagged.is_empty() and crings.is_empty())
	await _wait(0.3)
	_finish()

func _burst_and_refill(w: Weapon, sig: ArcCoilFx, rings: Array) -> void:
	var lit: Array[int] = []
	for i in 3:
		w._do_shot()
		lit.append(sig.lit_rings())
	_check("each round of the burst drains one ring (2, 1, 0)", lit == [2, 1, 0], str(lit))
	if rings.size() == 3:
		var e_front: float = (rings[0].mesh.material as StandardMaterial3D).emission_energy_multiplier
		_check("drained rings go dark", e_front < 1.0, "%.2f" % e_front)
	# Recharge one by one: the gun's own tick paused and driven in fixed 1/60 s
	# steps, so a slow headless frame cannot overshoot the partway sample.
	w.set_process(false)
	var refill: Array[int] = []
	var step := 1.0 / 60.0
	var t := 0.0
	while t < 1.0:
		sig.on_process(step)
		t += step
		if refill.is_empty() or refill.back() != sig.lit_rings():
			refill.append(sig.lit_rings())
	w.set_process(true)
	_check("through the cooldown they come back one at a time (0, 1, 2, 3)", refill == [0, 1, 2, 3], str(refill))
	_check("all three are back within a second", sig.lit_rings() == 3, str(sig.lit_rings()))

func _finish() -> void:
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _spawned(action: Callable, tag: String) -> Array:
	var before := get_children()
	action.call()
	var out: Array = []
	for n in get_children():
		if n in before:
			continue
		if tag == "" or n.get_meta("sig_fx", "") == tag:
			out.append(n)
	return out

func _wall(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.5)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb

## A robot stand-in in the "enemy" group: a body on the enemy layer with a
## Damageable, origin at its feet, 1.8 m tall, its +Z face at z + 0.4.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	sb.add_to_group("enemy")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	cs.shape = box
	cs.position.y = 0.9
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
