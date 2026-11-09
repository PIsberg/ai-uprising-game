extends Node3D
## Probe: the PALM Cannon's signature (PalmFx, scripts/weapons/fx/palm_fx.gd), the
## salvage gun torn off a stilt MECH's hand:
##   - an iris of RINGS rings stands on the bore ahead of the muzzle; a spent shot
##     throws them OPEN and dark, they close one after another (the far ring
##     first) as the gun's own cooldown runs out, and a ready gun holds them
##     tight and bright;
##   - a launched bolt carries one halo ring square to its line of flight and
##     leaves an echo ring hanging in the air every SHED_EVERY metres;
##   - where it goes off one clap ring spreads to the splash radius, and a wall
##     takes one handprint brand: a palm and FINGERS fingers lying on the face,
##     fingers up, off the scorch decal's render layer, which starts hot, cools
##     and is gone a little after BRAND_LIFE;
##   - a bolt fired down at the floor brands it flat, fingers along the shot;
##   - a burst in the open air claps but brands nothing;
##   - an unsigned PALM Cannon has no iris, halo, echo, clap or brand.
##   godot --headless --path . --audio-driver Dummy res://tests/palm_fx_probe.tscn

const PALM_FX := "res://scripts/weapons/fx/palm_fx.gd"
const SCENE := "res://scenes/weapons/salvage_palm.tscn"

var ok := true
var cam: Camera3D
## [tag, node, position when added] for every signature node added while watching.
var seen: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _watch(n: Node) -> void:
	var t: String = n.get_meta("sig_fx", "")
	if t != "":
		seen.append([t, n, (n as Node3D).position if n is Node3D else Vector3.ZERO])

func _of(tag: String) -> Array:
	return seen.filter(func(e) -> bool: return e[0] == tag)

func _live(tag: String) -> Array:
	var out: Array = []
	for e in seen:
		if e[0] == tag and is_instance_valid(e[1]):
			out.append(e[1])
	return out

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	_box(Vector3(0, -0.5, -10), Vector3(60, 1, 60)) # floor, top at y = 0
	_box(Vector3(0, 2.0, -8), Vector3(6, 4, 0.5)) # wall, face at z = -7.75
	get_tree().node_added.connect(_watch)
	var w: Weapon = (load(SCENE) as PackedScene).instantiate()
	add_child(w)
	var ctl: Weapon = (load(SCENE) as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the PALM Cannon carries the Palm signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == PALM_FX)
	w._active_shooter = null
	ctl._active_shooter = null

	# The iris on the muzzle.
	var irises := _live("palm_iris").filter(func(n) -> bool: return w.is_ancestor_of(n))
	_check("one iris stands on the gun", irises.size() == 1, str(irises.size()))
	if irises.size() == 1 and "PalmFx" in ProjectSettings.get_global_class_list().map(func(c) -> String: return c["class"]):
		var iris: Node3D = irises[0]
		var rings: Array = iris.rings
		_check("it has RINGS rings", rings.size() == PalmFx.RINGS, str(rings.size()))
		var muzzle: Node3D = w.muzzle
		var coaxial := rings.all(func(r: Node3D) -> bool:
				var rel := muzzle.global_transform.affine_inverse() * r.global_position
				return absf(rel.x) < 0.005 and absf(rel.y) < 0.005 and rel.z < -0.01)
		_check("the rings sit on the bore, ahead of the muzzle", coaxial)
		var interval: float = 1.0 / w.eff_fire_rate()
		# Spent: thrown open and dark.
		w._cooldown = interval
		w._sig.on_process(0.0)
		var open := rings.all(func(r: Node3D) -> bool: return absf(r.scale.x - PalmFx.OPEN) < 0.05)
		var e_spent: float = iris.energy_of(0)
		_check("a spent shot throws every ring OPEN", open and iris.charge < 0.05, "charge %.2f" % iris.charge)
		# Half way: the far ring has closed, the near one has not moved yet.
		w._cooldown = interval * 0.5
		w._sig.on_process(0.0)
		var far: Node3D = rings[PalmFx.RINGS - 1]
		var near: Node3D = rings[0]
		_check("the far ring closes first", absf(far.scale.x - 1.0) < 0.05 and absf(near.scale.x - PalmFx.OPEN) < 0.05,
				"far %.2f, near %.2f" % [far.scale.x, near.scale.x])
		# Ready: tight and bright.
		w._cooldown = 0.0
		w._sig.on_process(0.0)
		var tight := rings.all(func(r: Node3D) -> bool: return absf(r.scale.x - 1.0) < 0.01)
		_check("a ready gun holds the rings tight and bright", tight and iris.charge > 0.99 and iris.energy_of(0) > e_spent * 3.0,
				"energy %.1f vs %.1f spent" % [iris.energy_of(0), e_spent])
		# Through the gun's own frame: the cooldown runs out and the iris follows it.
		# (A long cooldown, so one slow headless frame cannot run it out.)
		# process_frame fires before the frame's _process calls: wait for the next one.
		w._cooldown = 10.0
		await get_tree().process_frame
		await get_tree().process_frame
		_check("the gun's own cooldown opens the iris", iris.charge < 0.05, "charge %.2f" % iris.charge)
		w._cooldown = interval
		await _wait(interval + 0.3)
		_check("and closes it again when the gun is ready", iris.charge > 0.99, "charge %.2f" % iris.charge)

	# A bolt in flight, at a wall, 1 m above the floor. Launched from z = 6, so it
	# spawns at z = 5.5 and flies ~13.2 m: five echoes at SHED_EVERY (2.5 m).
	seen.clear()
	var origin := Vector3(0, 1.0, 6.0)
	var proj := _launch(w, origin, Vector3(0, 0, -1))
	var halo: Node3D = proj.get_node_or_null("PalmHalo") if proj else null
	_check("a launched bolt carries a halo", halo != null)
	if halo:
		var ring: Node3D = halo.ring
		var axis := proj.global_basis.z.normalized()
		_check("the halo ring stands square to the line of flight",
				absf(ring.global_basis.y.normalized().dot(axis)) > 0.99, str(ring.global_basis.y))
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(proj) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	_check("the bolt went off on the wall", not is_instance_valid(proj))
	await get_tree().process_frame
	var echoes := _of("palm_echo")
	_check("it left five echoes on the way", echoes.size() == 5, str(echoes.size()))
	var spaced := echoes.size() == 5
	for i in echoes.size():
		var p: Vector3 = echoes[i][2]
		var want := Vector3(0, 1.0, 5.5 - PalmFx.SHED_EVERY * (i + 1))
		if p.distance_to(want) > 0.15:
			spaced = false
	_check("the echoes hang SHED_EVERY apart along the flight line", spaced, str(echoes.map(func(e) -> Vector3: return e[2])))
	_check("the blast claps once", _of("palm_clap").size() == 1, str(_of("palm_clap").size()))
	var claps := _live("palm_clap")
	if claps.size() == 1:
		_check("the clap spreads to the splash radius", absf(claps[0].radius - w.data.splash_radius) < 0.01, str(claps[0].radius))
	var brands := _live("palm_brand")
	_check("the wall takes one handprint", brands.size() == 1, str(brands.size()))
	if brands.size() == 1:
		var brand: Node3D = brands[0]
		_check("the print lies on the wall's face", absf(brand.global_position.z - (-7.75)) < 0.06
				and brand.global_basis.y.dot(Vector3(0, 0, 1)) > 0.98, "%s normal %s" % [brand.global_position, brand.global_basis.y])
		var fingers: Array = brand.fingers
		_check("it has FINGERS fingers", fingers.size() == PalmFx.FINGERS, str(fingers.size()))
		var up := fingers.size() > 2 and (fingers[2] as Node3D).global_position.y > brand.global_position.y + PalmFx.PALM_RADIUS * 0.8
		_check("on a wall the fingers point up", up)
		var off_palm := fingers.all(func(f: Node3D) -> bool:
				return f.global_position.distance_to(brand.global_position) > PalmFx.PALM_RADIUS * 0.8)
		_check("every finger reaches out of the palm", off_palm)
		# The blast's ScorchDecal projects onto render layer 1 at the same spot: a
		# print on that layer was charred black in the windowed shot.
		var clear := (brand.palm as VisualInstance3D).layers & 1 == 0 				and fingers.all(func(f: VisualInstance3D) -> bool: return f.layers & 1 == 0)
		_check("the print is off the scorch decal's render layer", clear)
		var h0: float = brand.heat()
		var e0: float = brand.mat.emission_energy_multiplier
		_check("the print starts hot", h0 > 0.85 and e0 > 3.0, "heat %.2f, emission %.1f" % [h0, e0])
		await _wait(2.0)
		if is_instance_valid(brand):
			_check("it cools as it ages", brand.heat() < h0 - 0.3 and brand.mat.emission_energy_multiplier < e0 * 0.5,
					"heat %.2f, emission %.1f" % [brand.heat(), brand.mat.emission_energy_multiplier])
		await _wait(PalmFx.BRAND_LIFE - 2.0 + 0.5)
		_check("it is gone a little after BRAND_LIFE", not is_instance_valid(brand))

	# Down at the floor: the print lies flat, fingers along the shot.
	seen.clear()
	var down := _launch(w, Vector3(12, 3, 0), Vector3(0, -1, -1).normalized())
	t0 = Time.get_ticks_msec()
	while is_instance_valid(down) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	var floor_brands := _live("palm_brand")
	_check("the floor takes one handprint", floor_brands.size() == 1, str(floor_brands.size()))
	if floor_brands.size() == 1:
		var fb: Node3D = floor_brands[0]
		_check("it lies flat on the floor", fb.global_basis.y.dot(Vector3.UP) > 0.98 and absf(fb.global_position.y) < 0.06,
				"%s normal %s" % [fb.global_position, fb.global_basis.y])
		var mid: Node3D = fb.fingers[2]
		_check("its fingers point along the shot", mid.global_position.z < fb.global_position.z - PalmFx.PALM_RADIUS * 0.8,
				"finger z %.2f, palm z %.2f" % [mid.global_position.z, fb.global_position.z])

	# Into the open air (burst by hand 8 m up): a clap, no print.
	seen.clear()
	var high := _launch(w, Vector3(-20, 8, 0), Vector3(0, 1, 0))
	if high:
		high._explode(high.global_position)
	await get_tree().process_frame
	_check("a burst in the open air claps", _of("palm_clap").size() == 1, str(_of("palm_clap").size()))
	_check("and brands nothing", _of("palm_brand").is_empty(), str(_of("palm_brand").size()))

	# Unsigned.
	_check("an unsigned PALM Cannon has no iris",
			not ctl.find_children("*", "Node3D", true, false).any(func(n: Node) -> bool: return n.has_meta("sig_fx")))
	await _wait(1.0)
	seen.clear()
	var cp := _launch(ctl, origin, Vector3(0, 0, -1))
	_check("an unsigned bolt has no halo", cp != null and cp.get_node_or_null("PalmHalo") == null)
	t0 = Time.get_ticks_msec()
	while is_instance_valid(cp) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check("an unsigned bolt leaves no echo, clap or print", seen.is_empty(), str(seen.map(func(e) -> String: return e[0])))
	get_tree().node_added.disconnect(_watch)
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
