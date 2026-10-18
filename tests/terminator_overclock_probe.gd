extends Node3D
## Probe: APEX ENDOFRAME's fight escalates once, at half health: OVERCLOCK.
## It was the one boss with no phase, so its bar had no notch and its fight no
## beat (#365).
## (1) one phase mark, at 50 %, and _phase() follows it (90 % -> 1, 40 % -> 2);
## (2) at 60 % nothing has changed;
## (3) crossing 50 % stages the final-phase beat (GameState.boss_phase_changed,
##     final) and overclocks it: move speed x1.25, burst cooldown x0.7, +2
##     rounds a burst, the lance back sooner (cooldown x0.6), barrels spin
##     faster; the live (elite/difficulty-scaled) values, not the authored ones;
## (4) healed back over 50 % and wounded again, it does not overclock twice.
##   godot --headless --path . --audio-driver Dummy res://tests/terminator_overclock_probe.tscn

var ok := true
var _beats: Array = []

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _stats(e: Node) -> Dictionary:
	return {"speed": float(e.get("move_speed")), "cd": float(e.get("attack_cooldown")),
		"burst": int(e.get("burst_count")), "beam_cd": float(e.get("beam_cooldown")) if e.get("beam_cooldown") != null else -1.0,
		"spin": float(e.get("spin_max")) if e.get("spin_max") != null else -1.0}

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	GameState.boss_phase_changed.connect(func(b: Node, ph: int, final: bool) -> void: _beats.append([ph, final]))
	var e: Node3D = (load("res://scenes/enemies/terminator.tscn") as PackedScene).instantiate()
	e.set("preview", true)
	e.set("_speed_mult", 1.3) # as an elite would: the overclock scales the live value
	add_child(e)
	for i in 4:
		await get_tree().process_frame
	var hp: Node = e.get_node("Damageable")
	hp.set("invulnerable", false)
	hp.set("armor", 0.0)
	var maxh: float = hp.get("max_health")

	# (1)
	var marks: Array = e.call("boss_phase_marks")
	_check("one phase mark at 50 %", marks == [0.5], "(%s)" % [marks])
	var got := []
	for f in [0.9, 0.4]:
		hp.set("current_health", maxh * f)
		got.append(e.call("_phase"))
	hp.set("current_health", maxh)
	_check("_phase() follows it", got == [1, 2], "(%s)" % [got])

	var base := _stats(e)
	print("  base %s" % base)
	_check("elite speed mult applied before the fight", absf(base["speed"] - 6.8 * 1.3) < 0.01, "(%.2f)" % base["speed"])
	# (2)
	hp.call("apply_damage", maxh * 0.4, null)
	await get_tree().process_frame
	var mid := _stats(e)
	_check("nothing changes at 60 %", mid == base and _beats.is_empty(), "(%s, %d beats)" % [mid, _beats.size()])
	# (3)
	hp.call("apply_damage", maxh * 0.15, null)
	await get_tree().process_frame
	var oc := _stats(e)
	print("  overclocked %s" % oc)
	_check("crossing 50 % stages the final beat", _beats == [[2, true]], "(%s)" % [_beats])
	_check("moves 1.25x faster", absf(oc["speed"] - base["speed"] * 1.25) < 0.01, "(%.2f)" % oc["speed"])
	_check("the gap between bursts shrinks to 0.7x", absf(oc["cd"] - base["cd"] * 0.7) < 0.01, "(%.2f)" % oc["cd"])
	_check("two more rounds a burst", oc["burst"] == base["burst"] + 2, "(%d)" % oc["burst"])
	_check("the lance comes back sooner", absf(oc["beam_cd"] - base["beam_cd"] * 0.6) < 0.01, "(%.2f)" % oc["beam_cd"])
	_check("the barrels spin faster", oc["spin"] > base["spin"], "(%.0f rad/s)" % oc["spin"])
	# (4)
	hp.set("current_health", maxh * 0.9)
	hp.call("apply_damage", maxh * 0.5, null)
	await get_tree().process_frame
	var again := _stats(e)
	_check("it overclocks once", again == oc and _beats.size() == 1, "(%s, %d beats)" % [again, _beats.size()])
	Engine.time_scale = 1.0
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
