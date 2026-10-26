extends Node3D
## Probe: the MK-VII Longshot's signature (LongshotFx, scripts/weapons/fx/longshot_fx.gd):
##   - a shot punches SHOCK_RINGS shock rings down the camera's line of fire,
##     each further out than the last (the last SHOCK_REACH away), spawned in
##     order a beat apart, their axes on the line, all gone within 0.6 s;
##   - a headshot throws one crit star at the hit; a body shot throws none;
##   - the shot throws no shared brass on the trigger: the hot case (case +
##     smoke thread) leaves CASE_DELAY later, out the right;
##   - an unsigned Longshot throws no rings, no star and keeps the shared brass.
##   godot --headless --path . --audio-driver Dummy res://tests/longshot_fx_probe.tscn

const LONGSHOT_FX := "res://scripts/weapons/fx/longshot_fx.gd"

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
	var w: Weapon = (load("res://scenes/weapons/sniper.tscn") as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, -0.1)
	var ctl: Weapon = (load("res://scenes/weapons/sniper.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, -0.1)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the MK-VII carries the Longshot signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == LONGSHOT_FX)

	# Fire into the open: shock rings and the hot case.
	w._active_camera = cam
	w._active_shooter = null
	w.mag = maxi(w.mag, 4)
	var rings: Array = []
	var order: Array = []
	var watch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") == "shock_ring":
			rings.append(n)
			order.append(int(n.get_meta("index")))
	get_tree().node_added.connect(watch)
	var shot := _spawned(func() -> void: w._do_shot(), "")
	_check("the shot throws no shared brass on the trigger",
			shot.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "brass").is_empty())
	# Sample each ring on the first frame it is alive (it lives 0.22 s).
	var seen := {}
	var t0 := Time.get_ticks_msec()
	var cases: Array = []
	while Time.get_ticks_msec() - t0 < 1000 and (cases.is_empty() or seen.size() < rings.size()):
		for r in rings:
			if is_instance_valid(r) and not seen.has(r):
				seen[r] = [(r as Node3D).global_position, (r as Node3D).global_basis.y.normalized()]
		await get_tree().process_frame
		cases = get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "hot_case")
	get_tree().node_added.disconnect(watch)
	_check("a shot punches SHOCK_RINGS shock rings", rings.size() == LongshotFx.SHOCK_RINGS, str(rings.size()))
	_check("the rings form in order down the line", order == [0, 1, 2, 3], str(order))
	var fwd := -cam.global_basis.z
	var dists: Array[float] = []
	var on_line := true
	for r in rings:
		if not seen.has(r):
			continue
		var rel: Vector3 = (seen[r][0] as Vector3) - w.muzzle.global_position
		dists.append(rel.dot(fwd))
		on_line = on_line and (rel - fwd * rel.dot(fwd)).length() < 0.05 \
				and absf((seen[r][1] as Vector3).dot(fwd)) > 0.95
	_check("each ring sits on the line of fire, facing down it", on_line)
	var rising := dists.size() == LongshotFx.SHOCK_RINGS
	for i in range(1, dists.size()):
		rising = rising and dists[i] > dists[i - 1] + 1.0
	_check("each ring further out, the last SHOCK_REACH away", rising and dists.size() > 0
			and absf(dists.back() - LongshotFx.SHOCK_REACH) < 0.1, str(dists))
	_check("the hot case leaves a beat after the shot", cases.size() == 1)
	if cases.size() == 1:
		var c: Node3D = cases[0]
		_check("it is a case with a smoke thread, thrown out the right",
				c.get_node_or_null("Case") != null and c.get_node_or_null("Smoke") != null
				and (c.get_node("Case") as CPUParticles3D).direction.dot(w.global_basis.x) > 0.5)
	await _wait(0.6)
	_check("the rings are gone within 0.6 s", rings.all(func(r) -> bool: return not is_instance_valid(r)))

	# Headshot vs body shot on a robot with a head.
	var robot := _robot(Vector3(0, 0, -10))
	await get_tree().physics_frame
	await get_tree().process_frame
	var origin := Vector3(0, 1.5, 0)
	var head := _spawned(func() -> void: w._do_hitscan(origin, (Vector3(0, 1.75, -9.6) - origin).normalized()), "crit_star")
	_check("a headshot throws one crit star", head.size() == 1, str(head.size()))
	if head.size() == 1:
		_check("the star sits at the hit", (head[0] as Node3D).global_position.distance_to(Vector3(0, 1.75, -9.6)) < 0.3)
	var body := _spawned(func() -> void: w._do_hitscan(origin, (Vector3(0, 0.8, -9.6) - origin).normalized()), "crit_star")
	_check("a body shot throws no star", body.is_empty(), str(body.size()))
	_check("the robot took both", robot.get_node("Damageable").current_health < 1.0e6)

	# Unsigned.
	ctl._active_camera = cam
	ctl.mag = maxi(ctl.mag, 3)
	var crings: Array = []
	var cwatch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") in ["shock_ring", "crit_star"]:
			crings.append(n)
	get_tree().node_added.connect(cwatch)
	var cshot := _spawned(func() -> void:
			ctl._do_shot()
			ctl._do_hitscan(origin, (Vector3(0, 1.75, -9.6) - origin).normalized()), "")
	# Read before waiting: some of what the shot spawned frees itself within 0.2 s.
	var cbrass := cshot.any(func(n: Node) -> bool: return is_instance_valid(n) and n.get_meta("shared_fx", "") == "brass")
	await _wait(0.2)
	get_tree().node_added.disconnect(cwatch)
	_check("an unsigned Longshot throws no rings and no star, and keeps the shared brass",
			crings.is_empty() and cbrass, "%d rings/stars, brass %s" % [crings.size(), cbrass])
	await _wait(1.5)
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

## A robot stand-in that knows its head: hits above 1.5 m are headshots.
func _robot(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.set_script(load("res://tests/longshot_fx_target.gd"))
	sb.collision_layer = 4
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 2.0, 0.8)
	cs.shape = box
	cs.position.y = 1.0
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
