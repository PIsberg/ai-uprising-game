extends Node3D
## Probe: the OMEGA-X Annihilator's signature (OmegaFx, scripts/weapons/fx/omega_fx.gd):
##   - a shot collapses one sphere of light into the muzzle: it starts
##     IMPLODE_RADIUS wide, shrinks, and is gone within 0.4 s;
##   - a launched round wears a corona of CORONA_RAYS rays, every tip CORONA_LEN
##     off the round square to its flight axis, turning as time passes;
##   - where it lands a pillar of light stands up out of the blast, PILLAR_HEIGHT
##     tall, and is gone within a second and a half;
##   - an unsigned OMEGA has no implosion, corona or pillar.
##   godot --headless --path . --audio-driver Dummy res://tests/omega_fx_probe.tscn

const OMEGA_FX := "res://scripts/weapons/fx/omega_fx.gd"

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
	_box(Vector3(0, -0.5, -10), Vector3(40, 1, 40))
	var w: Weapon = (load("res://scenes/weapons/omega.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0, 1.4, 0)
	var ctl: Weapon = (load("res://scenes/weapons/omega.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the OMEGA-X carries the Omega signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == OMEGA_FX)
	w._active_shooter = null
	ctl._active_shooter = null

	# Implosion: driven through the hook (the shot's round is tested below).
	if w._sig.has_method("_implode"):
		w._sig.on_fire()
	var imps := w.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "omega_implode")
	_check("a shot collapses one sphere of light into the muzzle", imps.size() == 1, str(imps.size()))
	if imps.size() == 1:
		var s: MeshInstance3D = imps[0]
		_check("it starts IMPLODE_RADIUS wide", is_equal_approx((s.mesh as SphereMesh).radius, OmegaFx.IMPLODE_RADIUS) and s.scale.x > 0.95)
		await get_tree().process_frame
		await get_tree().process_frame
		_check("it shrinks", not is_instance_valid(s) or s.scale.x < 0.95)
		await _wait(0.4)
		_check("it is gone within 0.4 s", not is_instance_valid(s))

	# Corona on a round fired at the floor 12 m ahead.
	var pillars: Array = []
	var watch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") == "omega_pillar":
			pillars.append(n)
	get_tree().node_added.connect(watch)
	var dir := (Vector3(0, 0, -12) - Vector3(0, 1.4, 0)).normalized()
	var r := _launch(w, Vector3(0, 1.4, 0), dir)
	var corona: Node3D = r.get_node_or_null("OmegaCorona") if r else null
	_check("a launched round wears a corona", corona != null)
	if corona:
		var tips: Array = corona.tips()
		_check("CORONA_RAYS rays", tips.size() == OmegaFx.CORONA_RAYS, str(tips.size()))
		var axis := r.global_basis.z.normalized()
		var square := true
		for t: Vector3 in tips:
			var rel := t - r.global_position
			square = square and absf(rel.dot(axis)) < 0.02 and absf(rel.length() - OmegaFx.CORONA_LEN) < 0.02
		_check("every tip CORONA_LEN off the round, square to its flight", square)
		var t0: Vector3 = tips[0]
		corona._tick(0.2)
		_check("the corona turns", (corona.tips()[0] as Vector3).distance_to(t0) > 0.05)
	var t1 := Time.get_ticks_msec()
	while is_instance_valid(r) and Time.get_ticks_msec() - t1 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	_check("where it lands a pillar of light stands up", pillars.size() == 1, str(pillars.size()))
	if pillars.size() == 1 and is_instance_valid(pillars[0]):
		var p: Node3D = pillars[0]
		_check("the pillar stands on the blast, PILLAR_HEIGHT tall",
				p.global_position.y < 0.5 and (p.get_child(0).mesh as CylinderMesh).height == OmegaFx.PILLAR_HEIGHT, str(p.global_position))
		await _wait(1.5)
		_check("it is gone within a second and a half", not is_instance_valid(p))

	# Unsigned.
	pillars.clear()
	get_tree().node_added.connect(watch)
	ctl._sig.on_fire()
	var cimps := ctl.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "omega_implode")
	var cr := _launch(ctl, Vector3(0, 1.4, 0), dir)
	_check("an unsigned OMEGA has no implosion or corona", cimps.is_empty() and cr != null and cr.get_node_or_null("OmegaCorona") == null)
	t1 = Time.get_ticks_msec()
	while is_instance_valid(cr) and Time.get_ticks_msec() - t1 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	_check("an unsigned round raises no pillar", pillars.is_empty(), str(pillars.size()))
	await _wait(1.0)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

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
