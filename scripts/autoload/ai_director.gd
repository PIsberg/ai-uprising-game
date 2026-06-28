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
## is reset at the start of every level. Below MIN_SAMPLES shots it stays neutral
## (returns "" / no taunt) so a fresh level doesn't pre-judge you.

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

func reset_profile() -> void:
	mobility = 0.5; range_pref = 0.5; accuracy = 0.0; headshot_rate = 0.0
	_shots = 0; _hits = 0; _heads = 0
	_range_n = 0; _range_sum = 0.0
	_mob_n = 0; _mob_sum = 0.0
	_weapon_shots.clear()

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
## off the cached WeaponManager so it can tell which gun you favour.
func note_shot() -> void:
	_shots += 1
	if _wm and is_instance_valid(_wm) and _wm.current and _wm.current.data:
		var nm: String = _wm.current.data.display_name
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

## The Elite affix the swarm should lean on to counter the player's current style,
## or "" while still calibrating (-> the swarm rolls random affixes as before).
func counter_affix() -> String:
	if calibrating():
		return ""
	if headshot_rate > 0.35 or accuracy > 0.55:
		return "warden"     # precise -> unflinching: you must DODGE, not suppress
	if range_pref > 0.6:
		return "swift"      # you fight at range -> rushers close the gap
	if weapon_focus() > 0.7:
		return "shielded"   # one-trick -> armour that shrugs your favourite off
	if range_pref < 0.35 or mobility < 0.3:
		return "shielded"   # brawler / camper -> soaks your burst
	return ""

## A profile-aware overlord taunt, or "" while calibrating / nothing stands out.
func taunt() -> String:
	if calibrating():
		return ""
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
