extends Node3D
## Optional bonus objectives (bonus_objective.gd): a ghost bonus is won (score
## paid once) when the level's tasks complete with no scanner alarm, and lost
## for good by one alarm; a dry bonus survives damage from a non-hazard source
## (the control) and is lost to hazard damage. A bonus is never part of the exit
## lock: with the bonus lost, all_tasks_done() still opens the exit. Then every
## campaign bonus: a known kind, a ghost only where scanners exist, a dry only
## where hazard beds exist. Live: each kind builds on a real level and hooks the
## real scanners / player.
##   godot --headless --path . --audio-driver Dummy res://tests/bonus_objective_probe.tscn

var _fails: Array[String] = []

class StubScanner extends Node:
	signal alarmed

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	await _frames(10)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit_ghost()
	await _unit_dry()
	_campaign()
	await _live()
	GameState.current_state = prev_state
	GameState.reset_tasks()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _bonus_state() -> String:
	return String(GameState.level_bonus.get("state", ""))

func _unit_ghost() -> void:
	print("unit ghost:")
	# Won: tasks done, no alarm.
	GameState.reset_tasks()
	GameState.register_task("t", "Task", 0.0)
	var sc := StubScanner.new()
	sc.add_to_group("scanner")
	add_child(sc)
	var bo := BonusObjective.new()
	bo.kind = "ghost"
	bo.label = "Ghost"
	bo.score = 500
	add_child(bo)
	await _frames(3)
	_check(_bonus_state() == "live", "the bonus starts live")
	_check(not GameState.level_tasks.any(func(t): return t["label"] == "Ghost"), "the bonus is not a checklist task")
	var s0: int = GameState.score
	GameState.complete_task("t")
	await _frames(3)
	_check(_bonus_state() == "won" and GameState.score - s0 == 500, "tasks done with no alarm wins it and pays 500 (+%d)" % (GameState.score - s0))
	await _frames(3)
	_check(GameState.score - s0 == 500, "the score is paid once")
	bo.queue_free()
	# Lost: one alarm, and it stays lost.
	GameState.reset_tasks()
	GameState.register_task("t", "Task", 0.0)
	var bo2 := BonusObjective.new()
	bo2.kind = "ghost"
	bo2.label = "Ghost"
	add_child(bo2)
	await _frames(3)
	sc.alarmed.emit()
	await _frames(2)
	_check(_bonus_state() == "failed", "one scanner alarm loses it")
	var s1: int = GameState.score
	GameState.complete_task("t")
	await _frames(3)
	_check(_bonus_state() == "failed" and GameState.score == s1, "finishing afterwards neither restores it nor pays")
	_check(GameState.all_tasks_done(), "a lost bonus never seals the exit")
	bo2.queue_free()
	sc.queue_free()
	GameState.reset_tasks()
	await _frames(2)

func _unit_dry() -> void:
	print("unit dry:")
	GameState.reset_tasks()
	GameState.register_task("t", "Task", 0.0)
	var p := CharacterBody3D.new()
	p.add_to_group("player")
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000.0
	p.add_child(hp)
	add_child(p)
	var robot := Node.new() # a non-hazard damage source: the control
	add_child(robot)
	var bed := Node.new()
	bed.add_to_group("hazard")
	add_child(bed)
	var bo := BonusObjective.new()
	bo.kind = "dry"
	bo.label = "Dry"
	add_child(bo)
	await _frames(3)
	hp.apply_damage(10.0, robot)
	await _frames(2)
	_check(_bonus_state() == "live", "damage from a robot keeps a dry bonus live (control)")
	hp.apply_damage(10.0, bed)
	await _frames(2)
	_check(_bonus_state() == "failed", "hazard damage loses it")
	for n in [bo, p, robot, bed]:
		n.queue_free()
	GameState.reset_tasks()
	await _frames(2)

func _campaign() -> void:
	print("campaign:")
	var kinds := {}
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var b: Dictionary = def.get("bonus", {})
		if b.is_empty():
			continue
		var k := String(b.get("kind", ""))
		kinds[k] = kinds.get(k, 0) + 1
		_check(["ghost", "dry"].has(k), "%s: bonus kind '%s' is known" % [id, k])
		_check(String(b.get("label", "")) != "", "%s: bonus has a label" % id)
		if k == "ghost":
			_check(not (def.get("scanners", []) as Array).is_empty(), "%s: a ghost bonus needs scanners to avoid" % id)
		if k == "dry":
			_check(not (def.get("lava", []) as Array).is_empty(), "%s: a dry bonus needs hazard beds to avoid" % id)
	_check(kinds.get("ghost", 0) >= 1 and kinds.get("dry", 0) >= 1, "campaign authors both kinds (%s)" % kinds)

func _live() -> void:
	print("live:")
	for id in ["neon", "lava_world"]:
		var lvl: Node = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
		add_child(lvl)
		for i in 10:
			await get_tree().create_timer(0.25).timeout
		var bo := lvl.get_node_or_null("BonusObjective") as BonusObjective
		_check(bo != null and _bonus_state() == "live", "%s live: the bonus is built and live" % id)
		if bo and bo.kind == "ghost":
			var hooked := get_tree().get_nodes_in_group("scanner").filter(func(s): return s.alarmed.is_connected(bo._on_broken))
			_check(hooked.size() == get_tree().get_nodes_in_group("scanner").size() and hooked.size() > 0,
				"%s live: hooked to all %d scanners" % [id, hooked.size()])
		# The level-complete debrief reports the settled bonus on its highlights line.
		if bo and id == "neon":
			var hud: Node = lvl.get_node_or_null("HUD")
			if hud:
				GameState.bonus_win()
				hud.call("_update_debrief_block")
				var hl = hud.get("_highlights_label")
				_check(hl != null and hl.visible and String(hl.text).contains("✔") and String(hl.text).contains(bo.label) and String(hl.text).contains("+500"),
					"%s live: a won bonus is on the debrief highlights (%s)" % [id, hl.text if hl else "<none>"])
				GameState.level_bonus["state"] = "failed"
				hud.call("_update_debrief_block")
				_check(String(hl.text).contains("✖") and not String(hl.text).contains("+500"),
					"%s live: a lost bonus shows as lost, unpaid (%s)" % [id, hl.text])
			else:
				_check(false, "%s live: the level has a HUD to debrief on" % id)
		if bo and bo.kind == "dry":
			_check(bo._player_hp != null and bo._player_hp.damaged.is_connected(bo._on_player_damaged),
				"%s live: hooked to the real player's damage" % id)
		lvl.queue_free()
		await _frames(3)
		GameState.reset_tasks()
