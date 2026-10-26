extends Node3D
## Probe: the ARC-9 Gauss Lance's signature (GaussFx, scripts/weapons/fx/gauss_fx.gd):
##   - two rails run along the barrel either side of the bore, behind the tip;
##   - the rails glow with the alt charge: dim uncharged, brighter half charged,
##     brightest full; arcs jump between them only at full charge, and land on
##     the rails;
##   - a round through a line of three robots leaves one punch-through ring at
##     each, every ring round the shot line, all gone within 0.5 s;
##   - a round into a wall leaves one slag spot flat on the wall that starts
##     white-hot, has cooled by 1 s and is gone a little after SLAG_LIFE;
##   - an unsigned Gauss has no rails, no rings, no slag.
##   godot --headless --path . --audio-driver Dummy res://tests/gauss_fx_probe.tscn

const GAUSS_FX := "res://scripts/weapons/fx/gauss_fx.gd"

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
	var w: Weapon = (load("res://scenes/weapons/gauss.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var ctl: Weapon = (load("res://scenes/weapons/gauss.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, 0)
	await get_tree().process_frame
	await get_tree().physics_frame
	var sig := w._sig as GaussFx
	_check("the ARC-9 carries the Gauss signature", sig != null and sig.get_script().resource_path == GAUSS_FX)

	# Rails on the barrel, found by meta so an unwired gun fails here too.
	var rails := w.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "gauss_rail")
	_check("two rails run along the barrel", rails.size() == 2, str(rails.size()))
	if rails.size() == 2:
		var bore := -w.muzzle.global_basis.z.normalized()
		var side := w.muzzle.global_basis.x.normalized()
		var behind: bool = rails.all(func(r: Node3D) -> bool: return (r.global_position - w.muzzle.global_position).dot(bore) < 0.0)
		var apart := ((rails[0] as Node3D).global_position - (rails[1] as Node3D).global_position).dot(side)
		_check("either side of the bore, behind the tip", behind and absf(apart) > 0.05, "%.3f m apart" % absf(apart))
	if sig:
		var energy := []
		var sparked := []
		for c in [0.0, 0.5, 1.0]:
			w._alt_charge = c
			sig.on_process(0.016)
			energy.append(sig.rail_energy())
			sparked.append(sig.spark.visible)
		_check("the rails glow with the charge (dim, brighter, brightest)",
				energy[0] < energy[1] and energy[1] < energy[2] and energy[0] < 1.0, str(energy))
		_check("arcs jump between the rails only at full charge", sparked == [false, false, true], str(sparked))
		var pts: PackedVector3Array = sig.spark.points()
		var a := w.muzzle.to_local(pts[0])
		var b := w.muzzle.to_local(pts[pts.size() - 1])
		_check("the arc lands on the rails", absf(absf(a.x) - GaussFx.RAIL_GAP) < 0.005 and absf(absf(b.x) - GaussFx.RAIL_GAP) < 0.005
				and a.z > 0.0 and a.z < GaussFx.RAIL_LEN + 0.05, "%s -> %s" % [a, b])
		w._alt_charge = 0.0
		sig.on_process(0.016)

	# A line of three robots.
	var robots := [_robot(Vector3(3, 1.5, -5)), _robot(Vector3(3, 1.5, -8)), _robot(Vector3(3, 1.5, -11))]
	await get_tree().physics_frame
	var origin := Vector3(3, 1.5, 0)
	var dir := Vector3(0, 0, -1)
	var hits := _spawned(func() -> void: w._do_hitscan(origin, dir), "pierce_ring")
	_check("a round through three robots leaves a ring at each", hits.size() == 3, str(hits.size()))
	var round_line: bool = hits.all(func(r: Node3D) -> bool:
			return absf(r.global_basis.y.normalized().dot(dir)) > 0.95 and Vector2(r.global_position.x - 3, r.global_position.y - 1.5).length() < 0.05)
	_check("every ring sits round the shot line", round_line and not hits.is_empty())
	_check("all three robots took the round", robots.all(func(r) -> bool: return r.get_node("Damageable").current_health < 1.0e6))
	await _wait(0.5)
	_check("the rings are gone within 0.5 s", hits.all(func(r) -> bool: return not is_instance_valid(r)))

	# A wall: slag.
	var wall := _wall(Vector3(-4, 1.5, -8))
	await get_tree().physics_frame
	var wo := Vector3(-4, 1.5, 0)
	var slags := _spawned(func() -> void: w._do_hitscan(wo, Vector3(0, 0, -1)), "slag")
	_check("a round into a wall leaves one slag spot", slags.size() == 1, str(slags.size()))
	if slags.size() == 1:
		var sl: Node3D = slags[0]
		_check("the slag lies flat on the wall", sl.global_basis.y.normalized().dot(Vector3.BACK) > 0.95
				and absf(sl.global_position.z - (-7.75)) < 0.05, str(sl.global_position))
		var h0: float = sl.heat()
		_check("it starts white-hot", h0 > 0.85 and sl.mat.emission_energy_multiplier > 5.0)
		await _wait(1.0)
		if is_instance_valid(sl):
			_check("it has cooled by 1 s", sl.heat() < 0.6 and sl.mat.emission_energy_multiplier < 3.0, "heat %.2f" % sl.heat())
		await _wait(GaussFx.SLAG_LIFE - 1.0 + 0.5)
		_check("it is gone a little after SLAG_LIFE", not is_instance_valid(sl))
	wall.queue_free()

	# Unsigned.
	ctl._active_shooter = null
	for i in 3:
		await get_tree().process_frame
	var crails := ctl.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "gauss_rail")
	var c := _spawned(func() -> void: ctl._do_hitscan(origin, dir), "")
	_check("an unsigned Gauss has no rails and leaves no rings",
			crails.is_empty() and c.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") != "").is_empty())
	await _wait(0.4)
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
	box.size = Vector3(4, 6, 0.5)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = at
	return sb

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
