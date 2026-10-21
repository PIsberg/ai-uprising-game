extends Node3D
## Toggle Aim / Toggle Sprint / Toggle Crouch (accessibility: no sustained holds).
##   - PlayerInput: with a toggle on, a press latches the action on through its
##     release and the next press latches it off; with it off, pressed() follows
##     the button; release() drops a latch; each PlayerInput latches on its own;
##   - on the real player: a tapped sprint runs (faster than walk_speed) with the
##     key up, and stopping drops it, so the next walk is a walk; a tapped crouch
##     stays crouched until tapped again; a tapped aim brings the gun to full ADS
##     and the HUD's crosshair closes to the aimed cone with the button up;
##   - the settings persist (settings_roundtrip_probe covers the save/load) and
##     reach PlayerInput through GraphicsSettings.
## Restores the player's settings.
##   godot --headless --path . --audio-driver Dummy res://tests/toggle_input_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

var _fail: Array[String] = []

func _check(cond: bool, label: String, detail: String = "") -> void:
	print(("  ok   " if cond else "  FAIL ") + label + ("  (" + detail + ")" if detail != "" else ""))
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _tap(action: String) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)
	await _frames(3)

func _run() -> void:
	var orig := [GraphicsSettings.toggle_aim, GraphicsSettings.toggle_sprint, GraphicsSettings.toggle_crouch]

	# --- PlayerInput latch.
	GraphicsSettings.set_toggle_aim(false)
	var pi := PlayerInput.new()
	Input.action_press("aim")
	var held := pi.pressed("aim")
	Input.action_release("aim")
	_check(held and not pi.pressed("aim"), "toggle off: aim follows the button")
	GraphicsSettings.set_toggle_aim(true)
	Input.action_press("aim")
	var a := pi.pressed("aim")
	Input.action_release("aim")
	var b := pi.pressed("aim")
	Input.action_press("aim")
	var c := pi.pressed("aim")
	Input.action_release("aim")
	var d := pi.pressed("aim")
	_check(a and b and not c and not d, "toggle on: press latches on through the release, next press latches off",
			"%s %s %s %s" % [a, b, c, d])
	Input.action_press("aim")
	pi.pressed("aim")
	Input.action_release("aim")
	var other := PlayerInput.new()
	_check(pi.pressed("aim") and not other.pressed("aim"), "each PlayerInput latches on its own")
	pi.release("aim")
	_check(not pi.pressed("aim"), "release() drops a latch")

	# --- Real player.
	GraphicsSettings.set_toggle_sprint(true)
	GraphicsSettings.set_toggle_crouch(true)
	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	await _frames(20)

	Input.action_press("move_forward")
	await _tap("sprint")
	await _frames(60)
	var run_speed := Vector2(player.velocity.x, player.velocity.z).length()
	_check(run_speed > player.walk_speed + 1.0, "a tapped sprint runs with the key up",
			"%.2f m/s (walk %.1f)" % [run_speed, player.walk_speed])
	Input.action_release("move_forward")
	await _frames(40)
	Input.action_press("move_forward")
	await _frames(60)
	var walk := Vector2(player.velocity.x, player.velocity.z).length()
	_check(walk <= player.walk_speed + 0.1, "stopping drops the sprint: the next walk is a walk", "%.2f m/s" % walk)
	Input.action_release("move_forward")
	await _frames(30)

	await _tap("crouch")
	await _frames(30)
	var crouched := bool(player.get("_is_crouching"))
	await _tap("crouch")
	await _frames(30)
	_check(crouched and not bool(player.get("_is_crouching")), "a tapped crouch holds until tapped again",
			"after 1st tap %s, after 2nd %s" % [crouched, player.get("_is_crouching")])

	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	await _tap("aim")
	await _frames(60)
	var ads: float = wm.get("_current_ads_lerp")
	_check(ads > 0.95, "a tapped aim holds full ADS with the button up", "ads %.2f" % ads)
	var w: Weapon = wm.current
	if w:
		_check(player.input.pressed("aim") and w.spread_now(player.input.pressed("aim"), player) < w.spread_now(false, player),
				"the aimed cone (what the crosshair draws) is tighter than hip")
	var hud := preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	await _frames(5)
	_check(hud.aim_held(), "the HUD reads aim through the player's input, so the crosshair closes")
	await _tap("aim")
	await _frames(60)
	_check(float(wm.get("_current_ads_lerp")) < 0.05 and not hud.aim_held(), "a second tap drops ADS")

	GraphicsSettings.set_toggle_aim(orig[0])
	GraphicsSettings.set_toggle_sprint(orig[1])
	GraphicsSettings.set_toggle_crouch(orig[2])
	print("RESULT %s" % ("PASS" if _fail.is_empty() else "FAIL"))
	get_tree().quit(0 if _fail.is_empty() else 1)
