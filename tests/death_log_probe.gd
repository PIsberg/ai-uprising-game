extends Node
## Probe: a robot's death prints a red terminal line (scripts/fx/death_log.gd).
## (1) a kill in view logs one line in the level, not on the robot, above the
##     body; it types out to "> " + a line from LINES, rises, and outlives the
##     robot's own node;
## (2) another kill inside GAP_MS logs nothing (one line at a time);
## (3) a kill out of view or out of RANGE logs nothing;
## (4) the Combat Callouts setting switches it off;
## (5) a boss-sized robot always logs, inside the gap, with BOSS_LINE;
## (6) every line frees itself.
##   godot --headless --path . --audio-driver Dummy res://tests/death_log_probe.tscn

var ok := true
var cam: Camera3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _logs() -> Array:
	return get_tree().get_nodes_in_group(DeathLog.GROUP)

func _spawn(at: Vector3, boss := false) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = at
	if boss:
		e.score_value = 1000
	return e

func _kill(e: EnemyBase) -> void:
	e.hp.apply_damage(100000.0, null, false, e.global_position + Vector3.UP)

func _run() -> void:
	DeathLog.chance = 1.0 # the roll is the only random part; the probe pins it
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(300, 1, 300)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.7, 10)
	cam.look_at(Vector3(0, 1.2, 0), Vector3.UP)
	cam.current = true
	var callouts: bool = GraphicsSettings.combat_callouts_enabled
	GraphicsSettings.combat_callouts_enabled = true
	await _frames(3)

	# 1. A kill in view.
	DeathLog.reset()
	var a := _spawn(Vector3.ZERO)
	await _frames(3)
	_kill(a)
	var logs := _logs()
	_check("a kill in view logs one line", logs.size() == 1, str(logs.size()))
	if logs.size() == 1:
		var lb: Label3D = logs[0]
		_check("in the level, not on the robot", lb.get_parent() == self)
		var y0 := lb.global_position.y
		_check("above the body", y0 > 1.0 and y0 < 3.5, "%.2f" % y0)
		await _frames(60) # typing takes up to 0.7 s
		_check("typed out to a known line", is_instance_valid(lb) and lb.text.begins_with("> ")
				and DeathLog.LINES.has(lb.text.substr(2)), lb.text if is_instance_valid(lb) else "freed")
		_check("rising", is_instance_valid(lb) and lb.global_position.y > y0 + 0.2)
		if is_instance_valid(a):
			a.free() # the wreck goes; the line must not go with it
		await _frames(2)
		_check("outlives the robot's node", is_instance_valid(lb))

	# 2. Inside the gap.
	var b := _spawn(Vector3(1.5, 0, 0))
	await _frames(3)
	var n := _logs().size()
	_kill(b)
	_check("a second kill inside GAP_MS logs nothing", _logs().size() == n)

	# 3. Out of view / out of range.
	DeathLog.reset()
	var c := _spawn(Vector3(0, 0, 30)) # behind the camera
	await _frames(3)
	n = _logs().size()
	_kill(c)
	_check("behind the camera: nothing", _logs().size() == n)
	DeathLog.reset()
	var d := _spawn(Vector3(0, 0, -DeathLog.RANGE - 15.0))
	await _frames(3)
	_kill(d)
	_check("past RANGE: nothing", _logs().size() == n)

	# 4. Callouts off.
	DeathLog.reset()
	GraphicsSettings.combat_callouts_enabled = false
	var f := _spawn(Vector3(-1.5, 0, 0))
	await _frames(3)
	_kill(f)
	_check("Combat Callouts off: nothing", _logs().size() == n)
	GraphicsSettings.combat_callouts_enabled = true

	# 5. A boss always logs, inside the gap.
	DeathLog.reset()
	var g := _spawn(Vector3(-2.5, 0, 0))
	await _frames(3)
	_kill(g)
	n = _logs().size()
	var boss := _spawn(Vector3(2.5, 0, 0), true)
	await _frames(3)
	_kill(boss)
	_check("a boss logs inside the gap", _logs().size() == n + 1, "%d -> %d" % [n, _logs().size()])
	await _frames(60) # typing takes up to 0.7 s
	var boss_line := false
	for lb in _logs():
		if is_instance_valid(lb) and (lb as Label3D).text == "> " + DeathLog.BOSS_LINE:
			boss_line = true
	_check("with BOSS_LINE", boss_line)

	# 6. Clean-up.
	var t := 0
	while not _logs().is_empty() and t < 60 * 8:
		await get_tree().physics_frame
		t += 1
	_check("every line frees itself", _logs().is_empty(), "%d left" % _logs().size())
	GraphicsSettings.combat_callouts_enabled = callouts

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
