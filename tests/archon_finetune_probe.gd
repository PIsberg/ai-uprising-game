extends Node3D
## Probe: ARCHON FINE-TUNES ON YOU (AIDirector.finetune_plan, EnemyArchon).
## (1) with no history and a calibrating level the plan is empty and the wave
##     tables come out unchanged;
## (2) a dossier that keeps its distance, never stops moving, aims for the head
##     and leans on one gun yields the three strongest habits (strongest first),
##     their roster swaps and the elite affix of the strongest habit that has one;
## (3) ARCHON booted on that dossier announces "FINE-TUNED ON YOU" naming the habits,
##     its first wave is built from the swapped roster (every other drone, spider
##     and android swapped for a counter) and one or two of
##     its heavies wear the affix;
## (4) its first phase-3 wave sends a BEHAVIOUR CLONE of the player, once.
##   godot --headless --path . --audio-driver Dummy res://tests/archon_finetune_probe.tscn

var ok := true
var _toasts: Array[String] = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait(seconds: float) -> void:
	var n := int(ceil(seconds / 0.25))
	for i in n: # short waits: one long timer stalls autoload ticking headless
		await get_tree().create_timer(0.25).timeout

func _run() -> void:
	if not AIDirector.has_method("finetune_plan"):
		_check("AIDirector.finetune_plan exists", false)
		print("RESULT FAIL")
		get_tree().quit(1)
		return
	GameState.skirmish_event.connect(func(t: String, d: String): _toasts.append(t + " | " + d))
	AIDirector.persist = false

	# 1. Nothing to train on.
	AIDirector.forget_dossier(false)
	AIDirector.reset_profile()
	var empty: Dictionary = AIDirector.finetune_plan()
	_check("no history -> empty plan", (empty["habits"] as Array).is_empty() and String(empty["affix"]) == "")
	var w1: Array = EnemyArchon.WAVES[1]
	_check("empty plan leaves the roster alone", AIDirector.finetune_roster(w1, empty) == w1)

	# 2. A dossier with four habits.
	var d: Dictionary = AIDirector.dossier
	d["reads"] = 4
	d["range_pref"] = 0.9
	d["mobility"] = 0.85
	d["headshot_rate"] = 0.5
	d["accuracy"] = 0.4
	d["weapons"] = {"SG-12 Breacher": 0.55, "AR-7 Pulse Rifle": 0.2}
	var plan: Dictionary = AIDirector.finetune_plan()
	var ids: Array = (plan["habits"] as Array).map(func(h): return h["id"])
	print("plan: ", ids, " swaps=", plan["swaps"], " affix=", plan["affix"])
	_check("three habits, strongest first", ids == ["range", "mobile", "crutch"], str(ids))
	_check("range habit swaps drones for seekers", String((plan["swaps"] as Dictionary).get("drone", "")) == "seeker")
	_check("affix from the strongest habit with one (crutch -> shielded)", String(plan["affix"]) == "shielded")
	var lines: Array = (plan["habits"] as Array).map(func(h): return h["line"])
	_check("crutch line names the gun", String(lines[2]).contains("SG-12 Breacher"), String(lines[2]))
	var swapped: Array = AIDirector.finetune_roster(w1, plan)
	_check("roster swap shifts the mix", swapped.count("drone") == w1.count("drone") - 1 and swapped.has("seeker")
			and swapped.has("android"), str(swapped))

	# 3. ARCHON booted on it.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	pcs.shape = CapsuleShape3D.new()
	player.add_child(pcs)
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.invulnerable = true
	player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(6, 1.6, 8)
	var boss: EnemyArchon = (load("res://scenes/enemies/archon.tscn") as PackedScene).instantiate()
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)
	await _wait(6.0)
	var announced := _toasts.filter(func(s: String): return s.begins_with("FINE-TUNED ON YOU"))
	print("toasts: ", _toasts)
	_check("boot announces the fine-tune", announced.size() == 1)
	_check("announcement names the habits", announced.size() == 1 and String(announced[0]).contains(tr("KEEPS ITS DISTANCE")))
	var kinds: Array = boss.last_roster
	var affixed := 0
	for m in boss._minions:
		if is_instance_valid(m) and String((m as EnemyBase).elite) == "shielded":
			affixed += 1
	print("wave 1: ", kinds, " shielded=", affixed)
	_check("first wave carries the swaps", kinds == swapped, str(kinds))
	_check("1-2 heavies wear the affix", affixed >= 1 and affixed <= 2, str(affixed))

	# 4. Phase 3 sends your clone, once.
	for m in boss._minions:
		if is_instance_valid(m):
			m.queue_free()
	boss.hp.current_health = boss.hp.max_health * 0.3
	boss._start_wave()
	await _wait(1.0)
	_check("phase 3 sends a behaviour clone", get_tree().get_nodes_in_group("behaviour_clone").size() == 1)
	boss._start_wave()
	await _wait(1.0)
	_check("only one clone per fight", get_tree().get_nodes_in_group("behaviour_clone").size() == 1)

	AIDirector.forget_dossier(false)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
