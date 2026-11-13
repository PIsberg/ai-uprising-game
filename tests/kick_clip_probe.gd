extends Node3D
## Probe: no gun's kick pushes the gun through the camera (#350).
## Each shot shoves the viewmodel back toward the eye (WeaponData "Kick Feel":
## kick_back up to 2.8 m/s on the OMEGA, on a soft spring) and flips the muzzle
## up, which swings the stock down and back. The camera's near plane is 5 cm
## out. A gun that crosses it INSIDE the view shows a cut-open cross-section.
## For every gun in the rack and every salvage gun, from the hip and aimed:
## fire two seconds of shots at the gun's own rate (a full magazine at most)
## through WeaponManager._on_fired, and on every frame test the gun's and the
## hands' triangles against the near plane: a triangle that crosses it at a
## point inside the view rectangle is a visible clip.
## Also printed per gun, as a report: the nearest the gun came to the eye and
## the furthest the spring pushed it back.
##   godot --headless --path . --audio-driver Dummy res://tests/kick_clip_probe.tscn

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const FIRE_SECONDS := 2.0
const SETTLE_FRAMES := 45

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## [{mi, verts, idx}] for every drawn mesh under `w`.
func _meshes(w: Node) -> Array:
	var out := []
	for n in w.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arr[Mesh.ARRAY_INDEX] != null:
				idx = arr[Mesh.ARRAY_INDEX]
			else:
				for i in verts.size():
					idx.append(i)
			out.append({"mi": mi, "verts": verts, "idx": idx})
	return out

## [nearest depth in front of the eye (m), true when a triangle crosses the near
## plane inside the view].
func _sample(cam: Camera3D, meshes: Array) -> Array:
	var near := cam.near
	var half_h := near * tan(deg_to_rad(cam.fov) * 0.5)
	var vp := get_viewport().get_visible_rect().size
	var half_w := half_h * vp.x / vp.y
	var to_cam := cam.global_transform.affine_inverse()
	var nearest := INF
	var clip := false
	for m in meshes:
		var mi: MeshInstance3D = m["mi"]
		if not is_instance_valid(mi) or not mi.is_visible_in_tree():
			continue
		var xf: Transform3D = to_cam * mi.global_transform
		var verts: PackedVector3Array = m["verts"]
		var pts := PackedVector3Array()
		pts.resize(verts.size())
		var lo := INF
		for i in verts.size():
			var p := xf * verts[i]
			pts[i] = p
			lo = minf(lo, -p.z)
		nearest = minf(nearest, lo)
		if lo >= near or clip:
			continue
		var idx: PackedInt32Array = m["idx"]
		for t in range(0, idx.size() - 2, 3):
			var a := pts[idx[t]]
			var b := pts[idx[t + 1]]
			var c := pts[idx[t + 2]]
			var da := -a.z - near
			var db := -b.z - near
			var dc := -c.z - near
			if (da < 0.0) == (db < 0.0) and (db < 0.0) == (dc < 0.0):
				continue
			for e in [[a, b, da, db], [b, c, db, dc], [c, a, dc, da]]:
				var d0: float = e[2]
				var d1: float = e[3]
				if (d0 < 0.0) == (d1 < 0.0):
					continue
				var hit: Vector3 = (e[0] as Vector3).lerp(e[1] as Vector3, d0 / (d0 - d1))
				if absf(hit.x) <= half_w and absf(hit.y) <= half_h:
					clip = true
					break
			if clip:
				break
	return [nearest, clip]

func _run() -> void:
	seed(350)
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
	player.set_process(false) # the camera-feel pass would rewrite the fov under the test
	var cam := player.get_node("Head/Camera3D") as Camera3D
	var wm: Node = player.get_node("Head/Camera3D/WeaponHolder")
	var guns: Array = GameState.WEAPON_ORDER.duplicate()
	for k in Salvage.TABLE:
		guns.append(String(Salvage.TABLE[k]["scene"]))
	var tested := 0
	for p: String in guns:
		var id := p.get_file().get_basename()
		wm.add_weapon(load(p), false)
		for i in wm.weapons.size():
			if (wm.weapons[i] as Weapon).scene_file_path == p:
				wm._equip(i)
		var w: Weapon = wm.current
		if w == null or w.scene_file_path != p or w.data == null:
			_check("%s could be equipped" % id, false)
			continue
		tested += 1
		for stance in ["hip", "aimed"]:
			if stance == "aimed":
				Input.action_press("aim")
			else:
				Input.action_release("aim")
			for i in SETTLE_FRAMES:
				await get_tree().process_frame
			var meshes := _meshes(w)
			var rest: Array = _sample(cam, meshes)
			var rate: float = maxf(w.data.fire_rate, 0.5)
			var shots := clampi(int(ceil(FIRE_SECONDS * rate)), 1, maxi(1, int(w.data.mag_size)))
			var nearest: float = rest[0]
			var clipped := false
			var back := 0.0
			var fired := 0
			var t := 0.0
			var next := 0.0
			var last := Time.get_ticks_usec()
			# Fire, then watch the spring settle for a second past the last shot.
			while t < float(shots - 1) / rate + 1.0:
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				t += minf(float(now - last) / 1e6, 0.05)
				last = now
				while fired < shots and t >= next:
					wm._on_fired(w)
					fired += 1
					next += 1.0 / rate
				var s: Array = _sample(cam, meshes)
				nearest = minf(nearest, s[0])
				clipped = clipped or bool(s[1])
				back = maxf(back, (wm.get("_kick_pos") as Vector3).z)
			Input.action_release("aim")
			if bool(rest[1]):
				# At rest already: not the kick's doing. Reported, not failed here.
				print("NOTE %s %s crosses the near plane at rest (nearest %.3f m)" % [id, stance, rest[0]])
			else:
				_check("%s %s: %d shots never push the gun through the camera" % [id, stance, shots], not clipped,
						"rest %.3f m, nearest %.3f m, pushed back %.3f m" % [rest[0], nearest, back])
	_check("every gun was tested", tested == guns.size() and tested >= 14, "%d of %d" % [tested, guns.size()])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
