extends Node
## Probe: the overlord's long-term DOSSIER (AIDirector, user://overlord.cfg).
## (1) booted from res://tests/, the director keeps the dossier in memory only, so the
##     suite can never read or grow a player's real file;
## (2) a calibrating level counters nothing with no history, but counters the DOSSIER
##     once two levels have been folded (the swarm comes pre-adapted);
## (3) leaning on one gun for three levels earns it a COUNTERMEASURE that cuts the real
##     Weapon.eff_damage to COUNTERMEASURE_MULT, the patch notes announce it, and
##     rotating to another gun lifts it again;
## (4) a death (through GameState.on_player_died) counts the death and the killer and
##     wipes the level read, but teaches the dossier nothing: five deaths on one gun
##     earn no countermeasure (a struggling player is never escalated against);
##     the greeting still cites the deaths;
## (5) the dossier survives a save + load round trip through a probe-only file.
##   godot --headless --path . --audio-driver Dummy res://tests/overlord_memory_probe.tscn

const SHOTGUN := "SG-12 Breacher"
const RIFLE := "AR-7 Pulse Rifle"
const PROBE_PATH := "user://overlord_probe.cfg"

var ok := true

func _ready() -> void:
	_run.call_deferred()

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

## One level of play: `shots` shots from `weapon`, every one a body hit at ~mid range.
func _play_level(weapon: String, shots: int = 20, heads: bool = false) -> void:
	AIDirector.reset_profile()
	for i in shots:
		AIDirector.note_shot(weapon)
		AIDirector.note_hit(heads, Vector3.ZERO)

func _run() -> void:
	await get_tree().process_frame # _decide_persistence is deferred off the autoload's _ready
	await get_tree().process_frame
	_check("probe boot keeps the dossier in memory", AIDirector.persist == false)

	AIDirector.forget_dossier(false)
	AIDirector.reset_profile()
	_check("no history: calibrating level counters nothing", AIDirector.counter_affix() == "")
	_check("no history: no greeting", AIDirector.greeting() == "")

	# Two precise levels -> the dossier reads a headshot player.
	for i in 2:
		_play_level(RIFLE, 20, true)
		AIDirector.fold_level()
	AIDirector.reset_profile() # a fresh level, still calibrating
	_check("calibrating level counters the dossier", AIDirector.calibrating() and AIDirector.counter_affix() == "warden",
		"counter=%s reads=%d" % [AIDirector.counter_affix(), int(AIDirector.dossier["reads"])])

	# A calibrating level with no ammo spent folds nothing.
	var reads_before := int(AIDirector.dossier["reads"])
	AIDirector.fold_level()
	_check("calibrating level folds nothing", int(AIDirector.dossier["reads"]) == reads_before)

	# Countermeasure: three shotgun-heavy levels on top.
	AIDirector.forget_dossier(false)
	var gun: Weapon = load("res://scenes/weapons/shotgun.tscn").instantiate()
	add_child(gun)
	await get_tree().process_frame
	var base_dmg: float = gun.eff_damage()
	for i in 2:
		_play_level(SHOTGUN)
		AIDirector.fold_level()
	_check("two levels: not patched yet", AIDirector.countermeasure_weapon() == "")
	_play_level(SHOTGUN)
	AIDirector.fold_level()
	var cm := AIDirector.countermeasure_weapon()
	var patched_dmg: float = gun.eff_damage()
	_check("three levels: shotgun countermeasured", cm == SHOTGUN, "cm=%s" % cm)
	_check("countermeasure cuts real eff_damage", is_equal_approx(patched_dmg, base_dmg * AIDirector.COUNTERMEASURE_MULT),
		"%.2f -> %.2f" % [base_dmg, patched_dmg])
	_check("other guns unaffected", AIDirector.countermeasure_mult(RIFLE) == 1.0)
	_play_level(SHOTGUN)
	var noted := false
	for n in AIDirector.patch_notes():
		if String(n).begins_with("+ COUNTERMEASURE: '%s'" % SHOTGUN):
			noted = true
	_check("patch notes announce the countermeasure", noted)

	# Rotating off the gun lifts it.
	var rotations := 0
	while AIDirector.countermeasure_weapon() == SHOTGUN and rotations < 10:
		_play_level(RIFLE)
		AIDirector.fold_level()
		rotations += 1
	_check("rotating arsenal lifts the countermeasure", AIDirector.countermeasure_weapon() != SHOTGUN and rotations <= 2,
		"levels=%d cm=%s" % [rotations, AIDirector.countermeasure_weapon()])
	_check("eff_damage restored", is_equal_approx(gun.eff_damage(), base_dmg) or AIDirector.countermeasure_weapon() == RIFLE)
	gun.queue_free()

	# Death through the real GameState hook.
	_play_level(RIFLE)
	var deaths := int(AIDirector.dossier["deaths"])
	var reads := int(AIDirector.dossier["reads"])
	GameState.on_player_died("K-9 HOUND")
	GameState.on_player_died("K-9 HOUND")
	_check("death counted", int(AIDirector.dossier["deaths"]) == deaths + 2)
	_check("killer tallied", int((AIDirector.dossier["killers"] as Dictionary).get("K-9 HOUND", 0)) == 2)
	_check("a death teaches the dossier nothing and wipes the level read", int(AIDirector.dossier["reads"]) == reads and AIDirector.calibrating())

	# A struggling player must never be escalated against: five deaths on one gun
	# (the survival bot's retry loop, or a new player stuck on level 1) earn no
	# countermeasure and no pre-adapted swarm. Only cleared levels teach the dossier.
	var saved: Dictionary = AIDirector.dossier.duplicate(true)
	AIDirector.forget_dossier(false)
	for i in 5:
		_play_level(SHOTGUN)
		GameState.on_player_died("ANDROID")
	_check("dying on one gun earns it no countermeasure", AIDirector.countermeasure_weapon() == "" and int(AIDirector.dossier["reads"]) == 0,
		"reads=%d cm=%s" % [int(AIDirector.dossier["reads"]), AIDirector.countermeasure_weapon()])
	_check("...and no pre-adapted swarm", AIDirector.counter_affix() == "")
	_check("...but the overlord still remembers the deaths", AIDirector.greeting().contains("killed you 5 times") or AIDirector.memory_lines().size() > 0, str(AIDirector.memory_lines()))
	AIDirector.dossier = saved
	var cites := false
	for line in AIDirector.memory_lines():
		if String(line).contains("K-9 HOUND units have put you down 2 times"):
			cites = true
	_check("memory cites the top killer", cites)
	_check("greeting draws on memory", AIDirector.greeting().begins_with("Operator file"), AIDirector.greeting())

	# Round trip through a probe-only file.
	AIDirector.dossier_path = PROBE_PATH
	AIDirector.persist = true
	AIDirector.note_run_start()
	var snap: Dictionary = AIDirector.dossier.duplicate(true)
	AIDirector.forget_dossier(false)
	AIDirector.load_dossier()
	var same := true
	for k in snap:
		# sort_keys: the reloaded dictionaries come back in file order, not insertion order
		if JSON.stringify(snap[k], "", true) != JSON.stringify(AIDirector.dossier.get(k), "", true):
			same = false
			print("  diff %s: %s vs %s" % [k, snap[k], AIDirector.dossier.get(k)])
	_check("dossier survives save + load", same)
	AIDirector.persist = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROBE_PATH))
	AIDirector.forget_dossier(false)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
