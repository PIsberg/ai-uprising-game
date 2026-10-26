extends Node3D
## Probe: the TPX-9 Tempest Coil's signature (TempestFx, scripts/weapons/fx/tempest_fx.gd):
##   - a launched orb carries a storm rig of TENDRILS arcs, each reaching from the
##     orb out to within TENDRIL_REACH, re-struck as it flies;
##   - flying 1.2 m over a floor it licks one ground arc down to the floor;
##     flying 6 m up it shows none;
##   - where it goes off a sky strike (LightningStrike) stands on the blast, its
##     light from the FX light budget: none when the budget is full;
##   - an unsigned Tempest's orb carries no storm and calls no strike.
##   godot --headless --path . --audio-driver Dummy res://tests/tempest_fx_probe.tscn

const TEMPEST_FX := "res://scripts/weapons/fx/tempest_fx.gd"

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
	_box(Vector3(0, -0.5, -20), Vector3(40, 1, 60)) # floor, top at y = 0
	_box(Vector3(0, 2.0, -14), Vector3(8, 4, 0.5)) # wall, face at z = -13.75
	var w: Weapon = (load("res://scenes/weapons/tempest.tscn") as PackedScene).instantiate()
	add_child(w)
	var ctl: Weapon = (load("res://scenes/weapons/tempest.tscn") as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("the TPX-9 carries the Tempest signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == TEMPEST_FX)
	w._active_shooter = null
	ctl._active_shooter = null

	# Low over the floor.
	var strikes: Array = []
	var watch := func(n: Node) -> void:
		if n.get_meta("sig_fx", "") == "sky_strike":
			strikes.append(n)
	get_tree().node_added.connect(watch)
	var orb := _launch(w, Vector3(0, 1.2, 0), Vector3(0, 0, -1))
	var storm: Node3D = orb.get_node_or_null("TempestStorm") if orb else null
	_check("a launched orb carries a storm rig", storm != null)
	if storm:
		var tendrils: Array = storm.tendrils
		_check("TENDRILS arcs crackle off it", tendrils.size() == TempestFx.TENDRILS, str(tendrils.size()))
		var reach_ok := true
		for b: ArcBolt in tendrils:
			var pts := b.points()
			reach_ok = reach_ok and pts[0].distance_to(storm.global_position) < 0.01 \
					and pts[pts.size() - 1].distance_to(storm.global_position) <= TempestFx.TENDRIL_REACH.y + 0.01
		_check("each reaches from the orb out to within TENDRIL_REACH", reach_ok)
		var before: Vector3 = (tendrils[0] as ArcBolt).points()[1]
		storm.strike()
		_check("re-struck, the arcs move", (tendrils[0] as ArcBolt).points()[1].distance_to(before) > 0.001)
		_check("1.2 m over the floor it licks a ground arc", storm.ground.visible)
		var gp := (storm.ground as ArcBolt).points()
		_check("the ground arc lands on the floor", absf(gp[gp.size() - 1].y) < 0.02, str(gp[gp.size() - 1]))
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(orb) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check("where it goes off a sky strike stands on the blast", strikes.size() == 1, str(strikes.size()))
	if strikes.size() == 1 and is_instance_valid(strikes[0]):
		var s: Node3D = strikes[0]
		_check("the strike is on the wall's face", absf(s.global_position.z - (-13.75)) < 0.4, str(s.global_position))
		_check("its light comes from the FX budget", s.light_budgeted)
	get_tree().node_added.disconnect(watch)

	# High: no ground arc.
	var high := _launch(w, Vector3(10, 6.0, 0), Vector3(0, 0, -1))
	var hs: Node3D = high.get_node_or_null("TempestStorm") if high else null
	if hs:
		hs.strike()
	_check("6 m up it shows no ground arc", hs != null and not hs.ground.visible)
	if high:
		high.queue_free()

	# Over budget: the strike brings no light.
	var live0: int = FXLights._live
	FXLights._live = FXLights._budget()
	var starved := LightningStrike.new()
	starved.light_budgeted = true
	add_child(starved)
	_check("with the FX light budget full a budgeted strike brings no light",
			starved.find_children("*", "OmniLight3D", true, false).is_empty())
	FXLights._live = live0
	var boss := LightningStrike.new()
	add_child(boss)
	_check("an unbudgeted strike (the boss's) keeps its light",
			not boss.find_children("*", "OmniLight3D", true, false).is_empty())

	# Unsigned.
	strikes.clear()
	get_tree().node_added.connect(watch)
	var co := _launch(ctl, Vector3(0, 1.2, 0), Vector3(0, 0, -1))
	_check("an unsigned orb carries no storm", co != null and co.get_node_or_null("TempestStorm") == null)
	t0 = Time.get_ticks_msec()
	while is_instance_valid(co) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_tree().node_added.disconnect(watch)
	_check("an unsigned orb calls no strike", strikes.is_empty(), str(strikes.size()))
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
