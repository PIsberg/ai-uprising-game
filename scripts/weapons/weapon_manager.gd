class_name WeaponManager
extends Node3D

signal weapon_changed(weapon: Weapon)
signal ammo_changed(mag: int, reserve: int)
signal weapon_added(weapon: Weapon) ## A new weapon was picked up at runtime.

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

# ADS & Sway variables
var _hip_position: Vector3
var _current_ads_lerp: float = 0.0
var _base_fov: float = 78.0

var _sway_offset: Vector3 = Vector3.ZERO
var _sway_rotation: Vector3 = Vector3.ZERO
var _mouse_input: Vector2 = Vector2.ZERO

var _bob_time: float = 0.0
var _bob_offset: Vector3 = Vector3.ZERO


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

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var m := event as InputEventMouseMotion
		_mouse_input += m.relative
	elif event is InputEventKey and event.pressed and not event.echo:
		# Number keys 1-9 directly select that weapon slot (if owned). Ignored mid-draw.
		var k := (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_9 and _equip_timer <= 0.0:
			var idx := k - KEY_1
			if idx < weapons.size():
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

func _process(delta: float) -> void:
	if _equip_timer > 0.0:
		_equip_timer -= delta
	# Number-key weapon selection (1-9) is handled in _input(). Wheel cycling is
	# locked out during the draw so you can't swap-spam through the rack.
	if _equip_timer <= 0.0:
		if Input.is_action_just_pressed("weapon_next"):
			_equip((current_index + 1) % maxi(1, weapons.size()))
		if Input.is_action_just_pressed("weapon_prev"):
			_equip((current_index - 1 + weapons.size()) % maxi(1, weapons.size()))
	if Input.is_action_just_pressed("reload") and current:
		current.start_reload()

	# Out of ammo entirely → quick-draw the best loaded backup instead of dry-firing.
	if current and camera and _equip_timer <= 0.0 \
			and Input.is_action_just_pressed("fire") and current.is_fully_dry():
		_auto_switch_dry()

	# Fire (suppressed for the brief draw while a freshly equipped weapon is raised).
	if current and camera and _equip_timer <= 0.0:
		var trigger := Input.is_action_pressed("fire")
		var aiming := Input.is_action_pressed("aim")
		current.try_fire(trigger, aiming, camera, shooter)
		current.try_alt_fire(Input.is_action_pressed("alt_fire"), delta, camera, shooter)

	# Recoil recovery
	if recoil_target:
		_recoil_pitch = lerpf(_recoil_pitch, 0.0, (current.data.recoil_recovery if current and current.data else 9.0) * delta)
		_recoil_yaw = lerpf(_recoil_yaw, 0.0, (current.data.recoil_recovery if current and current.data else 9.0) * delta)

	# ADS Update
	var aiming := Input.is_action_pressed("aim") and current != null
	_current_ads_lerp = lerpf(_current_ads_lerp, 1.0 if aiming else 0.0, 10.0 * delta)
	
	if camera:
		var target_fov := current.data.ads_fov if (aiming and current.data) else _base_fov
		# Speed-of-motion FOV: widen when sprinting (but never while aiming).
		if not aiming and shooter is CharacterBody3D:
			var hspeed := Vector2(shooter.velocity.x, shooter.velocity.z).length()
			var sprinting := Input.is_action_pressed("sprint")
			var widen := clampf(hspeed / 9.0, 0.0, 1.0) * (8.0 if sprinting else 3.0)
			target_fov += widen
		camera.fov = lerpf(camera.fov, target_fov, 8.0 * delta)
	
	var ads_offset := Vector3.ZERO
	if current and current.data:
		ads_offset = current.data.ads_position_offset
	
	var target_pos := _hip_position + ads_offset * _current_ads_lerp

	# Look Sway
	var sway_amount_x := -_mouse_input.x * 0.0006
	var sway_amount_y := _mouse_input.y * 0.0006
	var tilt_amount_z := _mouse_input.x * 0.0012
	var tilt_amount_x := _mouse_input.y * 0.0008
	
	_sway_offset.x = lerpf(_sway_offset.x, clampf(sway_amount_x, -0.04, 0.04), 8.0 * delta)
	_sway_offset.y = lerpf(_sway_offset.y, clampf(sway_amount_y, -0.04, 0.04), 8.0 * delta)
	
	_sway_rotation.z = lerpf(_sway_rotation.z, clampf(tilt_amount_z, -0.08, 0.08), 8.0 * delta)
	_sway_rotation.x = lerpf(_sway_rotation.x, clampf(tilt_amount_x, -0.06, 0.06), 8.0 * delta)
	_sway_rotation.y = lerpf(_sway_rotation.y, clampf(sway_amount_x * 2.0, -0.08, 0.08), 8.0 * delta)

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
		_bob_offset = _bob_offset.lerp(Vector3.ZERO, 8.0 * delta)

	# Apply final position and rotation
	position = target_pos + _sway_offset + _bob_offset
	rotation.x = _sway_rotation.x
	rotation.y = _sway_rotation.y
	rotation.z = _sway_rotation.z


func _on_fired(_w: Weapon) -> void:
	if current == null or current.data == null:
		return
	_recoil_pitch += deg_to_rad(current.data.recoil_pitch)
	_recoil_yaw += deg_to_rad(current.data.recoil_yaw) * (1.0 if randf() > 0.5 else -1.0)
	if recoil_target:
		recoil_target.rotation.x = clampf(recoil_target.rotation.x + deg_to_rad(current.data.recoil_pitch), -1.55, 1.55)
		recoil_target.rotation.y += deg_to_rad(current.data.recoil_yaw) * (1.0 if randf() > 0.5 else -1.0)
	# Punchy per-shot camera trauma, scaled by the weapon's recoil weight.
	if shooter and shooter.has_method("shake"):
		shooter.shake(clampf(0.18 + current.data.recoil_pitch * 0.05, 0.0, 0.6))

func _equip(index: int) -> void:
	if index == current_index or index < 0 or index >= weapons.size():
		return
	if current:
		current.on_unequip()
	current_index = index
	current.on_equip()
	_equip_timer = equip_time # draw time: blocks firing + re-switching for a beat
	# Remember the armed weapon so it persists into the next level.
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
