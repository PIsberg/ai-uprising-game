extends Node3D
## Probe: every gun is held by a pair of gloved hands (ViewmodelHands), not
## floated in front of the camera. For each gun in GameState.WEAPON_ORDER and
## each Salvage.TABLE gun, equipped on the real player:
##   - a trigger hand sits on the gun's grip: inside the fitted gun's footprint,
##     in the rear half of its length and the lower part of its height;
##   - long guns (fitted length >= ViewmodelHands.TWO_HAND_LEN) add a support
##     hand on the fore-end, well forward of the trigger hand; short guns keep
##     one hand;
##   - every forearm runs back out of view: its far end is outside the camera
##     frustum at hip and at full ADS, so no arm ever ends in mid-air on screen;
##   - the hands cast no shadow and take no RAMPAGE rim (rim_meshes skips them);
##   - on a reload of each style (MAG rifle, SHELLS shotgun, CELL plasma, TUBE
##     swarm) the support hand leaves the gun, dropping at least RELOAD_DROP
##     below its hold, stays on its forearm the whole time, and is back on the
##     gun once the reload is done, also when the reload finished holstered.
##   godot --headless --path . --audio-driver Dummy res://tests/viewmodel_hands_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RELOAD_DROP := 0.1
const RELOAD_GUNS := ["rifle", "shotgun", "plasma", "swarm"]

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
	player.global_position = Vector3(0, 1.0, 0)
	for i in 10:
		await get_tree().physics_frame
	player.set_physics_process(false)
	player.set_process(false) # the camera-feel pass would rewrite our fov
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	var guns: Array = GameState.WEAPON_ORDER.duplicate()
	for k in Salvage.TABLE:
		guns.append(String(Salvage.TABLE[k]["scene"]))
	var two_handed := 0
	for p: String in guns:
		var id := p.get_file().get_basename()
		wm.add_weapon(load(p), false)
		for i in wm.weapons.size():
			if (wm.weapons[i] as Weapon).scene_file_path == p:
				wm._equip(i)
		for i in 3:
			await get_tree().process_frame
		var w: Weapon = wm.current
		var hands := w.hands
		_check("%s is held by hands" % id, hands != null and hands.trigger_hand != null)
		if hands == null or hands.trigger_hand == null:
			continue
		var box: AABB = w._fit_box
		var g: Vector3 = hands.trigger_hand.position
		var rear_half := g.z > box.position.z + box.size.z * 0.5
		var low := g.y < box.position.y + box.size.y * 0.75
		var inside := g.x > box.position.x - 0.03 and g.x < box.end.x + 0.03 \
				and g.z > box.position.z and g.z < box.end.z
		_check("%s trigger hand is on the grip" % id, rear_half and low and inside,
				"hand %s box %s" % [g, box])
		var long := box.size.z >= ViewmodelHands.TWO_HAND_LEN
		if long:
			two_handed += 1
			var s_ok: bool = hands.support_hand != null
			_check("%s long gun has a support hand" % id, s_ok)
			if s_ok:
				var s: Vector3 = hands.support_hand.position
				_check("%s support hand is on the fore-end" % id,
						s.z < g.z - box.size.z * 0.2 and s.z > box.position.z,
						"support z %.2f trigger z %.2f front %.2f" % [s.z, g.z, box.position.z])
		else:
			_check("%s short gun is held one-handed" % id, hands.support_hand == null)
		for blend in [0.0, 1.0]:
			_set_ads(wm, w, cam, blend)
			await get_tree().process_frame
			for arm: Node3D in hands.forearm_ends():
				_check("%s forearm runs out of view (ads %.0f)" % [id, blend],
						not _in_frustum(cam, arm.global_position),
						"end at %s in camera space" % (cam.global_transform.affine_inverse() * arm.global_position))
		_set_ads(wm, w, cam, 0.0)
		var meshes := hands.find_children("*", "GeometryInstance3D", true, false)
		_check("%s hands have fingers, palms and sleeves" % id, meshes.size() >= 8, str(meshes.size()))
		var shadowless := meshes.all(func(m: Node) -> bool:
				return (m as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_check("%s hands cast no shadow" % id, shadowless)
		var rim := w.rim_meshes()
		_check("%s hands take no rampage rim" % id, not meshes.any(func(m: Node) -> bool: return m in rim))
	_check("several guns are two-handed", two_handed >= 8, str(two_handed))
	for id: String in RELOAD_GUNS:
		await _reload_check(wm, "res://scenes/weapons/%s.tscn" % id, id)
	# A reload that finishes while the gun is put away still puts the hand back.
	var rifle := _equip(wm, "res://scenes/weapons/rifle.tscn")
	await get_tree().process_frame
	var home := _support_pos(rifle)
	rifle.mag = 0
	rifle.start_reload()
	await _wait(maxf(0.6, rifle.eff_reload_time()) * 0.4)
	_equip(wm, "res://scenes/weapons/shotgun.tscn")
	await _wait(maxf(0.6, rifle.eff_reload_time()) + 0.4)
	_check("a reload finished holstered leaves the hand on the gun",
			not rifle._reloading and _support_pos(rifle).distance_to(home) < 0.01,
			"%.3f m off" % _support_pos(rifle).distance_to(home))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Equip the rack's copy of the gun at `p` and return it.
func _equip(wm: Node, p: String) -> Weapon:
	for i in wm.weapons.size():
		if (wm.weapons[i] as Weapon).scene_file_path == p:
			wm._equip(i)
			return wm.weapons[i]
	wm.add_weapon(load(p), false)
	return _equip(wm, p)

## The support hand in Hands space (it may sit under a pivot of its own).
func _support_pos(w: Weapon) -> Vector3:
	return w.hands.to_local(w.hands.support_hand.global_position)

func _wait(secs: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await get_tree().create_timer(0.05).timeout

## Reload the gun at `p` from empty and follow its support hand.
func _reload_check(wm: Node, p: String, id: String) -> void:
	var w := _equip(wm, p)
	for i in 3:
		await get_tree().process_frame
	if w.hands == null or w.hands.support_hand == null:
		_check("%s has a support hand to reload with" % id, false)
		return
	var home := _support_pos(w)
	var grip0: float = w.hands.support_hand.global_position.distance_to(w.hands.support_wrist().global_position)
	w.mag = 0
	w.reserve = maxi(w.reserve, w.eff_mag_size())
	w.start_reload()
	var drop := 0.0
	var worst_attach := 0.0
	var t0 := Time.get_ticks_msec()
	while w._reloading and Time.get_ticks_msec() - t0 < 8000:
		var off := home - _support_pos(w)
		drop = maxf(drop, off.y)
		var g: float = w.hands.support_hand.global_position.distance_to(w.hands.support_wrist().global_position)
		worst_attach = maxf(worst_attach, absf(g - grip0))
		await get_tree().process_frame
	await _wait(0.4)
	print("   %-8s reload: hand dropped %.2f m, wrist drift %.4f m, back within %.3f m" % [id, drop, worst_attach, _support_pos(w).distance_to(home)])
	_check("%s reload takes the support hand off the gun" % id, drop >= RELOAD_DROP, "%.2f m" % drop)
	_check("%s support hand stays on its forearm" % id, worst_attach < 0.002, "%.4f m" % worst_attach)
	_check("%s support hand is back on the gun after the reload" % id,
			_support_pos(w).distance_to(home) < 0.01, "%.3f m" % _support_pos(w).distance_to(home))

## Pose the holder and the camera at ADS blend `t` the way aiming would
## (WeaponManager._process offset, the camera-feel pass's fov), sway and kick off.
func _set_ads(wm: Node, w: Weapon, cam: Camera3D, t: float) -> void:
	wm.set_process(false)
	wm.position = wm._hip_position + w.data.ads_position_offset * t
	wm.rotation = Vector3.ZERO
	cam.fov = lerpf(wm._base_fov, w.data.ads_fov, t)

## True when `p` is inside the camera's view frustum (near plane included).
func _in_frustum(cam: Camera3D, p: Vector3) -> bool:
	for plane: Plane in cam.get_frustum():
		if plane.is_point_over(p):
			return false
	return true
