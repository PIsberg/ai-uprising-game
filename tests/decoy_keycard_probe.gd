extends Node3D
## Hallucinated keycards (Keycard.decoy, a key task's `decoys` + `ambush`).
## Unit pass, with this node standing in for the level (it records what the
## decoy asks the reinforcement spawner for):
##   - a decoy is a keycard in the objective group, like the real one;
##   - its "[citation needed]" tag is hidden from afar and shows inside TAG_RANGE;
##   - touching a decoy completes nothing, toasts HALLUCINATION, frees the card
##     and spawns its ambush at the card's position;
##   - a second decoy reads a different line;
##   - taking the real card completes the task and dissolves the decoys left,
##     without springing their ambush.
## Campaign pass: every level that authors decoys builds them (real card first,
## then one decoy per authored spot, flagged decoy, carrying the ambush) and the
## ambush types exist. Placement (clear floor near the navmesh) is
## task_reach_probe's job.
##   godot --headless --path . --audio-driver Dummy res://tests/decoy_keycard_probe.tscn

var _fails: Array[String] = []
var _toasts: Array[String] = []
var _spawned: Array = []

class StubPlayer extends CharacterBody3D:
	pass

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

## Stand-in for LevelBuilder._spawn_reinforcements.
func _spawn_reinforcements(specs: Array) -> void:
	_spawned.append_array(specs)

func _ready() -> void:
	await _frames(10)
	GameState.skirmish_event.connect(func(title: String, desc: String): _toasts.append("%s|%s" % [title, desc]))
	await _unit()
	await _campaign()
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _card(pos: Vector3, decoy: bool) -> Keycard:
	var k := Keycard.new()
	k.task_id = "key"
	k.decoy = decoy
	k.ambush = [{"type": "skitter", "count": 3}] if decoy else []
	k.position = pos
	add_child(k)
	return k

## Untyped on purpose: a typed Node parameter rejects a freed instance with a
## script error that aborts the caller, and the probe still printed PASS.
func _gone(n) -> bool:
	return not is_instance_valid(n) or (n as Node).is_queued_for_deletion()

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("key", "Card", 0.0)
	var p := StubPlayer.new()
	p.add_to_group("player")
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new()
	cs.position.y = 1.0
	p.add_child(cs)
	p.position = Vector3(0, 0, 60)
	add_child(p)
	var real := _card(Vector3(0, 0, 0), false)
	var d1 := _card(Vector3(20, 0, 0), true)
	var d2 := _card(Vector3(-20, 0, 0), true)
	await _frames(4)
	_check(d1.is_in_group("objective") and d1.is_in_group("keycard"), "a decoy shows on the waypoint like the real card")
	_check(not d1._tag.visible, "the [citation needed] tag is hidden from afar")
	p.global_position = Vector3(20, 0, 4.5)
	await _frames(3)
	_check(d1._tag.visible, "the tag shows inside %.0f m" % Keycard.TAG_RANGE)

	p.global_position = Vector3(20, 0, 0)
	await _frames(4)
	_check(not GameState.is_task_done("key"), "touching a decoy completes nothing")
	_check(_gone(d1), "the decoy glitches out")
	var hall := _toasts.filter(func(s): return s.begins_with(Keycard.HALLUCINATION_TITLE + "|"))
	_check(hall.size() == 1, "the HUD calls it a hallucination (%s)" % [hall])
	_check(_spawned.size() == 1 and _spawned[0].get("type") == "skitter" and int(_spawned[0].get("count")) == 3,
		"its ambush is asked for (%s)" % [_spawned])
	_check(_spawned.size() == 1 and (_spawned[0]["pos"] as Vector3).distance_to(Vector3(20, 0, 0)) < 0.01,
		"the ambush lands where the card stood")

	p.global_position = Vector3(-20, 0, 0)
	await _frames(4)
	hall = _toasts.filter(func(s): return s.begins_with(Keycard.HALLUCINATION_TITLE + "|"))
	_check(_gone(d2) and hall.size() == 2 and hall[0] != hall[1], "a second decoy reads a different line")

	# Fresh decoy, then the real card: the decoy left must dissolve.
	var d3 := _card(Vector3(30, 0, 0), true)
	await _frames(2)
	p.global_position = Vector3(0, 0, 0)
	await _frames(4)
	_check(GameState.is_task_done("key"), "the real card completes the task")
	_check(_gone(d3), "taking the real card dissolves the decoys left")
	_check(_spawned.size() == 2, "dissolving a decoy springs no ambush (%d spawned)" % _spawned.size())
	p.queue_free()
	if is_instance_valid(real):
		real.queue_free()
	GameState.reset_tasks()
	await _frames(3)

func _campaign() -> void:
	var found := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for t in def.get("tasks", []):
			var decoys: Array = t.get("decoys", [])
			if decoys.is_empty():
				continue
			found += 1
			print("level %s:" % id)
			_check(t.get("type", "") == "key", "%s decoys sit on a key task" % id)
			_check(not (t.get("ambush", []) as Array).is_empty(), "%s decoys carry an ambush" % id)
			for a in t.get("ambush", []):
				_check(LevelBuilder.ENEMY_SCENES.has(String(a.get("type", ""))), "%s ambush type %s exists" % [id, a.get("type")])
			var level := (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate() as Node3D
			add_child(level)
			# A staged key spawns later: only an unstaged one is live at build.
			await _frames(30)
			if t.has("after"):
				level.queue_free()
				await _frames(4)
				continue
			var tid: String = t.get("id", "key")
			var cards: Array = []
			for c in level.get_children():
				if c is Keycard and (c as Keycard).task_id == tid:
					cards.append(c)
			_check(cards.size() == decoys.size() + 1, "%s builds the real card + %d decoys (%d)" % [id, decoys.size(), cards.size()])
			if cards.size() == decoys.size() + 1:
				_check(not cards[0].decoy, "%s real card first" % id)
				var all_decoys := true
				for k in range(1, cards.size()):
					all_decoys = all_decoys and cards[k].decoy and not (cards[k].ambush as Array).is_empty()
				_check(all_decoys, "%s every later card is a decoy with an ambush" % id)
			level.queue_free()
			await _frames(4)
	_check(found >= 1, "at least one campaign level authors decoys (%d)" % found)
