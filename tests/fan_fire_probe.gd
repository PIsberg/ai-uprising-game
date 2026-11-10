extends Node3D
## Probe: the .50 Maelstrom's alt-fire, FAN THE HAMMER (WeaponData.AltMode.FAN,
## Weapon._alt_fan_logic). The revolver had no secondary fire. Through the real
## weapon scene, driven the way WeaponManager drives it:
##   - the Maelstrom's alt mode is FAN;
##   - held, it empties the six-round cylinder, a round every
##     1 / (fire_rate * FAN_RATE_MULT) seconds (the trigger alone fires 3 rounds
##     in the time the fan fires 6);
##   - every fanned round flies in a FAN_SPREAD_DEG cone, hip or aimed, and
##     does FAN_DAMAGE of the gun's damage;
##   - at 25 m a 1.2 m wide plate takes at least 15 of 18 aimed trigger shots
##     and fewer than 12 of 18 fanned ones (about 6 expected);
##   - letting go stops the fan with rounds left, and the hand needs
##     FAN_RECOVER before the trigger fires again;
##   - on an empty cylinder the fan fires nothing.
## Timed on summed process deltas.
##   godot --headless --path . --audio-driver Dummy res://tests/fan_fire_probe.tscn

var ok := true
var w: Weapon
var cam: Camera3D
var mode := "" ## "fan" or "trigger" or "": what _process holds down
var clock := 0.0
var tick := 0
var shots: Array = [] ## [clock, cone in degrees] per round fired
var hits: Array = [] ## damage per hit on the plate

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _process(delta: float) -> void:
	clock += delta
	if w == null:
		return
	if mode == "fan":
		w.try_alt_fire(true, delta, cam, null)
	else:
		w.try_alt_fire(false, delta, cam, null)
	# A semi-auto wants a fresh pull per round: squeeze on alternate frames.
	tick += 1
	w.try_fire(mode == "trigger" and tick % 2 == 0, mode == "trigger", cam, null)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1.6, 0)
	# The plate: 1.2 m wide, 4 m tall, 25 m down range (inside the gun's 35 m
	# full-damage band).
	var plate := StaticBody3D.new()
	plate.collision_layer = 4
	plate.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 4.0, 0.3)
	cs.shape = box
	plate.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000000.0
	plate.add_child(hp)
	add_child(plate)
	plate.global_position = Vector3(0, 2.0, -25.0)
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void: hits.append(amount))
	var scene := (load("res://scenes/weapons/magnum.tscn") as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.fired.connect(func(_w: Weapon) -> void: shots.append([clock, w.shot_spread_deg(mode == "trigger", null)]))
	var d := w.data
	_check("the Maelstrom's alt mode is FAN", d.alt_mode == WeaponData.AltMode.FAN, str(d.alt_mode))
	var gap := 1.0 / (d.fire_rate * Weapon.FAN_RATE_MULT)

	# The trigger alone, aimed, for as long as a full fan takes.
	seed(11)
	_load()
	await _wait(0.8)
	mode = "trigger"
	await _wait(gap * 6.0 + 0.1)
	var by_trigger := shots.size()
	_check("the trigger alone fires 3 rounds in that time", by_trigger == 3, str(by_trigger))
	# The rest of the cylinder, aimed, to score the plate.
	await _wait(2.0)
	mode = ""
	await _wait(0.3)
	var aimed_hits := hits.size()
	var aimed_shots := shots.size()
	var full: float = hits.max() if not hits.is_empty() else 0.0
	# Two more cylinders: 18 rounds each way, so the comparison is not luck.
	for i in 2:
		_load()
		await _wait(0.5)
		mode = "trigger"
		await _wait(2.4)
		mode = ""
		await _wait(0.3)
		aimed_hits += hits.size()
		aimed_shots += shots.size()
	_check("at 25 m the plate takes at least 15 of 18 aimed trigger shots", aimed_shots == 18 and aimed_hits >= 15, "%d shots, %d hits" % [aimed_shots, aimed_hits])

	# The fan.
	seed(11)
	_load()
	await _wait(0.8)
	mode = "fan"
	await _wait(gap * 6.0 + 0.1)
	_check("held, the fan empties the cylinder", shots.size() == 6 and w.mag == 0, "%d rounds, %d left" % [shots.size(), w.mag])
	if shots.size() == 6:
		var span: float = shots[5][0] - shots[0][0]
		_check("a round every 1 / (fire_rate * FAN_RATE_MULT) s", absf(span / 5.0 - gap) < 0.03, "%.3f s apart against %.3f" % [span / 5.0, gap])
		var cones: Array = shots.map(func(s: Array) -> float: return s[1])
		_check("every fanned round flies in a FAN_SPREAD_DEG cone", cones.min() == Weapon.FAN_SPREAD_DEG and cones.max() == Weapon.FAN_SPREAD_DEG, str(cones))
	var fan_hits := hits.size()
	for i in 2:
		_load()
		await _wait(0.8)
		mode = "fan"
		await _wait(gap * 6.0 + 0.1)
		mode = ""
		fan_hits += hits.size()
	_check("and fewer than 12 of 18 fanned ones", fan_hits < 12 and fan_hits < aimed_hits, "%d hits" % fan_hits)
	# The damage, off a point-blank round (it cannot miss the plate at 3 m).
	plate.global_position = Vector3(0, 2.0, -3.0)
	_load()
	await _wait(0.8)
	mode = "fan"
	await _wait(gap * 1.5)
	mode = ""
	await _wait(0.2)
	plate.global_position = Vector3(0, 2.0, -25.0)
	_check("a fanned round does FAN_DAMAGE of the gun's damage", not hits.is_empty() and full > 0.0 and absf(float(hits[0]) / full - Weapon.FAN_DAMAGE) < 0.02,
			"%s against %.1f" % [str(hits), full])
	# Dry.
	w.mag = 0
	shots.clear()
	mode = ""
	await _wait(0.8)
	mode = "fan"
	await _wait(0.4)
	mode = ""
	_check("on an empty cylinder the fan fires nothing", shots.is_empty(), str(shots.size()))

	# Letting go.
	_load()
	await _wait(0.8)
	mode = "fan"
	await _wait(gap * 2.5)
	mode = ""
	await _wait(0.05)
	var fanned := shots.size()
	_check("letting go stops the fan with rounds left", fanned >= 2 and fanned <= 4 and w.mag == 6 - fanned, "%d fired, %d left" % [fanned, w.mag])
	mode = "trigger"
	await _wait(Weapon.FAN_RECOVER - 0.15)
	_check("the hand needs FAN_RECOVER before the trigger fires", shots.size() == fanned, "%d rounds" % shots.size())
	await _wait(0.4)
	mode = ""
	_check("then the trigger fires again", shots.size() == fanned + 1, "%d rounds" % shots.size())

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## A full cylinder, a clean slate.
func _load() -> void:
	mode = ""
	w._reloading = false # the last case may have run the cylinder dry
	w._cooldown = 0.0
	w.mag = w.data.mag_size
	shots.clear()
	hits.clear()

func _wait(seconds: float) -> void:
	var until := clock + seconds
	while clock < until:
		await get_tree().process_frame
