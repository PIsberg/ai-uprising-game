extends Node3D
## Probe: FireVent, the floor fire vent ("fire_vents" def key).
## A vent at the origin (period 4 s), over two eruptions:
## (1) every eruption is warned WARN_TIME (1.2 s) ahead by `warning`;
## (2) through the warning the grate heats up (to white-hot) and flames lick
##     up through it, but the column only shows while it erupts;
## (3) a player standing on the grate burns only while it erupts, several
##     ticks per eruption, never while it warns; one standing just outside
##     the ring is never touched;
## (4) robots are never hurt: not on the grate, not 3 m off (traps are for the
##     player);
## (5) the first warning a nearby player sees teaches the rule, once;
## (6) the Crucible floors both bulkhead gaps with a row of vents that spans
##     the (scaled) gap, phased so no two in a row erupt at once;
## (7) Vulcan Forge puts vents on its recycler walkways: each sits on a
##     walkway's top, its ring fits the walkway, it leaves no gap past it a
##     body could use, and two on one walkway never erupt together;
## (8) a cryo vent (Mistral's coolant vents) frosts blue instead of glowing
##     orange and teaches its own line; the Mistral Cryo-Core floors its east
##     gap with a row of them, under the same row rules as the Crucible.
##   godot --headless --path . --audio-driver Dummy res://tests/fire_vent_probe.tscn

var ok := true
var _clock := 0.0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

func _robot(pos: Vector3) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	# Frozen where it stands: a live robot steps, strafes and is knocked about,
	# and on CI's slower runner it drifted half off the grate (6 burns, not 9).
	# Health, the enemy group and the deferred stat sync still run.
	e.process_mode = Node.PROCESS_MODE_DISABLED
	return e

func _phys(t: float) -> void:
	var tt := 0.0
	while tt < t:
		await get_tree().physics_frame
		tt += get_physics_process_delta_time()
		_clock += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_floor()
	var taught: Array[String] = []
	GameState.teach_hint.connect(func(text: String) -> void: taught.append(text))
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.0, 0)
	player.set_physics_process(false) # held where the probe puts it
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 1000000.0
	php.current_health = 1000000.0

	var vent := FireVent.new()
	vent.period = 4.0
	add_child(vent)
	vent.global_position = Vector3.ZERO
	var near_bot := _robot(Vector3(0.6, 0.0, -0.4))
	var far_bot := _robot(Vector3(0.0, 0.0, -1.4 - 3.0))
	var bot_hits := {near_bot: 0, far_bot: 0}
	for b in [near_bot, far_bot]:
		var bot: EnemyBase = b
		# The base stat too: EnemyBase's deferred _sync_stats rescales health
		# from it, and headless it can run after several physics frames.
		bot.max_health = 1000000.0
		bot.hp.max_health = 1000000.0
		bot.hp.current_health = 1000000.0
		bot.hp.damaged.connect(func(_a: float, src: Node) -> void:
			if src is FireVent:
				bot_hits[bot] += 1)

	var warn_at: Array[float] = []
	var erupt_at: Array[float] = []
	var hit_states: Array[int] = []
	vent.warning.connect(func() -> void: warn_at.append(_clock))
	vent.erupted.connect(func() -> void: erupt_at.append(_clock))
	php.damaged.connect(func(_a: float, src: Node) -> void:
		if src is FireVent:
			hit_states.append(vent.state))

	# Two full cycles standing on the grate, sampling the look as we go.
	var warn_heat_early := -1.0
	var warn_heat_late := -1.0
	var lick_in_warn := true
	var column_in_warn := false
	var column_in_erupt := true
	var shown_idle := false
	var t := 0.0
	while t < 8.2:
		await _phys(0.05)
		t += 0.05
		match vent.state:
			FireVent.Phase.WARN:
				var w := vent.warn_progress()
				if w < 0.2 and warn_heat_early < 0.0:
					warn_heat_early = vent.heat()
				if w > 0.85:
					warn_heat_late = vent.heat()
				lick_in_warn = lick_in_warn and vent.lick_visible()
				column_in_warn = column_in_warn or vent.column_visible()
			FireVent.Phase.ERUPT:
				column_in_erupt = column_in_erupt and vent.column_visible()
			FireVent.Phase.IDLE:
				shown_idle = shown_idle or vent.column_visible() or vent.lick_visible()

	_check("two eruptions in 8 s", erupt_at.size() == 2, "(%d)" % erupt_at.size())
	var leads: Array[float] = []
	for e in erupt_at:
		var lead := INF
		for w in warn_at:
			if w <= e:
				lead = e - w
		leads.append(lead)
	var warned := erupt_at.size() > 0
	for l in leads:
		warned = warned and absf(l - FireVent.WARN_TIME) < 0.06
	_check("every eruption is warned 1.2 s ahead", warned, "(leads %s)" % [leads])
	_check("the grate heats up through the warning", warn_heat_late > warn_heat_early and warn_heat_late > 0.85,
		"(%.2f -> %.2f)" % [warn_heat_early, warn_heat_late])
	_check("flames lick through the grate while it warns", lick_in_warn)
	_check("the column shows only while it erupts", column_in_erupt and not column_in_warn and not shown_idle)
	var only_erupt := hit_states.size() >= 8
	for s in hit_states:
		only_erupt = only_erupt and s == FireVent.Phase.ERUPT
	_check("a player on the grate burns while it erupts, never while it warns", only_erupt,
		"(%d hits, states %s)" % [hit_states.size(), hit_states])
	_check("a robot on the grate is not hurt", bot_hits[near_bot] == 0, "(%d)" % bot_hits[near_bot])
	_check("a robot 3 m off is not hurt", bot_hits[far_bot] == 0, "(%d)" % bot_hits[far_bot])
	_check("the first warning teaches the rule, once", taught.count(FireVent.TEACH_TEXT) == 1, "(%s)" % [taught])

	# Just outside the hazard ring: never touched.
	hit_states.clear()
	player.global_position = Vector3(vent.radius + FireVent.RING + 0.4, 0.0, 0.0)
	await _phys(4.2)
	_check("a player outside the ring is never touched", hit_states.is_empty(), "(%d)" % hit_states.size())
	vent.queue_free()

	# (8) a cryo vent looks and teaches like one.
	var cold := FireVent.new()
	cold.cryo = true
	add_child(cold)
	cold.global_position = Vector3(30, 0, 0)
	player.global_position = Vector3(30 + cold.radius + FireVent.RING + 1.0, 0, 0)
	await _phys(4.2)
	var fire_hot := Vector3(1.0, 0.42, 0.04) # the grate shader's default (fire) hot colour
	var cold_hot: Vector3 = (cold.get("_floor_mat") as ShaderMaterial).get_shader_parameter("hot_col")
	_check("a cryo vent's grate frosts blue", cold_hot.z > cold_hot.x and not cold_hot.is_equal_approx(fire_hot), "(%s)" % cold_hot)
	_check("a cryo vent teaches its own line", taught.count(FireVent.CRYO_TEXT) == 1, "(%s)" % [taught])
	cold.queue_free()

	_gap_rows("crucible", 2, false)
	_gap_rows("mistral", 1, true)
	_forge()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## Each gate gap of level `id` that holds vents holds a row spanning it, no two
## erupting at once; `rows` gaps must hold one, all `cryo` or all fire.
func _gap_rows(id: String, rows: int, cryo: bool) -> void:
	var def := LevelDefs.get_def(id)
	var vents: Array = def.get("fire_vents", [])
	_check("%s has vents" % id, vents.size() >= rows * 2, "(%d)" % vents.size())
	var kind_ok := true
	for v in vents:
		kind_ok = kind_ok and bool(v.get("cryo", false)) == cryo
	_check("%s's vents are all %s" % [id, "cryo" if cryo else "fire"], kind_ok)
	var found := 0
	for g in def.get("gates", []):
		var axis := String(g["axis"])
		var at := float(g["at"])
		var lo := float(g["gap_pos"]) - float(g["gap"]) * 0.5
		var hi := float(g["gap_pos"]) + float(g["gap"]) * 0.5
		var row: Array = []
		for v in vents:
			var p: Vector3 = v["pos"]
			var across := p.z if axis == "z" else p.x
			var along := p.x if axis == "z" else p.z
			if absf(across - at) < 0.5 and along >= lo - 0.5 and along <= hi + 0.5:
				row.append(v)
		if row.is_empty():
			continue
		found += 1
		_check("a row of vents in the %s=%.1f gap" % [axis, at], row.size() >= 2, "(%d)" % row.size())
		var r := float((row[0] as Dictionary).get("radius", 1.4))
		var min_a := INF
		var max_a := -INF
		for v in row:
			var p: Vector3 = v["pos"]
			var along := p.x if axis == "z" else p.z
			min_a = minf(min_a, along - r)
			max_a = maxf(max_a, along + r)
		_check("the %s=%.1f row spans its gap" % [axis, at], min_a <= lo + 0.3 and max_a >= hi - 0.3,
			"(vents %.1f..%.1f, gap %.1f..%.1f)" % [min_a, max_a, lo, hi])
		var apart := true
		for i in row.size():
			for j in range(i + 1, row.size()):
				var per := float((row[i] as Dictionary).get("period", 4.0))
				var d := absf(float((row[i] as Dictionary).get("phase", 0.0)) - float((row[j] as Dictionary).get("phase", 0.0)))
				d = minf(d, 1.0 - d) * per
				apart = apart and d >= FireVent.ERUPT_TIME
		_check("no two vents in the %s=%.1f row erupt at once" % [axis, at], apart)
	_check("%s has %d gap rows" % [id, rows], found == rows, "(%d)" % found)

func _forge() -> void:
	var def := LevelDefs.get_def("lava_world")
	var vents: Array = def.get("fire_vents", [])
	_check("lava_world has walkway vents", vents.size() >= 3, "(%d)" % vents.size())
	var by_walk := {}
	for v in vents:
		var p: Vector3 = v["pos"]
		var r := float(v.get("radius", 1.4))
		var on: Dictionary = {}
		for pl in def.get("platforms", []):
			var c: Vector3 = pl["pos"]
			var sz: Vector3 = pl["size"]
			if absf(p.x - c.x) <= sz.x * 0.5 and absf(p.z - c.z) <= sz.z * 0.5 					and absf(c.y + sz.y * 0.5 - p.y) < 0.05:
				# The narrowest platform under it is the walkway.
				if on.is_empty() or minf(sz.x, sz.z) < minf((on["size"] as Vector3).x, (on["size"] as Vector3).z):
					on = pl
		_check("vent at %s sits on a walkway top" % p, not on.is_empty())
		if on.is_empty():
			continue
		var sz: Vector3 = on["size"]
		var half := minf(sz.x, sz.z) * 0.5
		var c: Vector3 = on["pos"]
		var off := absf(p.z - c.z) if sz.x > sz.z else absf(p.x - c.x)
		_check("its ring fits the walkway", off + r + FireVent.RING <= half + 0.01,
			"(ring %.2f, half width %.2f)" % [off + r + FireVent.RING, half])
		_check("no gap past it a body could use", half - (r + FireVent.BODY_RADIUS * 0.5) - off <= 0.2,
			"(%.2f m)" % (half - (r + FireVent.BODY_RADIUS * 0.5) - off))
		var k := str(c)
		if not by_walk.has(k):
			by_walk[k] = []
		(by_walk[k] as Array).append(float(v.get("phase", 0.0)))
	for k in by_walk:
		var ph: Array = by_walk[k]
		for i in ph.size():
			for j in range(i + 1, ph.size()):
				var d := absf(float(ph[i]) - float(ph[j]))
				_check("two vents on one walkway never erupt together", minf(d, 1.0 - d) * 4.0 >= FireVent.ERUPT_TIME)
