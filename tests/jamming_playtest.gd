extends Node3D
## COMBAT PLAYTEST BOT for Geofenced Signal Jamming. Drives the real player: aims
## the actual camera, fires the weapon, and plants jam beacons on the closing hive
## to strip their shields, then kills the jammed units. Measures whether the fight
## is actually WINNABLE with the jammer (the core risk: shielded ranged flankers
## that never enter a zone would be unkillable) and reports kills/time/health.

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

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_head = _player.get_node("Head")
	_cam = _player.get_node("Head/Camera3D")
	_dmg = _player.get_node_or_null("Damageable")
	for n in lvl.find_children("*", "JammerController", true, false):
		_jc = n; break
	# Measure completability first: keep the bot alive so we learn whether the hive
	# can be CLEARED with jamming at all (survivability is a second question).
	# Survivability pass: NOT invulnerable — measure whether a (imperfect) bot can
	# take the close-range hive's crossfire and live. A human dodges far better.
	# Grab the rifle sitting at spawn so we're not stuck plinking with the sidearm.
	_player.global_position = Vector3(-4, 1.0, -22)
	await get_tree().create_timer(0.6).timeout
	print("PLAYTEST start jammer=%s weapon=%s" % [_jc != null, _weapon_name()])
	_phase = "fight"

func _weapon_name() -> String:
	var wm = _player.find_child("WeaponHolder", true, false)
	if wm and "current" in wm and wm.current:
		return str(wm.current.name)
	return "?"

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
	if _t > 60.0:
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
	var need_new: bool = _target == null or not is_instance_valid(_target) or (_target as EnemyHive).is_dead()
	if not need_new and not _target.jammed and not jammed_targets.is_empty():
		need_new = true # stop wasting fire on a shielded unit when a jammed one exists
	if need_new:
		_target = jammed_targets[0] if not jammed_targets.is_empty() else nearest
	_aim_at((_target as Node3D).global_position + Vector3(0, 1.1, 0))
	Input.action_press("fire")
	var thp = _target.get_node("Damageable").current_health
	if thp != _last_thp:
		_last_thp = thp

	# Strafe to dodge, AND creep toward the arena centre so we trip the back-ring
	# spawn triggers and meet the whole hive (they're proximity-radius spawns).
	if _strafe_t > 1.3:
		_strafe_t = 0.0
		_strafe = -_strafe
	var right := _player.global_transform.basis.x
	var advance := 3.0 if _player.global_position.z < 6.0 else 0.0
	_player.velocity.x = right.x * 3.0 * _strafe
	_player.velocity.z = right.z * 3.0 * _strafe + advance

func _objective_done() -> bool:
	return GameState.is_task_done("kill_all") and GameState.is_task_done("hvt")

func _finish(how: String) -> void:
	_phase = "done"
	Input.action_release("fire")
	var hives := _live_hives()
	print("PLAYTEST RESULT: %s  time=%.1fs  kills=%d  hive_left=%d  peak_jammed=%d  min_hp=%.0f" % [
		how, _t, GameState.kills, hives.size(), _peak_jammed, _min_hp])
	print("  tasks: kill_all=%s hvt=%s" % [GameState.is_task_done("kill_all"), GameState.is_task_done("hvt")])
	_cam.global_position = Vector3(0, 12, -26)
	_cam.look_at(Vector3(0, 1, 4), Vector3.UP)
	for c in get_tree().get_nodes_in_group("level_ceiling"): c.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/jamming_playtest.png")
	print("JAMMING_PLAYTEST_DONE")
	get_tree().quit()
