extends Node3D
## Probe: a player standing still breathes; the gun in their hands is never
## frozen dead in place (WeaponManager idle breathing). With the real player
## standing on a floor and no input:
##   - the WeaponHolder drifts: its vertical travel over 4 s is between MIN_MM
##     and MAX_MM (alive, but a breath, not a bob) and it pitches a little;
##   - aiming steadies it to at most ADS_SHARE of that;
##   - winded (stamina at 0) it breathes at least WINDED_GAIN times as hard,
##     and settles back once stamina is full again.
##   godot --headless --path . --audio-driver Dummy res://tests/idle_breath_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MIN_MM := 2.0
const MAX_MM := 12.0
const ADS_SHARE := 0.35
const WINDED_GAIN := 1.5

var ok := true

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
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.2, 0)
	GameState.set_state(GameState.State.PLAYING)
	var wm: Node3D = player.get_node("Head/Camera3D/WeaponHolder")
	await _wait(1.5) # land and settle the draw
	var rest := await _travel(wm, 4.0)
	print("   rested: %.1f mm vertical, %.2f deg pitch" % [rest.x, rest.y])
	_check("a standing player's gun drifts (%.0f-%.0f mm)" % [MIN_MM, MAX_MM], rest.x >= MIN_MM and rest.x <= MAX_MM, "%.1f mm" % rest.x)
	_check("it pitches with the breath", rest.y > 0.05, "%.2f deg" % rest.y)
	Input.action_press("aim")
	await _wait(0.6)
	var ads := await _travel(wm, 4.0)
	Input.action_release("aim")
	print("   aiming: %.1f mm" % ads.x)
	_check("aiming steadies it (<= %.0f%% of rested)" % (ADS_SHARE * 100.0), ads.x <= rest.x * ADS_SHARE, "%.1f mm" % ads.x)
	await _wait(0.6)
	player.stamina_changed.emit(0.0, player.max_stamina, true)
	await _wait(0.8)
	var winded := await _travel(wm, 4.0)
	print("   winded: %.1f mm" % winded.x)
	_check("winded it breathes harder (>= %.1fx)" % WINDED_GAIN, winded.x >= rest.x * WINDED_GAIN, "%.1f mm" % winded.x)
	player.stamina_changed.emit(player.max_stamina, player.max_stamina, false)
	await _wait(2.5)
	var again := await _travel(wm, 4.0)
	_check("rested again it settles back", again.x < winded.x * 0.8, "%.1f mm" % again.x)
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().create_timer(0.1).timeout

## Peak-to-peak vertical travel (mm) and pitch range (deg) of `n` over `secs`.
func _travel(n: Node3D, secs: float) -> Vector2:
	var y_lo := INF
	var y_hi := -INF
	var p_lo := INF
	var p_hi := -INF
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		y_lo = minf(y_lo, n.position.y)
		y_hi = maxf(y_hi, n.position.y)
		p_lo = minf(p_lo, n.rotation.x)
		p_hi = maxf(p_hi, n.rotation.x)
		await get_tree().process_frame
	return Vector2((y_hi - y_lo) * 1000.0, rad_to_deg(p_hi - p_lo))
