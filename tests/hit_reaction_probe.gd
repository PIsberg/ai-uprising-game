extends Node3D
## Probe: a robot reacts to WHAT hit it (EnemyBase._on_damaged / _play_hit_flash).
## (1) the hit flash takes the hitting gun's damage-class colour
##     (DamageMatrix.CLASS_COLORS), white for untagged damage;
## (2) an ARC hit stutters (the flash dips and comes back before it fades), a
##     THERMAL hit glows off slower than a KINETIC one;
## (3) poise follows the matchup: on a HEAVY PLATE gunner, equal hits from a
##     counter gun (Longshot, RAIL) stagger it in fewer hits than untagged
##     damage, and a resisted gun (AR-7, KINETIC) needs more.
##   godot --headless --path . --audio-driver Dummy res://tests/hit_reaction_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(100, 1, 100)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var shooter := Node3D.new()
	shooter.add_to_group("player")
	add_child(shooter)
	shooter.global_position = Vector3(0, 1.5, 30)
	var android := await _enemy("android", Vector3(-10, 0, 0))
	var gunner := await _enemy("gunner", Vector3(10, 0, 0))

	# 1-2. Flash colour and shape per class.
	var guns := {}
	for p: String in GameState.WEAPON_ORDER:
		var d := DamageMatrix.weapon_data_of(p)
		if not guns.has(d.damage_class):
			guns[d.damage_class] = d
	for c: int in guns:
		_hit(android, guns[c], 1.0, shooter)
		var col: Color = android._flash_mat.albedo_color
		var want: Color = DamageMatrix.CLASS_COLORS[c]
		_check("%s hit flashes its class colour" % DamageMatrix.CLASS_NAMES[c],
			Color(col.r, col.g, col.b).is_equal_approx(want), "%s vs %s" % [col, want])
	_hit(android, null, 1.0, shooter)
	var plain: Color = android._flash_mat.albedo_color
	_check("untagged hit flashes white", Color(plain.r, plain.g, plain.b).is_equal_approx(Color.WHITE), str(plain))

	# Settle first: loading every gun scene above makes the next frame's delta
	# huge, which would fast-forward the first trace's tween.
	for i in 5:
		await get_tree().process_frame
	var kin := await _alpha_trace(android, guns[WeaponData.DamageClass.KINETIC], shooter)
	var arc := await _alpha_trace(android, guns[WeaponData.DamageClass.ARC], shooter)
	var dipped := false
	var came_back := false
	for i in range(1, arc.size()):
		if arc[i] < 0.3 and not dipped:
			dipped = true
		elif dipped and arc[i] > 0.5:
			came_back = true
	_check("ARC flash stutters (dips, then flares again)", dipped and came_back, str(arc))
	var th := await _alpha_trace(android, guns[WeaponData.DamageClass.THERMAL], shooter)
	_check("THERMAL glow outlasts a KINETIC flash", _lit_frames(th) > _lit_frames(kin),
		"%d vs %d frames lit" % [_lit_frames(th), _lit_frames(kin)])

	# 3. Poise by matchup on HEAVY PLATE.
	var per_hit := gunner.stagger_threshold * 0.2
	var n_counter := _hits_to_stagger(gunner, guns[WeaponData.DamageClass.RAIL], per_hit, shooter)
	var n_plain := _hits_to_stagger(gunner, null, per_hit, shooter)
	var n_resist := _hits_to_stagger(gunner, guns[WeaponData.DamageClass.KINETIC], per_hit, shooter)
	print("   gunner staggers after: RAIL %d, untagged %d, KINETIC %d hits of %.1f" % [n_counter, n_plain, n_resist, per_hit])
	_check("a counter gun staggers HEAVY PLATE in fewer hits", n_counter < n_plain, "%d vs %d" % [n_counter, n_plain])
	_check("a resisted gun needs more hits to stagger it", n_resist > n_plain, "%d vs %d" % [n_resist, n_plain])
	# The table's damage multiplier alone already reorders these; poise must
	# add to it: fewer / more hits than the damage alone would take.
	var dmg_only_counter := ceili(gunner.stagger_threshold / (per_hit * DamageMatrix.mult("gunner", WeaponData.DamageClass.RAIL)) - 0.001)
	var dmg_only_resist := ceili(gunner.stagger_threshold / (per_hit * DamageMatrix.mult("gunner", WeaponData.DamageClass.KINETIC)) - 0.001)
	_check("counter poise beats what its damage alone would do", n_counter < dmg_only_counter, "%d vs %d" % [n_counter, dmg_only_counter])
	_check("resisted poise lags what its damage alone would do", n_resist > dmg_only_resist, "%d vs %d" % [n_resist, dmg_only_resist])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _enemy(type: String, at: Vector3) -> EnemyBase:
	var e: EnemyBase = (load(LevelBuilder.ENEMY_SCENES[type]) as PackedScene).instantiate()
	e.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	e.process_mode = Node.PROCESS_MODE_DISABLED # AI off; its hit signals still run
	add_child(e)
	e.global_position = at
	for i in 3:
		await get_tree().physics_frame
	e.hp.max_health = 100000.0
	e.hp.current_health = 100000.0
	e.hp.armor = 0.0
	return e

## `amount` through e's Damageable with `w` tagged on it (null: untagged).
func _hit(e: EnemyBase, w: WeaponData, amount: float, shooter: Node) -> void:
	KillFx.tag(e.hp, 0, w)
	e.hp.apply_damage(amount, shooter)
	KillFx.untag(e.hp)

## The flash overlay's alpha over 30 process frames after one hit. The flash
## tween is bound to the robot, so the robot's processing is switched back on
## for the trace (its physics, the AI, stays off).
func _alpha_trace(e: EnemyBase, w: WeaponData, shooter: Node) -> Array:
	e.process_mode = Node.PROCESS_MODE_INHERIT
	e.set_physics_process(false)
	_hit(e, w, 1.0, shooter)
	var out: Array = []
	for i in 30:
		await get_tree().process_frame
		out.append(snappedf(e._flash_mat.albedo_color.a, 0.01))
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return out

func _lit_frames(trace: Array) -> int:
	return trace.filter(func(a: float) -> bool: return a > 0.05).size()

func _hits_to_stagger(e: EnemyBase, w: WeaponData, amount: float, shooter: Node) -> int:
	e.set_state(EnemyBase.State.IDLE)
	e._poise = 0.0
	for i in 40:
		_hit(e, w, amount, shooter)
		if e.state == EnemyBase.State.STAGGER:
			return i + 1
	return 99
