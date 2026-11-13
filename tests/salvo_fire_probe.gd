extends Node3D
## Probe: the SW-7 Swarm Launcher's alt-fire, SALVO (WeaponData.AltMode.SALVO).
## The launcher had no secondary fire (#496). One press ripples every round left
## in the magazine, then the gun rests. Through the real weapon scene, driven
## the way WeaponManager drives it:
##   - the launcher's alt mode is SALVO and the HUD tag needs SALVO_MIN rounds;
##   - one press on a full magazine fires all 9 rounds (27 missiles) and leaves
##     it empty, the button let go at once;
##   - the 9 rounds leave in under 1 s, where the trigger takes over 3 s;
##   - every round keeps the launcher's cone (a salvo is a spread, not a beam);
##   - the gun then rests SALVO_REST shot intervals before the trigger works;
##   - a press on 4 rounds fires 4; a press on 1 round fires nothing;
##   - holstering the gun mid-salvo stops it with rounds left.
## Timed on summed process deltas.
##   godot --headless --path . --audio-driver Dummy res://tests/salvo_fire_probe.tscn

const GUN := "res://scenes/weapons/swarm.tscn"

var ok := true
var w: Weapon
var cam: Camera3D
var alt := false
var trigger := false
var clock := 0.0
var tick := 0
var shots: Array = [] ## [clock, cone in degrees] per round fired
var missiles := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	child_entered_tree.connect(func(n: Node) -> void:
		if n.has_method("launch"):
			missiles += 1)
	_run.call_deferred()

func _process(delta: float) -> void:
	clock += delta
	if w == null:
		return
	# A semi-auto wants a fresh pull per round: squeeze on alternate frames.
	tick += 1
	w.try_fire(trigger and tick % 2 == 0, false, cam, null)
	w.try_alt_fire(alt, delta, cam, null)

func _wait(sec: float) -> void:
	var until := clock + sec
	while clock < until:
		await get_tree().process_frame

func _load(rounds: int) -> void:
	trigger = false
	alt = false
	await _wait(0.3)
	w._reloading = false
	w._cooldown = 0.0
	w.mag = rounds
	shots.clear()
	missiles = 0

## One press of the alt-fire button, let go again.
func _tap() -> void:
	alt = true
	await _wait(0.05)
	alt = false

func _span() -> float:
	return float(shots[-1][0]) - float(shots[0][0]) if shots.size() > 1 else 0.0

func _const(c: String) -> float:
	return float(w.get(c)) if w.get(c) != null else -1.0

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 60, 0) # into open air: the missiles run out their range
	var scene := (load(GUN) as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.fired.connect(func(_w: Weapon) -> void: shots.append([clock, w.shot_spread_deg(false, null)]))
	var d := w.data
	w.reserve = 0 # no auto-reload behind the probe's back
	var rest := _const("SALVO_REST")
	var smin := int(_const("SALVO_MIN"))
	var keys := WeaponData.AltMode.keys()
	var mode_name: String = keys[int(d.alt_mode)]
	_check("the launcher's alt mode is SALVO", mode_name == "SALVO", mode_name)
	_check("the HUD tag needs SALVO_MIN (2) rounds", smin == 2 and int(w.alt_cost()) == smin, "%d, alt_cost %d" % [smin, w.alt_cost()])
	_check("the magazine holds 9 rounds of 3 missiles", d.mag_size == 9 and d.pellets == 3, "%d x %d" % [d.mag_size, d.pellets])

	# The trigger, for the comparison.
	await _load(9)
	trigger = true
	var t0 := clock
	while shots.size() < 9 and clock - t0 < 8.0:
		await get_tree().process_frame
	trigger = false
	var trig_span := _span()
	_check("the trigger takes over 3 s to fire 9 rounds", shots.size() == 9 and trig_span > 3.0, "%.2f s" % trig_span)

	# One press, full magazine.
	await _load(9)
	await _tap()
	await _wait(1.6)
	_check("one press on a full magazine fires all 9 rounds", shots.size() == 9 and w.mag == 0, "%d rounds, %d left" % [shots.size(), w.mag])
	_check("27 missiles leave the gun", missiles == 27, str(missiles))
	_check("the 9 rounds leave in under 1 s", shots.size() == 9 and _span() < 1.0, "%.2f s" % _span())
	var cone := true
	for s in shots:
		if float(s[1]) < 3.0:
			cone = false
	_check("every round keeps the launcher's cone", not shots.is_empty() and cone, "%.1f deg" % (float(shots[0][1]) if not shots.is_empty() else 0.0))

	# The rest after it.
	await _load(9)
	await _tap()
	var until := clock + 3.0
	while shots.size() < 9 and clock < until:
		await get_tree().process_frame
	await get_tree().process_frame
	var interval := 1.0 / d.fire_rate
	_check("the gun then rests SALVO_REST shot intervals", rest > 1.0 and absf(w._cooldown - interval * rest) < 0.06, "cooldown %.2f s, %.1f intervals of %.2f s" % [w._cooldown, rest, interval])

	# Part magazines.
	await _load(4)
	await _tap()
	await _wait(1.0)
	_check("a press on 4 rounds fires 4", shots.size() == 4 and w.mag == 0, "%d rounds, %d left" % [shots.size(), w.mag])
	await _load(1)
	await _tap()
	await _wait(0.5)
	_check("a press on 1 round fires nothing", shots.is_empty() and w.mag == 1, "%d rounds, %d left" % [shots.size(), w.mag])

	# Holstered mid-salvo.
	await _load(9)
	await _tap()
	until = clock + 3.0
	while shots.size() < 3 and clock < until:
		await get_tree().process_frame
	w.on_unequip()
	var held := w
	w = null # the manager stops driving a holstered gun
	var at := shots.size()
	await _wait(1.0)
	_check("holstering the gun mid-salvo stops it", at >= 3 and shots.size() <= at + 1 and held.mag >= 9 - at - 1 and held.mag > 0, "%d rounds out at the holster, %d in all, %d left" % [at, shots.size(), held.mag])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
