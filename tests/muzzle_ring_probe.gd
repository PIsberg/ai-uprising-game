extends Node3D
## Probe: the heavy guns' muzzle pressure ring (Weapon._muzzle_shockwave) stays
## a ring in the world, never a disc over the screen. It used to scale a torus
## 6x where it spawned, 0.1 m off the muzzle, so for 0.18 s on every Breacher,
## .50, Longshot, Gauss, Plasma, Swarm, Tempest, Devastator and OMEGA shot an
## opaque donut covered about half the view (tests/viewmodel_shot).
## For every gun that throws one, fired from the player's real camera, the ring's
## angular radius seen from the camera stays under MAX_DEG on every frame of its
## life, it travels away from the camera, and it is gone within 0.4 s. Guns too
## light for one throw none.
##   godot --headless --path . --audio-driver Dummy res://tests/muzzle_ring_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const MAX_DEG := 14.0

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
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	var throwers := 0
	for p: String in GameState.WEAPON_ORDER:
		var id := p.get_file().get_basename()
		wm.add_weapon(load(p), false)
		for i in wm.weapons.size():
			if (wm.weapons[i] as Weapon).scene_file_path == p:
				wm._equip(i)
		await get_tree().process_frame
		var w: Weapon = wm.current
		var heavy := w.data.recoil_pitch >= 1.8 or w.data.splash_radius > 0.0
		# Diff by identity: scopes carry static tori of their own.
		var before := _rings()
		w._active_camera = cam
		w._muzzle_shockwave()
		var mine: Array = _rings().filter(func(r: Node) -> bool: return not r in before)
		if not heavy:
			_check("%s throws no ring" % id, mine.is_empty())
			continue
		throwers += 1
		_check("%s throws a ring" % id, mine.size() == 1)
		if mine.is_empty():
			continue
		var ring: MeshInstance3D = mine[0]
		var worst := 0.0
		var d0 := -1.0
		var d_last := 0.0
		var t0 := Time.get_ticks_msec()
		while is_instance_valid(ring) and Time.get_ticks_msec() - t0 < 1000:
			var deg := _angular_radius_deg(ring, cam)
			worst = maxf(worst, deg)
			var d := cam.global_position.distance_to(ring.global_position)
			if d0 < 0.0:
				d0 = d
			d_last = d
			await get_tree().process_frame
		var life := (Time.get_ticks_msec() - t0) / 1000.0
		print("   %-10s ring: widest %.1f deg, %.2f -> %.2f m from the eye, gone after %.2f s" % [id, worst, d0, d_last, life])
		_check("%s ring never covers the view (< %.0f deg)" % [id, MAX_DEG], worst < MAX_DEG, "%.1f deg" % worst)
		_check("%s ring travels away from the eye" % id, d_last > d0 + 0.5, "%.2f -> %.2f m" % [d0, d_last])
		_check("%s ring is gone within 0.4 s" % id, not is_instance_valid(ring) and life <= 0.4, "%.2f s" % life)
	_check("the heavy guns throw rings", throwers >= 8, str(throwers))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## Every live torus in the scene (the ring is a TorusMesh MeshInstance3D).
func _rings() -> Array:
	var out: Array = []
	for n in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh is TorusMesh:
			out.append(n)
	return out

## Half the angle the ring's outer edge spans from the camera.
func _angular_radius_deg(ring: MeshInstance3D, cam: Camera3D) -> float:
	var tm := ring.mesh as TorusMesh
	var r := tm.outer_radius * ring.global_basis.get_scale().x
	var d := maxf(0.01, cam.global_position.distance_to(ring.global_position))
	return rad_to_deg(atan(r / d))
