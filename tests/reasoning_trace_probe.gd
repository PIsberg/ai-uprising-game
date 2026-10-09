extends Node3D
## Probe: leaked robot reasoning (ReasoningTrace, EnemyBase._think).
## (1) first contact floats a `<think>` alert line over a robot in view, typed
##     out, and it clears itself after a few seconds;
## (2) a second robot spotting you inside the global gap stays quiet;
## (3) a robot behind the camera, or past RANGE, never shows one;
## (4) an EMP is the player's doing and shows inside the global gap, but one
##     burst over a pack shows one line;
## (5) the Combat Callouts setting switches them off.
##   godot --headless --path . --audio-driver Dummy res://tests/reasoning_trace_probe.tscn

const ANDROID := "res://scenes/enemies/android.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	cam.look_at(Vector3(0, 1.6, -10), Vector3.UP)
	cam.current = true
	var a := _robot(Vector3(-2, 0, -10))
	var b := _robot(Vector3(2, 0, -10))
	var behind := _robot(Vector3(0, 0, 12))
	var far := _robot(Vector3(0, 0, -60))
	var pack: Array[EnemyBase] = [_robot(Vector3(-4, 0, -14)), _robot(Vector3(0, 0, -14)), _robot(Vector3(4, 0, -14))]
	await _frames(4)
	GraphicsSettings.combat_callouts_enabled = true
	ReasoningTrace._last_ms = -100000

	# 1. First contact.
	a.set_state(EnemyBase.State.CHASE)
	var la := _trace(a)
	_check("first contact floats a trace", la != null)
	if la:
		await _frames(45)
		var txt := la.text
		var known := false
		for l in ReasoningTrace.LINES["alert"]:
			if txt == "<think> " + String(l):
				known = true
		_check("typed out to a full alert line", known, "'%s'" % txt)
		_check("over the robot's head", la.position.y >= 1.2, "y %.2f" % la.position.y)

	# 2. Second robot inside the gap.
	b.set_state(EnemyBase.State.CHASE)
	_check("second contact inside the gap stays quiet", _trace(b) == null)

	# 3. Off screen / out of range, with the gap cleared.
	ReasoningTrace._last_ms = -100000
	behind.set_state(EnemyBase.State.CHASE)
	_check("robot behind the camera stays quiet", _trace(behind) == null)
	far.set_state(EnemyBase.State.CHASE)
	_check("robot past RANGE stays quiet", _trace(far) == null)

	# 4. EMP inside the global gap: one line for the whole burst.
	a.set_state(EnemyBase.State.IDLE)
	ReasoningTrace._last_ms = Time.get_ticks_msec() - 1000 # a trace played 1 s ago: inside the global gap
	for e in pack:
		e.emp_disable(2.0)
	var shown := 0
	for e in pack:
		if _trace(e) != null:
			shown += 1
	_check("EMP burst over a pack shows exactly one line", shown == 1, "%d lines" % shown)

	# 5. Setting off.
	ReasoningTrace._last_ms = -100000
	GraphicsSettings.combat_callouts_enabled = false
	b.set_state(EnemyBase.State.IDLE)
	var c := _robot(Vector3(0, 0, -8))
	await _frames(3)
	c.set_state(EnemyBase.State.CHASE)
	_check("Combat Callouts off: no trace", _trace(c) == null)
	GraphicsSettings.combat_callouts_enabled = true

	# 1b. The first trace cleared itself (typing ~0.6 s + HOLD + 0.4 s fade).
	var deadline := int((ReasoningTrace.HOLD + 1.6) * 60.0)
	for i in deadline:
		await get_tree().physics_frame
		if not is_instance_valid(la):
			break
	_check("the trace clears itself", not is_instance_valid(la))

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _trace(e: Node) -> Label3D:
	return e.get_node_or_null("ReasoningTrace") as Label3D

func _robot(pos: Vector3) -> EnemyBase:
	# Live (the trace's typing tween runs on the robot's process mode), but with
	# no player in the scene its AI has nobody to chase: the probe drives state.
	var e: EnemyBase = (load(ANDROID) as PackedScene).instantiate()
	add_child(e)
	e.global_position = pos
	return e
