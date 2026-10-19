# @lat: [[weapons#Weapon Manager]]
# @lat: [[weapons#Collision Mask Configuration]]
class_name WeaponManager
extends Node3D


signal weapon_changed(weapon: Weapon)
signal ammo_changed(mag: int, reserve: int)
signal weapon_added(weapon: Weapon) ## A new weapon was picked up at runtime.
signal weapon_removed(weapon: Weapon) ## A salvage gun ran dry and was tossed out of the rack.

@export var weapon_scenes: Array[PackedScene] = []
@export var start_index: int = 0
@export var recoil_target: Node3D ## Apply recoil to this (usually player Head)
@export var camera: Camera3D
@export var shooter: Node

var weapons: Array[Weapon] = []
var current_index: int = -1
var current: Weapon:
	get: return weapons[current_index] if current_index >= 0 and current_index < weapons.size() else null

var _recoil_pitch: float = 0.0
var _recoil_yaw: float = 0.0

## Draw time: switching weapons takes this long, during which you can't fire or
## switch again. Combined with holster reloads, it stops swap-to-reload spam.
@export var equip_time: float = 0.5
var _equip_timer: float = 0.0

## Double-tap-a-digit tracking (reach slots 11+ from the keyboard). See _input.
const DOUBLE_TAP_MS := 350
var _last_digit_key: int = -1
var _last_digit_ms: int = 0

# ADS & Sway variables
var _hip_position: Vector3
var _current_ads_lerp: float = 0.0
var _base_fov: float = 78.0

var _sway_offset: Vector3 = Vector3.ZERO
var _sway_rotation: Vector3 = Vector3.ZERO
var _mouse_input: Vector2 = Vector2.ZERO

# Viewmodel recoil kick: a spring-damped impulse so the GUN visibly punches back
# and the muzzle climbs on every shot (the camera kick is separate). Velocity is
# integrated against a stiff spring for a snappy, Vlambeer-y settle.
var _kick_pos: Vector3 = Vector3.ZERO
var _kick_rot: Vector3 = Vector3.ZERO
var _kick_pos_vel: Vector3 = Vector3.ZERO
var _kick_rot_vel: Vector3 = Vector3.ZERO
const KICK_STIFFNESS := 220.0   # spring constant (snap-back speed)
const KICK_DAMPING := 22.0      # critical-ish damping (no wobble)
## Fixed integration step for the kick spring. Explicit Euler needs
## h < 2/KICK_DAMPING (0.0909 s) to be stable at all; 1/120 s leaves a wide
## margin and makes the recoil feel identical whatever the framerate.
const KICK_MAX_STEP := 1.0 / 120.0
## Never simulate more than this much spring per frame. A 3-second stall (level
## load, shader compile) should not spend 360 substeps catching up — the kick has
## long since settled anyway.
const KICK_MAX_SIM := 0.1
const KICK_SANE := 2.0
## Per-gun spring bounds (WeaponData.kick_stiffness / kick_damping). The
## substepped integrator stays stable while h * sqrt(k) < 2 and h * c < 2, i.e.
## k < 57600 and c < 240 at KICK_MAX_STEP; these keep a typo far inside that.
const KICK_MAX_STIFFNESS := 900.0
const KICK_MAX_DAMPING := 80.0

var external_kick_pos: Vector3 = Vector3.ZERO
var block_ads: bool = false


var _bob_time: float = 0.0
var _bob_offset: Vector3 = Vector3.ZERO

# Sprint lower-ready: flat-out running drops the gun toward the chest (muzzle
# down, pulled in) — the near-universal modern-shooter read for "sprinting".
# The pose is purely visual: firing is never gated on it. The trigger or ADS
# breaks the pose immediately, and raising is much faster than lowering, so
# snapping onto a target out of a sprint never feels sluggish.
const SPRINT_POSE_POS := Vector3(-0.04, -0.09, 0.06)
const SPRINT_POSE_ROT := Vector3(-0.38, 0.24, 0.10) # pitch down, yaw in, slight roll
const SPRINT_POSE_MIN_SPEED := 6.5 ## above walk (6) and below full sprint (9)
var _sprint_lerp: float = 0.0

# Idle breathing: a player standing still is still a person holding a gun, so
# it rises and falls on a slow figure-eight with each breath instead of hanging
# frozen in the air. It fades out while moving (the walk bob takes over), drops
# to BREATH_ADS while aiming, and a winded player (stamina spent) breathes up to
# BREATH_WINDED times as hard. Covered by tests/idle_breath_probe.
const BREATH_AMP := Vector3(0.0018, 0.0026, 0.0) ## metres at the top of a breath
const BREATH_ROT := 0.0045 ## radians of pitch at the top of a breath (roll 0.6x)
const BREATH_RATE := 1.7 ## radians per second: one breath about every 3.7 s
const BREATH_ADS := 0.2 ## share of the breath left while fully aimed
const BREATH_WINDED := 2.4 ## breath size with stamina at 0 (1 when full)
const BREATH_WINDED_RATE := 1.6 ## and it comes this much faster
var _breath_t: float = 0.0
var _breath_lerp: float = 0.0 ## 1 standing still, 0 moving
var _winded: float = 0.0 ## 0 rested .. 1 stamina spent (from the shooter's stamina_changed)
var _winded_shown: float = 0.0 ## _winded, eased so a breath never jumps

## External roll (radians), e.g. the player's wall-run lean. This node's own
## _process() sets rotation.z every frame (sway + kick), which would silently
## erase any direct rotation.z write from outside — so external callers feed
## it in here instead and it's folded into the same final assignment below.
var external_roll: float = 0.0


func _ready() -> void:
	_register_alt_fire_action()
	# Auto-resolve refs assuming this node sits under Player/Head/Camera3D/WeaponHolder
	if camera == null:
		var p := get_parent()
		while p and not (p is Camera3D):
			p = p.get_parent()
		camera = p as Camera3D
	if shooter == null:
		var n := get_parent()
		while n and not (n is CharacterBody3D):
			n = n.get_parent()
		shooter = n
	if recoil_target == null and shooter:
		recoil_target = shooter.get_node_or_null("Head")
	if shooter and shooter.has_signal("stamina_changed"):
		shooter.stamina_changed.connect(_on_stamina_changed)
	for s in weapon_scenes:
		_instantiate_weapon(s)
	# Bonus weapons unlocked earlier in the campaign carry across levels.
	for path in GameState.unlocked_weapons:
		if _owns_scene_path(path):
			continue # warp grants the full arsenal; don't double up the base loadout
		var ps := load(path) as PackedScene
		if ps:
			_instantiate_weapon(ps)
	# Keep the rack ordered weakest→strongest so number keys 1-9 (and the wheel)
	# always run low-power to high-power, regardless of pickup/loadout order.
	_sort_by_power()
	if weapons.size() > 0:
		# Carry the weapon armed on the previous level; fall back to start_index.
		var idx := clampi(start_index, 0, weapons.size() - 1)
		if GameState.equipped_weapon != "":
			for i in weapons.size():
				if weapons[i].scene_file_path == GameState.equipped_weapon:
					idx = i
					break
		_equip(idx)

	# Initial ADS cache
	_hip_position = position
	if camera:
		_base_fov = camera.fov

func _on_stamina_changed(current: float, max_value: float, _exhausted: bool) -> void:
	_winded = 1.0 - clampf(current / maxf(1.0, max_value), 0.0, 1.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_mouse_input += m.relative
	elif event is InputEventKey and event.pressed and not event.echo:
		# Number keys 1-9 select that weapon slot directly; 0 selects the 10th.
		# DOUBLE-TAPPING a digit d reaches slot 10+d (dbl-1 -> slot 11, dbl-2 -> 12,
		# ...), so racks past 10 weapons are keyboard-reachable without the wheel.
		# The mouse wheel (weapon_next/prev) still cycles the whole rack. Ignored
		# mid-draw.
		var k := (event as InputEventKey).physical_keycode
		if _equip_timer <= 0.0:
			var d := -1                       # the 1-9 digit pressed (0 stays slot 10)
			var idx := -1
			if k >= KEY_1 and k <= KEY_9:
				d = k - KEY_1 + 1
				idx = d - 1
			elif k == KEY_0:
				idx = 9
			if d >= 1:
				var now := Time.get_ticks_msec()
				# A quick second tap of the SAME digit jumps to its +10 slot.
				if k == _last_digit_key and now - _last_digit_ms <= DOUBLE_TAP_MS \
						and (9 + d) < weapons.size():
					idx = 9 + d               # slot 10+d (idx is 0-based)
				_last_digit_key = k
				_last_digit_ms = now
			if idx >= 0 and idx < weapons.size():
				_equip(idx)


func _instantiate_weapon(scene: PackedScene) -> Weapon:
	if scene == null:
		return null
	var w := scene.instantiate() as Weapon
	add_child(w)
	w.visible = false
	w.fired.connect(_on_fired)
	w.ammo_changed.connect(func(m, r): ammo_changed.emit(m, r))
	weapons.append(w)
	# A weapon that lands in the rack has been HELD — unlock its codex dossier
	# (persists across runs; covers base loadout, pickups and the warp arsenal).
	GameState.discover_weapon(scene.resource_path)
	return w

## Reorder the rack weakest→strongest by GameState.weapon_power_rank, keeping the
## currently-armed weapon armed (current_index is re-resolved to its new slot).
func _sort_by_power() -> void:
	var cur := current
	weapons.sort_custom(func(a: Weapon, b: Weapon) -> bool:
		return GameState.weapon_power_rank(a.scene_file_path) < GameState.weapon_power_rank(b.scene_file_path))
	if cur:
		current_index = weapons.find(cur)

## True if a weapon spawned from this scene path is already in the rack.
func _owns_scene_path(path: String) -> bool:
	for w in weapons:
		if w.scene_file_path == path:
			return true
	return false

## Add a weapon at runtime (weapon pickup). Returns true if newly added.
func add_weapon(scene: PackedScene, equip: bool = true) -> bool:
	if scene == null:
		return false
	# Already owned? Just top up its reserve.
	for w in weapons:
		if w.scene_file_path == scene.resource_path:
			if w.data:
				w.reserve = w.data.reserve_max
				w.ammo_changed.emit(w.mag, w.reserve)
			return false
	var nw := _instantiate_weapon(scene)
	if nw == null:
		return false
	# Slot the pickup into its power-ranked position so the rack stays weak→strong.
	_sort_by_power()
	weapon_added.emit(nw)
	# Auto-switch to the freshly picked-up weapon.
	if equip or current == null:
		_equip(weapons.find(nw))
	return true

# ---------- SALVAGE: a heavy robot's own gun, for one magazine (Salvage) ----------
var _pre_salvage: Weapon = null ## what you held before the salvage, re-armed when it's tossed

## Arm a salvage gun at once: a full magazine, no reserve. One at a time: a new
## one tosses the old. It joins the rack (after your arsenal: it has no power
## rank) but never GameState.equipped_weapon, so it can't follow you out of the level.
func take_salvage(scene: PackedScene) -> Weapon:
	if scene == null:
		return null
	for w in weapons:
		if w.salvage:
			_toss_salvage(w, false)
	var keep := current
	var w := scene.instantiate() as Weapon
	w.salvage = true
	add_child(w)
	w.visible = false
	w.fired.connect(_on_fired)
	w.ammo_changed.connect(func(m, r): ammo_changed.emit(m, r))
	w.reserve = 0
	w.mag = w.data.mag_size
	weapons.append(w)
	_sort_by_power()
	_watch_rack = weapons.size()
	if keep and not keep.salvage:
		_pre_salvage = keep
	weapon_added.emit(w)
	_equip(weapons.find(w))
	w.ammo_changed.emit(w.mag, w.reserve)
	w.fired.connect(func(_x) -> void:
		if w.mag <= 0:
			_toss_salvage.call_deferred(w, true))
	return w

## Out of the rack and freed. `rearm` puts the gun you held before it back.
func _toss_salvage(w: Weapon, rearm: bool) -> void:
	if not is_instance_valid(w) or not weapons.has(w):
		return
	var was_current := w == current
	if was_current:
		w.on_unequip()
	weapons.erase(w)
	_watch_rack = weapons.size() # an intended removal, not a lost weapon
	current_index = -1
	weapon_removed.emit(w)
	w.queue_free()
	if weapons.is_empty():
		return
	var back := _pre_salvage if is_instance_valid(_pre_salvage) and weapons.has(_pre_salvage) else weapons[0]
	if rearm or was_current:
		_equip(weapons.find(back))
		if rearm:
			AudioBus.play_synth_ui("empty_click", -6.0, 0.7)
	else:
		current_index = weapons.find(back)

## Registers the alt-fire action (V + mouse thumb button) at runtime, same
## pattern as the player's dash — no project input-map edit needed.
func _register_alt_fire_action() -> void:
	if InputMap.has_action("alt_fire"):
		return
	InputMap.add_action("alt_fire")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_V
	InputMap.action_add_event("alt_fire", key)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_XBUTTON1
	InputMap.action_add_event("alt_fire", mb)

## Watchdog for the recurring "I shoot / get shot and lose my weapons" report.
##
## The original version only checked `current` for null and `current.visible`.
## Neither ever fired in a repro attempt (tests/weapon_vanish_probe drives 3000
## frames of firing, taking hits, wheel-swapping and mid-fight pickups), so the
## real failure is something it could not see. It now also watches:
##   - the rack SHRINKING (a Weapon freed out from under us),
##   - current_index drifting off the end,
##   - visibility of the whole HOLDER / any ancestor (visible_in_tree), which the
##     `.visible` check misses entirely,
##   - the weapon node being detached from the tree.
##
## It RECOVERS rather than leaving the player disarmed: a mitigation, not a cure.
## Every trip prints (so it lands in stdout AND the rotated game log — see
## project.godot [debug], retention raised from 5 files to 40 because a few
## headless probe runs were enough to evict the sessions that had the evidence).
var _watch_ok: bool = true
var _watch_rack: int = -1

func _watch_weapon() -> void:
	# Only while actually playing. Cutscenes, menus and the death sequence hide
	# the viewmodel ON PURPOSE; a watchdog that "recovers" there would yank the
	# gun back into frame mid-cutscene.
	if GameState.current_state != GameState.State.PLAYING:
		_watch_ok = true
		_watch_rack = weapons.size()
		return
	if _watch_rack < 0:
		_watch_rack = weapons.size()
	if weapons.size() < _watch_rack:
		print("[WEAPON-WATCH] rack SHRANK %d -> %d (index=%d state=%d)"
			% [_watch_rack, weapons.size(), current_index, GameState.current_state])
	_watch_rack = weapons.size()

	if weapons.is_empty():
		return
	if current == null or not is_instance_valid(current):
		if _watch_ok:
			_watch_ok = false
			print("[WEAPON-WATCH] equipped weapon null/freed (weapons=%d index=%d state=%d) — recovering"
				% [weapons.size(), current_index, GameState.current_state])
		_recover_weapon()
		return
	# Something hid an ANCESTOR (the holder, the camera, the head): `current.visible`
	# stays true and the old watchdog saw nothing, but the player sees no gun.
	var drawn := _equip_timer > 0.0
	var ok := current.is_inside_tree() and (current.is_visible_in_tree() or drawn)
	if ok != _watch_ok:
		_watch_ok = ok
		if not ok:
			var who := "self" if not current.visible else "an ancestor"
			print("[WEAPON-WATCH] '%s' vanished — hidden by %s (in_tree=%s self.visible=%s holder.visible=%s mag=%d reserve=%d reloading=%s equip_timer=%.2f state=%d) — recovering"
				% [current.name, who, current.is_inside_tree(), current.visible, visible,
					current.mag, current.reserve, current._reloading, _equip_timer,
					GameState.current_state])
			_recover_weapon()

## Put a usable weapon back in the player's hands. Never leaves them disarmed
## because of a bug we have not yet caught.
## Belt and braces for the kick spring. The substepping above should make this
## unreachable, but a NaN here is unrecoverable (NaN propagates through every
## later frame and the viewmodel never comes back), so it is worth a cheap check.
func _sanitize_kick() -> void:
	var bad := not (_kick_pos.is_finite() and _kick_pos_vel.is_finite()
		and _kick_rot.is_finite() and _kick_rot_vel.is_finite())
	if not bad and (_kick_pos.length() > KICK_SANE or _kick_rot.length() > KICK_SANE):
		bad = true
	if not bad:
		return
	print("[WEAPON-WATCH] viewmodel kick blew up (pos=%s rot=%s) — reset" % [_kick_pos, _kick_rot])
	_kick_pos = Vector3.ZERO
	_kick_pos_vel = Vector3.ZERO
	_kick_rot = Vector3.ZERO
	_kick_rot_vel = Vector3.ZERO

func _recover_weapon() -> void:
	if not visible:
		visible = true
	# Drop any dead slots first: a freed Weapon left in the rack shows up as an
	# empty cell in the HUD carousel and makes the number keys point at nothing.
	var live: Array[Weapon] = []
	for w in weapons:
		if w != null and is_instance_valid(w):
			live.append(w)
	if live.size() != weapons.size():
		weapons = live
		_watch_rack = weapons.size()
	for i in weapons.size():
		var w := weapons[i]
		if w != null and is_instance_valid(w) and w.is_inside_tree():
			current_index = i
			w.visible = true
			w.on_equip()
			weapon_changed.emit(w)
			ammo_changed.emit(w.mag, w.reserve)
			_watch_ok = true
			print("[WEAPON-WATCH] re-armed '%s' (slot %d)" % [w.name, i])
			return

func _process(delta: float) -> void:
	_watch_weapon()
	if _equip_timer > 0.0:
		_equip_timer -= delta
	# Number-key weapon selection (1-9) is handled in _input(). Wheel cycling is
	# locked out during the draw so you can't swap-spam through the rack.
	if _equip_timer <= 0.0:
		if _pin().just_pressed("weapon_next"):
			_equip((current_index + 1) % maxi(1, weapons.size()))
		if _pin().just_pressed("weapon_prev"):
			_equip((current_index - 1 + weapons.size()) % maxi(1, weapons.size()))
	if _pin().just_pressed("reload") and current:
		current.start_reload()

	# Out of ammo entirely → quick-draw the best loaded backup instead of dry-firing.
	if current and camera and _equip_timer <= 0.0 \
			and _pin().just_pressed("fire") and current.is_fully_dry():
		_auto_switch_dry()

	# Fire (suppressed for the brief draw while a freshly equipped weapon is raised).
	if current and camera and _equip_timer <= 0.0:
		var trigger := _pin().pressed("fire")
		var aiming := _pin().pressed("aim")
		current.try_fire(trigger, aiming, camera, shooter)
		current.try_alt_fire(_pin().pressed("alt_fire"), delta, camera, shooter)

	# Recoil recovery: _recoil_pitch/_recoil_yaw hold the portion of applied
	# kick that still owes the camera a settle-back. Bleed it off and counter-
	# rotate the head by the same amount, so a burst climbs then returns toward
	# the pre-shot aim instead of walking the view up permanently.
	if recoil_target and (absf(_recoil_pitch) > 0.00001 or absf(_recoil_yaw) > 0.00001):
		var rk := clampf((current.data.recoil_recovery if current and current.data else 9.0) * delta, 0.0, 1.0)
		var dp := _recoil_pitch * rk
		var dy := _recoil_yaw * rk
		recoil_target.rotation.x = clampf(recoil_target.rotation.x - dp, -1.55, 1.55)
		recoil_target.rotation.y -= dy
		_recoil_pitch -= dp
		_recoil_yaw -= dy

	# ADS Update. camera.fov is NOT written here — the player's camera-feel pass
	# is the single fov writer and pulls ads_blend()/ads_target_fov() from us.
	# (Two competing writers used to reset each other every frame, which capped
	# the RMB zoom at a sliver of the intended ads_fov.)
	var aiming := _pin().pressed("aim") and current != null and not block_ads
	_current_ads_lerp = lerpf(_current_ads_lerp, 1.0 if aiming else 0.0, clampf(10.0 * delta, 0.0, 1.0))
	
	var ads_offset := Vector3.ZERO
	if current and current.data:
		ads_offset = current.data.ads_position_offset
	
	var target_pos := _hip_position + ads_offset * _current_ads_lerp

	# Look Sway
	var sway_amount_x := -_mouse_input.x * 0.0006
	var sway_amount_y := _mouse_input.y * 0.0006
	var tilt_amount_z := _mouse_input.x * 0.0012
	var tilt_amount_x := _mouse_input.y * 0.0008
	
	_sway_offset.x = lerpf(_sway_offset.x, clampf(sway_amount_x, -0.04, 0.04), clampf(8.0 * delta, 0.0, 1.0))
	_sway_offset.y = lerpf(_sway_offset.y, clampf(sway_amount_y, -0.04, 0.04), clampf(8.0 * delta, 0.0, 1.0))
	
	_sway_rotation.z = lerpf(_sway_rotation.z, clampf(tilt_amount_z, -0.08, 0.08), clampf(8.0 * delta, 0.0, 1.0))
	_sway_rotation.x = lerpf(_sway_rotation.x, clampf(tilt_amount_x, -0.06, 0.06), clampf(8.0 * delta, 0.0, 1.0))
	_sway_rotation.y = lerpf(_sway_rotation.y, clampf(sway_amount_x * 2.0, -0.08, 0.08), clampf(8.0 * delta, 0.0, 1.0))

	_mouse_input = Vector2.ZERO

	# Movement Bob
	var movement_speed := 0.0
	var is_moving_on_floor := false
	if shooter and shooter is CharacterBody3D:
		var vel: Vector3 = shooter.velocity
		movement_speed = Vector2(vel.x, vel.z).length()
		is_moving_on_floor = shooter.is_on_floor() and movement_speed > 0.1
	
	if is_moving_on_floor:
		_bob_time += delta * movement_speed * 2.2
		var bob_x := cos(_bob_time * 0.5) * 0.006
		var bob_y := sin(_bob_time) * 0.008
		var ads_bob_reduction := 1.0 - _current_ads_lerp * 0.85
		_bob_offset.x = bob_x * ads_bob_reduction
		_bob_offset.y = bob_y * ads_bob_reduction
	else:
		_bob_time = 0.0
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, clampf(8.0 * delta, 0.0, 1.0))

	# Idle breathing (see constants above).
	_breath_lerp = move_toward(_breath_lerp, 0.0 if is_moving_on_floor else 1.0, delta * 2.5)
	_winded_shown = move_toward(_winded_shown, _winded, delta * 0.6)
	_breath_t += delta * BREATH_RATE * lerpf(1.0, BREATH_WINDED_RATE, _winded_shown)
	var breath := _breath_lerp * lerpf(1.0, BREATH_WINDED, _winded_shown) 		* lerpf(1.0, BREATH_ADS, _current_ads_lerp)
	var breath_pos := Vector3(sin(_breath_t * 0.5) * BREATH_AMP.x, sin(_breath_t) * BREATH_AMP.y, 0.0) * breath
	var breath_rot := Vector3(-sin(_breath_t) * BREATH_ROT, 0.0, sin(_breath_t * 0.5) * BREATH_ROT * 0.6) * breath

	# Sprint lower-ready pose (see constants above): engage only in a genuine
	# grounded sprint, and drop it the instant the player aims or squeezes the
	# trigger so the raise never fights the shot.
	var sprint_now := is_moving_on_floor and movement_speed > SPRINT_POSE_MIN_SPEED \
		and _pin().pressed("sprint") \
		and not aiming and not _pin().pressed("fire")
	_sprint_lerp = move_toward(_sprint_lerp, 1.0 if sprint_now else 0.0, delta * (4.5 if sprint_now else 14.0))
	# Ease the blend (smoothstep) so the gun settles into and out of the pose
	# instead of hitting it linearly.
	var sp := _sprint_lerp * _sprint_lerp * (3.0 - 2.0 * _sprint_lerp)

	# Spring the recoil kick back to rest (snappy, lightly underdamped for punch).
	#
	# SUBSTEPPED, and not optional. This is an explicit Euler integrator: its
	# damping term alone diverges once the timestep exceeds 2/KICK_DAMPING, i.e.
	# ~0.09 s — any single frame slower than about 11 fps. The frame that compiles
	# the muzzle-flash shader on your FIRST shot is exactly that frame. Measured
	# (tests/kick_stability_probe): 30 frames at 10 fps drove |_kick_pos| to
	# 1.9e12 metres; even after the framerate recovers, float precision leaves a
	# permanent ~1.9 m residual, so the WeaponHolder sits 1.4 m off the hip for
	# the rest of the level and EVERY weapon in it is out of frame. A longer stall
	# reaches inf, then NaN, and nothing ever resets _kick_pos — which is why
	# switching weapons never brought the gun back, and why the old watchdog saw
	# nothing (the weapon is still in the rack, still `visible`).
	var sim := minf(delta, KICK_MAX_SIM)
	var steps := maxi(1, int(ceil(sim / KICK_MAX_STEP)))
	var h := sim / float(steps)
	# The equipped gun's spring: a light gun snaps home, a heavy one drifts.
	var k := KICK_STIFFNESS
	var c := KICK_DAMPING
	if current and current.data:
		k = clampf(current.data.kick_stiffness, 40.0, KICK_MAX_STIFFNESS)
		c = clampf(current.data.kick_damping, 4.0, KICK_MAX_DAMPING)
	for _i in steps:
		_kick_pos_vel -= (_kick_pos * k + _kick_pos_vel * c) * h
		_kick_pos += _kick_pos_vel * h
		_kick_rot_vel -= (_kick_rot * k + _kick_rot_vel * c) * h
		_kick_rot += _kick_rot_vel * h
	_sanitize_kick()

	# Apply final position and rotation (sway + bob + breath + recoil kick + sprint pose + external punch)
	position = target_pos + _sway_offset + _bob_offset + breath_pos + _kick_pos + SPRINT_POSE_POS * sp + external_kick_pos
	rotation.x = _sway_rotation.x + _kick_rot.x + breath_rot.x + SPRINT_POSE_ROT.x * sp
	rotation.y = _sway_rotation.y + _kick_rot.y + SPRINT_POSE_ROT.y * sp
	rotation.z = _sway_rotation.z + _kick_rot.z + breath_rot.z + external_roll + SPRINT_POSE_ROT.z * sp


## How far into aim-down-sights we are (0 hip → 1 fully aimed). The player's
## camera-feel pass blends its fov toward ads_target_fov() by this amount.
func ads_blend() -> float:
	return clampf(_current_ads_lerp, 0.0, 1.0)

## The equipped weapon's zoom fov (falls back to the base fov when unarmed).
func ads_target_fov() -> float:
	if current and current.data:
		return current.data.ads_fov
	return _base_fov

func _on_fired(_w: Weapon) -> void:
	if current == null or current.data == null:
		return
	# One kick per shot; recoil_return of it is banked so _process can settle the
	# camera back. The yaw sign is rolled once, so the recovery undoes the same
	# direction the camera was actually kicked (two rolls used to desync them).
	var pitch_kick := deg_to_rad(current.data.recoil_pitch)
	var yaw_kick := deg_to_rad(current.data.recoil_yaw) * (1.0 if randf() > 0.5 else -1.0)
	_recoil_pitch += pitch_kick * current.data.recoil_return
	_recoil_yaw += yaw_kick * current.data.recoil_return
	if recoil_target:
		recoil_target.rotation.x = clampf(recoil_target.rotation.x + pitch_kick, -1.55, 1.55)
		recoil_target.rotation.y += yaw_kick
	# Punchy per-shot camera trauma, scaled by the weapon's recoil weight.
	if shooter and shooter.has_method("shake"):
		shooter.shake(clampf(0.18 + current.data.recoil_pitch * 0.05, 0.0, 0.6))
	# Punch the GUN itself with this gun's kick signature (WeaponData "Kick
	# Feel"): a velocity impulse the spring then settles — the viewmodel jolts
	# back (+Z, toward the player), lifts and the muzzle climbs, with random
	# yaw/roll so repeat fire never looks metronomic and a roll bias for the
	# guns that twist.
	var d: WeaponData = current.data
	_kick_pos_vel += Vector3(randf_range(-0.06, 0.06), d.kick_lift, d.kick_back)
	_kick_rot_vel += Vector3(d.kick_climb, randf_range(-d.kick_side, d.kick_side),
		d.kick_roll_bias + randf_range(-d.kick_roll, d.kick_roll))
	# The blast pushing on you: a beat of wider view on the heavy rounds.
	if d.fov_punch > 0.0 and shooter and shooter.has_method("fov_punch"):
		shooter.fov_punch(d.fov_punch)

func _equip(index: int) -> void:
	if index == current_index or index < 0 or index >= weapons.size():
		return
	if current:
		current.on_unequip()
	current_index = index
	current.on_equip()
	_equip_timer = equip_time # draw time: blocks firing + re-switching for a beat
	# Remember the armed weapon so it persists into the next level (never a
	# salvage gun: it stays behind).
	if not current.salvage:
		GameState.equipped_weapon = current.scene_file_path
	weapon_changed.emit(current)
	ammo_changed.emit(current.mag, current.reserve)

## Current weapon is bone dry — quick-draw the best loaded backup for the fight at
## hand. "Best" = the loaded weapon with the highest effective damage up close (so
## a run-dry mid-brawl puts a CQB shredder in your hands), skipping splash weapons
## so you don't auto-pull a rocket into your own face. Falls back to any loaded gun.
func _auto_switch_dry() -> void:
	var best: Weapon = null
	var best_score := -1.0
	for w in weapons:
		if w == current or (w.mag <= 0 and w.reserve <= 0):
			continue
		if w.data and w.data.splash_radius > 0.0:
			continue
		# Score = true close-range DPS at ~6 m: per-shot damage × pellets × fire rate,
		# scaled by its range identity. This favours shredders (shotgun/SMG/Tesla)
		# over a high-per-shot-but-slow long gun (a sniper is a poor panic pick).
		var pellets: int = maxi(1, w.data.pellets) if w.data else 1
		var score := w.eff_damage() * float(pellets) * w.eff_fire_rate() * w._range_mult(6.0)
		if score > best_score:
			best_score = score
			best = w
	if best == null: # nothing safe-and-loaded — take any gun with rounds left
		for w in weapons:
			if w != current and (w.mag > 0 or w.reserve > 0):
				best = w
				break
	if best:
		AudioBus.play_synth_ui("empty_click", -8.0, 0.8) # the dry click that kicks the draw
		_equip(weapons.find(best))

## The input of the player holding this rack (co-op: player two's pad for player
## two). A rack with no player (a codex preview) reads player one's.
var _pin_cache: PlayerInput = null
func _pin() -> PlayerInput:
	if _pin_cache == null:
		var n := get_parent()
		while n != null and not (n.get("input") is PlayerInput):
			n = n.get_parent()
		_pin_cache = n.get("input") if n != null else PlayerInput.new()
	return _pin_cache
