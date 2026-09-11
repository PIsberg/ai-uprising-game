extends Node3D
## Ground-truth combat damage math: fires REAL shots from a real Weapon at REAL
## android enemies and reads the damage actually recorded by their Damageable
## node (via the `damaged` signal) -- never derives a number purely from the
## .tres fields. "Expected" values below apply the same formula the game runs
## (scripts/weapons/weapon.gd `_range_mult` ~line 34, hit block ~595-620:
## final_damage = eff_damage() * _range_mult(dist) * max(headshot_mult, weak_mult),
## then pierce) to a distance that is itself MEASURED with a physics raycast --
## not assumed from spawn position -- so capsule-collider offsets do not skew
## the comparison.
##
##   1. RANGE FALLOFF (rifle): mid-band = full damage, near range_m = far_mult,
##      point-blank = close_mult, plus a range_falloff=false control that must
##      give identical damage near and far.
##   2. HEADSHOT (rifle): a shot at the eye deals body_damage * headshot_mult
##      and is reported as a crit (GameState.player_dealt_damage); a body shot
##      is not.
##   3. PIERCE (gauss, pierce=3 as shipped): one shot through two enemies lined
##      up on the aim ray damages BOTH; the same shot with a pierce=0 twin only
##      damages the first.
##
##   godot --headless --path . --audio-driver Dummy res://tests/damage_math_probe.tscn

const REF_ENEMY := "res://scenes/enemies/android.tscn"
const RIFLE := "res://scenes/weapons/rifle.tscn"
const GAUSS := "res://scenes/weapons/gauss.tscn"
const TOL_REL := 0.03   # +-3%
const TOL_ABS := 1.0    # or +-1 damage point, whichever is looser

var _cam: Camera3D
var _shooter: Node3D
var _ok := true
var _last_crit := false
var _dealt_conn: Callable

func _ready() -> void:
	_run.call_deferred()

func _check(cond: bool, label: String) -> void:
	print("%s %s" % ["ok  " if cond else "BAD ", label])
	if not cond:
		_ok = false

func _close_enough(measured: float, expected: float) -> bool:
	var tol: float = maxf(TOL_ABS, absf(expected) * TOL_REL)
	return absf(measured - expected) <= tol

func _run() -> void:
	GameState.current_state = GameState.State.PLAYING
	# A floor per project convention, parked well clear of the horizontal
	# firing lane -- targets spawn with physics/process disabled so they never
	# fall, but this keeps the rig honest if that ever changes.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(400, 2, 400)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -50, 0)
	add_child(floor_body)
	add_child(DirectionalLight3D.new())

	_shooter = Node3D.new()
	_shooter.add_to_group("player") # Damageable only reports crit via GameState for player-sourced hits
	add_child(_shooter)
	_cam = Camera3D.new()
	_cam.current = true
	add_child(_cam)
	_dealt_conn = func(_a, _p, _k, crit): _last_crit = crit
	GameState.player_dealt_damage.connect(_dealt_conn)
	await get_tree().physics_frame

	print("=== 1. RANGE FALLOFF (rifle) ===")
	await _test_range_falloff()

	print("=== 2. HEADSHOT (rifle) ===")
	await _test_headshot()

	print("=== 3. PIERCE (gauss) ===")
	await _test_pierce()

	if GameState.player_dealt_damage.is_connected(_dealt_conn):
		GameState.player_dealt_damage.disconnect(_dealt_conn)
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

# ---------- rig ----------

## Same formula as Weapon._range_mult (private, so re-declared here) -- applied
## to a distance MEASURED by raycast, not assumed from spawn position.
func _range_mult_formula(data: WeaponData, dist: float) -> float:
	if not data.range_falloff:
		return 1.0
	if dist <= data.opt_min:
		var t: float = 1.0 if data.opt_min <= 0.0 else clampf(dist / data.opt_min, 0.0, 1.0)
		return lerpf(data.close_mult, 1.0, t)
	if dist >= data.opt_max:
		var span: float = maxf(0.001, data.range_m - data.opt_max)
		var t2: float = clampf((dist - data.opt_max) / span, 0.0, 1.0)
		return lerpf(1.0, data.far_mult, t2)
	return 1.0

## Same query Weapon._do_hitscan runs (world+enemy mask), capped at the
## weapon own range_m so a target beyond real reach does not read as a hit.
func _raycast_dist(origin: Vector3, dir: Vector3, max_range: float) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range)
	q.collision_mask = 0b0000101 # world + enemy
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1.0
	return origin.distance_to(hit.position)

## Loads a weapon SCENE (not just the script) so muzzle/viewmodel wiring is
## real, duplicates its WeaponData so edits never touch the shared .tres, and
## zeroes spread so every shot goes exactly down the camera axis.
func _weapon(scene_path: String, overrides: Dictionary = {}) -> Weapon:
	var w: Weapon = (load(scene_path) as PackedScene).instantiate()
	add_child(w)
	w.data = w.data.duplicate(true)
	w.data.spread_deg = 0.0
	for k in overrides:
		w.data.set(k, overrides[k])
	w.mag = 20
	w.reserve = 200
	await get_tree().physics_frame
	return w

## A frozen android: real collider + "enemy" group (so is_headshot/pierce see
## it), huge HP so nothing dies mid-probe, damage tallied off the `damaged`
## signal (a dict, so the closure below mutates state the caller can read).
func _spawn_target(pos: Vector3) -> Dictionary:
	var e: Node3D = (load(REF_ENEMY) as PackedScene).instantiate()
	e.position = pos
	add_child(e)
	e.set_physics_process(false)
	e.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hp: Node = e.get_node_or_null("Damageable")
	hp.invulnerable = false
	hp.max_health = 1000000.0
	hp.current_health = 1000000.0
	var rec := {"amt": 0.0, "hits": 0}
	hp.damaged.connect(func(amount: float, _src): rec.amt += amount; rec.hits += 1)
	return {"node": e, "hp": hp, "rec": rec}

func _cleanup(t: Dictionary) -> void:
	if is_instance_valid(t["node"]):
		(t["node"] as Node).queue_free()
	await get_tree().physics_frame

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()

## Fires exactly one shot (press then release -- AUTO/SEMI both land one round
## this way) and lets the hit resolve. Hitscan damage is applied synchronously
## inside try_fire itself; the extra frames are slack for FX/signal fan-out.
func _fire_once_raw(w: Weapon) -> void:
	_last_crit = false
	w.mag = maxi(w.mag, 4)
	w.try_fire(true, false, _cam, _shooter)
	w.try_fire(false, false, _cam, _shooter)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _wait_game(0.1)

func _fire_single(w: Weapon, rec: Dictionary) -> void:
	rec.amt = 0.0
	rec.hits = 0
	await _fire_once_raw(w)

# ---------- 1. range falloff ----------

func _test_range_falloff() -> void:
	var w: Weapon = await _weapon(RIFLE)
	var d: WeaponData = w.data
	_cam.global_position = Vector3(0, 0.9, 0) # android capsule cylindrical mid-height
	_cam.rotation = Vector3.ZERO
	var dir := Vector3(0, 0, -1)

	var cases := [
		{"label": "mid-band (inside opt window)", "spawn": 20.0},
		{"label": "far (~range_m-0.5)", "spawn": d.range_m - 0.5 + 0.32},
		{"label": "point-blank", "spawn": 0.5},
	]
	print("%-28s %8s %9s %9s %7s" % ["case", "hitDist", "measured", "expected", "mult"])
	for c in cases:
		var t: Dictionary = await _spawn_target(Vector3(0, 0, -float(c["spawn"])))
		var hit_dist: float = _raycast_dist(_cam.global_position, dir, d.range_m)
		_check(hit_dist > 0.0, "%s: shot reaches the target (hitDist=%.2f)" % [c["label"], hit_dist])
		var mult: float = _range_mult_formula(d, maxf(0.0, hit_dist))
		var expected: float = w.eff_damage() * mult
		await _fire_single(w, t["rec"])
		var measured: float = t["rec"]["amt"]
		print("%-28s %8.2f %9.1f %9.1f %7.3f" % [c["label"], hit_dist, measured, expected, mult])
		_check(_close_enough(measured, expected),
			"%s: dmg %.1f ~= expected %.1f (tol +-%.0f%%/+-1)" % [c["label"], measured, expected, TOL_REL * 100.0])
		await _cleanup(t)

	# control: range_falloff = false must give identical damage near and far
	var w2: Weapon = await _weapon(RIFLE, {"range_falloff": false})
	var near_t: Dictionary = await _spawn_target(Vector3(0, 0, -6.0))
	await _fire_single(w2, near_t["rec"])
	var near_dmg: float = near_t["rec"]["amt"]
	await _cleanup(near_t)
	var far_t: Dictionary = await _spawn_target(Vector3(0, 0, -40.0))
	await _fire_single(w2, far_t["rec"])
	var far_dmg: float = far_t["rec"]["amt"]
	await _cleanup(far_t)
	print("%-28s near=%.1f far=%.1f  (eff_damage=%.1f)" % ["range_falloff=false control", near_dmg, far_dmg, w2.eff_damage()])
	_check(_close_enough(near_dmg, far_dmg),
		"range_falloff=false: near dmg ~= far dmg (%.1f vs %.1f)" % [near_dmg, far_dmg])
	_check(_close_enough(near_dmg, w2.eff_damage()),
		"range_falloff=false: dmg == eff_damage() regardless of range (%.1f vs %.1f)" % [near_dmg, w2.eff_damage()])

# ---------- 2. headshot ----------

func _test_headshot() -> void:
	var w: Weapon = await _weapon(RIFLE)
	var d: WeaponData = w.data
	var dist := 15.0 # well inside rifle [opt_min, opt_max] -- range_mult is 1.0 for both shots
	var t: Dictionary = await _spawn_target(Vector3(0, 0, -dist))
	var e: Node = t["node"]
	var eye: Node3D = e.get("eye")
	_check(eye != null, "target exposes an eye marker for is_headshot")
	_cam.global_position = Vector3(0, 0.9, 0)

	_cam.look_at(Vector3(0, 0.9, -dist), Vector3.UP)
	await _fire_single(w, t["rec"])
	var body_dmg: float = t["rec"]["amt"]
	var body_crit := _last_crit

	_cam.look_at(eye.global_position, Vector3.UP)
	await _fire_single(w, t["rec"])
	var head_dmg: float = t["rec"]["amt"]
	var head_crit := _last_crit

	var expected_body: float = w.eff_damage()
	var expected_head: float = w.eff_damage() * d.headshot_mult
	print("%-28s %9s %9s %6s" % ["case", "measured", "expected", "crit"])
	print("%-28s %9.1f %9.1f %6s" % ["body shot", body_dmg, expected_body, body_crit])
	print("%-28s %9.1f %9.1f %6s" % ["head shot", head_dmg, expected_head, head_crit])
	_check(_close_enough(body_dmg, expected_body),
		"body dmg ~= eff_damage() (%.1f vs %.1f)" % [body_dmg, expected_body])
	_check(_close_enough(head_dmg, expected_head),
		"head dmg ~= body x headshot_mult %.1f (%.1f vs %.1f)" % [d.headshot_mult, head_dmg, expected_head])
	_check(not body_crit, "body shot NOT reported as a crit")
	_check(head_crit, "head shot IS reported as a crit (GameState.player_dealt_damage)")
	await _cleanup(t)

# ---------- 3. pierce ----------

func _test_pierce() -> void:
	var w_pierce: Weapon = await _weapon(GAUSS)
	_check(w_pierce.data.pierce >= 1, "gauss ships with pierce >= 1 (pierce=%d)" % w_pierce.data.pierce)
	_cam.global_position = Vector3(0, 0.9, 0)
	_cam.rotation = Vector3.ZERO

	var ta: Dictionary = await _spawn_target(Vector3(0, 0, -20.0))
	var tb: Dictionary = await _spawn_target(Vector3(0, 0, -24.0)) # directly behind A on the aim ray
	ta["rec"].amt = 0.0
	tb["rec"].amt = 0.0
	await _fire_once_raw(w_pierce)
	var a1: float = ta["rec"]["amt"]
	var b1: float = tb["rec"]["amt"]
	var eff: float = w_pierce.eff_damage()
	print("%-28s %9s %9s %9s" % ["case", "dmgA", "dmgB", "eff_dmg"])
	print("%-28s %9.1f %9.1f %9.1f" % ["pierce=%d shot" % w_pierce.data.pierce, a1, b1, eff])
	_check(a1 > 0.0, "pierce shot damages the FIRST enemy in line")
	_check(b1 > 0.0, "pierce shot damages the SECOND enemy in line -- pierce works")
	_check(_close_enough(a1, eff), "pierce: enemy A dmg ~= eff_damage() (%.1f vs %.1f)" % [a1, eff])
	_check(_close_enough(b1, eff), "pierce: enemy B dmg ~= eff_damage() (%.1f vs %.1f)" % [b1, eff])
	await _cleanup(ta)
	await _cleanup(tb)

	# control: identical line, pierce=0 twin -- only the first enemy is hit
	var w_flat: Weapon = await _weapon(GAUSS, {"pierce": 0})
	var ta2: Dictionary = await _spawn_target(Vector3(0, 0, -20.0))
	var tb2: Dictionary = await _spawn_target(Vector3(0, 0, -24.0))
	ta2["rec"].amt = 0.0
	tb2["rec"].amt = 0.0
	await _fire_once_raw(w_flat)
	var a2: float = ta2["rec"]["amt"]
	var b2: float = tb2["rec"]["amt"]
	print("%-28s %9.1f %9.1f %9s" % ["pierce=0 control shot", a2, b2, "n/a"])
	_check(a2 > 0.0, "pierce=0: FIRST enemy still takes damage")
	_check(b2 <= 0.0, "pierce=0: SECOND enemy takes NO damage -- the ray stops at the first hit")
	await _cleanup(ta2)
	await _cleanup(tb2)