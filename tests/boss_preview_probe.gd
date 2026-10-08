extends Node3D
## Bosses shown in the Enemy Codex (main menu -> Encyclopedia) run in preview
## mode: idle on a turntable, with no entrance, boss bar, AI or minion waves.
## ARCHON's whole fight is spawning waves, so a broken preview flag would fill
## the bestiary with live robots. For every codex entry whose scene has a
## `preview` flag, the probe stages it exactly as encyclopedia.gd does
## (preview = true, physics off, under a turntable), lets it run for WATCH
## seconds, and samples every frame:
##   * it is the only node in the "enemy" group (no minions or waves);
##   * nothing new appears under root or the current scene (no portals,
##     telegraphs or entrance FX left in the world);
##   * it never emits GameState.boss_spawned (the HUD's boss health bar).
## (This replaces the old briefing_probe, which tested the same guarantee on
## the 3D level briefing that the game no longer uses: #158.)
##   godot --headless --path . --audio-driver Dummy res://tests/boss_preview_probe.tscn

const WATCH := 4.0

var _fail: Array[String] = []
var _boss_bars := 0

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	GameState.boss_spawned.connect(func(_b): _boss_bars += 1)
	var tested := 0
	for type in EnemyCodex.ORDER:
		var entry: Dictionary = EnemyCodex.get_entry(type)
		var path: String = entry.get("scene", "")
		if path == "":
			continue
		var bot: Node3D = (load(path) as PackedScene).instantiate()
		if not "preview" in bot:
			bot.free()
			continue
		tested += 1
		var before := {}
		for n in get_tree().root.get_children() + get_children():
			before[n] = true
		var turntable := Node3D.new()
		add_child(turntable)
		before[turntable] = true
		# Mirrors Encyclopedia._spawn_model.
		bot.preview = true
		turntable.add_child(bot)
		bot.scale = Vector3.ONE * float(entry.get("scale", 1.0))
		if bot.has_method("set_physics_process"):
			bot.set_physics_process(false)
		var max_enemies := 0
		var extra: Array[String] = []
		_boss_bars = 0
		var t := 0.0
		while t < WATCH:
			await get_tree().process_frame
			t += get_process_delta_time()
			max_enemies = maxi(max_enemies, get_tree().get_nodes_in_group("enemy").size())
			for n in get_tree().root.get_children() + get_children():
				if not before.has(n) and not extra.has(n.name):
					extra.append(String(n.name))
		_check(max_enemies <= 1, "%s preview: max %d enemies in the tree (just itself)" % [type, max_enemies])
		_check(_boss_bars == 0, "%s preview: no boss bar raised (boss_spawned x%d)" % [type, _boss_bars])
		_check(extra.is_empty(), "%s preview: nothing spawned into the world%s" % [type, "" if extra.is_empty() else " (got " + ", ".join(extra) + ")"])
		turntable.queue_free()
		for n in get_tree().root.get_children() + get_children():
			if not before.has(n):
				n.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	_check(tested >= 8, "covered %d preview-capable codex entries (archon, colossus, manus, overseer, smasher, terminator, titan, vacuum)" % tested)
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)
