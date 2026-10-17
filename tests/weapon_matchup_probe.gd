extends Node
## Probe: every gun is the right tool for some robots and the wrong one for
## others (DamageMatrix, scripts/weapons/damage_matrix.gd).
## (1) coverage: every enemy type the level builder spawns has an armour class,
##     and every weapon in WEAPON_ORDER a damage class;
## (2) the table is a real choice: every damage class some weapon carries
##     counters at least one armour class and is resisted by another, and every
##     non-CHASSIS armour class has at least two gun classes that counter it;
## (3) bosses take the matchup at half strength;
## (4) through the real hit paths (a hitscan, a projectile's splash, a beam
##     tick): the hit lands at base x the table's multiplier, measured against
##     the same hit on a CHASSIS android;
## (5) untagged damage (grenades, melee) ignores the table;
## (6) feedback: a counter hit and a resisted hit emit GameState.weapon_matchup
##     and tint the damage number; a neutral hit emits nothing; the first
##     counter / resist on an armour class teaches its hint once;
## (7) the codex lists only guns that exist and counter the robot.
##   godot --headless --path . --audio-driver Dummy res://tests/weapon_matchup_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Coverage.
	var missing: Array = []
	for type: String in LevelBuilder.ENEMY_SCENES:
		var ps := load(LevelBuilder.ENEMY_SCENES[type]) as PackedScene
		var inst := ps.instantiate() # not added: no _ready, no entrance
		var key: String = inst.codex_key() if inst.has_method("codex_key") else type
		inst.free()
		if not DamageMatrix.has_armour(key):
			missing.append(key)
	_check("every spawnable enemy has an armour class", missing.is_empty(), str(missing))
	for key: String in EnemyCodex.ORDER:
		if not DamageMatrix.has_armour(key):
			missing.append(key)
	_check("every codex entry has an armour class", missing.is_empty(), str(missing))
	var classes := {}
	for p: String in GameState.WEAPON_ORDER:
		var d := DamageMatrix.weapon_data_of(p)
		_check("weapon data readable: %s" % p.get_file(), d != null)
		if d:
			classes[d.damage_class] = classes.get(d.damage_class, []) + [d.display_name]
	_check("all six damage classes are carried by some gun", classes.size() == DamageMatrix.CLASS_NAMES.size(),
			str(classes))

	# 2. A real choice.
	for c: int in classes:
		_check("%s counters something" % DamageMatrix.CLASS_NAMES[c], not DamageMatrix.strong_vs(c).is_empty())
		_check("%s is resisted by something" % DamageMatrix.CLASS_NAMES[c], not DamageMatrix.weak_vs(c).is_empty())
	for a in range(1, DamageMatrix.TABLE.size()):
		var n := 0
		for c: int in classes:
			if DamageMatrix.TABLE[a][c] >= DamageMatrix.WEAK_AT:
				n += 1
		_check("%s has 2+ counter classes" % DamageMatrix.ARMOUR_NAMES[a], n >= 2, str(n))

	# 3. Bosses half-strength.
	var full: float = DamageMatrix.TABLE[DamageMatrix.Armour.PLATED][WeaponData.DamageClass.EXPLOSIVE]
	_check("boss damping", is_equal_approx(DamageMatrix.mult("colossus", WeaponData.DamageClass.EXPLOSIVE),
			1.0 + (full - 1.0) * DamageMatrix.BOSS_DAMP), "%.3f" % DamageMatrix.mult("colossus", 4))
	_check("non-boss plated gets the full swing",
			is_equal_approx(DamageMatrix.mult("gunner", WeaponData.DamageClass.EXPLOSIVE), full))

	# 4. Real hit paths.
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(400, 1, 400)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 60)

	# Flyers hover above the floor so a ray at their centre clears it.
	var android := await _enemy("android", Vector3(-40, 0, 0))
	var gunner := await _enemy("gunner", Vector3(-20, 0, 0))
	var drone := await _enemy("drone", Vector3(0, 3, 0))
	var mender := await _enemy("mender", Vector3(20, 3, 0))

	var rifle := _gun("rifle", shooter)      # KINETIC
	var shotgun := _gun("shotgun", shooter)  # SHRED
	var sniper := _gun("sniper", shooter)    # RAIL
	var tesla := _gun("tesla", shooter)      # ARC (beam)
	var plasma := _gun("plasma", shooter)    # THERMAL (projectile + splash)
	var events: Array = []
	GameState.weapon_matchup.connect(func(k: String, w: String, m: float, _p: Vector3) -> void:
		events.append([k, w, m]))

	# Exact damage through Damageable with each gun tagged on real robots (a
	# body hit's crit zones would muddy a raw comparison; the table is the
	# only thing between a tagged 100 and what comes off).
	for pair in [[rifle, android], [rifle, gunner], [rifle, drone], [shotgun, drone], [shotgun, gunner],
			[sniper, gunner], [sniper, mender], [tesla, mender], [plasma, gunner], [plasma, mender]]:
		var w: Weapon = pair[0]
		var e: EnemyBase = pair[1]
		var want := 100.0 * DamageMatrix.mult(e.codex_key(), w.data.damage_class)
		var got := _tagged(w, e, 100.0)
		_check("%s on %s: %.0f" % [w.data.display_name, e.codex_key(), want], is_equal_approx(got, want), "%.2f" % got)
	_check("tagged neutral hit emits nothing; resists and counters do",
			events.size() == 9 and events.all(func(ev: Array) -> bool: return ev[0] != "android"), str(events.size()))
	events.clear()
	_tagged(rifle, gunner, 10.0)
	var resist_num := _last_number()
	_check("resisted damage number is steel", resist_num != null and resist_num.modulate.is_equal_approx(Damageable.RESIST_TINT))
	_tagged(shotgun, drone, 10.0)
	var weak_num := _last_number()
	_check("counter damage number is cyan", weak_num != null and weak_num.modulate.is_equal_approx(Damageable.WEAK_TINT))

	# The real hit paths carry the gun to the table (Damageable.matchup is the
	# multiplier the last hit actually took).
	events.clear()
	_check("hitscan on android lands", _hitscan(rifle, android) > 0.0)
	_check("neutral hitscan: matchup 1.0, no event", is_equal_approx(android.hp.matchup, 1.0) and events.is_empty(), str(events))
	_check("hitscan on gunner lands", _hitscan(rifle, gunner) > 0.0)
	_check("rifle hitscan on gunner took x0.8", is_equal_approx(gunner.hp.matchup, DamageMatrix.mult("gunner", 0)),
			"%.2f" % gunner.hp.matchup)
	_check("rifle hitscan on drone lands", _hitscan(rifle, drone) > 0.0)
	_check("rifle hitscan on drone took x1.25", is_equal_approx(drone.hp.matchup, 1.25), "%.2f" % drone.hp.matchup)
	_check("shotgun pellets on drone land", _point_blank(shotgun, drone) > 0.0)
	_check("shotgun pellets on drone took x1.5", is_equal_approx(drone.hp.matchup, 1.5), "%.2f" % drone.hp.matchup)
	_check("rail hitscan on mender lands", _hitscan(sniper, mender) > 0.0)
	_check("rail on mender took x1.25", is_equal_approx(mender.hp.matchup, 1.25), "%.2f" % mender.hp.matchup)
	_check("Tesla beam tick on mender lands", await _beam_tick(tesla, mender) > 0.0)
	_check("ARC beam tick on mender took x1.6", is_equal_approx(mender.hp.matchup, 1.6), "%.2f" % mender.hp.matchup)
	_check("plasma splash on gunner lands", await _splash(plasma, gunner) > 0.0)
	_check("THERMAL splash on gunner took x1.35", is_equal_approx(gunner.hp.matchup, 1.35), "%.2f" % gunner.hp.matchup)
	_check("real hits emitted matchup events", events.size() >= 5, str(events.size()))

	# 5. Untagged damage.
	var h := gunner.hp.current_health
	gunner.hp.apply_damage(50.0, shooter)
	_check("untagged damage ignores the table", is_equal_approx(h - gunner.hp.current_health, 50.0),
			"%.1f" % (h - gunner.hp.current_health))

	# 6. The hint teaches once per armour class and result.
	_check("plated resist hint taught", GameState._taught.has("matchup_plated_resist"))
	_check("light weak hint taught", GameState._taught.has("matchup_light_weak"))
	_check("networked weak hint taught", GameState._taught.has("matchup_networked_weak"))
	var hints: Array = []
	GameState.teach_hint.connect(func(t: String) -> void: hints.append(t))
	_hitscan(rifle, gunner)
	_check("second resist on the same class teaches nothing", hints.is_empty(), str(hints))

	# 7. Codex.
	var lines := DamageMatrix.codex_lines("gunner")
	_check("codex leads with the armour", lines.size() > 1 and "HEAVY PLATE" in String(lines[0]), str(lines))
	var named_ok := true
	for d: WeaponData in DamageMatrix.recommended("gunner", GameState.WEAPON_ORDER):
		named_ok = named_ok and DamageMatrix.mult("gunner", d.damage_class) >= DamageMatrix.WEAK_AT
	_check("codex recommends only counters", named_ok)
	_check("CHASSIS codex says no edge", DamageMatrix.codex_lines("android").size() == 2)
	_check("no codex entry still authors a weapons list", EnemyCodex.ENTRIES.values().all(
			func(e: Dictionary) -> bool: return not e.has("weapons")))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _enemy(type: String, at: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(LevelBuilder.ENEMY_SCENES[type]) as PackedScene).instantiate()
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED # AI off: it must stay in the line of fire
	add_child(e)
	e.global_position = at
	await _frames(3)
	e.hp.max_health = 100000.0
	e.hp.current_health = 100000.0
	e.hp.armor = 0.0
	return e

func _gun(id: String, shooter: Node) -> Weapon:
	var w: Weapon = (load("res://scenes/weapons/%s.tscn" % id) as PackedScene).instantiate()
	add_child(w)
	w._active_shooter = shooter
	return w

## A point on the robot's body under the head-crit band.
func _body(e: EnemyBase) -> Vector3:
	for c in e.find_children("*", "CollisionShape3D", true, false):
		if (c as CollisionShape3D).get_parent() == e:
			return (c as Node3D).global_position
	return e.global_position + Vector3.UP * 0.7

## One hitscan from 10 m in front (+Z) of the body; the damage it did.
func _hitscan(w: Weapon, e: EnemyBase) -> float:
	var at := _body(e)
	var h := e.hp.current_health
	w._do_hitscan(at + Vector3(0, 0, 10), Vector3(0, 0, -1))
	return h - e.hp.current_health

## Every pellet of one shotgun blast from 1.5 m, aimed straight (spread 0).
func _point_blank(w: Weapon, e: EnemyBase) -> float:
	var at := _body(e)
	var h := e.hp.current_health
	for i in w.data.pellets:
		w._do_hitscan(at + Vector3(0, 0, 4), Vector3(0, 0, -1))
	return h - e.hp.current_health

## One Tesla beam tick on `e`, from a camera 6 m in front of it.
func _beam_tick(w: Weapon, e: EnemyBase) -> float:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = _body(e) + Vector3(0, 0, 4)
	cam.look_at(_body(e))
	w._active_camera = cam
	w.mag = 50
	var h := e.hp.current_health
	w._beam_wanted = true
	w._beam_tick = 0.0
	w._update_beam(0.001)
	w._beam_wanted = false
	w._update_beam(0.001)
	cam.queue_free()
	await get_tree().process_frame
	return h - e.hp.current_health

## A plasma round detonating on the floor 1.2 m from the robot's feet.
func _splash(w: Weapon, e: EnemyBase) -> float:
	var proj := w.data.projectile_scene.instantiate()
	add_child(proj)
	proj.weapon_data = w.data
	var h := e.hp.current_health
	proj.global_position = e.global_position + Vector3(0, 40, 0) # out of everything's way
	proj.launch(Vector3.ZERO, w._active_shooter, 0.0, w.data.splash_radius, w.data.splash_damage)
	await get_tree().physics_frame
	proj._explode(e.global_position + Vector3(1.2, 0.0, 0.0))
	await get_tree().physics_frame
	return h - e.hp.current_health

## `amount` through e's Damageable with `w` tagged on the hit, the way every
## weapon path applies it; the damage that came off.
func _tagged(w: Weapon, e: EnemyBase, amount: float) -> float:
	var h := e.hp.current_health
	KillFx.tag(e.hp, 0, w.data)
	e.hp.apply_damage(amount, w._active_shooter)
	KillFx.untag(e.hp)
	return h - e.hp.current_health

## The newest floating damage number (Damageable spawns them in current_scene).
func _last_number() -> Label3D:
	var best: Label3D = null
	for c in get_tree().current_scene.get_children():
		if c is Label3D:
			best = c
	return best
