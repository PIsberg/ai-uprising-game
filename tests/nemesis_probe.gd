extends Node
## Dev probe: validates the NEMESIS grudge loop.
## (1) an elite that kills the player is recorded as a named, ranked nemesis;
## (2) a spawner substitutes the nemesis (same chassis, apply_nemesis buffs,
##     kill-feed name, one per level) on its next spawn;
## (3) killing the nemesis settles the grudge (score bonus + record cleared);
## (4) a repeat player-kill by the returned nemesis ranks the grudge up.
##   godot --headless --path . res://tests/nemesis_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var ENEMY := "res://scenes/enemies/android.tscn"

	# 1. Elite kills player -> promoted to nemesis.
	GameState.nemesis = {}
	var killer: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(killer)
	await get_tree().physics_frame
	killer.elite = "swift"
	GameState.record_nemesis_killer(killer)
	var n: Dictionary = GameState.nemesis
	var recorded: bool = not n.is_empty() and String(n["kind"]) == "swift" \
		and String(n["scene"]) == ENEMY and int(n["rank"]) == 1 and String(n["name"]) != ""
	print("RECORD: %s recorded=%s" % [n, recorded])
	if not recorded:
		ok = false
	killer.queue_free()

	# Non-elite deaths must NOT overwrite the grudge.
	var mook: Node3D = load(ENEMY).instantiate()
	get_tree().root.add_child(mook)
	await get_tree().physics_frame
	var before_name: String = String(GameState.nemesis["name"])
	GameState.record_nemesis_killer(mook)
	var stable: bool = String(GameState.nemesis["name"]) == before_name
	print("STABLE: mook death kept nemesis=%s" % stable)
	if not stable:
		ok = false
	mook.queue_free()

	# 2. Spawner substitution: nemesis_due + claim + apply_nemesis dressing.
	GameState.reset_level_stats()
	var due: bool = GameState.nemesis_due()
	var e: Node3D = load(String(GameState.nemesis["scene"])).instantiate()
	var data: Dictionary = GameState.claim_nemesis_spawn()
	Elite.apply_nemesis(e, data)
	get_tree().root.add_child(e)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var named: bool = e.nemesis_name == String(data["name"]) and e._kill_label() == String(data["name"])
	var buffed: bool = e.elite == "swift" and e._health_mult > 1.4 # 1.45 nemesis rank-1 (x affix speed kind: no hp affix) with margin
	var once: bool = not GameState.nemesis_due() # slot claimed — no second spawn this level
	print("SPAWN: named=%s buffed=%s (hm=%.2f) due_before=%s once=%s" % [named, buffed, e._health_mult, due, once])
	if not (due and named and buffed and once):
		ok = false

	# 3. Killing the nemesis settles the grudge.
	var score0: int = GameState.score
	e.hp.apply_damage(99999.0, null)
	await get_tree().physics_frame
	var settled: bool = GameState.nemesis.is_empty() and GameState.score >= score0 + 500
	print("SETTLED: cleared=%s score %d->%d" % [GameState.nemesis.is_empty(), score0, GameState.score])
	if not settled:
		ok = false
	e.queue_free()

	# 4. Repeat kill by a live nemesis ranks the grudge up.
	GameState.nemesis = {"name": "VX-101 'TEST'", "kind": "warden", "scene": ENEMY, "rank": 1}
	var e2: Node3D = load(ENEMY).instantiate()
	Elite.apply_nemesis(e2, GameState.nemesis)
	get_tree().root.add_child(e2)
	await get_tree().physics_frame
	GameState.record_nemesis_killer(e2)
	var ranked: bool = int(GameState.nemesis.get("rank", 0)) == 2
	print("RANKUP: rank=%s" % GameState.nemesis.get("rank"))
	if not ranked:
		ok = false
	e2.queue_free()
	GameState.nemesis = {}

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
