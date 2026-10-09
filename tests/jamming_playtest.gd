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
## outranks any hive. It only shoots a hive it has a clear ray to, and walks in
## on the navmesh when none is in sight. Before #184 it completed 1 run in 3:
## it cut path corners into cover and fired at hives through walls. After,
## 10 of 10 runs completed in 38-76 s (2026-10-09, five at a time).
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
# Navmesh travel (#184): the current path, what it leads to and how old it is,
# plus the stuck check (no 0.6 m of progress in 1.5 s means pinned on cover).
var _path := PackedVector3Array()
var _path_goal := Vector3.INF
var _path_age := 0.0
var _stuck_from := Vector3.ZERO
var _stuck_t := 0.0
var _unstick_t := 0.0
var _unstick_dir := Vector3.ZERO
var _unsticks := 0
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

## Whether a shot from the camera at `n` would reach it, not a wall or cover.
func _has_los(n: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(_cam.global_position, n.global_position + Vector3(0, 1.1, 0), 1)
	q.exclude = [_player.get_rid()]
	return _player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _halt() -> void:
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	_stuck_t = 0.0
	_stuck_from = _player.global_position

## Walk toward `goal` on the navmesh; returns the flat distance left. The bot
## steers at a point 0.8 m further along the path polyline. The old follower
## steered at the first corner more than 1.2 m away, which cut the corner, and in
## a run on 2026-10-09 it stayed pinned on the spine wall's end for 140 s (#184).
## If it still makes no progress, it sidesteps and plans a fresh path.
func _move_to(goal: Vector3, speed := 6.0) -> float:
	var pos := _player.global_position
	var flat := Vector2(goal.x - pos.x, goal.z - pos.z).length()
	_path_age += get_physics_process_delta_time()
	if _path.is_empty() or _path_age > 1.0 or Vector2(goal.x - _path_goal.x, goal.z - _path_goal.z).length() > 1.5:
		_path = NavigationServer3D.map_get_path(_player.get_world_3d().navigation_map, pos, goal, true)
		_path_goal = goal
		_path_age = 0.0
	var v: Vector3
	if _unstick_t > 0.0:
		_unstick_t -= get_physics_process_delta_time()
		v = _unstick_dir * speed
	else:
		var to := (_carrot(pos, 0.8) if _path.size() >= 2 else goal) - pos
		to.y = 0.0
		v = to.normalized() * speed
	_player.velocity.x = v.x
	_player.velocity.z = v.z
	_stuck_t += get_physics_process_delta_time()
	if _stuck_t >= 1.5:
		if Vector2(pos.x - _stuck_from.x, pos.z - _stuck_from.z).length() < 0.6 and _unstick_t <= 0.0:
			# Sidestep at right angles to the blocked heading, alternating sides.
			_unsticks += 1
			var side := 1.0 if _unsticks % 2 == 0 else -1.0
			_unstick_dir = Vector3(-v.z, 0.0, v.x).normalized() * side
			if _unstick_dir == Vector3.ZERO:
				_unstick_dir = Vector3(side, 0.0, 0.0)
			_unstick_t = 0.6
			_path = PackedVector3Array()
		_stuck_t = 0.0
		_stuck_from = pos
	return flat

## The point `ahead` metres along the current path past the path point nearest
## `pos` (flat distances: path points sit on the floor, the body above it).
func _carrot(pos: Vector3, ahead: float) -> Vector3:
	var p2 := Vector2(pos.x, pos.z)
	var best_i := 0
	var best_q := Vector2(_path[0].x, _path[0].z)
	var best_d := INF
	for i in _path.size() - 1:
		var a := Vector2(_path[i].x, _path[i].z)
		var b := Vector2(_path[i + 1].x, _path[i + 1].z)
		var q := Geometry2D.get_closest_point_to_segment(p2, a, b)
		var d := q.distance_to(p2)
		if d < best_d:
			best_d = d
			best_i = i
			best_q = q
	var left := ahead
	var at := best_q
	for i in range(best_i + 1, _path.size()):
		var nxt := Vector2(_path[i].x, _path[i].z)
		var seg := at.distance_to(nxt)
		if seg >= left:
			at = at + (nxt - at).normalized() * left
			return Vector3(at.x, pos.y, at.y)
		left -= seg
		at = nxt
	return Vector3(at.x, pos.y, at.y)

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
		_move_to(Vector3(0, 0, 8))
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
	# Only targets a shot can reach count as shootable: in a run on 2026-10-09
	# the bot fired at the PRIME's three escorts through cover for 120 s.
	hives = hives.filter(func(h): return not _ignore.has(h))
	if hives.is_empty():
		_ignore.clear()
		return
	var seen := hives.filter(func(h): return _has_los(h))
	var seen_jammed := seen.filter(func(h): return h.jammed)
	var need_new: bool = _target == null or not is_instance_valid(_target) or (_target as EnemyHive).is_dead()
	# A locked target in sight that takes no damage for 3 s is soaking the fire
	# somehow (shielded, or clipped by a ledge the ray misses): drop it.
	if not need_new and _stall_t > 3.0:
		_ignore.append(_target)
		need_new = true
	if not need_new and not _target.jammed and not seen_jammed.is_empty():
		need_new = true # stop wasting fire on a shielded unit when a jammed one is in sight
	if not need_new and not seen.is_empty() and not seen.has(_target):
		need_new = true # the locked one went behind cover; another is in sight
	if need_new:
		if not seen_jammed.is_empty(): _target = seen_jammed[0]
		elif not seen.is_empty(): _target = seen[0]
		else: _target = hives[0]
		_stall_t = 0.0
	_aim_at((_target as Node3D).global_position + Vector3(0, 1.1, 0))
	if not _has_los(_target):
		# Nothing in sight: hold fire and close in on the navmesh until the
		# target comes round the cover.
		Input.action_release("fire")
		_stall_t = 0.0
		_move_to((_target as Node3D).global_position)
		return
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
		_aim_at(relay.global_position + Vector3(0, 1.3, 0))
		_move_to(relay.global_position)
		return
	_halt()
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
	print("  tasks: kill_all=%s hvt=%s  unsticks=%d  bot=%v" % [GameState.is_task_done("kill_all"),
		GameState.is_task_done("hvt"), _unsticks, _player.global_position])
	# Where a timeout left things: the leftovers and whether the bot could see them.
	for h in hives:
		print("  left: hive at %v hp=%.0f jammed=%s los=%s" % [h.global_position,
			h.get_node("Damageable").current_health, h.jammed, _has_los(h)])
	var relay = _next_relay()
	if relay != null:
		print("  left: relay at %v hp=%.0f" % [(relay as Node3D).global_position, relay.hp.current_health])
	_cam.global_position = Vector3(0, 12, -26)
	_cam.look_at(Vector3(0, 1, 4), Vector3.UP)
	for c in get_tree().get_nodes_in_group("level_ceiling"): c.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	# Headless has no framebuffer: reading it back logs an engine error.
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png(OS.get_user_data_dir() + "/jamming_playtest.png")
	print("JAMMING_PLAYTEST_DONE")
	get_tree().quit()
