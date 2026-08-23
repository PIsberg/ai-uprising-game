extends Node
## Playtest instrument: does aiming at an enemy actually HIT it?
##
## gun_range_probe already proves the accuracy model against a wall (cone,
## bloom, ADS, recoil). This asks the question that matters in a fight: put the
## crosshair on a robot and pull the trigger — does it take damage?
##
## Two axes, because a miss can come from either side:
##   A. every weapon against a reference enemy at several ranges — catches range
##      limits, projectile travel, beam/chain weapons that resolve differently.
##   B. every enemy against a reference weapon — catches a collision shape that
##      does not match the visible model, or a Damageable the ray cannot find.
##
## A shot that stops short of a target beyond the weapon's own `range_m` is
## CORRECT, not a miss, so those combinations are skipped and reported as such.
##   godot --headless --path . --audio-driver Dummy res://tests/aim_hit_probe.tscn

const REF_ENEMY := "res://scenes/enemies/android.tscn"
const REF_WEAPON := "res://scenes/weapons/rifle.tscn"
const DISTS := [6.0, 18.0, 35.0]
const ENEMY_DIST := 14.0
const SHOTS := 8

var _player: CharacterBody3D
var _cam: Camera3D
var _head: Node3D
var _wm: Node
var _fails: PackedStringArray = []
var _last_note: String = ""

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	if has_node("/root/GraphicsSettings"):
		get_node("/root/GraphicsSettings").set_quality(2)
	# Own flat arena rather than a real level: borrowing level_range dropped
	# spawned robots off the platform edge (measured 160m of "movement" as they
	# fell), which reads as "the shot missed" when nothing was wrong with aiming.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(400, 2, 400)
	fcs.shape = fb
	floor_body.add_child(fcs)
	floor_body.position = Vector3(0, -1.0, 0)
	add_child(floor_body)
	add_child(DirectionalLight3D.new())
	var pl: Node3D = load("res://scenes/player/player.tscn").instantiate()
	add_child(pl)
	pl.global_position = Vector3(0, 1.0, 0)
	await get_tree().process_frame
	await _wait_game(0.8)
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if _player == null:
		print("NO PLAYER"); print("RESULT FAIL"); get_tree().quit(); return
	if "hp" in _player and _player.hp:
		_player.hp.invulnerable = true
	_cam = _player.get("camera") as Camera3D
	_head = _player.get_node_or_null("Head") as Node3D
	_wm = _find_wm(_player)
	if _cam == null or _wm == null:
		print("NO CAMERA/WM"); print("RESULT FAIL"); get_tree().quit(); return
	GameState.set_state(GameState.State.PLAYING)

	print("== A. every weapon vs ANDROID ==")
	print("%-14s %6s %6s %6s" % ["weapon", "%.0fm" % DISTS[0], "%.0fm" % DISTS[1], "%.0fm" % DISTS[2]])
	for wpath in GameState.ALL_WEAPONS:
		var w: Weapon = await _arm(wpath)
		var name := wpath.get_file().trim_suffix(".tscn")
		var cells: PackedStringArray = []
		for d in DISTS:
			if d > w.data.range_m + 0.5:
				cells.append("  n/a")   # beyond the weapon's designed reach — not a miss
				continue
			var dmg := await _shoot_at(REF_ENEMY, d, w)
			cells.append("%6.0f" % dmg)
			if dmg <= 0.0:
				_fails.append("%s@%.0fm" % [name, d])
		print("%-14s %s   (range_m=%.0f)" % [name, " ".join(cells), w.data.range_m])

	print("== B. every enemy vs RIFLE at %.0fm ==" % ENEMY_DIST)
	var rifle: Weapon = await _arm(REF_WEAPON)
	var miss: PackedStringArray = []
	for f in _enemy_scenes():
		var dmg := await _shoot_at(f, ENEMY_DIST, rifle)
		var id := f.get_file().trim_suffix(".tscn")
		if dmg <= 0.0:
			print("  ZERO %-12s %s" % [id, _last_note])
			miss.append(id)
			_fails.append("enemy:" + id)
	print("enemies tested=%d  took no damage=[%s]" % [_enemy_scenes().size(), ", ".join(miss)])

	print("AIM_HIT fails=%d %s" % [_fails.size(), " ".join(_fails)])
	print("RESULT %s" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit()

## Spawns `scene` `dist` ahead, points the camera at its body centre, empties
## SHOTS rounds into it and returns how much health it actually lost.
func _shoot_at(scene: String, dist: float, w: Weapon) -> float:
	# Clear anything left over — the ARCHON spawns minion waves, and a leftover
	# robot standing between the muzzle and the next target eats the shot and
	# looks exactly like a miss.
	for stray in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(stray):
			stray.queue_free()
	await get_tree().process_frame
	var e: Node3D = load(scene).instantiate()
	add_child(e)
	e.global_position = Vector3(0, 1.0, -dist)   # fixed frame, not the player's rotated one
	await _wait_game(1.8)   # land, finish any entrance, settle the collider
	if not is_instance_valid(e):
		return -1.0
	var hp = e.get_node_or_null("Damageable")
	if hp == null:
		e.queue_free(); return -1.0
	hp.invulnerable = false
	var before: float = hp.current_health
	var start_pos := _body_centre(e)
	var min_hp := before
	var was_invuln := false
	# Re-aim before every shot at the collision shape's own position rather than a
	# guessed height: works for a knee-high skitter and a boss alike, and tracks a
	# flyer the way a player would instead of firing at where it used to be.
	if w.data.fire_mode == WeaponData.FireMode.BEAM:
		# A beam is not a series of shots: try_fire only records intent, and
		# _update_beam does the damage each frame while the trigger is HELD.
		# It must be driven through the real INPUT action, because WeaponManager
		# calls try_fire from Input every frame — so a direct try_fire(true, ...)
		# is overwritten by the manager's own try_fire(false, ...) on the next
		# frame and the beam never fires at all.
		Input.action_press("fire")
		var held := 0.0
		while held < 1.6:
			if not is_instance_valid(e) or not is_instance_valid(hp): break
			w.mag = maxi(w.mag, 4)
			_aim_at(_body_centre(e))
			await get_tree().physics_frame
			held += get_physics_process_delta_time()
			if not is_instance_valid(hp): break
			was_invuln = was_invuln or hp.invulnerable
			min_hp = minf(min_hp, hp.current_health)
		Input.action_release("fire")
	else:
		for i in SHOTS:
			if not is_instance_valid(e): break
			w.mag = maxi(w.mag, 4)
			_aim_at(_body_centre(e))
			w.try_fire(true, false, _cam, _player)
			w.try_fire(false, false, _cam, _player)
			await _wait_game(0.18)
			if not is_instance_valid(hp): break
			was_invuln = was_invuln or hp.invulnerable
			min_hp = minf(min_hp, hp.current_health)
	await _wait_game(0.8)   # projectile travel + splash resolve
	if not is_instance_valid(e):
		return 999.0   # killed outright — the strongest possible hit
	min_hp = minf(min_hp, hp.current_health)
	var lost: float = before - hp.current_health
	var moved: float = start_pos.distance_to(_body_centre(e))
	_last_note = "invuln=%s moved=%.1fm minHP=%.0f/%.0f" % [was_invuln, moved, min_hp, before]
	e.queue_free()
	await get_tree().process_frame
	return lost

func _body_centre(e: Node3D) -> Vector3:
	var stack: Array = [e]
	while stack:
		var n: Node = stack.pop_back()
		if n is CollisionShape3D and (n as CollisionShape3D).shape != null:
			return (n as CollisionShape3D).global_position
		for c in n.get_children():
			stack.append(c)
	return e.global_position + Vector3.UP

func _aim_at(target: Vector3) -> void:
	var eye := _cam.global_position
	var d := target - eye
	_player.rotation.y = atan2(-d.x, -d.z)
	_cam.rotation = Vector3.ZERO
	if _head:
		_head.rotation = Vector3(atan2(d.y, Vector2(d.x, d.z).length()), 0, 0)

func _enemy_scenes() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open("res://scenes/enemies")
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			out.append("res://scenes/enemies/" + f)
	out.sort()
	return out

func _arm(path: String) -> Weapon:
	var ps := load(path) as PackedScene
	_wm.add_weapon(ps, true)
	if _wm.current == null or _wm.current.scene_file_path != path:
		for i in range(_wm.weapons.size()):
			if _wm.weapons[i].scene_file_path == path:
				_wm._equip(i)
				break
	await _wait_game(0.7)
	var w: Weapon = _wm.current
	w.mag = w.eff_mag_size()
	w.reserve = w.data.reserve_max
	return w

func _find_wm(root: Node) -> Node:
	var stack: Array = [root]
	while stack:
		var n: Node = stack.pop_back()
		if "current" in n and "weapons" in n:
			return n
		for c in n.get_children():
			stack.append(c)
	return null

func _wait_game(seconds: float) -> void:
	var acc := 0.0
	while acc < seconds:
		await get_tree().physics_frame
		acc += get_physics_process_delta_time()
