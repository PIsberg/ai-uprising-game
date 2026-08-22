extends Node
## Headless gun-range playtest: loads the Armory range, takes over the player's
## weapon manager, and live-fires the hitscan arsenal at the range floor,
## measuring every shot's real angular deviation from the crosshair via the
## bullet-hole decals the shots punch. Verifies the whole accuracy model:
##   1. spread cone honoured (no shot lands outside the live cone)
##   2. bloom opens the cone over a mag dump (rifle)
##   3. cold first-shot accuracy is tighter than warm fire (rifle)
##   4. ADS is tighter than hip fire (pistol)
##   5. sniper ADS is pinpoint
##   6. shotgun pellet cone opens wide but stays bounded
##   7. recoil climbs then settles back (recoil_return)
##   godot --headless --path . res://tests/gun_range_probe.tscn

const AIM_DIST := 18.0        # aim at the range floor this far downrange
const DECAL_LIFT := 0.02      # _spawn_bullet_hole offsets decals off the surface

var _player: CharacterBody3D
var _cam: Camera3D
var _head: Node3D
var _wm: Node
var _ok := true

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Force max detail: bullet-mark decals (this probe's whole measurement
	# channel) are gated below MEDIUM detail (BulletMark.spawn), and a stale
	# local settings.cfg can otherwise leave a headless run on LOW. Same fix as
	# level_detail_probe.
	if has_node("/root/GraphicsSettings"):
		get_node("/root/GraphicsSettings").set_quality(2) # HIGH
	var lvl: Node = load("res://scenes/levels/level_range.tscn").instantiate()
	add_child(lvl)
	var hud := lvl.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait_game(0.6) # let the player land + settle
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("NO PLAYER"); print("RESULT FAIL"); get_tree().quit(); return
	if "hp" in _player and _player.hp:
		_player.hp.invulnerable = true
	_cam = _player.get("camera") as Camera3D
	_head = _player.get_node_or_null("Head") as Node3D
	_wm = _find_wm(_player)
	if _cam == null or _wm == null or _head == null:
		print("NO CAMERA/WM/HEAD"); print("RESULT FAIL"); get_tree().quit(); return

	await _test_rifle_bloom_and_cone()
	await _test_rifle_first_shot()
	await _test_pistol_ads_vs_hip()
	await _test_sniper_pinpoint()
	await _test_shotgun_cone()
	await _test_recoil_recovery()

	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

func _check(name: String, cond: bool, detail: String) -> void:
	print("%s %s (%s)" % ["ok  " if cond else "BAD ", name, detail])
	if not cond:
		_ok = false

# ---------- rig ----------

func _find_wm(root: Node) -> Node:
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if "current" in n and "weapons" in n:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

## Arm `path`, topped up, and wait out the draw timer. add_weapon only equips
## NEW guns — re-arming one already in the rack needs an explicit equip.
func _arm(path: String) -> Weapon:
	var ps := load(path) as PackedScene
	_wm.add_weapon(ps, true)
	if _wm.current == null or _wm.current.scene_file_path != path:
		for i in range(_wm.weapons.size()):
			if _wm.weapons[i].scene_file_path == path:
				_wm._equip(i)
				break
	await _wait_game(0.65) # equip_time 0.5 blocks firing
	var w: Weapon = _wm.current
	assert(w.scene_file_path == path)
	w.mag = w.eff_mag_size()
	w.reserve = w.data.reserve_max
	return w

## Point the camera level at the floor AIM_DIST out (small depression angle) and
## zero any recoil climb, so each shot leaves from an identical reference frame.
func _reset_aim() -> void:
	_player.rotation.y = 0.0
	if _head:
		var drop := atan2(_cam.global_position.y, AIM_DIST)
		_head.rotation = Vector3(-drop, 0, 0)
	_cam.rotation = Vector3.ZERO

func _clear_holes() -> void:
	for h in get_tree().get_nodes_in_group("bullet_hole"):
		h.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

## Angular deviation (deg) of each NEW bullet hole from `fwd` out of `origin`.
## Waits `seconds` of GAME time (fixed physics steps), NOT wall-clock.
##
## Every quantity this probe measures evolves on the game clock: bloom decay,
## the first_shot_delay re-arm, equip_time, recoil settle. A `create_timer` wait
## is wall-clock, and when a machine cannot hold the physics rate Godot clamps
## physics steps per frame so game time falls behind — meaning the gun was in a
## DIFFERENT state than the probe assumed, in proportion to how loaded the
## machine was. That is what made "pistol ADS tighter" fail in CI (hip=0.25°
## ads=0.19°, ratio 0.76) while the same assertion reads a rock-steady ~0.31 here
## over 5 runs, matching the designed aim_spread_mult of 0.3.
func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

func _new_hole_angles(before: Array, origin: Vector3, fwd: Vector3) -> Array[float]:
	var angles: Array[float] = []
	for h in get_tree().get_nodes_in_group("bullet_hole"):
		if before.has(h):
			continue
		var p := (h as Node3D).global_position - Vector3(0, DECAL_LIFT, 0)
		angles.append(rad_to_deg(fwd.angle_to((p - origin).normalized())))
	return angles

## Fire `shots` rounds one at a time (trigger released between), `gap` seconds
## apart, ADS per `aiming`, re-zeroing the camera before every shot. Returns the
## per-shot deviation angle of every decal punched (pellets give several).
func _fire_series(w: Weapon, shots: int, gap: float, aiming: bool) -> Array[float]:
	var all: Array[float] = []
	for i in shots:
		if all.size() > 24: # stay clear of the 36-decal recycle cap
			await _clear_holes()
		_reset_aim()
		await get_tree().physics_frame
		var before := get_tree().get_nodes_in_group("bullet_hole")
		var origin := _cam.global_position
		var fwd := -_cam.global_transform.basis.z
		w.mag = maxi(w.mag, 10)
		w.try_fire(true, aiming, _cam, _player)
		w.try_fire(false, aiming, _cam, _player)
		# The hit has to resolve in physics before its decal exists; one
		# process_frame was enough on a fast machine and could silently drop
		# shots on a slow one, thinning the sample the means are computed from.
		await get_tree().physics_frame
		await get_tree().process_frame
		all.append_array(_new_hole_angles(before, origin, fwd))
		await _wait_game(gap)
	return all

static func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()

static func _peak(a: Array[float]) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m

# ---------- tests ----------

## Rifle mag dump: every round inside the fully-bloomed cone; the back half of
## the mag measurably wider than the opening shots (bloom is real). Fired as
## true full-auto — trigger held every physics frame, cooldown sets the pace.
func _test_rifle_bloom_and_cone() -> void:
	var w: Weapon = await _arm("res://scenes/weapons/rifle.tscn")
	await _clear_holes()
	await _wait_game(0.7) # go in cold
	var angles: Array[float] = []
	var frames := 0
	while angles.size() < 24 and frames < 600:
		frames += 1
		_reset_aim()
		var before := get_tree().get_nodes_in_group("bullet_hole")
		var origin := _cam.global_position
		var fwd := -_cam.global_transform.basis.z
		w.mag = maxi(w.mag, 10)
		w.try_fire(true, false, _cam, _player)
		angles.append_array(_new_hole_angles(before, origin, fwd))
		await get_tree().physics_frame
	# Read the LIVE cone right at the end of the dump, before recovery kicks in
	# (bloom only starts decaying 0.1 s after the last shot). This is the
	# deterministic "bloom is real" gate: the old check compared the mean of two
	# 6-shot random samples (each deviation is randf() inside the cone), which
	# fails on an unlucky roll — it did exactly that on CI.
	var live_cone: float = w.spread_now(false, _player)
	var d: WeaponData = w.data
	var cone := d.spread_deg * d.bloom_max_mult + 0.3 # + decal-lift slack
	_check("rifle shots land", angles.size() >= 20, "decals=%d" % angles.size())
	_check("rifle cone bounded", _peak(angles) <= cone,
		"peak=%.2f° max=%.2f°" % [_peak(angles), cone])
	var early := _mean(angles.slice(1, 7)) # skip the cold first shot
	var late := _mean(angles.slice(angles.size() - 6))
	_check("rifle bloom opens", live_cone > d.spread_deg * 1.1,
		"live=%.2f° base=%.2f° (decal telemetry: early=%.2f° late=%.2f°)" % [
			live_cone, d.spread_deg, early, late])

## Cold single taps land tighter than the warm-fire average.
func _test_rifle_first_shot() -> void:
	var w: Weapon = await _arm("res://scenes/weapons/rifle.tscn")
	await _clear_holes()
	var cold: Array[float] = []
	for i in 6:
		await _wait_game(0.7) # > first_shot_delay re-arms the bonus
		var got := await _fire_series(w, 1, 0.0, false)
		cold.append_array(got)
	var d: WeaponData = w.data
	var bound := d.spread_deg * d.first_shot_mult + 0.15 # decal-lift measurement slack
	_check("rifle first-shot tight", _peak(cold) <= bound,
		"peak=%.2f° bound=%.2f°" % [_peak(cold), bound])

## ADS pistol groups measurably tighter than hip fire.
func _test_pistol_ads_vs_hip() -> void:
	var w: Weapon = await _arm("res://scenes/weapons/pistol.tscn")
	await _clear_holes()
	var hip := await _fire_series(w, 14, 0.25, false)
	await _clear_holes()
	var ads := await _fire_series(w, 14, 0.25, true)
	# n= is reported deliberately: these are MEANS, and a mean over a handful of
	# decals is not evidence. Require a real sample rather than quietly averaging
	# whatever survived.
	var enough := hip.size() >= 10 and ads.size() >= 10
	_check("pistol ADS tighter", enough and _mean(ads) < _mean(hip) * 0.75,
		"hip=%.2f°(n=%d) ads=%.2f°(n=%d) ratio=%.2f want<0.75%s" % [
			_mean(hip), hip.size(), _mean(ads), ads.size(),
			_mean(ads) / maxf(0.0001, _mean(hip)),
			"" if enough else "  SAMPLE TOO SMALL"])

## Sniper ADS: effectively pinpoint (spread 0.3° × aim 0.04 ≈ 0.012°).
func _test_sniper_pinpoint() -> void:
	var w: Weapon = await _arm("res://scenes/weapons/sniper.tscn")
	await _clear_holes()
	var angles := await _fire_series(w, 5, 1.2, true)
	_check("sniper pinpoint", angles.size() >= 4 and _peak(angles) <= 0.2,
		"peak=%.2f°" % _peak(angles))

## One shotgun blast: pellets spread into a real cone but never past it.
func _test_shotgun_cone() -> void:
	var w: Weapon = await _arm("res://scenes/weapons/shotgun.tscn")
	await _clear_holes()
	await _wait_game(0.6)
	var angles := await _fire_series(w, 2, 0.9, false)
	var d: WeaponData = w.data
	_check("shotgun pellets land", angles.size() >= 10, "decals=%d" % angles.size())
	_check("shotgun cone bounded", _peak(angles) <= d.spread_deg + 0.3,
		"peak=%.2f° max=%.2f°" % [_peak(angles), d.spread_deg])
	_check("shotgun cone opens", _peak(angles) >= d.spread_deg * 0.4,
		"peak=%.2f° want≥%.2f°" % [_peak(angles), d.spread_deg * 0.4])

## Recoil: a burst climbs the view, then the camera settles most of the way
## back on its own (recoil_return), instead of walking up permanently.
func _test_recoil_recovery() -> void:
	var w: Weapon = await _arm("res://scenes/weapons/rifle.tscn")
	_reset_aim()
	await get_tree().physics_frame
	var pitch0: float = _head.rotation.x
	var climbed := pitch0
	for i in 10:
		w.mag = maxi(w.mag, 10)
		w.try_fire(true, false, _cam, _player)
		climbed = maxf(climbed, _head.rotation.x)
		await _wait_game(1.05 / w.data.fire_rate)
	var peak_climb: float = climbed - pitch0
	_check("recoil climbs", peak_climb > deg_to_rad(1.0),
		"climb=%.2f°" % rad_to_deg(peak_climb))
	await _wait_game(1.3) # let recovery settle
	# By design the camera keeps (1 - recoil_return) of the total kick as
	# permanent drift the player owns; everything else must settle back.
	var residual: float = _head.rotation.x - pitch0
	var designed: float = (1.0 - w.data.recoil_return) * 10.0 * deg_to_rad(w.data.recoil_pitch)
	_check("recoil settles back", residual <= designed * 1.25 + deg_to_rad(0.1),
		"residual=%.2f° designed=%.2f°" % [rad_to_deg(residual), rad_to_deg(designed)])
