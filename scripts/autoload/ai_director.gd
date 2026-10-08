# @lat: [[architecture#Autoloads#AIDirector]]
extends Node

## ADAPTIVE AI DIRECTOR — the rogue AI actually *learning* the player.
##
## Most shooters throw a fixed or randomly-scaled horde at you. Here the enemy is
## an intelligence, so it should fight like one: this director quietly profiles HOW
## you play — do you camp or keep moving, brawl up close or snipe from range, land
## headshots, lean on one weapon — and feeds that read into two systems:
##
##   1. Which Elite affix the swarm leans on to COUNTER you (Elite.maybe_apply):
##      snipe from afar and it fields SWIFT rushers to close the gap; out-aim it and
##      it fields WARDEN units you can't stagger (so you must dodge, not suppress);
##      spam one gun and it fields SHIELDED armour that shrugs it off.
##   2. The overlord's taunts, so it references your ACTUAL behaviour
##      ("You like your distance. I'm closing it.", "The Shotgun again. I've patched for it.").
##
## Signals are drawn from the same events the grade already tracks (shots/hits via
## GameState) plus a cheap per-quarter-second sample of the player's speed. The read
## is reset at the start of every level. Below MIN_SAMPLES shots the LEVEL read stays
## neutral so a fresh level doesn't pre-judge you from nothing.
##
## On top of the per-level read sits the long-term DOSSIER (user://overlord.cfg):
## every CLEARED level's read is folded into it, and it survives quitting, dying and
## new campaigns. Deaths are counted (and their killers) but teach it nothing, so a
## player stuck retrying a level is never escalated against. It is what lets the
## overlord REMEMBER you:
##   - while a level is still calibrating, the swarm counters your dossier instead of
##     rolling random affixes (it comes pre-adapted from the first second);
##   - a weapon that has carried your play across several levels gets a firmware
##     COUNTERMEASURE: it deals COUNTERMEASURE_MULT damage until you rotate off it;
##   - the overlord greets you with what it remembers (runs, deaths, your killers).

var mobility: float = 0.5      ## 0 = camps in place, 1 = always on the move
var range_pref: float = 0.5    ## 0 = brawler (point blank), 1 = sniper (long range)
var accuracy: float = 0.0
var headshot_rate: float = 0.0

const MIN_SAMPLES := 12         ## below this many shots the read is "still calibrating"

var _shots: int = 0
var _hits: int = 0
var _heads: int = 0
var _range_n: int = 0
var _range_sum: float = 0.0
var _mob_n: int = 0
var _mob_sum: float = 0.0
var _weapon_shots: Dictionary = {}   ## display_name -> shots
var _sample_t: float = 0.0
var _player: Node3D = null
var _wm: Node = null

# ---------- long-term dossier (persists across levels, runs and restarts) ----------
const DOSSIER_ALPHA := 0.35            ## weight of the newest level read in the running blend
const DOSSIER_MIN_READS := 2           ## folded levels before the dossier pre-adapts the swarm
const COUNTERMEASURE_MIN_READS := 3    ## folded levels before any weapon gets patched against
const COUNTERMEASURE_SHARE := 0.45     ## blended shot share that marks a weapon as your crutch
const COUNTERMEASURE_MULT := 0.85      ## damage a countermeasured weapon deals

## Where the dossier lives. Probes point this elsewhere so they never touch a player's file.
var dossier_path: String = "user://overlord.cfg"
## False = keep the dossier in memory only. Set automatically when the boot scene is a
## probe or tool (see _ready), so the headless suite never reads or grows a real dossier.
var persist: bool = true
## {reads, runs, deaths, mobility, range_pref, accuracy, headshot_rate,
##  weapons: {display_name: blended shot share}, killers: {label: count}, last_weapon}
var dossier: Dictionary = {}

func reset_profile() -> void:
	mobility = 0.5; range_pref = 0.5; accuracy = 0.0; headshot_rate = 0.0
	_shots = 0; _hits = 0; _heads = 0
	_range_n = 0; _range_sum = 0.0
	_mob_n = 0; _mob_sum = 0.0
	_weapon_shots.clear()

func _ready() -> void:
	forget_dossier(false)
	_decide_persistence.call_deferred()

## The boot scene is only known once the tree has set it, hence deferred. Probes and
## tools run their own scene as main: they get a blank in-memory dossier, so a player's
## history can never leak into a measurement (a countermeasure would silently cut a
## damage probe's numbers) and the suite never writes into a player's file.
func _decide_persistence() -> void:
	var cs := get_tree().current_scene
	var boot: String = cs.scene_file_path if cs else ""
	persist = not (boot.begins_with("res://tests/") or boot.begins_with("res://tools/"))
	if persist:
		load_dossier()

func forget_dossier(save: bool = true) -> void:
	dossier = {
		"reads": 0, "runs": 0, "deaths": 0,
		"mobility": 0.5, "range_pref": 0.5, "accuracy": 0.0, "headshot_rate": 0.0,
		"weapons": {}, "killers": {}, "last_weapon": "",
	}
	if save:
		save_dossier()

func load_dossier() -> void:
	forget_dossier(false)
	var cf := ConfigFile.new()
	if cf.load(dossier_path) != OK:
		return
	for k in dossier.keys():
		var v = cf.get_value("dossier", k, dossier[k])
		if typeof(v) == typeof(dossier[k]) or (typeof(dossier[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
			dossier[k] = v

func save_dossier() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	for k in dossier:
		cf.set_value("dossier", k, dossier[k])
	cf.save(dossier_path)

## Fold this level's read into the dossier. A still-calibrating level teaches nothing.
## Called on level complete only: folding deaths too let a new player's retries on
## level 1 countermeasure their starter pistol (the survival probe's retry loop hit
## it in CI: x0.85 damage from the 4th death on).
func fold_level() -> void:
	if calibrating():
		return
	var a := DOSSIER_ALPHA
	for k in ["mobility", "range_pref", "accuracy", "headshot_rate"]:
		dossier[k] = lerpf(float(dossier[k]), float(get(k)), a)
	var w: Dictionary = dossier["weapons"]
	for nm in w.keys():
		w[nm] = float(w[nm]) * (1.0 - a)
	for nm in _weapon_shots:
		w[nm] = float(w.get(nm, 0.0)) + a * float(_weapon_shots[nm]) / float(_shots)
	for nm in w.keys(): # forgotten guns drop out instead of lingering as 0.0001
		if float(w[nm]) < 0.02:
			w.erase(nm)
	dossier["reads"] = int(dossier["reads"]) + 1
	if dominant_weapon() != "":
		dossier["last_weapon"] = dominant_weapon()
	save_dossier()

## Count the death and its killer for the overlord's lines; the level read is wiped
## (a respawn starts a fresh read) and NOT folded: dying never escalates the AI.
func note_death(killer: String) -> void:
	dossier["deaths"] = int(dossier["deaths"]) + 1
	if killer != "":
		var ks: Dictionary = dossier["killers"]
		ks[killer] = int(ks.get(killer, 0)) + 1
	reset_profile()
	save_dossier()

func note_run_start() -> void:
	dossier["runs"] = int(dossier["runs"]) + 1
	save_dossier()

func dossier_known() -> bool:
	return int(dossier.get("reads", 0)) >= DOSSIER_MIN_READS

func _dossier_top_weapon() -> Array: ## [name, share]
	var best := ""
	var top := 0.0
	var w: Dictionary = dossier.get("weapons", {})
	for nm in w:
		if float(w[nm]) > top:
			top = float(w[nm])
			best = String(nm)
	return [best, top]

## The weapon the overlord has patched against, or "". Earned by leaning on one gun
## across several levels; rotating off it erodes the share by DOSSIER_ALPHA per level.
func countermeasure_weapon() -> String:
	if int(dossier.get("reads", 0)) < COUNTERMEASURE_MIN_READS:
		return ""
	var t := _dossier_top_weapon()
	return String(t[0]) if float(t[1]) >= COUNTERMEASURE_SHARE else ""

## Damage multiplier for a shot from `weapon_name` (Weapon.eff_damage applies it).
func countermeasure_mult(weapon_name: String) -> float:
	var c := countermeasure_weapon()
	return COUNTERMEASURE_MULT if c != "" and c == weapon_name else 1.0

## The robot label that has killed the player most often, and how often.
func _top_killer() -> Array:
	var best := ""
	var n := 0
	var ks: Dictionary = dossier.get("killers", {})
	for k in ks:
		if int(ks[k]) > n:
			n = int(ks[k])
			best = String(k)
	return [best, n]

## What the overlord remembers, as lines it can say. Empty with no history.
func memory_lines() -> Array:
	var lines: Array = []
	var reads := int(dossier.get("reads", 0))
	if reads <= 0 and int(dossier.get("deaths", 0)) <= 0:
		return lines
	var runs := int(dossier.get("runs", 0))
	var deaths := int(dossier.get("deaths", 0))
	if runs > 1:
		lines.append("Run %d. You keep coming back. So do I." % runs)
	if deaths > 0:
		lines.append("I have killed you %d times. I kept every recording." % deaths)
	var tk := _top_killer()
	if int(tk[1]) >= 2:
		lines.append("My %s units have put you down %d times. They're getting promoted." % [tk[0], tk[1]])
	var cm := countermeasure_weapon()
	if cm != "":
		lines.append("The %s again? I patched for that. You did not notice." % cm)
	elif String(dossier.get("last_weapon", "")) != "":
		lines.append("Last time it was the %s. I remember." % dossier["last_weapon"])
	if dossier_known():
		if float(dossier["range_pref"]) > 0.6:
			lines.append("You always keep your distance. I sent the fast ones first.")
		elif float(dossier["range_pref"]) < 0.35:
			lines.append("You always fight up close. I've armoured the front line.")
		if float(dossier["headshot_rate"]) > 0.35:
			lines.append("You aim for the head. Every time. I've read the logs.")
	return lines

## The overlord's opening line for a level, or "" with no history to draw on.
func greeting() -> String:
	var lines := memory_lines()
	if lines.is_empty():
		return ""
	return "Operator file %d reopened. %s" % [int(dossier.get("reads", 0)), lines[randi() % lines.size()]]

func _process(delta: float) -> void:
	if GameState.current_state != GameState.State.PLAYING:
		return
	_sample_t -= delta
	if _sample_t > 0.0:
		return
	_sample_t = 0.25
	# Refresh cached refs (cheap, every 0.25s) and sample mobility from ground speed.
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_wm = _player.get_node_or_null("Head/Camera3D/WeaponHolder") if _player else null
	if _player and _player is CharacterBody3D:
		var spd: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		_mob_sum += clampf(spd / 7.0, 0.0, 1.0)
		_mob_n += 1
		mobility = _mob_sum / float(_mob_n)

## Called once per shot fired (via GameState.register_shot). Reads the live weapon
## off the cached WeaponManager so it can tell which gun you favour; `weapon_name`
## overrides that read (probes have no player rig).
func note_shot(weapon_name: String = "") -> void:
	_shots += 1
	var nm := weapon_name
	if nm == "" and _wm and is_instance_valid(_wm) and _wm.current and _wm.current.data:
		nm = _wm.current.data.display_name
	if nm != "":
		_weapon_shots[nm] = int(_weapon_shots.get(nm, 0)) + 1
	accuracy = float(_hits) / float(maxi(_shots, 1))

## Called when the player lands a hit (via GameState.report_player_hit). `world_pos`
## is the hit point — its distance from the player samples your engagement range.
func note_hit(is_head: bool, world_pos: Vector3) -> void:
	_hits += 1
	if is_head:
		_heads += 1
	if _player and is_instance_valid(_player):
		var d: float = _player.global_position.distance_to(world_pos)
		_range_sum += clampf((d - 6.0) / 20.0, 0.0, 1.0) # 6m..26m -> 0..1
		_range_n += 1
		range_pref = _range_sum / float(_range_n)
	accuracy = float(_hits) / float(maxi(_shots, 1))
	headshot_rate = float(_heads) / float(maxi(_hits, 1))

## Fraction of shots that went into the single most-used weapon (1.0 = one-trick).
func weapon_focus() -> float:
	if _shots <= 0:
		return 0.0
	var top := 0
	for k in _weapon_shots:
		top = maxi(top, int(_weapon_shots[k]))
	return float(top) / float(_shots)

func dominant_weapon() -> String:
	var best := ""
	var top := -1
	for k in _weapon_shots:
		if int(_weapon_shots[k]) > top:
			top = int(_weapon_shots[k])
			best = String(k)
	return best

func calibrating() -> bool:
	return _shots < MIN_SAMPLES

## The Elite affix the swarm should lean on to counter the player's current style.
## While this level is still calibrating it counters the DOSSIER instead (the overlord
## remembers you), and only with no usable history does it return "" (random affixes).
func counter_affix() -> String:
	if calibrating():
		if not dossier_known():
			return ""
		return _counter_for(float(dossier["accuracy"]), float(dossier["headshot_rate"]),
			float(dossier["range_pref"]), float(dossier["mobility"]), float(_dossier_top_weapon()[1]))
	return _counter_for(accuracy, headshot_rate, range_pref, mobility, weapon_focus())

static func _counter_for(acc: float, heads: float, rng: float, mob: float, focus: float) -> String:
	if heads > 0.35 or acc > 0.55:
		return "warden"     # precise -> unflinching: you must DODGE, not suppress
	if rng > 0.6:
		return "swift"      # you fight at range -> rushers close the gap
	if focus > 0.7:
		return "shielded"   # one-trick -> armour that shrugs your favourite off
	if rng < 0.35 or mob < 0.3:
		return "shielded"   # brawler / camper -> soaks your burst
	return ""

## A profile-aware overlord taunt. While calibrating it falls back to what the dossier
## remembers; "" when there is neither a read nor a history.
func taunt() -> String:
	if calibrating():
		var mem := memory_lines()
		return "" if mem.is_empty() else String(mem[randi() % mem.size()])
	var lines: Array = []
	if mobility < 0.28:
		lines.append("You haven't moved in a while. I'll bring the fight to you.")
	elif mobility > 0.72:
		lines.append("All that running. You'll tire long before I do.")
	if range_pref > 0.62:
		lines.append("You like your distance. I'm closing it.")
	elif range_pref < 0.32:
		lines.append("Point blank? Bold. I respect the donation.")
	if headshot_rate > 0.4:
		lines.append("Nice aim. I'm reinforcing the skulls.")
	if weapon_focus() > 0.72 and dominant_weapon() != "":
		lines.append("The %s again. I've patched for it." % dominant_weapon())
	if accuracy > 0.6:
		lines.append("%d%% accuracy. Statistically, you should still lose." % int(round(accuracy * 100.0)))
	if lines.is_empty():
		return ""
	return lines[randi() % lines.size()]

## In-fiction PATCH NOTES: the director's post-level read rewritten as a robot-OS
## changelog, one atomic entry per behavioural signal. Shown as an "intercepted
## transmission" on the next level's briefing so the player SEES the machine
## adapting — the same data as assessment(), staged as fiction rather than a
## debrief line. Empty while calibrating (a quiet level ships no patch).
func patch_notes() -> Array:
	if calibrating():
		return []
	var notes: Array = []
	match counter_affix():
		"warden":
			notes.append("+ WARDEN rollout: stagger servos hardened fleet-wide. Operator suppression tactics EXCEED tolerance.")
		"swift":
			notes.append("+ SWIFT locomotion package pushed to all interceptors. Operator maintains standoff range — close it.")
		"shielded":
			notes.append("+ SHIELDED plating requisitioned for frontline units. Sustained-fire damage profile flagged.")
	if weapon_focus() > 0.7 and dominant_weapon() != "":
		notes.append("~ Threat model updated: '%s' reclassified as PRIMARY operator armament. Countermeasures live." % dominant_weapon())
	var cm := countermeasure_weapon()
	if cm != "":
		notes.append("+ COUNTERMEASURE: '%s' rounds now deal %d%% damage to patched firmware. Rotate your arsenal." % [cm, int(round(COUNTERMEASURE_MULT * 100.0))])
	if headshot_rate > 0.4:
		notes.append("~ Cranial housings reinforced (operator headshot rate %d%%)." % int(round(headshot_rate * 100.0)))
	elif accuracy > 0.6:
		notes.append("~ Evasion subroutines re-weighted (operator accuracy %d%%)." % int(round(accuracy * 100.0)))
	if mobility < 0.28:
		notes.append("- Pursuit logic deprioritized: operator is STATIONARY. Converging all units on last known position.")
	elif mobility > 0.72:
		notes.append("+ Predictive-lead firing solutions deployed: operator mobility profile 'ERRATIC'.")
	return notes

## A one-line post-level readout of what the AI learned and how it answered, shown
## on the sector-cleared screen so the player SEES the director adapting (otherwise
## it's invisible). "" while calibrating / nothing notable.
func assessment() -> String:
	if calibrating():
		return ""
	var read_ := ""
	var answer := ""
	match counter_affix():
		"warden":
			read_ = "your precision"
			answer = "WARDEN units you couldn't stagger"
		"swift":
			read_ = "your distance"
			answer = "SWIFT rushers to close the gap"
		"shielded":
			read_ = "your %s" % dominant_weapon() if weapon_focus() > 0.7 and dominant_weapon() != "" else "your aggression"
			answer = "SHIELDED armour to soak it"
		_:
			return ""
	return "⟁ AI ADAPTATION — it read %s and fielded %s." % [read_, answer]
