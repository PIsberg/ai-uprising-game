extends Node3D
## Probe: FireVent, the floor fire vent ("fire_vents" def key).
## A vent at the origin (period 4 s), over two eruptions:
## (1) every eruption is warned WARN_TIME (1.2 s) ahead by `warning`;
## (2) through the warning the grate heats up (to white-hot) and flames lick
##     up through it, but the column only shows while it erupts;
## (3) a player standing on the grate burns only while it erupts, several
##     ticks per eruption, never while it warns; one standing just outside
##     the ring is never touched;
## (4) a robot on the grate burns, one 3 m off does not;
## (5) the first warning a nearby player sees teaches the rule, once;
## (6) the Crucible floors both bulkhead gaps with a row of vents that spans
##     the (scaled) gap, phased so no two in a row erupt at once.
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
	_check("a robot on the grate burns", bot_hits[near_bot] >= 8, "(%d)" % bot_hits[near_bot])
	_check("a robot 3 m off does not", bot_hits[far_bot] == 0, "(%d)" % bot_hits[far_bot])
	_check("the first warning teaches the rule, once", taught.count(FireVent.TEACH_TEXT) == 1, "(%s)" % [taught])

	# Just outside the hazard ring: never touched.
	hit_states.clear()
	player.global_position = Vector3(vent.radius + FireVent.RING + 0.4, 0.0, 0.0)
	await _phys(4.2)
	_check("a player outside the ring is never touched", hit_states.is_empty(), "(%d)" % hit_states.size())
	vent.queue_free()

	_crucible()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _crucible() -> void:
	var def := LevelDefs.get_def("crucible")
	var vents: Array = def.get("fire_vents", [])
	_check("crucible has fire vents", vents.size() >= 6, "(%d)" % vents.size())
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
		_check("a row of vents in the %s=%.1f gap" % [axis, at], row.size() >= 2, "(%d)" % row.size())
		if row.is_empty():
			continue
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
