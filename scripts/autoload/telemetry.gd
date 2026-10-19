extends Node
## TELEMETRY: a local playtest recorder. One JSON object per line in
## user://telemetry/<date>-<time>.jsonl, so a playtest leaves data behind instead
## of only impressions: where you died and to what, what hurt you, which guns you
## used, how long each task took, and where the player stood pressing forward
## without moving (a ramp or a gap that traps the player, #339).
## It never sends anything anywhere. On by default for windowed runs of a debug
## build (playing from source), off headless (the probe suite) and in exported
## releases; `--telemetry` on the command line turns it on anywhere, `--no-telemetry`
## off. tools/telemetry_report.py summarises a file. Covered by tests/telemetry_probe.
# @lat: [[meta-systems#Telemetry]]

const DIR := "user://telemetry"
const KEEP_FILES := 50       ## oldest session files beyond this are deleted
const RECENT_WINDOW := 5.0   ## seconds of hits listed with a death
const STUCK_TIME := 2.0      ## pressing a move key this long without moving logs a stuck event
const STUCK_SPEED := 0.3     ## m/s: slower than this counts as not moving
const STUCK_REPEAT_M := 3.0  ## a second stuck event needs to be this far from the last

var _file: FileAccess = null
var _t := 0.0 ## game seconds since the session started
var _player: Node3D = null
var _has_player := false ## a player was attached (a freed _player reads as null, so track it apart)
var _level := ""
var _level_t0 := 0.0
var _acc: Dictionary = {} ## the level's running totals, written with level_end
var _recent: Array = []   ## [{t, source, amount}] for the death's last RECENT_WINDOW s
var _grade := ""
var _stuck_for := 0.0
var _last_stuck := Vector3.INF
var _hp_seen := 0.0 ## the player's health as of the last health_changed
var _stuck_pos := Vector3.ZERO ## where the player stood last physics tick
var _shot_open: Dictionary = {} ## weapon -> a shot fired that has not hit yet
var _died_last := false ## the level's last notable event was a death

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if enabled_by_default():
		start_session()

## On for a windowed debug run, off headless and in release exports; the
## command line overrides either way.
func enabled_by_default() -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--no-telemetry" in args:
		return false
	if "--telemetry" in args:
		return true
	return OS.is_debug_build() and DisplayServer.get_name() != "headless"

## Quitting (closing the window, a bot run's quit) closes the open level and the file,
## or the last level of the session never got its level_end.
func _exit_tree() -> void:
	end_session()

func is_recording() -> bool:
	return _file != null

## Open a session file (a dated one in DIR by default) and start listening.
func start_session(path: String = "") -> void:
	end_session()
	if path == "":
		DirAccess.make_dir_recursive_absolute(DIR)
		_prune()
		path = DIR.path_join(Time.get_datetime_string_from_system().replace(":", "") + ".jsonl")
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return
	_t = 0.0
	_level = ""
	_player = null
	_connect(GameState.player_died, _on_player_died)
	_connect(GameState.level_graded, _on_level_graded)
	_connect(GameState.level_completed, _on_level_completed)
	_connect(GameState.task_completed, _on_task)
	_connect(GameState.enemy_killed, _on_kill)
	_connect(GameState.player_dealt_damage, _on_dealt)
	_log("session_start", {"version": String(ProjectSettings.get_setting("application/config/version", "")),
		"difficulty": GameState.difficulty_label(), "graphics": int(GraphicsSettings.quality)})

## Close the level (as "left" if it never ended) and the file.
func end_session() -> void:
	if _file == null:
		return
	if _level != "":
		_end_level(_gone_result())
	_log("session_end", {})
	_file.close()
	_file = null

func _connect(sig: Signal, fn: Callable) -> void:
	if not sig.is_connected(fn):
		sig.connect(fn)

func _prune() -> void:
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f): return String(f).ends_with(".jsonl"))
	files.sort()
	while files.size() >= KEEP_FILES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(files.pop_front())))

func _log(event: String, data: Dictionary) -> void:
	if _file == null:
		return
	data["event"] = event
	data["t"] = snappedf(_t, 0.01)
	if _level != "":
		data["level"] = _level
		data["lt"] = snappedf(_t - _level_t0, 0.01)
	_file.store_line(JSON.stringify(data))
	_file.flush()

static func _v(p: Vector3) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]

func _mode() -> String:
	if GameState.is_uprising():
		return "uprising"
	if GameState.is_daily_op():
		return "daily"
	return "campaign" if GameState.campaign().has(GameState.current_level_path) else "other"

func _process(delta: float) -> void:
	if _file == null:
		return
	if GameState.current_state == GameState.State.PLAYING:
		_t += delta
	var p := get_tree().get_first_node_in_group("player") as Node3D
	# is_instance_valid, not ==: a freed player compares EQUAL to null, so `p != _player`
	# never saw the old one go and its level stayed open until the session closed.
	if p != null and (not is_instance_valid(_player) or p != _player):
		_attach(p)
	elif p == null and _has_player and not is_instance_valid(_player):
		if _level != "" and GameState.current_state != GameState.State.LEVEL_COMPLETE:
			# Gone after a death: TRY AGAIN reloaded it, or the player quit from the death screen.
			_end_level(_gone_result())
		_player = null
		_has_player = false

func _physics_process(delta: float) -> void:
	if _file == null or not is_instance_valid(_player) or GameState.current_state != GameState.State.PLAYING:
		return
	var body := _player as CharacterBody3D
	var pushing := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.5
	# Ground covered, not velocity: riding the convoy truck moves you with no velocity
	# of your own, and read as stuck in the first bot session.
	var here := _player.global_position
	var flat := Vector2(here.x - _stuck_pos.x, here.z - _stuck_pos.z).length() / maxf(delta, 0.0001)
	_stuck_pos = here
	if pushing and flat < STUCK_SPEED and body and body.is_on_floor():
		_stuck_for += delta
		if _stuck_for >= STUCK_TIME:
			_stuck_for = -1e9 # once per push
			if _last_stuck.distance_to(_player.global_position) > STUCK_REPEAT_M:
				_last_stuck = _player.global_position
				_log("stuck", {"pos": _v(_player.global_position)})
	elif not pushing:
		_stuck_for = 0.0

## A new player instance: a level started (or restarted).
func _gone_result() -> String:
	return "died" if _died_last else "left"

func _attach(p: Node3D) -> void:
	if _level != "":
		_end_level("died" if _died_last else "restart")
	_player = p
	_has_player = true
	_level = GameState.level_id_from_path(GameState.current_level_path)
	_level_t0 = _t
	_grade = ""
	_recent.clear()
	_shot_open.clear()
	_died_last = false
	_stuck_for = 0.0
	_last_stuck = Vector3.INF
	_acc = {"deaths": 0, "damage_taken": {}, "damage_dealt": 0.0, "shots_by_weapon": {}, "hits_by_weapon": {},
		"kills_by_weapon": {}, "tasks": 0}
	var hp: Damageable = p.get("hp")
	if hp:
		_hp_seen = hp.current_health
		hp.damaged.connect(_on_hurt.bind(hp))
		hp.health_changed.connect(func(cur: float, _max: float) -> void: _hp_seen = cur)
	_log("level_start", {"mode": _mode(), "difficulty": GameState.difficulty_label(),
		"directive": GameState.directive_id, "patches": (GameState.uprising.get("patches", []) as Array).duplicate(),
		"pos": _v(p.global_position)})
	_hook_weapons.call_deferred(p)

func _hook_weapons(p: Node3D) -> void:
	if not is_instance_valid(p):
		return
	for wm in p.find_children("*", "WeaponManager", true, false):
		for w in (wm as WeaponManager).weapons:
			_hook_weapon(w)
		_connect((wm as WeaponManager).weapon_added, _hook_weapon)

func _hook_weapon(w: Weapon) -> void:
	if is_instance_valid(w):
		_connect(w.fired, _on_fired)

func _weapon_name() -> String:
	if not is_instance_valid(_player):
		return "?"
	for wm in _player.find_children("*", "WeaponManager", true, false):
		var w: Weapon = (wm as WeaponManager).current
		if is_instance_valid(w) and w.data:
			return w.data.display_name
	return "melee"

func _bump(key: String, sub: String, by: float = 1.0) -> void:
	var d: Dictionary = _acc.get(key, {})
	d[sub] = float(d.get(sub, 0.0)) + by
	_acc[key] = d

## Counts the health a hit took, not its raw size: `damaged` fires after the
## health drops and before health_changed, so the loss is what _hp_seen still
## holds minus the new health (a 99999 finisher on 40 HP counts 40).
func _on_hurt(_amount: float, source: Node, hp: Damageable) -> void:
	var lost := maxf(_hp_seen - hp.current_health, 0.0)
	var label := Damageable.source_label(source, _player)
	_bump("damage_taken", label if label != "" else "UNKNOWN", lost)
	_recent.append({"t": _t, "source": label if label != "" else "UNKNOWN", "amount": snappedf(lost, 0.1)})
	while not _recent.is_empty() and _t - float(_recent[0]["t"]) > RECENT_WINDOW:
		_recent.pop_front()

func _on_fired(w: Weapon) -> void:
	if w.data:
		_bump("shots_by_weapon", w.data.display_name)
		_shot_open[w.data.display_name] = true

func _on_dealt(amount: float, _pos: Vector3, _killed: bool, _crit: bool) -> void:
	if _level == "":
		return
	_acc["damage_dealt"] = float(_acc.get("damage_dealt", 0.0)) + amount
	# A hit is a shot that connected: every pellet of a shotgun blast reports
	# damage, so count the first after each shot (accuracy read 157% otherwise).
	var gun := _weapon_name()
	if _shot_open.get(gun, false):
		_shot_open[gun] = false
		_bump("hits_by_weapon", gun)

func _on_kill(_score: int, label: String) -> void:
	if _level == "":
		return
	_bump("kills_by_weapon", _weapon_name())
	_bump("kills_by_enemy", label)

func _on_player_died() -> void:
	if _level == "":
		return
	_acc["deaths"] = int(_acc.get("deaths", 0)) + 1
	_died_last = true
	var recent := _recent.filter(func(h): return _t - float(h["t"]) <= RECENT_WINDOW).map(
		func(h): return {"source": h["source"], "amount": h["amount"], "ago": snappedf(_t - float(h["t"]), 0.01)})
	_log("death", {"killer": GameState.last_killer, "weapon": _weapon_name(),
		"pos": _v(_player.global_position) if is_instance_valid(_player) else [], "recent": recent})

func _on_task(label: String) -> void:
	if _level == "":
		return
	_acc["tasks"] = int(_acc.get("tasks", 0)) + 1
	_log("task", {"label": label})

func _on_level_graded(grade: String, _stats: Dictionary) -> void:
	_grade = grade

func _on_level_completed() -> void:
	if _level != "":
		_end_level("clear")

func _end_level(result: String) -> void:
	var data := _acc.duplicate(true)
	data["result"] = result
	data["grade"] = _grade
	data["time"] = snappedf(_t - _level_t0, 0.01)
	data["score"] = GameState.score
	_log("level_end", data)
	_level = ""
