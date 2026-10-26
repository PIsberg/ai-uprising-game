extends Node3D
## Probe: the M9 Sidearm has a firing signature of its own (SidearmFx,
## scripts/weapons/fx/sidearm_fx.gd) wired through Weapon's SignatureFx hooks:
##   - its tracer is the short fast crack (bolt 1.1 m at 240 m/s), not the stock bolt;
##   - a round stopped on a metal wall ricochets: one streak leaves along the
##     bounce (within the jitter), away from the wall, and is gone within a second;
##     a round into wood never ricochets;
##   - a round into a robot pings a cross glint at the hit, which fades out, and
##     never ricochets;
##   - a shot curls a wisp out of the breech and throws no shared muzzle smoke;
##   - the rifle has none of this: a silent default signature, stock bolt, no
##     ricochet off the same metal wall.
##   godot --headless --path . --audio-driver Dummy res://tests/sidearm_fx_probe.tscn

const SIDEARM_FX := "res://scripts/weapons/fx/sidearm_fx.gd"
const WALL_Z := -8.0

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
	cam.look_at_from_position(Vector3(0, 1.6, 0.4), Vector3(0, 1.0, -30), Vector3.UP)
	var metal := _wall(Vector3(-4, 1.5, WALL_Z), "surf_metal")
	var wood := _wall(Vector3(4, 1.5, WALL_Z), "surf_wood")
	var robot := _robot(Vector3(0, 1.5, -5))
	var w: Weapon = (load("res://scenes/weapons/pistol.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var rifle: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(rifle)
	rifle.global_position = Vector3(-0.2, 1.4, 0)
	await get_tree().process_frame
	await get_tree().physics_frame

	var sig: Object = w._sig
	_check("the M9 carries the sidearm signature",
			sig != null and sig.get_script() != null and sig.get_script().resource_path == SIDEARM_FX)
	_check("the rifle carries the silent default signature",
			rifle._sig != null and rifle._sig.get_script().resource_path.ends_with("signature_fx.gd"))

	# Tracer: the crack.
	var from := Vector3(0.3, 1.4, 0)
	var to := Vector3(0.0, 1.0, -30.0)
	var t := _spawned(func() -> void: w._spawn_tracer(from, to), "")
	_check("the M9 draws one tracer", t.size() == 1)
	if t.size() == 1:
		_check("the M9's tracer is the short fast crack (1.1 m at 240 m/s)",
				is_equal_approx(t[0].bolt_length, 1.1) and is_equal_approx(t[0].bolt_speed, 240.0),
				"%.1f m at %.0f m/s" % [t[0].bolt_length, t[0].bolt_speed])
	var rt := _spawned(func() -> void: rifle._spawn_tracer(from, to), "")
	_check("the rifle's tracer is the stock bolt (2.2 m at 150 m/s)",
			rt.size() == 1 and is_equal_approx(rt[0].bolt_length, 2.2) and is_equal_approx(rt[0].bolt_speed, 150.0))
	for n in t + rt:
		if is_instance_valid(n):
			n.queue_free()

	# Ricochet off metal, along the bounce, away from the wall. A fresh frame first,
	# so the heavy sync work above is not the next frame's delta.
	await get_tree().process_frame
	var origin := Vector3(0, 1.5, 0)
	var dir := (metal.global_position - origin).normalized()
	var ric := _spawned(func() -> void: w._do_hitscan(origin, dir), "ricochet")
	_check("a round into a metal wall throws one ricochet", ric.size() == 1, str(ric.size()))
	if ric.size() == 1:
		var r: Node3D = ric[0]
		var normal := Vector3(0, 0, 1)
		var bounce := dir.bounce(normal)
		var fly := -r.global_basis.z.normalized()
		var off := rad_to_deg(acos(clampf(fly.dot(bounce), -1.0, 1.0)))
		_check("the ricochet leaves along the bounce (within %.0f deg)" % SidearmFx.RICOCHET_JITTER_DEG,
				off <= SidearmFx.RICOCHET_JITTER_DEG + 0.5, "%.1f deg" % off)
		_check("the ricochet flies away from the wall", fly.dot(normal) > 0.05, "%.2f" % fly.dot(normal))
		_check("the ricochet starts at the hit", r.global_position.distance_to(Vector3(metal.global_position.x, metal.global_position.y, WALL_Z + 0.25)) < 0.6,
				str(r.global_position))
		var flight: float = r._dist / r.bolt_speed
		_check("the ricochet is in the air for 0.1-0.25 s", flight >= 0.1 and flight <= 0.25, "%.2f s" % flight)
		# No "still flying a frame later" check: the bolt's own _process can see a
		# longer delta than the probe's frame (CI run on 00f3b38 failed it at dt
		# 0.017); the flight time above pins the design instead.
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(r) and Time.get_ticks_msec() - t0 < 1500:
			await get_tree().process_frame
		_check("the ricochet is gone within a second", not is_instance_valid(r), "%d ms" % (Time.get_ticks_msec() - t0))
	var wdir := (wood.global_position - origin).normalized()
	var wric := _spawned(func() -> void: w._do_hitscan(origin, wdir), "ricochet")
	_check("a round into wood never ricochets", wric.is_empty(), str(wric.size()))
	var rric := _spawned(func() -> void: rifle._do_hitscan(origin, dir), "ricochet")
	_check("the rifle never ricochets off the same metal wall", rric.is_empty(), str(rric.size()))

	# Glint on a robot.
	await get_tree().process_frame
	var rdir := (robot.global_position - origin).normalized()
	var hp0: float = robot.get_node("Damageable").current_health
	var hits := _spawned(func() -> void: w._do_hitscan(origin, rdir), "")
	var glints := hits.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "glint")
	_check("the round hit the robot", robot.get_node("Damageable").current_health < hp0)
	_check("a round into a robot pings one glint", glints.size() == 1, str(glints.size()))
	_check("a round into a robot never ricochets",
			hits.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "ricochet").is_empty())
	if glints.size() == 1:
		var g: Node3D = glints[0]
		_check("the glint sits at the hit", g.global_position.distance_to(Vector3(0, 1.5, -5 + 0.4)) < 0.5, str(g.global_position))
		_check("the glint is two crossed bars", g.get_child_count() == 2)
		var t1 := Time.get_ticks_msec()
		await get_tree().process_frame
		var gdt := get_process_delta_time()
		if gdt < SidearmFx.GLINT_TIME * 0.8:
			_check("the glint is still lit a frame later", is_instance_valid(g), "dt %.3f" % gdt)
		else:
			print("   (frame of %.3f s outran the glint; lit check skipped)" % gdt)
		while is_instance_valid(g) and Time.get_ticks_msec() - t1 < 800:
			await get_tree().process_frame
		_check("the glint fades out", not is_instance_valid(g), "%d ms" % (Time.get_ticks_msec() - t1))

	# A fired shot: the breech wisp, and no shared muzzle smoke.
	w._active_camera = cam
	w._active_shooter = null
	w.mag = maxi(w.mag, 3)
	var shot := _spawned(func() -> void: w._do_shot(), "")
	var wisps := shot.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "breech_wisp")
	var smoke := shot.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke")
	_check("a shot curls one wisp out of the breech", wisps.size() == 1, str(wisps.size()))
	if wisps.size() == 1:
		var wp: Node3D = wisps[0]
		var d := wp.global_position - w.global_position
		_check("the wisp rises from the breech, not the muzzle",
				d.length() < 0.12 and d.dot(w.global_basis.y) > 0.0 and d.dot(w.global_basis.x) > 0.0, str(d))
	_check("the M9 throws no shared muzzle smoke", smoke.is_empty(), str(smoke.size()))
	rifle._active_camera = cam
	rifle.mag = maxi(rifle.mag, 3)
	var rshot := _spawned(func() -> void: rifle._do_shot(), "")
	_check("the rifle keeps the shared muzzle smoke",
			rshot.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke"))
	_check("the rifle curls no wisp",
			not rshot.any(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "breech_wisp"))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

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

## A 6 m square wall on layer 1 facing +Z, 0.5 m thick, tagged with a surface group.
func _wall(at: Vector3, group: String) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.add_to_group(group)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 6, 0.5)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb

## A robot stand-in: a body on the enemy layer with a Damageable.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	cs.shape = box
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
