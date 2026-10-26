extends Node3D
## Probe: the .50 Maelstrom has a firing signature of its own (MaelstromFx,
## scripts/weapons/fx/maelstrom_fx.gd) through Weapon's SignatureFx hooks:
##   - its tracer is the long fat white-hot streak (3.0 m at 260 m/s, hotter than
##     the gun's own colour);
##   - a shot spits two flame tongues straight up from the top of the barrel
##     behind the tip, one behind the other along the bore, gone within 0.3 s;
##   - a shot rolls one smoke ring forward off the muzzle, its axis down the line
##     of fire, travelling forward, widening and rising, gone by 1.6 s, and no
##     shared puff;
##   - a round into a robot blows an exit spray out of its far side along the round;
##   - a round into a wall throws one crater burst flat on the wall, with a dust
##     ring spreading across the surface;
##   - an unsigned .50 (signature cleared) does none of it.
##   godot --headless --path . --audio-driver Dummy res://tests/magnum_fx_probe.tscn

const MAELSTROM_FX := "res://scripts/weapons/fx/maelstrom_fx.gd"

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
	var wall := _wall(Vector3(-4, 1.5, -8))
	var robot := _robot(Vector3(3, 1.5, -6))
	var w: Weapon = (load("res://scenes/weapons/magnum.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var ctl: Weapon = (load("res://scenes/weapons/magnum.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, 0)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the .50 carries the Maelstrom signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == MAELSTROM_FX)

	# Tracer.
	var t := _spawned(func() -> void: w._spawn_tracer(Vector3(0.3, 1.4, 0), Vector3(0, 1, -30)), "")
	_check("the .50's tracer is the long fat streak (3.0 m at 260 m/s)",
			t.size() == 1 and is_equal_approx(t[0].bolt_length, 3.0) and is_equal_approx(t[0].bolt_speed, 260.0))
	if t.size() == 1:
		var tint: Color = t[0]._mat.get_shader_parameter("tint")
		var own := w.data.tracer_color
		_check("the streak burns hotter than the gun's own colour", tint.b > own.b + 0.1, "%s vs %s" % [tint, own])
	for n in t:
		n.queue_free()

	# A shot: port jets, smoke ring, no shared puff.
	w._active_camera = cam
	w._active_shooter = null
	w.mag = maxi(w.mag, 3)
	await get_tree().process_frame
	var shot := _spawned(func() -> void: w._do_shot(), "")
	var jets := w.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "port_jet")
	_check("a shot spits two compensator jets", jets.size() == 2, str(jets.size()))
	if jets.size() == 2:
		var up := w.muzzle.global_basis.y.normalized()
		var bore := -w.muzzle.global_basis.z.normalized()
		var both_up: bool = jets.all(func(j: Node3D) -> bool:
				return j.global_basis.y.normalized().dot(up) > 0.95 and (j.global_position - w.muzzle.global_position).dot(up) > 0.03)
		_check("the jets stand straight up from the top of the barrel", both_up)
		var along := absf((jets[0].global_position - jets[1].global_position).dot(bore))
		_check("one jet behind the other along the bore", along > 0.02, "%.3f m" % along)
		_check("the jets sit behind the tip", jets.all(func(j: Node3D) -> bool:
				return (j.global_position - w.muzzle.global_position).dot(bore) < 0.0))
	var rings := _tagged(shot, "smoke_ring")
	_check("a shot rolls one smoke ring", rings.size() == 1, str(rings.size()))
	_check("the .50 throws no shared puff",
			shot.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke").is_empty())
	if rings.size() == 1:
		var r: Node3D = rings[0]
		var bore := -w.muzzle.global_basis.z.normalized()
		_check("the ring's axis runs down the line of fire", absf(r.global_basis.y.normalized().dot(bore)) > 0.95)
		var p0 := r.global_position
		var s0 := r.scale.x
		await _wait(0.4)
		if is_instance_valid(r):
			var moved := r.global_position - p0
			_check("the ring rolls forward, widening and rising",
					moved.dot(bore) > 0.3 and r.scale.x > s0 * 1.5 and moved.y > 0.05,
					"forward %.2f m, scale %.1f -> %.1f, up %.2f m" % [moved.dot(bore), s0, r.scale.x, moved.y])
		await _wait(1.3)
		_check("the ring is gone by 1.6 s", not is_instance_valid(r))
	for i in 20:
		await get_tree().process_frame
	_check("the jets are gone", w.muzzle.get_children().filter(func(n: Node) -> bool:
			return n.get_meta("sig_fx", "") == "port_jet").is_empty())

	# Exit spray out the far side of a robot.
	var origin := Vector3(0, 1.5, 0)
	var rdir := (robot.global_position + Vector3(0, 0, 0.4) - origin).normalized()
	var hp0: float = robot.get_node("Damageable").current_health
	var hits := _spawned(func() -> void: w._do_hitscan(origin, rdir), "")
	var sprays := _tagged(hits, "exit_spray")
	_check("the round hit the robot", robot.get_node("Damageable").current_health < hp0)
	_check("a round into a robot blows one exit spray", sprays.size() == 1, str(sprays.size()))
	if sprays.size() == 1:
		var sp: CPUParticles3D = sprays[0]
		_check("the spray leaves the far side, along the round",
				sp.direction.dot(rdir) > 0.98 and sp.global_position.z < robot.global_position.z + 0.4 - 0.4,
				"dir %s at %s" % [sp.direction, sp.global_position])

	# Crater burst on a wall.
	await get_tree().process_frame
	var wdir := (wall.global_position + Vector3(0, 0, 0.25) - origin).normalized()
	var whits := _spawned(func() -> void: w._do_hitscan(origin, wdir), "")
	var craters := _tagged(whits, "crater")
	_check("a round into a wall throws one crater burst", craters.size() == 1, str(craters.size()))
	if craters.size() == 1:
		var c: Node3D = craters[0]
		_check("the crater sits on the wall", absf(c.global_position.z - (-8 + 0.25)) < 0.1, str(c.global_position))
		_check("its local up is the wall's normal", c.global_basis.y.normalized().dot(Vector3.BACK) > 0.95, str(c.global_basis.y))
		var dust := c.get_node_or_null("DustRing") as CPUParticles3D
		_check("its dust ring spreads flat across the surface", dust != null and dust.flatness >= 0.99 and dust.local_coords)

	# Unsigned: none of it.
	ctl._active_camera = cam
	ctl.mag = maxi(ctl.mag, 3)
	await get_tree().process_frame
	var cshot := _spawned(func() -> void: ctl._do_shot(), "")
	var cjets := ctl.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "port_jet")
	_check("an unsigned .50 spits no jets and rolls no ring, but keeps the shared puff",
			cjets.is_empty() and _tagged(cshot, "smoke_ring").is_empty()
			and cshot.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke"))
	var chits := _spawned(func() -> void:
			ctl._do_hitscan(origin, rdir)
			ctl._do_hitscan(origin, wdir), "")
	_check("an unsigned .50 blows no exit spray and no crater",
			_tagged(chits, "exit_spray").is_empty() and _tagged(chits, "crater").is_empty())
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _tagged(nodes: Array, tag: String) -> Array:
	return nodes.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == tag)

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

## A 6 m square concrete wall on layer 1 facing +Z, its face at z + 0.25.
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

## A robot stand-in: a body on the enemy layer with a Damageable, its +Z face at z + 0.4.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.8, 0.8)
	cs.shape = box
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
