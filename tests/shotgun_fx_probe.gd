extends Node3D
## Probe: the SG-12 Breacher has a firing signature of its own (BreacherFx,
## scripts/weapons/fx/breacher_fx.gd) through Weapon's SignatureFx hooks:
##   - a blast draws nine stubby pellet beads (0.55 m at 200 m/s); the SLUG alt
##     draws one fat bolt (2.6 m); an unsigned gun draws stock bolts;
##   - a blast belches one fire bloom down the bore, throws one glowing wad
##     forward, rolls one cloud off the muzzle and no shared puff, and throws
##     no brass case on the shot: the red hull leaves on the pump beat after it;
##   - nine pellets into a robot pepper it once (one burst per blast), while an
##     unsigned gun's pellets never do.
##   godot --headless --path . --audio-driver Dummy res://tests/shotgun_fx_probe.tscn

const BREACHER_FX := "res://scripts/weapons/fx/breacher_fx.gd"

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
	cam.look_at_from_position(Vector3(0, 1.5, 0), Vector3(0, 1.5, -30), Vector3.UP)
	var robot := _robot(Vector3(0, 1.5, -4))
	var w: Weapon = (load("res://scenes/weapons/shotgun.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.3, -0.2)
	var ctl: Weapon = (load("res://scenes/weapons/shotgun.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.3, -0.2)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the SG-12 carries the Breacher signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == BREACHER_FX)
	_check("an unsigned gun carries the silent default signature",
			ctl._sig != null and ctl._sig.get_script().resource_path.ends_with("signature_fx.gd"))

	# A blast at the robot: pellets, bloom, wad, cloud, no shared smoke, no brass, one pepper.
	w._active_camera = cam
	w._active_shooter = null
	w.mag = maxi(w.mag, 4)
	var hp0: float = robot.get_node("Damageable").current_health
	await get_tree().process_frame
	var blast := _spawned(func() -> void: w._do_shot(), "")
	var tracers := blast.filter(func(n: Node) -> bool: return "bolt_length" in n)
	_check("the round hit the robot", robot.get_node("Damageable").current_health < hp0)
	_check("a blast draws nine pellet beads", tracers.size() == 9, str(tracers.size()))
	if not tracers.is_empty():
		_check("every pellet is the stubby bead (0.55 m at 200 m/s)",
				tracers.all(func(t: Node) -> bool: return is_equal_approx(t.bolt_length, 0.55) and is_equal_approx(t.bolt_speed, 200.0)),
				"%.2f m" % tracers[0].bolt_length)
	_check("a blast belches one fire bloom down the bore",
			w.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "blast_bloom").size() == 1)
	var wads := _tagged(blast, "wad")
	_check("a blast throws one wad", wads.size() == 1, str(wads.size()))
	if wads.size() == 1:
		var bore := -w.muzzle.global_basis.z
		_check("the wad flies out the bore", (wads[0] as CPUParticles3D).direction.dot(bore) > 0.95
				and wads[0].global_position.distance_to(w.muzzle.global_position) < 0.2)
	_check("a blast rolls one cloud off the muzzle", _tagged(blast, "blast_smoke").size() == 1)
	_check("the SG-12 throws no shared muzzle smoke",
			blast.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke").is_empty())
	_check("the SG-12 throws no brass case on the shot",
			blast.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "brass").is_empty())
	var peppers := _tagged(blast, "pepper")
	_check("nine pellets into a robot pepper it once", peppers.size() == 1, str(peppers.size()))
	if peppers.size() == 1:
		_check("the pepper sits on the plating", peppers[0].global_position.distance_to(Vector3(0, 1.5, -3.6)) < 0.9,
				str(peppers[0].global_position))
	# The hull leaves on the pump beat, not on the shot.
	var before := get_children()
	var t0 := Time.get_ticks_msec()
	var hulls: Array = []
	while Time.get_ticks_msec() - t0 < 900 and hulls.is_empty():
		await get_tree().process_frame
		hulls = get_children().filter(func(n: Node) -> bool: return not n in before and n.get_meta("sig_fx", "") == "hull")
	var when := (Time.get_ticks_msec() - t0) / 1000.0
	_check("the red hull leaves on the pump beat after the shot", hulls.size() == 1, "%d after %.2f s" % [hulls.size(), when])
	if hulls.size() == 1:
		var h := hulls[0] as CPUParticles3D
		_check("the hull is thrown out the right of the gun", h.direction.dot(w.global_basis.x) > 0.5, str(h.direction))

	# The slug alt: one fat bolt.
	await get_tree().process_frame
	w._alt_slug = true
	var slug := _spawned(func() -> void: w._do_shot(), "")
	w._alt_slug = false
	var st := slug.filter(func(n: Node) -> bool: return "bolt_length" in n)
	_check("the SLUG alt draws one fat bolt (2.6 m)", st.size() == 1 and is_equal_approx(st[0].bolt_length, 2.6),
			"%d bolts" % st.size())

	# An unsigned gun: stock bolts, brass, shared smoke, no wad, no pepper.
	ctl._active_camera = cam
	ctl.mag = maxi(ctl.mag, 3)
	await get_tree().process_frame
	var cb := _spawned(func() -> void: ctl._do_shot(), "")
	var ct := cb.filter(func(n: Node) -> bool: return "bolt_length" in n)
	_check("an unsigned gun's pellets are stock bolts (2.2 m)",
			ct.size() == 9 and ct.all(func(t: Node) -> bool: return is_equal_approx(t.bolt_length, 2.2)))
	_check("an unsigned gun keeps the shared smoke and brass",
			cb.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke")
			and cb.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "brass"))
	_check("an unsigned gun throws no wad and peppers nothing",
			_tagged(cb, "wad").is_empty() and _tagged(cb, "pepper").is_empty())
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _tagged(nodes: Array, tag: String) -> Array:
	return nodes.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == tag)

## Run `action` and return the nodes it added under this scene, optionally only
## those tagged with the given sig_fx meta.
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

## A robot stand-in wide enough to catch every pellet of a 6 deg cone at 4 m: a
## body on the enemy layer with a Damageable, its +Z face at z + 0.4.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 6.0, 0.8)
	cs.shape = box
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
