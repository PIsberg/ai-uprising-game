extends Node3D
## Probe: the trigger finger pulls when the player pulls the trigger. On the real
## player, for a SEMI gun (pistol), an AUTO gun (rifle) and the BEAM gun (tesla):
##   - holding the trigger curls the index finger back through the guard: its
##     tip moves at least PULL_BACK toward the palm (+z) and down, in the
##     trigger hand's own space, and stays back for as long as it is held;
##   - letting go puts the finger back where it rested;
##   - a one-frame tap still shows: the finger reaches most of its full pull;
##   - during a reload the finger stays off the trigger: holding fire moves it
##     at most REST_TOL.
##   godot --headless --path . --audio-driver Dummy res://tests/trigger_pull_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const GUNS := ["pistol", "rifle", "tesla"]
const PULL_BACK := 0.004 ## metres the tip must travel toward the palm
const REST_TOL := 0.001

var ok := true
var _cam: Camera3D
var _player: CharacterBody3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(60, 1, 60)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 1.0, 0)
	for i in 10:
		await get_tree().physics_frame
	_player.set_physics_process(false)
	_cam = _player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = _player.get_node("Head/Camera3D/WeaponHolder")
	# The manager would call try_fire(false) every frame and undo the held trigger.
	wm.set_process(false)
	wm.set_physics_process(false)
	for id: String in GUNS:
		await _gun_check(wm, id)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _gun_check(wm: Node, id: String) -> void:
	var w := _equip(wm, "res://scenes/weapons/%s.tscn" % id)
	w.mag = w.eff_mag_size()
	w.reserve = maxi(w.reserve, w.eff_mag_size() * 2)
	for i in 5:
		await get_tree().process_frame
	if w.hands == null or w.hands.trigger_tip == null:
		_check("%s has a trigger finger" % id, false)
		return
	var rest := _tip(w)
	# Held: sample every frame for 0.4 s once the finger has had 0.1 s to get there.
	var t := 0.0
	var max_back := 0.0
	var min_back := INF
	var down := 0.0
	while t < 0.5:
		w.try_fire(true, false, _cam, _player)
		await get_tree().process_frame
		t += get_process_delta_time()
		var d := _tip(w) - rest
		if t > 0.1:
			max_back = maxf(max_back, d.z)
			min_back = minf(min_back, d.z)
			down = maxf(down, -d.y)
	_check("%s holding the trigger pulls the finger back" % id, max_back >= PULL_BACK and down > 0.0,
			"back %.4f m, down %.4f m" % [max_back, down])
	_check("%s the finger stays back while the trigger is held" % id, min_back >= max_back * 0.8,
			"min %.4f of max %.4f" % [min_back, max_back])
	await _release(w, 0.4)
	_check("%s letting go puts the finger back" % id, _tip(w).distance_to(rest) < REST_TOL,
			"%.4f m off rest" % _tip(w).distance_to(rest))
	# One-frame tap.
	w._cooldown = 0.0
	w.try_fire(true, false, _cam, _player)
	var tap := 0.0
	t = 0.0
	while t < 0.3:
		await get_tree().process_frame
		t += get_process_delta_time()
		w.try_fire(false, false, _cam, _player)
		tap = maxf(tap, (_tip(w) - rest).z)
	_check("%s a one-frame tap still shows the pull" % id, tap >= max_back * 0.8,
			"tap %.4f of full %.4f" % [tap, max_back])
	await _release(w, 0.3)
	# Reloading: finger off the trigger.
	w.mag = 0
	w.start_reload()
	var moved := 0.0
	t = 0.0
	while t < 0.25 and w._reloading:
		w.try_fire(true, false, _cam, _player)
		await get_tree().process_frame
		t += get_process_delta_time()
		moved = maxf(moved, _tip(w).distance_to(rest))
	_check("%s the finger stays off the trigger during a reload" % id, moved < REST_TOL,
			"moved %.4f m" % moved)

func _release(w: Weapon, secs: float) -> void:
	var t := 0.0
	while t < secs:
		w.try_fire(false, false, _cam, _player)
		await get_tree().process_frame
		t += get_process_delta_time()

## The finger tip in the trigger hand's own space (unscaled by the hand's size).
func _tip(w: Weapon) -> Vector3:
	return w.hands.trigger_hand.to_local(w.hands.trigger_tip.global_position)

func _equip(wm: Node, p: String) -> Weapon:
	for i in wm.weapons.size():
		if (wm.weapons[i] as Weapon).scene_file_path == p:
			wm._equip(i)
			return wm.weapons[i]
	wm.add_weapon(load(p), false)
	return _equip(wm, p)
