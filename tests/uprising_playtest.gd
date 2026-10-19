extends Node
## Playtest driver for UPRISING MODE: plays a whole run with the reference bot
## (tests/playtest_bot.gd) on the real sectors, real enemies and drafted patches.
## Each sector the bot fights for `fight` game seconds; a death goes through the
## same TRY AGAIN / RESPAWN path the HUD uses, so reboots are spent for real. A
## sector it survives is then force-cleared (on_level_complete + advance_level),
## since the bot plays combat, not objectives. Prints one SECTOR line per sector
## and a RUN summary; a report, not a gate (RESULT PASS = the run reached its end).
##   godot --headless --path . --audio-driver Dummy res://tests/uprising_playtest.tscn -- seed=7 fight=60 pick=random

const RECORDS := "user://records_uprising_playtest.cfg"

var bot
var args := {"seed": "7", "fight": "60", "pick": "random"}

func _ready() -> void:
	if get_parent() != get_tree().root or get_tree().current_scene == self:
		var runner := Node.new()
		runner.set_script(get_script())
		runner.name = "UprisingPlaytestRunner"
		get_tree().root.add_child.call_deferred(runner)
		return
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	bot = preload("res://tests/playtest_bot.gd").new(self)
	_run.call_deferred()

func _wait(pred: Callable, limit_s: float = 90.0) -> bool:
	var t := 0.0
	while t < limit_s:
		if pred.call():
			return true
		await get_tree().create_timer(0.25, true).timeout
		t += 0.25
	return false

func _in_level() -> bool:
	var p = bot.player()
	return p != null and is_instance_valid(p) and GameState.current_state == GameState.State.PLAYING

func _pick(offers: Array, rng: RandomNumberGenerator) -> String:
	match String(args["pick"]):
		"first":
			return String(offers[0])
		"damage":
			var best := String(offers[0])
			for o in offers:
				if float(GameState.uprising_patch(String(o)).get("damage", 1.0)) > float(GameState.uprising_patch(best).get("damage", 1.0)):
					best = String(o)
			return best
	return String(offers[rng.randi() % offers.size()])

func _run() -> void:
	GameState.uprising_records_path = RECORDS
	var run_seed := int(args["seed"])
	var fight_s := float(args["fight"])
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	GameState.start_uprising(run_seed)
	var plan: Array = GameState.uprising["levels"]
	print("PLAN seed=%d %s" % [run_seed, plan.map(func(x): return GameState.level_id_from_path(x))])
	var totals := {"kills": 0, "damage_taken": 0.0, "deaths": 0, "t": 0.0}
	var sector_i := 0
	while GameState.is_uprising() and sector_i < plan.size():
		if not await _wait(_in_level):
			print("STUCK sector %d never reached a playable level (scene %s)" % [sector_i + 1, get_tree().current_scene.scene_file_path if get_tree().current_scene else "?"])
			break
		var lid := GameState.level_id_from_path(GameState.current_level_path)
		var deaths := 0
		var s := {"t": 0.0, "kills": 0, "damage_taken": 0.0, "min_hp": 1e9}
		var left := fight_s
		var killers: Array = []
		while left > 0.5 and GameState.is_uprising():
			var r: Dictionary = await bot.fight(left)
			if r.is_empty():
				break
			left -= float(r["t"])
			s["t"] += float(r["t"]); s["kills"] += int(r["kills"]); s["damage_taken"] += float(r["damage_taken"])
			s["min_hp"] = minf(float(s["min_hp"]), float(r["min_hp"]))
			if not bool(r["died"]):
				break
			deaths += 1
			killers.append(String(r["killer"]))
			await bot.wait_game(0.5)
			if GameState.uprising_run_over():
				break
			# The HUD's TRY AGAIN / RESPAWN.
			if GameState.has_checkpoint():
				GameState.respawn_at_checkpoint()
			else:
				GameState.load_level(GameState.current_level_path)
			await _wait(_in_level)
		var mults := "dmg=%.2f inc=%.2f move=%.2f" % [GameState.directive_damage_mult(), GameState.directive_incoming_mult(), GameState.directive_move_mult()]
		print("SECTOR %d %-12s t=%5.1f kills=%3d taken=%6.0f deaths=%d min_hp=%4.0f score=%6d lives=%d %s patches=%s killers=%s" % [
			sector_i + 1, lid, s["t"], s["kills"], s["damage_taken"], deaths, s["min_hp"], GameState.score,
			int(GameState.uprising.get("lives", -1)), mults, GameState.uprising.get("patches", []), killers])
		totals["kills"] += s["kills"]; totals["damage_taken"] += s["damage_taken"]; totals["deaths"] += deaths; totals["t"] += s["t"]
		if GameState.uprising_run_over():
			await _wait(func(): return not GameState.is_uprising(), 15.0)
			break
		GameState.on_level_complete()
		GameState.advance_level()
		sector_i += 1
		if not GameState.is_uprising():
			break
		if not await _wait(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("pick"), 30.0):
			print("STUCK no draft after sector %d" % sector_i)
			break
		var offers: Array = GameState.uprising["offers"]
		var choice := _pick(offers, rng)
		print("DRAFT after %d: offers=%s pick=%s" % [sector_i, offers, choice])
		var draft: Node = get_tree().current_scene
		draft.call("pick", choice)
	await _wait(func(): return not GameState.is_uprising(), 15.0)
	print("RUN %s" % GameState.uprising_result)
	print("TOTAL kills=%d taken=%.0f deaths=%d fight_t=%.0f" % [totals["kills"], totals["damage_taken"], totals["deaths"], totals["t"]])
	print("RECORD %s" % GameState.uprising_record())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))
	print("RESULT PASS")
	get_tree().quit(0)
