extends Node3D
## Probe: co-op INPUT (PlayerInput, stage 2 of local co-op). Two real players,
## co-op on with player one on keyboard + pad 0 and player two on pad 1:
## (1) pad 1's left stick walks player two and not player one; W walks player one
##     and not player two; pad 0's stick walks player one;
## (2) pad 1's A jumps player two only;
## (3) pad 1's right stick turns player two's view only;
## (4) an action only player one reads (flashlight on its pad button) does not
##     fire from pad 1;
## (5) reset_coop: back to one player, pad 1 drives player one again and no p2_
##     action is left.
##   godot --headless --path . --audio-driver Dummy res://tests/coop_input_probe.tscn

const PLAYER := "res://scenes/player/player.tscn"
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["OK  " if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

func _stick(device: int, axis: JoyAxis, v: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = v
	Input.parse_input_event(e)

func _button(device: int, b: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = b
	e.pressed = down
	Input.parse_input_event(e)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _player(index: int, pos: Vector3) -> CharacterBody3D:
	var p: CharacterBody3D = (load(PLAYER) as PackedScene).instantiate()
	p.set("player_index", index)
	add_child(p)
	p.global_position = pos
	return p

func _moved(p: Node3D, from: Vector3) -> float:
	return Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length()

func _run() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	PlayerInput.setup_coop(0, 1)
	GameState.set_state(GameState.State.PLAYING)
	var p1 := _player(0, Vector3(-5, 0.1, 0))
	var p2 := _player(1, Vector3(5, 0.1, 0))
	await _wait_game(0.6)

	# 1. Walking.
	var a1 := p1.global_position
	var a2 := p2.global_position
	_stick(1, JOY_AXIS_LEFT_Y, -1.0)
	await _wait_game(0.6)
	_stick(1, JOY_AXIS_LEFT_Y, 0.0)
	_check("pad 1 walks player two", _moved(p2, a2) > 1.0, "%.2f m" % _moved(p2, a2))
	_check("pad 1 does not walk player one", _moved(p1, a1) < 0.2, "%.2f m" % _moved(p1, a1))
	await _wait_game(0.4)
	a1 = p1.global_position
	a2 = p2.global_position
	_key(KEY_W, true)
	await _wait_game(0.6)
	_key(KEY_W, false)
	_check("W walks player one", _moved(p1, a1) > 1.0, "%.2f m" % _moved(p1, a1))
	_check("W does not walk player two", _moved(p2, a2) < 0.2, "%.2f m" % _moved(p2, a2))
	await _wait_game(0.4)
	a1 = p1.global_position
	a2 = p2.global_position
	_stick(0, JOY_AXIS_LEFT_Y, -1.0)
	await _wait_game(0.6)
	_stick(0, JOY_AXIS_LEFT_Y, 0.0)
	_check("pad 0 walks player one and not two", _moved(p1, a1) > 1.0 and _moved(p2, a2) < 0.2, "%.2f / %.2f m" % [_moved(p1, a1), _moved(p2, a2)])
	await _wait_game(0.4)

	# 2. Jumping.
	var y1 := p1.global_position.y
	var y2 := p2.global_position.y
	_button(1, JOY_BUTTON_A, true)
	await _wait_game(0.15)
	_button(1, JOY_BUTTON_A, false)
	await _wait_game(0.1)
	_check("pad 1's A jumps player two only", p2.global_position.y > y2 + 0.2 and p1.global_position.y < y1 + 0.05,
		"%.2f / %.2f" % [p2.global_position.y - y2, p1.global_position.y - y1])
	await _wait_game(1.0)

	# 3. Looking.
	var r1 := p1.rotation.y
	var r2 := p2.rotation.y
	_stick(1, JOY_AXIS_RIGHT_X, 1.0)
	await _wait_game(0.4)
	_stick(1, JOY_AXIS_RIGHT_X, 0.0)
	_check("pad 1's right stick turns player two only", absf(p2.rotation.y - r2) > 0.3 and absf(p1.rotation.y - r1) < 0.01,
		"%.2f / %.2f rad" % [p2.rotation.y - r2, p1.rotation.y - r1])

	# 4. Player one's own action from player two's pad.
	var lamp: Node = p1.find_child("Flashlight", true, false)
	var lamp_on := lamp != null and bool(lamp.get("visible"))
	(p1.get("input") as PlayerInput).act("flashlight") # player one has read it this level
	var pad_ev := InputEventJoypadButton.new()
	pad_ev.device = 1
	pad_ev.button_index = JOY_BUTTON_DPAD_UP
	pad_ev.pressed = true
	_check("player one's flashlight does not answer pad 1", not pad_ev.is_action_pressed("flashlight"))
	pad_ev.device = 0
	_check("it still answers pad 0", pad_ev.is_action_pressed("flashlight"))

	# 5. Back to one player.
	PlayerInput.reset_coop()
	var left := Array(InputMap.get_actions()).filter(func(a): return String(a).begins_with(PlayerInput.P2))
	_check("reset leaves no p2_ action", left.is_empty(), str(left))
	pad_ev.device = 1
	_check("after reset pad 1 drives player one's actions again", pad_ev.is_action_pressed("flashlight"))

	GameState.set_state(GameState.State.MENU)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
