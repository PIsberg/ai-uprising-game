extends Node
## Dev probe for the staged mission-arc objectives.
##
## Static pass — every campaign level def's task graph is validated:
##   unique ids, "after" references resolve (no self-refs / cycles), authored
##   positions inside the floor, reinforcement enemy types exist.
## Runtime pass — builds the Assembly and Uplink levels and drives their arcs:
##   staged tasks register dimmed, prerequisites going done spawns the staged
##   objects mid-mission, reinforcement waves pour in, kill_quota counts kills.
##   godot --headless --path . res://tests/mission_arc_probe.tscn

const LEVELS := [
	"01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss", "mistral",
	"overseer", "alien", "uplink", "assembly", "titan", "archon", "range",
	"horde", "sublevel", "crucible", "frostbreak", "neon", "lava_world",
	"water_world", "desert",
]

var _ok := true

func _ready() -> void:
	_run.call_deferred()

func _check(name: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "BAD ", name, detail])
	if not cond:
		_ok = false

func _run() -> void:
	_validate_defs()
	await _runtime_assembly()
	await _runtime_uplink()
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

# ---------- static def validation ----------

func _task_id(t: Dictionary) -> String:
	match t.get("type", ""):
		"kill_all": return "kill_all"
		"kill_quota": return t.get("id", "quota")
		"key": return t.get("id", "key")
		"destroy_core": return t.get("id", "core")
		"collect_shards": return t.get("id", "shards")
		"hack_terminal", "sabotage": return t.get("id", t.get("type", "hack"))
		"survive": return t.get("id", "survive")
		"hold_zone": return t.get("id", "hold")
		"assassinate": return t.get("id", "hvt")
	return t.get("id", "task")

func _validate_defs() -> void:
	for lid in LEVELS:
		var def := LevelDefs.get_def(lid)
		var tasks: Array = def.get("tasks", [])
		var fs: Vector2 = def.get("floor_size", Vector2(100, 100))
		var half := fs * 0.5 + Vector2(6, 6) # small grace margin (desert mast sits proud)
		var ids: Array = []
		for t in tasks:
			if t.get("type", "") == "none":
				continue
			var id := _task_id(t)
			_check("%s id unique" % lid, not ids.has(id), id)
			ids.append(id)
		for t in tasks:
			# after-references resolve and never point at the task itself
			var a = t.get("after", [])
			var prereqs: Array = [a] if a is String else (a as Array)
			for p in prereqs:
				_check("%s after resolves" % lid, ids.has(p) and p != _task_id(t),
					"%s after %s" % [_task_id(t), p])
			# authored positions stay on the floor
			var pts: Array = []
			if t.has("pos"):
				pts.append(t["pos"])
			for sp in t.get("points", []):
				pts.append(sp["pos"] if sp is Dictionary else sp)
			for r in t.get("reinforce", []):
				if r.has("pos"):
					pts.append(r["pos"])
				_check("%s reinforce type" % lid,
					LevelBuilder.ENEMY_SCENES.has(r.get("type", "")), str(r.get("type")))
			for p in pts:
				var v := p as Vector3
				_check("%s pos in bounds" % lid,
					absf(v.x) <= half.x and absf(v.z) <= half.y,
					"%s %s" % [_task_id(t), str(v)])
			if t.get("type", "") == "kill_quota":
				_check("%s quota count" % lid, int(t.get("count", 0)) > 0, _task_id(t))
		# no cycles: repeatedly peel tasks whose prereqs are all peeled
		var remaining := ids.duplicate()
		var made_progress := true
		while made_progress and not remaining.is_empty():
			made_progress = false
			for t in tasks:
				var id := _task_id(t)
				if not remaining.has(id):
					continue
				var a2 = t.get("after", [])
				var pre: Array = [a2] if a2 is String else (a2 as Array)
				var free := true
				for p in pre:
					if remaining.has(p):
						free = false
						break
				if free:
					remaining.erase(id)
					made_progress = true
		_check("%s acyclic" % lid, remaining.is_empty(), str(remaining))

# ---------- runtime: assembly (sabotage -> reinforce + kill_quota) ----------

func _alive_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and (e as EnemyBase).hp != null and (e as EnemyBase).hp.is_alive():
			n += 1
	return n

func _task_flag(id: String, key: String) -> bool:
	for t in GameState.level_tasks:
		if t["id"] == id:
			return bool(t.get(key, false))
	return false

func _runtime_assembly() -> void:
	var lvl: Node = load("res://scenes/levels/level_assembly.tscn").instantiate()
	get_tree().root.add_child(lvl)
	await _wait(1.5)
	_check("assembly batch staged", _task_flag("batch", "staged"))
	var before := _alive_enemies()
	GameState.complete_task("sabotage")
	await _wait(3.2) # staggered reinforcement wave pours in
	var after := _alive_enemies()
	_check("assembly reinforce spawned", after >= before + 4, "%d -> %d" % [before, after])
	_check("assembly batch live", not _task_flag("batch", "staged"))
	for i in 6: # kill_quota counts kills and completes at the goal
		GameState.enemy_killed.emit(100, "TEST")
	await _wait(0.2)
	_check("assembly batch done", GameState.is_task_done("batch"))
	lvl.queue_free()
	await _wait(0.3)

# ---------- runtime: uplink (hold -> key -> hold chain) ----------

func _runtime_uplink() -> void:
	var lvl: Node = load("res://scenes/levels/level_uplink.tscn").instantiate()
	get_tree().root.add_child(lvl)
	await _wait(1.5)
	_check("uplink key staged", _task_flag("key", "staged"))
	_check("uplink boost staged", _task_flag("boost", "staged"))
	_check("uplink no keycard yet", get_tree().get_nodes_in_group("keycard").is_empty())
	GameState.complete_task("uplink")
	await _wait(0.5)
	_check("uplink keycard spawned", get_tree().get_nodes_in_group("keycard").size() == 1)
	_check("uplink boost still staged", _task_flag("boost", "staged"))
	GameState.complete_task("key")
	await _wait(0.5)
	_check("uplink boost live", not _task_flag("boost", "staged"))
	lvl.queue_free()
	await _wait(0.3)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
