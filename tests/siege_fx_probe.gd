extends Node3D
## Probe: the SIEGE Chaingun's signature (SiegeFx, scripts/weapons/fx/siege_fx.gd),
## the salvaged GUNNER arm gun firing like the robot's own:
##   - a cluster of six barrels (the GUNNER's count) rings the bore at the muzzle,
##     its tips at the muzzle point;
##   - at rest it does not turn; the trigger spins it to SPIN_MAX (the GUNNER's
##     rotor speed) inside SPIN_UP; let go and it coasts, still turning half a
##     second later, at rest after COAST, with one wind-down whine;
##   - the barrels soak heat: cold and dark at rest, glowing after 20 rounds,
##     brighter after 40 and capped there, their colour from the GUNNER's
##     HEAT_COLD to its HEAT_HOT; they hold their heat while the gun runs and
##     cool once it stops;
##   - every round is a short fast tracer, in the gun's colour cold and burning
##     toward white hot;
##   - every shot throws one case and one belt link downward, no shared brass
##     and no shared muzzle smoke;
##   - hot barrels smoke once the gun stops (wisps at the tips), cold ones do
##     not, and nothing smokes while it fires;
##   - a round into a wall leaves one scorch flat on the wall; more rounds into
##     the same spot feed that one scorch (hotter, wider, brighter) instead of
##     adding more; a round elsewhere starts another; a scorch cools and is gone
##     after CHEW_LIFE; never more than MAX_SCORCH at once;
##     once one has been freed, a hit on another still feeds that one;
##   - every CHIP_EVERY-th round on a robot knocks a falling chip off its plating;
##   - an unsigned chaingun has none of it and keeps the shared brass and smoke.
##   godot --headless --path . --audio-driver Dummy res://tests/siege_fx_probe.tscn

const SIEGE_FX := "res://scripts/weapons/fx/siege_fx.gd"
const GUN := "res://scenes/weapons/salvage_chaingun.tscn"
const STEP := 1.0 / 14.0 ## the gun's own cadence

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
	cam.look_at_from_position(Vector3(0, 1.6, 0.4), Vector3(0, 1.6, -30), Vector3.UP)
	var w: Weapon = (load(GUN) as PackedScene).instantiate()
	add_child(w)
	w.global_position = Vector3(0.2, 1.4, 0)
	var ctl: Weapon = (load(GUN) as PackedScene).instantiate()
	ctl.data = ctl.data.duplicate()
	ctl.data.signature_fx = null
	add_child(ctl)
	ctl.global_position = Vector3(-0.2, 1.4, 0)
	# Off to the sides, so the shots fired down the camera's line hit nothing.
	var wall := _wall(Vector3(-12, 3, -8))
	var robot := _robot(Vector3(8, 1.5, -5))
	for i in 3:
		await get_tree().process_frame
	await get_tree().physics_frame
	w._active_camera = cam
	ctl._active_camera = cam

	_check("the SIEGE Chaingun carries the siege signature",
			w._sig != null and w._sig.get_script() != null and w._sig.get_script().resource_path == SIEGE_FX)
	# Everything below is found by meta or read through hooks an unwired gun
	# does not have, so each check fails on its own when the signature is missing.
	var sig: Object = w._sig
	var wired := sig.has_method("spin")

	# --- the barrel cluster ---
	var rotors := w.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "siege_rotor")
	_check("one barrel cluster sits on the muzzle", rotors.size() == 1, str(rotors.size()))
	var rotor: Node3D = rotors[0] if rotors.size() == 1 else null
	var barrels: Array = []
	if rotor:
		barrels = rotor.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "siege_barrel")
	_check("it has the GUNNER's six barrels", barrels.size() == EnemyGunner.ROTOR_BARRELS, str(barrels.size()))
	if rotor and not barrels.is_empty():
		var bore := -w.muzzle.global_basis.z.normalized()
		var radii := barrels.map(func(b: Node3D) -> float:
				var d := b.global_position - w.muzzle.global_position
				return (d - bore * d.dot(bore)).length())
		_check("the barrels ring the bore", radii.min() > 0.012 and radii.max() < 0.04 and radii.max() - radii.min() < 0.001,
				"%.3f..%.3f m" % [radii.min(), radii.max()])
		var tips := barrels.map(func(b: Node3D) -> float:
				return ((b.global_position - w.muzzle.global_position).dot(bore)) + (b.mesh as CylinderMesh).height * 0.5)
		_check("their tips are at the muzzle point", absf(tips.max()) < 0.01 and absf(tips.min()) < 0.01, "%.3f m" % tips.max())

	# --- spin: rest, spin-up, coast ---
	if wired:
		_reset(sig)
		var x0 := rotor.basis.x
		sig.on_process(0.1)
		_check("at rest the cluster does not turn", is_zero_approx(sig.spin()) and rotor.basis.x.is_equal_approx(x0))
		var t := 0.0
		while t < SiegeFx.SPIN_UP + STEP:
			sig.on_fire()
			sig.on_process(STEP)
			t += STEP
		_check("the trigger spins it to the GUNNER's rotor speed inside SPIN_UP",
				is_equal_approx(sig.spin(), SiegeFx.SPIN_MAX) and is_equal_approx(SiegeFx.SPIN_MAX, EnemyGunner.ROTOR_SPIN_MAX),
				"%.1f rad/s" % sig.spin())
		_check("the cluster turned about the bore",
				not rotor.basis.x.is_equal_approx(x0) and rotor.basis.z.is_equal_approx(Vector3.BACK), str(rotor.basis.x))
		var whines0: int = sig.wind_downs
		for i in 10:
			sig.on_process(0.05)
		var x1 := rotor.basis.x
		var coasting: float = sig.spin()
		sig.on_process(0.05)
		_check("half a second after letting go it is still coasting",
				coasting > 1.0 and coasting < SiegeFx.SPIN_MAX and not rotor.basis.x.is_equal_approx(x1), "%.1f rad/s" % coasting)
		for i in int(SiegeFx.COAST / 0.05) + 2:
			sig.on_process(0.05)
		_check("it is at rest after COAST", is_zero_approx(sig.spin()), "%.2f" % sig.spin())
		_check("letting go from full speed whines down once", sig.wind_downs == whines0 + 1, str(sig.wind_downs - whines0))

		# --- soak ---
		_reset(sig)
		sig.on_process(0.0)
		var g0: float = sig.glow()
		_check("cold barrels are dark", is_zero_approx(sig.soak()) and is_zero_approx(g0))
		for i in 20:
			sig.on_fire()
			sig.on_process(STEP)
		var s20: float = sig.soak()
		var g20: float = sig.glow()
		var c20: Color = sig.barrel_color()
		for i in 40:
			sig.on_fire()
			sig.on_process(STEP)
		var s60: float = sig.soak()
		var g60: float = sig.glow()
		_check("the barrels glow after 20 rounds, brighter after 60, and the soak caps at 1",
				s20 > 0.3 and s20 < 0.8 and g20 > 0.2 and g60 > g20 * 1.5 and is_equal_approx(s60, 1.0),
				"soak %.2f -> %.2f, glow %.2f -> %.2f" % [s20, s60, g20, g60])
		_check("their colour runs from the GUNNER's HEAT_COLD to its HEAT_HOT",
				SiegeFx.HEAT_COLD.is_equal_approx(EnemyGunner.HEAT_COLD) and SiegeFx.HEAT_HOT.is_equal_approx(EnemyGunner.HEAT_HOT)
				and sig.barrel_color().is_equal_approx(EnemyGunner.HEAT_HOT) and c20.g < sig.barrel_color().g and c20.g > EnemyGunner.HEAT_COLD.g,
				"%s -> %s" % [c20, sig.barrel_color()])
		for i in 14:
			sig.on_process(STEP)
		_check("once the gun stops the barrels cool", sig.soak() < 0.9 and sig.soak() > 0.5 and sig.glow() < g60, "%.2f" % sig.soak())

	# --- the tracer stream ---
	var from := Vector3(0.3, 1.4, 0)
	var to := Vector3(0.0, 1.6, -30.0)
	if wired:
		_reset(sig)
	var cold_t := _tracers(w, from, to, 4)
	_check("every round is a short fast tracer",
			cold_t.size() == 4 and cold_t.all(func(t: Node) -> bool: return is_equal_approx(t.bolt_length, 1.5) and is_equal_approx(t.bolt_speed, 210.0)),
			str(cold_t.map(func(t: Node) -> float: return t.bolt_length)))
	var cold_tint: Color = cold_t[0]._mat.get_shader_parameter("tint") if not cold_t.is_empty() else Color.BLACK
	_check("a cold gun's tracer is the gun's own colour", cold_tint.is_equal_approx(w.shot_color()), str(cold_tint))
	if wired:
		sig._soak = 1.0
		var hot_t := _tracers(w, from, to, 1)
		var hot_tint: Color = hot_t[0]._mat.get_shader_parameter("tint")
		_check("a hot gun's tracer burns toward white",
				hot_tint.g + hot_tint.b > cold_tint.g + cold_tint.b + 0.3, "%s vs %s" % [hot_tint, cold_tint])
		for n in hot_t:
			n.queue_free()
	for n in cold_t:
		n.queue_free()

	# --- cases, links, no shared brass or smoke ---
	if wired:
		_reset(sig)
	var shots: Array = []
	for i in 3:
		shots.append_array(_spawned(func() -> void: w._do_shot()))
	var cases := _tagged(shots, "siege_case")
	var links := _tagged(shots, "siege_link")
	_check("three shots throw three cases and three belt links", cases.size() == 3 and links.size() == 3,
			"%d cases, %d links" % [cases.size(), links.size()])
	_check("cases and links fall out of the bottom of the gun",
			not cases.is_empty() and (cases + links).all(func(p: CPUParticles3D) -> bool:
				return p.direction.y < -0.7 and p.global_position.y < w.global_position.y and p.gravity.y < 0.0))
	_check("the chaingun throws no shared brass and no shared muzzle smoke",
			shots.filter(func(n: Node) -> bool: return n.get_meta("shared_fx", "") in ["brass", "muzzle_smoke"]).is_empty()
			and wired)

	# --- cooling smoke ---
	if wired:
		_reset(sig)
		var cold_wisps := _spawned(func() -> void:
				for i in 20:
					sig.on_process(0.05))
		_check("cold barrels do not smoke", _tagged(cold_wisps, "siege_wisp").is_empty())
		sig._soak = 1.0
		var firing_wisps := _spawned(func() -> void:
				for i in 14:
					sig.on_fire()
					sig.on_process(STEP))
		_check("nothing smokes while the gun fires", _tagged(firing_wisps, "siege_wisp").is_empty())
		sig._soak = 1.0
		var idle_wisps := _tagged(_spawned(func() -> void:
				for i in 24:
					sig.on_process(0.05)), "siege_wisp")
		_check("hot barrels smoke once it stops", idle_wisps.size() >= 3 and idle_wisps.size() <= 6, str(idle_wisps.size()))
		_check("the smoke leaves the barrel tips",
				not idle_wisps.is_empty() and idle_wisps.all(func(p: Node3D) -> bool: return p.global_position.distance_to(w.muzzle.global_position) < 0.05))
		sig._soak = SiegeFx.WISP_AT - 0.05
		var warm_wisps := _spawned(func() -> void:
				for i in 20:
					sig.on_process(0.05))
		_check("barrels under WISP_AT do not smoke", _tagged(warm_wisps, "siege_wisp").is_empty())

	# --- chewing a wall ---
	# The wall's +Z face is at z = -7.75, x from -16 to -8.
	var wo := Vector3(-12, 2.0, 0)
	var dir := Vector3(0, 0, -1)
	var first := _tagged(_spawned(func() -> void: w._do_hitscan(wo, dir)), "siege_scorch")
	_check("a round into a wall leaves one scorch", first.size() == 1, str(first.size()))
	if first.size() == 1:
		var sc: Node3D = first[0]
		_check("the scorch lies flat on the wall where the round struck",
				sc.global_basis.y.normalized().dot(Vector3.BACK) > 0.95 and sc.global_position.distance_to(Vector3(-12, 2.0, -7.75)) < 0.05,
				str(sc.global_position))
		var h1: float = sc.heat
		var r1: float = sc.radius()
		var e1: float = sc.mat.emission_energy_multiplier
		var more := _tagged(_spawned(func() -> void:
				for i in 4:
					w._do_hitscan(wo + Vector3(0.1 * (i % 2), 0.05 * i, 0), dir)), "siege_scorch")
		_check("four more rounds into the same spot feed that one scorch", more.is_empty() and _live_scorches().size() == 1,
				"%d new" % more.size())
		_check("a fed scorch is hotter, wider and brighter",
				sc.heat > h1 * 3.0 and sc.radius() > r1 * 1.3 and sc.mat.emission_energy_multiplier > e1,
				"heat %.2f -> %.2f, r %.2f -> %.2f" % [h1, sc.heat, r1, sc.radius()])
		var far := _tagged(_spawned(func() -> void: w._do_hitscan(wo + Vector3(3, 0, 0), dir)), "siege_scorch")
		_check("a round elsewhere starts another scorch", far.size() == 1 and _live_scorches().size() == 2)
		var hot: float = sc.heat
		sc._tick(0.5)
		_check("a scorch cools", sc.heat < hot and sc.heat > 0.0, "%.2f -> %.2f" % [hot, sc.heat])
		sc.heat = 1.0
		sc._tick(SiegeFx.CHEW_LIFE + 0.01)
		_check("a scorch is gone after CHEW_LIFE", sc.is_queued_for_deletion())
		for i in 7:
			w._do_hitscan(Vector3(-15.5 + i, 4.5, 0), dir)
		_check("never more than MAX_SCORCH at once", _live_scorches().size() == SiegeFx.MAX_SCORCH, str(_live_scorches().size()))

	# --- chips off a robot ---
	var ro := Vector3(8, 1.5, 0)
	var hp0: float = robot.get_node("Damageable").current_health
	var hits: Array = []
	for i in 4:
		hits.append_array(_spawned(func() -> void: w._do_hitscan(ro, dir)))
	var chips := _tagged(hits, "siege_chip")
	_check("the rounds hit the robot", robot.get_node("Damageable").current_health < hp0)
	_check("every CHIP_EVERY-th round on a robot knocks a chip off", wired and chips.size() == 4 / SiegeFx.CHIP_EVERY, str(chips.size()))
	_check("the chips fall from the hit",
			not chips.is_empty() and chips.all(func(p: CPUParticles3D) -> bool:
				return p.gravity.y < 0.0 and p.global_position.distance_to(Vector3(8, 1.5, -4.6)) < 0.3))

	# --- unsigned control ---
	var crotors := ctl.muzzle.get_children().filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == "siege_rotor")
	var cshots := _spawned(func() -> void:
			ctl._do_shot()
			ctl._do_hitscan(wo + Vector3(-3, 0, 0), dir)
			ctl._do_hitscan(ro, dir)
			ctl._do_hitscan(ro, dir))
	_check("an unsigned chaingun has no cluster, no scorch, no chips, no links",
			crotors.is_empty() and cshots.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") != "").is_empty())
	_check("an unsigned chaingun keeps the shared brass and muzzle smoke",
			cshots.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "brass")
			and cshots.any(func(n: Node) -> bool: return n.get_meta("shared_fx", "") == "muzzle_smoke"))
	var ct := _tracers(ctl, from, to, 1)
	_check("an unsigned chaingun's tracer is the stock bolt (2.2 m at 150 m/s)",
			ct.size() == 1 and is_equal_approx(ct[0].bolt_length, 2.2) and is_equal_approx(ct[0].bolt_speed, 150.0))
	# A scorch that has really been freed (not just queued) must not break the
	# bookkeeping: a hit on a live scorch after that still feeds it.
	var live := _live_scorches()
	if live.size() >= 2:
		var dead: Node3D = live[0]
		var kept: Node3D = live[live.size() - 1]
		var kept_at := kept.global_position
		dead.heat = 0.01
		dead._tick(1.0)
		kept.heat = 0.5
		await get_tree().process_frame
		await get_tree().process_frame
		kept.heat = 0.5
		var after := _tagged(_spawned(func() -> void: w._do_hitscan(Vector3(kept_at.x, kept_at.y, 0), dir)), "siege_scorch")
		_check("after a scorch is freed, a hit on a live one still feeds it",
				not is_instance_valid(dead) and after.is_empty() and kept.heat > 0.6, "%d new, heat %.2f" % [after.size(), kept.heat])
	else:
		_check("after a scorch is freed, a hit on a live one still feeds it", false, "no scorches to test")
	wall.queue_free()
	var t_end := 0.0
	while t_end < 0.4:
		await get_tree().process_frame
		t_end += get_process_delta_time()
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Put the signature back to a cold gun that has been at rest for a long time.
func _reset(sig: Object) -> void:
	sig._spin = 0.0
	sig._soak = 0.0
	sig._since_fire = 999.0
	sig._wisp_t = 0.0

func _tracers(w: Weapon, from: Vector3, to: Vector3, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append_array(_spawned(func() -> void: w._spawn_tracer(from, to)).filter(func(n: Node) -> bool: return "bolt_length" in n))
	return out

func _live_scorches() -> Array:
	return get_children().filter(func(n: Node) -> bool:
			return n.get_meta("sig_fx", "") == "siege_scorch" and not n.is_queued_for_deletion())

func _tagged(nodes: Array, tag: String) -> Array:
	return nodes.filter(func(n: Node) -> bool: return n.get_meta("sig_fx", "") == tag)

## Run `action` and return the nodes it added under this scene.
func _spawned(action: Callable) -> Array:
	var before := get_children()
	action.call()
	return get_children().filter(func(n: Node) -> bool: return not n in before)

func _wall(at: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 6, 0.5)
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
	box.size = Vector3(3.0, 1.8, 0.8)
	cs.shape = box
	sb.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	sb.add_child(hp)
	add_child(sb)
	sb.global_position = at
	return sb
