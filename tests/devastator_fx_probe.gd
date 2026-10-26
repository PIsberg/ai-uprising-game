extends Node3D
## Probe: the GRK-X Devastator's signature (DevastatorFx, scripts/weapons/fx/devastator_fx.gd):
##   - a shot blows a fire cone out of the back of the tube (behind the gun,
##     opposite the bore, its wide mouth pointing back) and a burst of smoke
##     thrown back; the cone is gone within 0.5 s;
##   - a rocket into the floor rolls one dust ring out flat on the floor and
##     leaves DEBRIS small fires on the floor within the splash radius;
##   - the fires burn on, then die down and are gone a little after DEBRIS_LIFE;
##   - a rocket that goes off with no floor in reach leaves neither;
##   - an unsigned Devastator has no backblast, ring or fires;
##   - a signature script that cannot be instanced leaves the gun on the silent
##     default, firing cleanly.
##   godot --headless --path . --audio-driver Dummy res://tests/devastator_fx_probe.tscn

const DEVASTATOR_FX := "res://scripts/weapons/fx/devastator_fx.gd"

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 1.6, 0), Vector3(0, 0, -10), Vector3.UP)
	_box(Vector3(0, -0.5, -10), Vector3(40, 1, 40)) # floor, top at y = 0
	var w: Weapon = (load("res://scenes/weapons/devastator.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var ctl: Weapon = (load("res://scenes/weapons/devastator.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, 0)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the GRK-X carries the Devastator signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == DEVASTATOR_FX)
	w._active_camera = cam
	w._active_shooter = null
	ctl._active_camera = cam
	ctl._active_shooter = null

	# Backblast: call the shot's FX directly (the round itself is tested below).
	var bore := -w.muzzle.global_basis.z.normalized()
	var bb := _spawned(func() -> void: w._sig.on_fire(), "")
	var cones := _tagged(bb, "backblast")
	var smoke := _tagged(bb, "backblast_smoke")
	_check("a shot blows one fire cone out the back", cones.size() == 1, str(cones.size()))
	if cones.size() == 1:
		var c: Node3D = cones[0]
		var rel := c.global_position - w.global_position
		_check("the cone sits behind the gun", rel.dot(bore) < -0.3, "%.2f m" % rel.dot(bore))
		_check("its wide mouth points back, opposite the bore", c.global_basis.y.normalized().dot(-bore) > 0.95)
		await _wait(0.5)
		_check("the cone is gone within 0.5 s", not is_instance_valid(c))
	_check("a burst of smoke is thrown back", smoke.size() == 1)

	# A rocket into the floor 8 m ahead.
	var tags: Array = []
	var watch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") in ["dust_ring", "burning_debris"]:
			tags.append(n)
	get_tree().node_added.connect(watch)
	var rocket := _launch(w, Vector3(0, 1.4, 0), (Vector3(0, 0, -8) - Vector3(0, 1.4, 0)).normalized())
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(rocket) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	var rings := tags.filter(func(n) -> bool: return is_instance_valid(n) and n.get_meta("sig_fx", "") == "dust_ring")
	var debris := tags.filter(func(n) -> bool: return is_instance_valid(n) and n.get_meta("sig_fx", "") == "burning_debris")
	_check("the rocket rolls one dust ring", rings.size() == 1, str(rings.size()))
	if rings.size() == 1:
		var r: Node3D = rings[0]
		_check("the ring lies flat on the floor", r.global_basis.y.normalized().dot(Vector3.UP) > 0.95 and r.global_position.y < 0.3,
				str(r.global_position))
	_check("it leaves burning debris", debris.size() == 1, str(debris.size()))
	if debris.size() == 1:
		var d: Node3D = debris[0]
		var fires: Array = d.fires
		_check("DEBRIS fires", fires.size() == DevastatorFx.DEBRIS, str(fires.size()))
		var radius: float = w.data.splash_radius
		var placed: bool = fires.all(func(f: Node3D) -> bool:
				return f.global_position.y < 0.4 and Vector2(f.global_position.x - d.global_position.x, f.global_position.z - d.global_position.z).length() <= radius)
		_check("every fire sits on the floor within the splash radius", placed)
		await _wait(1.0)
		_check("the fires burn on a second later", is_instance_valid(d) and d.strength() > 0.9)
		await _wait(DevastatorFx.DEBRIS_LIFE - 1.0 + 0.5)
		_check("they die down and are gone a little after DEBRIS_LIFE", not is_instance_valid(d))

	# No floor in reach.
	var high := _launch(w, Vector3(15, 8, 0), Vector3(0, 1, 0))
	var hn := _spawned(func() -> void: high._explode(high.global_position), "")
	_check("a blast with no floor in reach leaves no ring and no fires",
			_tagged(hn, "dust_ring").is_empty() and _tagged(hn, "burning_debris").is_empty())

	# Unsigned.
	var cb := _spawned(func() -> void: ctl._sig.on_fire(), "")
	tags.clear()
	get_tree().node_added.connect(watch)
	var cr := _launch(ctl, Vector3(0, 1.4, 0), (Vector3(0, 0, -8) - Vector3(0, 1.4, 0)).normalized())
	t0 = Time.get_ticks_msec()
	while is_instance_valid(cr) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	_check("an unsigned Devastator has no backblast, ring or fires",
			_tagged(cb, "backblast").is_empty() and tags.is_empty(), "%d" % tags.size())

	# A signature script that cannot be instanced (here: never compiled) leaves
	# the gun on the silent default, firing cleanly, instead of a null signature
	# that errors on every hook call.
	var bw: Weapon = (load("res://scenes/weapons/devastator.tscn") as PackedScene).instantiate()
	bw.data = bw.data.duplicate()
	bw.data.signature_fx = GDScript.new()
	add_child(bw)
	await get_tree().process_frame
	_check("a signature that cannot be instanced falls back to the silent default",
			bw._sig != null and bw._sig.get_script() != null and bw._sig.get_script().resource_path.ends_with("signature_fx.gd"))
	bw._active_camera = cam
	bw._active_shooter = null
	bw.mag = maxi(bw.mag, 2)
	bw._do_shot()
	await get_tree().process_frame
	bw.queue_free()
	await _wait(1.6)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _launch(w: Weapon, origin: Vector3, dir: Vector3) -> Node3D:
	var before := get_children()
	w._spawn_projectile(origin, dir)
	for n in get_children():
		if not n in before and n.has_method("launch"):
			return n
	return null

func _tagged(nodes: Array, tag: String) -> Array:
	return nodes.filter(func(n) -> bool: return is_instance_valid(n) and n.get_meta("sig_fx", "") == tag)

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
