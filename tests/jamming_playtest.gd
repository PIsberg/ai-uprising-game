extends Node3D
## COMBAT PLAYTEST BOT for Geofenced Signal Jamming. Drives the real player: aims
## the actual camera, fires the weapon, and plants jam beacons on the closing hive
## to strip their shields, then kills the jammed units. Measures whether the fight
## is actually WINNABLE with the jammer (the core risk: shielded ranged flankers
## that never enter a zone would be unkillable) and reports kills/time/health.
##
## Completability first: the player gets a 100000 HP pool, so the run shows
## whether the level CAN be cleared with the jammer and how long it takes, and
## `hp_lost` (damage soaked) is the survivability read. A real 100 HP bot dies
## in 5-7 s (it strafes, it does not take cover), which measures the bot, not
## the level. Pass `-- mortal` for that run anyway.
##
## On the relay arc (#174) the bot walks to each jam-shielded relay on the
## navmesh, beacons it and shoots it while exposed; an exposed relay in reach
## outranks any hive. It is still a weak player: in 3 runs on 2026-10-09 it
## completed once (71.6 s, 4576 HP soaked) and timed out twice with a relay
## or the last hive standing. Read a single run as a sample, not a verdict.
##
## It reports `fired` (rounds spent) beside the kills: a 0-kill run with 0 fired
## means the bot never shot, not that the hive is unkillable. It scored 0 kills
## on every run from the 2x expansion until #179, because the boot left
## GameState at MENU (weapons do not fire outside PLAYING) and its rifle
## pickup spot was the pre-expansion one, so it fought a dead fight with an
## unfired pistol and kept "fighting" after the player died.
##   godot --headless --path . --audio-driver Dummy res://tests/jamming_playtest.tscn [-- mortal]

var _player: CharacterBody3D
var _head: Node3D
var _cam: Camera3D
var _jc
var _dmg
var _phase := "boot"
var _t := 0.0
var _min_hp := 100.0
var _log_t := 0.0
var _beacon_t := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _kills_seen := 0
var _peak_jammed := 0
var _target
var _last_thp := -1.0
var _wm
var _ammo0 := 0
var _stall_t := 0.0     ## seconds the locked target has taken no damage
var _ignore: Array = [] ## targets dropped for soaking fire (blocked by cover)
const POOL := 100000.0
var _mortal := false

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_head = _player.get_node("Head")
	_cam = _player.get_node("Head/Camera3D")
	_dmg = _player.get_node_or_null("Damageable")
	_wm = _player.find_child("WeaponHolder", true, false)
	# A probe-loaded level leaves GameState at MENU, and weapons only fire while
	# PLAYING: set it, or every trigger pull is a no-op.
	GameState.current_state = GameState.State.PLAYING
	_mortal = OS.get_cmdline_user_args().has("mortal")
	if _dmg and not _mortal:
		_dmg.max_health = POOL
		_dmg.current_health = POOL
		_min_hp = POOL
	for n in lvl.find_children("*", "JammerController", true, false):
		_jc = n; break
	# Measure completability first: keep the bot alive so we learn whether the hive
	# can be CLEARED with jamming at all (survivability is a second question).
	# Survivability pass: NOT invulnerable — measure whether a (imperfect) bot can
	# take the close-range hive's crossfire and live. A human dodges far better.
	# Grab the rifle sitting at spawn so we're not stuck plinking with the sidearm.
	# Read from the def: the hardcoded spot went stale when the arena doubled.
	var rifle: Vector3 = LevelDefs.get_def("hivemind")["weapon"]["pos"]
	_player.global_position = rifle + Vector3(0, 0.4, 0)
	await get_tree().create_timer(0.6).timeout
	_player.global_position = Vector3(-4, 1.0, -22)
	await get_tree().create_timer(0.3).timeout
	_ammo0 = _ammo_left()
	print("PLAYTEST start jammer=%s weapon=%s" % [_jc != null, _weapon_name()])
	_phase = "fight"

func _weapon_name() -> String:
	var wm = _player.find_child("WeaponHolder", true, false)
	if wm and "current" in wm and wm.current:
		return str(wm.current.name)
	return "?"

func _ammo_left() -> int:
	var n := 0
	if _wm and "weapons" in _wm:
		for w in _wm.weapons:
			if is_instance_valid(w):
				n += int(w.mag) + int(w.reserve)
	return n

func _live_hives() -> Array:
	var a: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyHive and not (e as EnemyHive).is_dead():
			a.append(e)
	return a

func _aim_at(p: Vector3) -> void:
	var eye := _cam.global_position
	var flat := Vector2(p.x - eye.x, p.z - eye.z)
	if flat.length() > 0.01:
		_player.rotation.y = atan2(-flat.x, -flat.y)
	var pitch := atan2(p.y - eye.y, flat.length())
	_head.rotation.x = clampf(pitch, -1.3, 1.3)

func _physics_process(delta: float) -> void:
	if _phase != "fight":
		return
	_t += delta
	_beacon_t = maxf(0.0, _beacon_t - delta)
	_strafe_t += delta
	if _dmg: _min_hp = minf(_min_hp, _dmg.current_health)

	if _objective_done():
		_finish("COMPLETE")
		return
	if _dmg and _dmg.current_health <= 0.0:
		_finish("DIED")
		return
	if _t > 180.0:
		_finish("TIMEOUT")
		return

	var hives := _live_hives()
	var nj := 0
	for h in hives:
		if h.jammed: nj += 1
	_peak_jammed = maxi(_peak_jammed, nj)

	_log_t += delta
	if _log_t >= 5.0:
		_log_t = 0.0
		var thp := -1.0
		if _target != null and is_instance_valid(_target):
			thp = _target.get_node("Damageable").current_health
		print("  t=%.0fs live=%d jammed=%d kills=%d tgt_hp=%.0f tgt_jam=%s" % [
			_t, hives.size(), nj, GameState.kills, thp,
			(_target.jammed if _target != null and is_instance_valid(_target) else false)])
		var r = _next_relay()
		if r != null:
			print("    relay: left=%d d=%.1f exposed=%s hp=%.0f bot=%v cd=%.2f" % [
				get_tree().get_nodes_in_group("objective_core").filter(func(c): return c.get("jam_shielded") == true).size(),
				(r as Node3D).global_position.distance_to(_player.global_position), r.get("exposed"),
				r.hp.current_health, _player.global_position, (_jc._cd if _jc else -1.0)])

	# Relays first whenever no hive is close: the PRIME will not come out until
	# they fall, so clearing the hive alone can never finish the level.
	var relay = _next_relay()
	# An exposed relay in reach beats any hive: its shield is only down for the
	# beacon's 8 s, and a hive will always be close enough to steal the bot.
	var relay_open: bool = relay != null and relay.get("exposed") == true \
		and (relay as Node3D).global_position.distance_to(_player.global_position) < 12.0
	if relay != null and (relay_open or hives.filter(func(h): return h.global_position.distance_to(_player.global_position) < 14.0).is_empty()):
		_work_relay(relay)
		return

	if hives.is_empty():
		# Between waves: advance to the arena centre to trip the next trigger ring.
		Input.action_release("fire")
		_aim_at(Vector3(0, 1.2, 8))
		_player.velocity.x = 0.0
		_player.velocity.z = 6.0
		return

	# Nearest enemy + the closing cluster centroid (enemies within 14 m of us).
	var ppos := _player.global_position
	hives.sort_custom(func(a, b): return a.global_position.distance_to(ppos) < b.global_position.distance_to(ppos))
	var nearest = hives[0]
	var jammed_targets := hives.filter(func(h): return h.jammed)

	# BEACON: if fewer than ~half the visible hive is jammed and a beacon is ready,
	# drop one on the closing cluster's centroid to catch the flankers.
	if _jc and _jc._cd <= 0.0 and _beacon_t <= 0.0 and jammed_targets.size() < maxi(1, hives.size() / 2):
		var near := hives.filter(func(h): return h.global_position.distance_to(ppos) < 16.0)
		if not near.is_empty():
			var c := Vector3.ZERO
			for h in near: c += h.global_position
			c /= near.size()
			c.y = 0.2
			_aim_at(c)
			_jc._cd = 0.0
			_jc._fire()
			_beacon_t = 0.6
			return # spend this beat aiming/planting, not shooting

	# SHOOT: LOCK onto one target until it dies (don't let the aim flip between
	# enemies every frame). Prefer a jammed, shield-down unit; upgrade to a jammed
	# one if we're currently chipping a shielded target.
	hives = hives.filter(func(h): return not _ignore.has(h))
	if hives.is_empty():
		_ignore.clear()
		return
	nearest = hives[0]
	jammed_targets = hives.filter(func(h): return h.jammed)
	var need_new: bool = _target == null or not is_instance_valid(_target) or (_target as EnemyHive).is_dead()
	# A locked target that takes no damage for 3 s is behind cover: drop it.
	if not need_new and _stall_t > 3.0:
		_ignore.append(_target)
		need_new = true
	if not need_new and not _target.jammed and not jammed_targets.is_empty():
		need_new = true # stop wasting fire on a shielded unit when a jammed one exists
	if need_new:
		_target = jammed_targets[0] if not jammed_targets.is_empty() else nearest
		_stall_t = 0.0
	_aim_at((_target as Node3D).global_position + Vector3(0, 1.1, 0))
	Input.action_press("fire")
	var thp = _target.get_node("Damageable").current_health
	if thp != _last_thp:
		_last_thp = thp
		_stall_t = 0.0
	else:
		_stall_t += delta

	# Strafe to dodge, AND creep toward the arena centre so we trip the back-ring
	# spawn triggers and meet the whole hive (they're proximity-radius spawns).
	if _strafe_t > 1.3:
		_strafe_t = 0.0
		_strafe = -_strafe
	var right := _player.global_transform.basis.x
	var advance := 3.0 if _player.global_position.z < 6.0 else 0.0
	_player.velocity.x = right.x * 3.0 * _strafe
	_player.velocity.z = right.z * 3.0 * _strafe + advance

## The jammer fight is done when the HIVE PRIME is dead and no hive is left.
## kill_all also needs the ring patrols (orbs, a bowler, a drone, an android)
## that only wake when the player walks the outer ring; walking a patrol route
## is not this bot's job, so it does not wait on them.
func _objective_done() -> bool:
	return GameState.is_task_done("hvt") and _live_hives().is_empty()

## A jam-shielded relay still standing (hivemind's mesh relays stage the PRIME
## behind them), nearest first, or null.
func _next_relay():
	var best = null
	var bd := INF
	for c in get_tree().get_nodes_in_group("objective_core"):
		if is_instance_valid(c) and c.get("jam_shielded") == true:
			var d: float = (c as Node3D).global_position.distance_to(_player.global_position)
			if d < bd:
				bd = d
				best = c
	return best

## Walk to a relay, plant a beacon on it, and burn it down while it is exposed.
func _work_relay(relay: Node3D) -> void:
	var to := relay.global_position - _player.global_position
	to.y = 0.0
	var d := to.length()
	if d > 7.0:
		Input.action_release("fire")
		# Follow the navmesh, not a straight line: a cover wall or a relay tower
		# between the bot and the relay pinned it in place for minutes.
		var map := _player.get_world_3d().navigation_map
		var path := NavigationServer3D.map_get_path(map, _player.global_position, relay.global_position, true)
		var goal := relay.global_position
		for p in path:
			if Vector2(p.x - _player.global_position.x, p.z - _player.global_position.z).length() > 1.2:
				goal = p
				break
		var step := goal - _player.global_position
		step.y = 0.0
		_aim_at(goal + Vector3(0, 1.3, 0))
		var v := step.normalized() * 6.0
		_player.velocity.x = v.x
		_player.velocity.z = v.z
		return
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	if relay.get("exposed") != true:
		Input.action_release("fire")
		if _jc and _jc._cd <= 0.0 and _beacon_t <= 0.0:
			_aim_at(relay.global_position + Vector3(0, 0.2, 0))
			_jc._fire()
			_beacon_t = 1.0
		return
	_aim_at(relay.global_position + Vector3(0, 1.3, 0))
	Input.action_press("fire")

func _finish(how: String) -> void:
	_phase = "done"
	Input.action_release("fire")
	var hives := _live_hives()
	var lost := (POOL - _min_hp) if not _mortal else (100.0 - _min_hp)
	print("PLAYTEST RESULT: %s  time=%.1fs  kills=%d  fired=%d  weapon=%s  hive_left=%d  peak_jammed=%d  hp_lost=%.0f%s" % [
		how, _t, GameState.kills, maxi(0, _ammo0 - _ammo_left()), _weapon_name(), hives.size(), _peak_jammed, lost,
		"" if _mortal else " (pool)"])
	print("  tasks: kill_all=%s hvt=%s" % [GameState.is_task_done("kill_all"), GameState.is_task_done("hvt")])
	_cam.global_position = Vector3(0, 12, -26)
	_cam.look_at(Vector3(0, 1, 4), Vector3.UP)
	for c in get_tree().get_nodes_in_group("level_ceiling"): c.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img: # headless has no framebuffer to read back
		img.save_png(OS.get_user_data_dir() + "/jamming_playtest.png")
	print("JAMMING_PLAYTEST_DONE")
	get_tree().quit()
