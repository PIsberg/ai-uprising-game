extends Node3D
## Probe: the SIEGE Chaingun's alt-fire, BRACE (WeaponData.AltMode.BRACE). The
## chaingun had no secondary fire (#496). BRACE is a stance, not a shot: hold
## the alt-fire button and the gun is planted. Through the real weapon scene,
## driven the way WeaponManager drives it, then through the real player:
##   - the chaingun's alt mode is BRACE and the HUD tag needs 1 round;
##   - the button alone fires nothing;
##   - trigger rounds from the hip fly in a cone over 2 degrees wide; with the
##     button held every round flies in BRACE_SPREAD_DEG, and it does not bloom;
##   - 30 braced rounds all land on a 0.5 m plate at 25 m, where 30 hip rounds
##     land fewer;
##   - bracing does not change the fire rate or the damage;
##   - Weapon.move_mult() is BRACE_MOVE while the button is held, 1 when it is
##     let go and 1 through a reload;
##   - the real player with the braced chaingun in hand moves at BRACE_MOVE of
##     its speed, and at full speed once the gun is put away with the button
##     still down.
## Timed on summed process deltas.
##   godot --headless --path . --audio-driver Dummy res://tests/brace_fire_probe.tscn

const GUN := "res://scenes/weapons/salvage_chaingun.tscn"

var ok := true
var w: Weapon
var cam: Camera3D
var alt := false
var trigger := false
var clock := 0.0
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
	# The order WeaponManager uses: trigger, then alt-fire.
	w.try_fire(trigger, false, cam, null)
	w.try_alt_fire(alt, delta, cam, null)

func _wait(sec: float) -> void:
	var until := clock + sec
	while clock < until:
		await get_tree().process_frame

func _load() -> void:
	trigger = false
	alt = false
	await _wait(0.8) # the bloom bleeds off
	w._reloading = false
	w._cooldown = 0.0
	w.mag = w.data.mag_size
	shots.clear()
	hits.clear()

## Hold the trigger until `n` rounds are out. Returns the seconds it took.
func _fire(n: int) -> float:
	var from := clock
	trigger = true
	while shots.size() < n and w.mag > 0 and clock - from < 10.0:
		await get_tree().process_frame
	trigger = false
	return clock - from

func _widest() -> float:
	var m := 0.0
	for s in shots:
		m = maxf(m, float(s[1]))
	return m

func _move(c: String) -> float:
	return float(w.call(c)) if w.has_method(c) else -1.0

func _run() -> void:
	GameState.reset_run()
	GameState.set_state(GameState.State.PLAYING)
	cam = Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 41.6, 0) # the weapon half runs 40 m above the player half
	var plate := StaticBody3D.new()
	plate.collision_layer = 4
	plate.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 4.0, 0.3)
	cs.shape = box
	plate.add_child(cs)
	var hp := Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1000000.0
	plate.add_child(hp)
	add_child(plate)
	plate.global_position = Vector3(0, 42.0, -25.0)
	hp.current_health = 1000000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void: hits.append(amount))
	var scene := (load(GUN) as PackedScene).instantiate()
	cam.add_child(scene)
	await get_tree().process_frame
	await get_tree().physics_frame
	w = scene as Weapon
	w.fired.connect(func(_w: Weapon) -> void: shots.append([clock, w.shot_spread_deg(false, null)]))
	var d := w.data
	var brace_deg: float = float(w.get("BRACE_SPREAD_DEG")) if w.get("BRACE_SPREAD_DEG") != null else -1.0
	var brace_move: float = float(w.get("BRACE_MOVE")) if w.get("BRACE_MOVE") != null else -1.0
	var mode_name: String = WeaponData.AltMode.keys()[int(d.alt_mode)]
	_check("the chaingun's alt mode is BRACE", mode_name == "BRACE", mode_name)
	_check("the HUD tag needs 1 round", int(w.alt_cost()) == 1, str(w.alt_cost()))
	_check("a braced round flies in 0.5 degrees and the feet move at 0.45", is_equal_approx(brace_deg, 0.5) and is_equal_approx(brace_move, 0.45), "%.2f deg, %.2f" % [brace_deg, brace_move])

	# The button alone.
	seed(11)
	await _load()
	alt = true
	await _wait(0.8)
	_check("the button alone fires nothing", shots.is_empty() and w.mag == d.mag_size, "%d rounds" % shots.size())
	_check("move_mult is BRACE_MOVE while the button is held", brace_move > 0.0 and is_equal_approx(_move("move_mult"), brace_move), "%.2f" % _move("move_mult"))
	alt = false
	await _wait(0.1)
	_check("and 1 once it is let go", is_equal_approx(_move("move_mult"), 1.0), "%.2f" % _move("move_mult"))

	# From the hip.
	await _load()
	var hip_time := await _fire(30)
	await _wait(0.2)
	var hip_hits := hits.size()
	var hip_wide := _widest()
	_check("hip rounds fly in a cone over 2 degrees wide", shots.size() == 30 and float(shots[0][1]) > 2.0, "%.2f to %.2f deg" % [float(shots[0][1]) if not shots.is_empty() else 0.0, hip_wide])

	# Braced.
	await _load()
	alt = true
	await _wait(0.1)
	var brace_time := await _fire(30)
	await _wait(0.2)
	var every := shots.size() == 30
	for s in shots:
		if not is_equal_approx(float(s[1]), brace_deg):
			every = false
	_check("every braced round flies in BRACE_SPREAD_DEG, bloom or not", every, "%d rounds, widest %.2f deg (hip reached %.2f)" % [shots.size(), _widest(), hip_wide])
	_check("30 braced rounds all land on a 0.5 m plate at 25 m", hits.size() == 30, "%d hits" % hits.size())
	_check("30 hip rounds land fewer", hip_hits < hits.size(), "%d hits" % hip_hits)
	_check("bracing does not change the fire rate", absf(brace_time - hip_time) < 0.12, "%.2f s braced, %.2f s from the hip" % [brace_time, hip_time])
	var full := not hits.is_empty()
	for h in hits:
		if absf(float(h) - d.damage) > 0.5:
			full = false
	_check("or the damage", full, "%s against %.0f" % [str(hits.slice(0, 2)), d.damage])

	# A reload takes the brace off.
	w._reloading = true
	w._reload_timer = 5.0 # or the weapon ends the reload on its next tick
	await _wait(0.1)
	_check("move_mult is 1 through a reload, button held", is_equal_approx(_move("move_mult"), 1.0), "%.2f" % _move("move_mult"))
	w._reloading = false
	w._reload_timer = 0.0
	alt = false
	w.queue_free()
	w = null
	await _wait(0.1)

	# The real player.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(40, 1, 40)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.2, 0)
	for i in 4:
		await get_tree().process_frame
	var wm := player.get_node_or_null("Head/Camera3D/WeaponHolder") as WeaponManager
	wm.add_weapon(load(GUN) as PackedScene)
	var gun: Weapon = null
	for i in wm.weapons.size():
		if wm.weapons[i].scene_file_path == GUN:
			wm._equip(i)
			gun = wm.weapons[i]
	await _wait(0.8) # the draw
	var free_speed: float = player.call("_current_speed")
	_check("the chaingun is in the player's hand", gun != null and wm.current == gun, str(wm.current))
	Input.action_press("alt_fire")
	await _wait(0.3)
	var braced_speed: float = player.call("_current_speed")
	_check("the player with the braced chaingun moves at BRACE_MOVE of its speed", free_speed > 1.0 and absf(braced_speed - free_speed * brace_move) < 0.01, "%.2f against %.2f free" % [braced_speed, free_speed])
	# Put it away with the button still down: the stance stays with the gun.
	for i in wm.weapons.size():
		if wm.weapons[i] != gun:
			wm._equip(i)
			break
	await _wait(0.8)
	var away_speed: float = player.call("_current_speed")
	_check("and at full speed with the gun put away, button still down", wm.current != gun and absf(away_speed - free_speed) < 0.01, "%.2f against %.2f" % [away_speed, free_speed])
	Input.action_release("alt_fire")

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
