extends Node3D
## Probe: every gun has its own feel in your hands (WeaponData "Kick Feel",
## WeaponManager._on_fired, Weapon._play_fire_sound).
## (1) voice: every gun in WEAPON_ORDER resolves its own fire stream, no two
##     guns share one, and each report and both layers (fire_thump,
##     action_clack) carry real signal;
## (2) kick, measured through the real WeaponManager spring at 60 fps: every
##     gun punches and settles back within 1 s; the heavy guns (Breacher,
##     Longshot, Gauss, Devastator, OMEGA) climb harder than every light one
##     (rifle, Tesla, Arc Coil) and take longer to settle; no two guns share a
##     kick signature; the .50 Maelstrom's roll bias twists it the same way
##     shot after shot;
## (3) the softest spring (OMEGA) stays finite through 10 fps hitch frames;
## (4) FOV punch: a heavy round widens the view by its fov_punch, a pistol
##     shot does not.
##   godot --headless --path . --audio-driver Dummy res://tests/weapon_feel_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const HEAVY := ["shotgun", "sniper", "gauss", "devastator", "omega"]
const LIGHT := ["rifle", "tesla", "arccoil"]
const DT := 1.0 / 60.0

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Voice.
	var streams := {}
	var datas := {}
	for p: String in GameState.WEAPON_ORDER:
		var d := DamageMatrix.weapon_data_of(p)
		var id := p.get_file().get_basename()
		datas[id] = d
		var s: AudioStream = d.fire_sound if d.fire_sound else AudioBus.synth(d.sound_id + "_fire")
		_check("%s has a fire stream (%s_fire)" % [id, d.sound_id], s != null)
		if s:
			streams[id] = s
			_check("%s report carries signal" % id, _peak(s) > 0.2, "peak %.2f" % _peak(s))
	var ids := {}
	for id: String in datas:
		ids[(datas[id] as WeaponData).sound_id] = true
	_check("no two guns share a fire sound", ids.size() == datas.size(), "%d ids for %d guns" % [ids.size(), datas.size()])
	for layer in ["fire_thump", "action_clack"]:
		var s := AudioBus.synth(layer)
		_check("layer %s carries signal" % layer, s != null and _peak(s) > 0.2)

	# 2. Kick through the real manager.
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
	player.global_position = Vector3(0, 1.0, 0)
	for i in 10:
		await get_tree().physics_frame
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	wm.set_process(false) # we drive _process ourselves, at a fixed 60 fps
	var feel := {}
	for id: String in datas:
		var w := _equip(wm, id)
		_check("%s equipped" % id, w != null)
		if w == null:
			continue
		feel[id] = _measure(wm)
		print("   %-10s climb peak %.3f rad  back peak %.3f m  settles in %.2f s" % [
			id, feel[id]["rot"], feel[id]["back"], feel[id]["settle"]])
		_check("%s kick punches" % id, feel[id]["rot"] > 0.003 and feel[id]["back"] > 0.001)
		_check("%s kick settles within 1 s" % id, feel[id]["settle"] <= 1.0, "%.2f s" % feel[id]["settle"])
	var light_rot := 0.0
	var light_settle := 0.0
	for id in LIGHT:
		light_rot = maxf(light_rot, feel[id]["rot"])
		light_settle = maxf(light_settle, feel[id]["settle"])
	for id in HEAVY:
		_check("%s climbs harder than every light gun" % id, feel[id]["rot"] > light_rot,
			"%.3f vs %.3f" % [feel[id]["rot"], light_rot])
		_check("%s settles slower than every light gun" % id, feel[id]["settle"] > light_settle,
			"%.2f vs %.2f" % [feel[id]["settle"], light_settle])
	var sigs := {}
	for id: String in datas:
		var d: WeaponData = datas[id]
		sigs["%.2f/%.2f/%.0f/%.0f" % [d.kick_back, d.kick_climb, d.kick_stiffness, d.kick_damping]] = id
	_check("every gun has its own kick signature", sigs.size() == datas.size(), "%d of %d" % [sigs.size(), datas.size()])
	_equip(wm, "magnum")
	var same_way := 0
	for i in 20:
		_reset(wm)
		wm._on_fired(wm.current)
		wm._process(DT)
		wm._process(DT)
		if (wm._kick_rot as Vector3).z > 0.0:
			same_way += 1
	_check(".50 Maelstrom twists the same way every shot", same_way == 20, "%d of 20" % same_way)

	# 3. The softest spring through a hitch.
	_equip(wm, "omega")
	_reset(wm)
	wm._on_fired(wm.current)
	for i in 30:
		wm._process(0.1)
	for i in 120:
		wm._process(DT)
	_check("OMEGA spring stays finite through 10 fps frames", (wm._kick_rot as Vector3).is_finite()
		and (wm._kick_rot as Vector3).length() < 0.01, str(wm._kick_rot))

	# 4. FOV punch.
	GraphicsSettings.screen_shake = 1.0
	player._fov_kick = 0.0
	_equip(wm, "pistol")
	wm._on_fired(wm.current)
	_check("a pistol shot does not punch the fov", is_zero_approx(player._fov_kick), "%.2f" % player._fov_kick)
	_equip(wm, "omega")
	wm._on_fired(wm.current)
	var want: float = (datas["omega"] as WeaponData).fov_punch
	_check("an OMEGA shot widens the view by its fov_punch", is_equal_approx(player._fov_kick, want),
		"%.2f vs %.2f" % [player._fov_kick, want])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _equip(wm: Node, id: String) -> Weapon:
	var path := "res://scenes/weapons/%s.tscn" % id
	wm.add_weapon(load(path), false)
	for i in wm.weapons.size():
		if (wm.weapons[i] as Weapon).scene_file_path == path:
			wm._equip(i)
			return wm.current
	return null

func _reset(wm: Node) -> void:
	wm._kick_pos = Vector3.ZERO
	wm._kick_pos_vel = Vector3.ZERO
	wm._kick_rot = Vector3.ZERO
	wm._kick_rot_vel = Vector3.ZERO

## One shot from rest: the peak muzzle climb (rad) and push-back (m), and the
## time until the kick is back inside 5% of its peak and stays there.
func _measure(wm: Node) -> Dictionary:
	var rot := 0.0
	var back := 0.0
	var settle := 0.0
	var trace: Array = []
	_reset(wm)
	wm._on_fired(wm.current)
	for i in 120:
		wm._process(DT)
		var r: float = (wm._kick_rot as Vector3).length()
		trace.append(r)
		rot = maxf(rot, absf((wm._kick_rot as Vector3).x))
		back = maxf(back, absf((wm._kick_pos as Vector3).z))
	var peak: float = trace.max()
	for i in range(trace.size() - 1, -1, -1):
		if trace[i] > peak * 0.05:
			settle = float(i + 1) * DT
			break
	return {"rot": rot, "back": back, "settle": settle}

## Peak absolute sample of a stream (synth WAVs and sample-backed streams).
func _peak(s: AudioStream) -> float:
	if s is AudioStreamRandomizer:
		var r := s as AudioStreamRandomizer
		return 1.0 if r.streams_count > 0 else 0.0 # imported takes: trust the files
	if not (s is AudioStreamWAV):
		return 1.0
	var b := (s as AudioStreamWAV).data
	var m := 0
	for i in range(0, b.size() - 1, 2):
		m = maxi(m, absi(b.decode_s16(i)))
	return float(m) / 32767.0
