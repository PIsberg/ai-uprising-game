extends Node3D
## Probe: the PL-1 Plasma Launcher's signature (PlasmaFx, scripts/weapons/fx/plasma_fx.gd)
## through the projectile hooks (on_projectile, and projectile.gd calling
## on_projectile_hit from _explode):
##   - a launched round carries one orbit rig: MOTES motes circling its line of
##     travel at MOTE_RADIUS, which move between frames, and a wobbling shell;
##   - fired at a wall standing on a floor, it throws one crown of droplets at
##     the blast and pours one pool on the floor below it, lying flat;
##   - the pool starts hot (heat near 1, bright), cools as it ages (heat and
##     emission fall), and is gone a little after POOL_LIFE;
##   - fired into the open air with no floor in reach, it pours no pool;
##   - an unsigned Plasma Launcher's round has no orbit, no crown, no pool.
##   godot --headless --path . --audio-driver Dummy res://tests/plasma_fx_probe.tscn

const PLASMA_FX := "res://scripts/weapons/fx/plasma_fx.gd"

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
	_box(Vector3(0, -0.5, -10), Vector3(20, 1, 30)) # floor
	_box(Vector3(0, 2.0, -8), Vector3(6, 4, 0.5)) # wall, face at z = -7.75
	var w: Weapon = (load("res://scenes/weapons/plasma.tscn") as PackedScene).instantiate()
	add_child(w)
	var ctl: Weapon = (load("res://scenes/weapons/plasma.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the PL-1 carries the Plasma signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == PLASMA_FX)
	w._active_shooter = null
	ctl._active_shooter = null

	# A round in flight, at a wall 7.5 m off, 1 m above the floor.
	var tags: Array = []
	var watch := func(n: Node) -> void:
		var t: String = n.get_meta("sig_fx", "")
		if t != "":
			tags.append(n)
	get_tree().node_added.connect(watch)
	# Launched 15 m back so it is in flight for a few frames, even slow headless ones.
	var origin := Vector3(0, 1.0, 7)
	var proj := _launch(w, origin, Vector3(0, 0, -1))
	var orbit: Node3D = proj.get_node_or_null("PlasmaOrbit") if proj else null
	_check("a launched round carries an orbit rig", orbit != null)
	if orbit:
		var motes: Array = orbit.motes
		_check("MOTES motes ride the round", motes.size() == PlasmaFx.MOTES, str(motes.size()))
		var axis := proj.global_basis.z.normalized()
		var circling := motes.all(func(m: Node3D) -> bool:
				var rel := m.global_position - proj.global_position
				var off := (rel - axis * rel.dot(axis)).length()
				return absf(off - PlasmaFx.MOTE_RADIUS) < 0.02 and absf(rel.dot(axis)) < 0.02)
		_check("the motes circle the line of travel at MOTE_RADIUS", circling)
		# Step the rig by hand (the round may land within a slow frame or two).
		var p0: Vector3 = (motes[0] as Node3D).position
		var s0: Vector3 = (orbit.shell as Node3D).scale
		orbit._tick(0.05)
		_check("the motes orbit (move as time passes)", (motes[0] as Node3D).position.distance_to(p0) > 0.005)
		_check("the shell wobbles", not (orbit.shell as Node3D).scale.is_equal_approx(s0))
	# Wait for the detonation.
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(proj) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	_check("the round went off on the wall", not is_instance_valid(proj))
	await get_tree().process_frame
	var crowns := tags.filter(func(n) -> bool: return is_instance_valid(n) and n.get_meta("sig_fx", "") == "plasma_crown")
	var pools := tags.filter(func(n) -> bool: return is_instance_valid(n) and n.get_meta("sig_fx", "") == "plasma_pool")
	_check("the blast throws one crown of droplets", crowns.size() == 1, str(crowns.size()))
	_check("it pours one pool", pools.size() == 1, str(pools.size()))
	if pools.size() == 1:
		var pool: Node3D = pools[0]
		_check("the pool lies on the floor below the blast", absf(pool.global_position.y - 0.02) < 0.05
				and absf(pool.global_position.z - (-7.45)) < 0.6, str(pool.global_position))
		var h0: float = pool.heat()
		var e0: float = pool.mat.emission_energy_multiplier
		_check("the pool starts hot", h0 > 0.85 and e0 > 4.0, "heat %.2f, emission %.1f" % [h0, e0])
		await _wait(1.6)
		if is_instance_valid(pool):
			var h1: float = pool.heat()
			var e1: float = pool.mat.emission_energy_multiplier
			_check("it cools as it ages", h1 < h0 - 0.3 and e1 < e0 * 0.5, "heat %.2f, emission %.1f" % [h1, e1])
		await _wait(PlasmaFx.POOL_LIFE - 1.6 + 0.5)
		_check("it is gone a little after POOL_LIFE", not is_instance_valid(pool))
	get_tree().node_added.disconnect(watch)

	# Into the open air: no floor in reach, no pool. (Burst it by hand at 6 m up.)
	tags.clear()
	get_tree().node_added.connect(watch)
	var high := _launch(w, Vector3(30, 6, 0), Vector3(0, 1, 0))
	if high:
		high._explode(high.global_position)
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	var high_pools := tags.filter(func(n) -> bool: return is_instance_valid(n) and n.get_meta("sig_fx", "") == "plasma_pool")
	_check("a blast with no floor in reach pours no pool", high_pools.is_empty(), str(high_pools.size()))

	# Unsigned.
	tags.clear()
	get_tree().node_added.connect(watch)
	var cp := _launch(ctl, origin, Vector3(0, 0, -1))
	_check("an unsigned round has no orbit", cp != null and cp.get_node_or_null("PlasmaOrbit") == null)
	t0 = Time.get_ticks_msec()
	while is_instance_valid(cp) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	_check("an unsigned round throws no crown and pours no pool",
			tags.filter(func(n) -> bool: return is_instance_valid(n)).is_empty(), str(tags.size()))
	await _wait(0.5)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Fire one round from `origin` along `dir` and return it.
func _launch(w: Weapon, origin: Vector3, dir: Vector3) -> Node3D:
	var before := get_children()
	w._spawn_projectile(origin, dir)
	for n in get_children():
		if not n in before and n.has_method("launch"):
			return n
	return null

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().process_frame
		t += get_process_delta_time()

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb
