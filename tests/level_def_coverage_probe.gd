extends Node
## Every typed entry in every campaign level definition resolves through the
## builder's own tables. LevelBuilder silently skips an unknown enemy type,
## prop type or pickup kind (`continue`), and an unknown task type falls out of
## its match, so a typo in level_defs.gd is a robot, crate, med-kit or
## objective that never exists and nothing reports (this repo once shipped ~88
## pickups authored under the wrong key that never spawned). Walks the real
## defs (LevelDefs.get_def, i.e. after WORLD_SCALE) and checks:
##   enemies[].type, tasks[].enemy, tasks[].reinforce[].type,
##   tasks[].waves[].enemies[].type -> LevelBuilder.ENEMY_SCENES
##   props[].type                   -> LevelBuilder.PROP_SCENES
##   pickups[].type|kind            -> LevelBuilder.PICKUP_SCENES
##   tasks[].type                   -> the arms of LevelBuilder._build_tasks
##   extra_weapons[] scene paths    -> ResourceLoader.exists
## The task-type list is a deliberate twin of the builder's match: adding a
## task type means adding it here, and this probe going red is the reminder.
##   godot --headless --path . --audio-driver Dummy res://tests/level_def_coverage_probe.tscn

const TASK_TYPES := ["assassinate", "collect_shards", "destroy_core", "escape", "generative_zone", "haul",
	"hack_terminal", "hold_zone", "key", "kill_all", "kill_quota", "none", "sabotage", "survive"]
const MIN_ENTRIES := 300 ## fewer than this and the walk itself is broken

var _fail: Array[String] = []
var _entries := 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

func _enemy(id: String, where: String, t) -> void:
	_entries += 1
	if not LevelBuilder.ENEMY_SCENES.has(String(t)):
		_fail.append("%s: %s enemy type '%s' has no ENEMY_SCENES entry" % [id, where, str(t)])

func _ready() -> void:
	var campaign: Array = GameState.campaign()
	var levels := 0
	for path in campaign:
		var id := GameState.level_id_from_path(String(path))
		var def: Dictionary = LevelDefs.get_def(id)
		if def.is_empty():
			continue # level_01 is a hand-authored scene with no def
		levels += 1
		for e in def.get("enemies", []):
			if e is Dictionary and e.has("type"):
				_enemy(id, "enemies", e["type"])
		for t in def.get("tasks", []):
			if not (t is Dictionary):
				continue
			_entries += 1
			var tt := String(t.get("type", ""))
			if not TASK_TYPES.has(tt):
				_fail.append("%s: task type '%s' is not a _build_tasks arm" % [id, tt])
			if t.has("enemy"):
				_enemy(id, "tasks.enemy", t["enemy"])
			for r in t.get("reinforce", []):
				if r is Dictionary and r.has("type"):
					_enemy(id, "tasks.reinforce", r["type"])
			for w in t.get("waves", []):
				if w is Dictionary:
					for we in w.get("enemies", []):
						if we is Dictionary and we.has("type"):
							_enemy(id, "tasks.waves", we["type"])
		for p in def.get("props", []):
			if p is Dictionary:
				_entries += 1
				if not LevelBuilder.PROP_SCENES.has(String(p.get("type", ""))):
					_fail.append("%s: prop type '%s' has no PROP_SCENES entry" % [id, str(p.get("type", ""))])
		for p in def.get("pickups", []):
			if p is Dictionary:
				_entries += 1
				var kind := String(p.get("type", p.get("kind", "")))
				if not LevelBuilder.PICKUP_SCENES.has(kind):
					_fail.append("%s: pickup kind '%s' has no PICKUP_SCENES entry" % [id, kind])
		for w in def.get("extra_weapons", []):
			var wp := ""
			if w is String:
				wp = w
			elif w is Dictionary:
				wp = String(w.get("scene", w.get("path", w.get("weapon", ""))))
			if wp.begins_with("res://"):
				_entries += 1
				if not ResourceLoader.exists(wp):
					_fail.append("%s: extra weapon '%s' does not exist" % [id, wp])
	print("walked %d level defs, %d typed entries" % [levels, _entries])
	for f in _fail:
		print("    " + f)
	var bad := _fail.size()
	_fail.clear()
	_check(levels >= 20, "walked a real campaign (%d defs)" % levels)
	_check(_entries >= MIN_ENTRIES, "walk found at least %d typed entries (%d)" % [MIN_ENTRIES, _entries])
	_check(bad == 0, "every typed entry resolves through the builder's tables (%d unresolved)" % bad)
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
