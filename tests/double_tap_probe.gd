extends Node3D
## Probe: the M9 Sidearm's alt-fire, DOUBLE TAP (WeaponData.AltMode.DOUBLE,
## Weapon._fire_volley with DOUBLE_ROUNDS). The starter pistol had no secondary
## fire (#496). Through the real weapon scene, driven the way WeaponManager
## drives it:
##   - the M9's alt mode is DOUBLE and one use costs 2 rounds;
##   - a tap fires exactly two rounds, the second within 0.07 s and two frames
##     of the first, and takes 2 from the magazine;
##   - both fly dead straight from the hip: 5 taps put 10 of 10 rounds on a
##     0.3 m wide plate at 30 m, where 10 hip-fired trigger rounds land fewer;
##   - each does the gun's full damage;
##   - holding the button fires one pair only;
##   - after a pair the gun takes a breather: the trigger does not fire for
##     DOUBLE_REST times the gun's own shot interval;
##   - with one round left the tap fires nothing and keeps the round.
## Timed on summed process deltas.
##   godot --headless --path . --audio-driver Dummy res://tests/double_tap_probe.tscn

const PAIR_GAP := 0.07 ## Weapon._fire_volley's pause between rounds

var ok := true
var w: Weapon
var cam: Camera3D
var mode := "" ## "alt" (button held), "hip" or "aim" (trigger pulled), "": what _process holds down
var clock := 0.0
var tick := 0
var shots: Array = [] ## [clock, cone in degrees] per round fired
var hits: Array = [] ## damage per hit on the plate
var worst := 0.0 ## the longest frame since the last tap began

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _process(delta: float) -> void:
	clock += delta
	worst = maxf(worst, delta)
	if w == null:
		return
	w.try_alt_fire(mode == "alt", delta, cam, null)
	# A semi-auto wants a fresh pull per round: squeeze on alternate frames.
	tick += 1
	var pull := mode == "hip" or mode == "aim"
	w.try_fire(pull and tick % 2 == 0, mode == "aim", cam, null)

func _wait(sec: float) -> void:
	var until := clock + sec
	while clock < until:
		await get_tree().process_frame

## One press of the alt-fire button, let go again.
func _tap() -> void:
	worst = 0.0
	mode = "alt"
	await _wait(0.05)
	mode = ""

func _load() -> void:
	mode = ""
	w._reloading = false
	w._cooldown = 0.0
	w.mag = w.data.mag_size
	shots.clear()
	hits.clear()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	# The plate: 0.3 m wide, 4 m tall, 30 m down range (inside the M9's 40 m
	# full-damage band). The hip cone is 1 degree: 0.52 m at that range.
	var plate := StaticBody3D.new()
	plate.collision_layer = 4
	plate.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 4.0, 0.3)
	cs.shape = box
	plate.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000000.0
	plate.add_child(hp)
	add_child(plate)
	plate.global_position = Vector3(0, 2.0, -30.0)
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void: hits.append(amount))
	var scene := (load("res://scenes/weapons/pistol.tscn") as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.fired.connect(func(_w: Weapon) -> void: shots.append([clock, w.shot_spread_deg(mode == "aim", null)]))
	var d := w.data
	var interval := 1.0 / d.fire_rate
	_check("the M9's alt mode is DOUBLE", int(d.alt_mode) == 5 and WeaponData.AltMode.keys()[int(d.alt_mode)] == "DOUBLE", "%d" % int(d.alt_mode))
	_check("one use costs 2 rounds", w.has_method("alt_cost") and int(w.call("alt_cost")) == 2, str(w.call("alt_cost") if w.has_method("alt_cost") else "no alt_cost"))

	# One tap.
	seed(7)
	_load()
	await _wait(0.6)
	await _tap()
	await _wait(0.4)
	_check("a tap fires exactly two rounds and takes 2 from the magazine", shots.size() == 2 and w.mag == d.mag_size - 2, "%d rounds, %d left of %d" % [shots.size(), w.mag, d.mag_size])
	if shots.size() == 2:
		# The second round leaves on the first frame past PAIR_GAP, and the clock
		# here is summed frames: the gap can be a frame out at each end, and the
		# first round's frame is the long one (its effects are built then). A
		# flat 0.12 s failed 2 runs in 24 at 0.121 s on a 50 ms frame (#543).
		var gap01: float = float(shots[1][0]) - float(shots[0][0])
		_check("the second round follows within PAIR_GAP and two frames", gap01 > PAIR_GAP * 0.5 and gap01 < PAIR_GAP + 2.0 * worst + 0.002,
				"%.3f s, longest frame %.3f s" % [gap01, worst])
		_check("both dead straight from the hip", float(shots[0][1]) == 0.0 and float(shots[1][1]) == 0.0, "%s and %s degrees" % [shots[0][1], shots[1][1]])
	_check("each does the gun's full damage", hits.size() == 2 and absf(float(hits[0]) - d.damage) < 0.5 and absf(float(hits[1]) - d.damage) < 0.5, "%s against %.0f" % [str(hits), d.damage])

	# Five taps against ten hip-fired trigger rounds.
	_load()
	await _wait(0.6)
	for i in 5:
		await _tap()
		await _wait(0.75)
	var tap_shots := shots.size()
	var tap_hits := hits.size()
	_load()
	await _wait(0.6)
	mode = "hip"
	while shots.size() < 10 and w.mag > 0:
		await get_tree().process_frame
	mode = ""
	await _wait(0.3)
	var hip_hits := hits.size()
	_check("5 taps put 10 of 10 rounds on a 0.3 m plate at 30 m", tap_shots == 10 and tap_hits == 10, "%d rounds, %d hits" % [tap_shots, tap_hits])
	_check("10 hip-fired trigger rounds land fewer", shots.size() == 10 and hip_hits < tap_hits, "%d hits" % hip_hits)

	# Held.
	_load()
	await _wait(0.6)
	mode = "alt"
	await _wait(1.6)
	mode = ""
	_check("holding the button fires one pair only", shots.size() == 2, "%d rounds" % shots.size())

	# The breather.
	_load()
	await _wait(0.6)
	await _tap()
	await _wait(0.1)
	var rest: float = float(w.get("DOUBLE_REST")) if w.get("DOUBLE_REST") != null else 0.0
	mode = "aim"
	while shots.size() < 3 and clock - float(shots[0][0]) < 2.0 if not shots.is_empty() else false:
		await get_tree().process_frame
	mode = ""
	if shots.size() >= 3:
		var gap: float = float(shots[2][0]) - float(shots[1][0])
		_check("after a pair the trigger waits DOUBLE_REST shot intervals", rest > 1.5 and gap > interval * rest - 0.04 and gap < interval * rest + 0.12, "%.3f s against %.3f" % [gap, interval * rest])
	else:
		_check("after a pair the trigger waits DOUBLE_REST shot intervals", false, "%d rounds fired" % shots.size())

	# One round left.
	_load()
	w.mag = 1
	await _wait(0.6)
	await _tap()
	await _wait(0.4)
	_check("with one round left the tap fires nothing and keeps the round", shots.is_empty() and w.mag == 1, "%d rounds, %d left" % [shots.size(), w.mag])

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
