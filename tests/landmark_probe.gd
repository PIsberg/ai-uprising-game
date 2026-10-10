extends Node3D
## Probe: hero landmarks (scripts/levels/landmark.gd, def key `landmark`).
## (1) every open-sky level def authors a landmark of a known kind;
## (2) built from the real (scaled) def it stands past the floor edge, on the
##     spawn-to-exit heading, and is pure scenery: no collision, no shadows;
## (3) a labelled landmark carries its name tag;
## (4) LOW drops the animated extras (steam, and the drone flocks: every
##     open-sky landmark has at least two flocks of lit drones wheeling high
##     around it, shadowless, moving frame to frame);
## (5) a real level scene built through LevelBuilder carries it;
## (6) every interior level gets the AI core, sized into the clear air between
##     the highest walkable top near the centre (+ headroom) and the ceiling,
##     its constants match LevelBuilder's, and its eye turns to the camera;
## (8) every interior AI (core or screen) is fed by at least CABLES_MIN data
##     conduits strung from the perimeter walls under the ceiling: each starts
##     at a wall, ends on the AI, stays between 4 m and the ceiling, and passes
##     through no authored wall, platform or tower;
## (7) an interior with no room for the core gets the wall screen instead: on a
##     perimeter wall ahead of the spawn, just off its inner face, above head
##     height and under the ceiling, clear of every route gate and authored wall
##     that meets that wall, pure scenery; its pupil follows the camera; and the
##     facility billboard moves off the screen's wall (claude, guardrails, range).
##   godot --headless --path . --audio-driver Dummy res://tests/landmark_probe.tscn

const KINDS := ["spire", "twin", "dish", "stacks", "monolith"]
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var n_open := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		if not def.get("open_sky", false):
			continue
		n_open += 1
		var spec: Dictionary = def.get("landmark", {})
		_check("%s authors a landmark" % id, KINDS.has(String(spec.get("kind", ""))), str(spec))
		var lm := Landmark.build_for(self, def, Color(0.6, 0.8, 1.0), false)
		if lm == null:
			_check("%s builds" % id, false)
			continue
		var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
		var flat := Vector2(lm.position.x, lm.position.z)
		_check("%s stands past the floor" % id, flat.length() > maxf(fs.x, fs.y) * 0.5 + 100.0,
				"%.0f m vs half-floor %.0f" % [flat.length(), maxf(fs.x, fs.y) * 0.5])
		var ex: Vector3 = def.get("exit", Vector3(0, 0, -1))
		var sp: Vector3 = def.get("spawn", Vector3.ZERO)
		var heading := Vector2(ex.x - sp.x, ex.z - sp.z)
		if heading.length() > 1.0 and float(spec.get("bearing", 0.0)) == 0.0:
			_check("%s is ahead of the player" % id, flat.normalized().dot(heading.normalized()) > 0.99)
		var meshes := lm.find_children("*", "GeometryInstance3D", true, false)
		var lit := true
		for g in meshes:
			if (g as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				lit = false
		_check("%s is scenery" % id, meshes.size() >= 6 and lit
				and lm.find_children("*", "CollisionObject3D", true, false).is_empty(),
				"%d pieces" % meshes.size())
		var flocks := lm.find_children("Flock*", "MultiMeshInstance3D", true, false)
		var flock_ok := flocks.size() >= 2
		for f in flocks:
			var mm := (f as MultiMeshInstance3D).multimesh
			flock_ok = flock_ok and mm.instance_count >= Landmark.FLOCK_MIN
			for i in mm.instance_count:
				flock_ok = flock_ok and (lm.global_transform * lm.flock_point(flocks.find(f), i)).y > 60.0
		_check("%s has its drone flocks, high in the sky" % id, flock_ok, "%d flocks" % flocks.size())
		# Night levels: a data aurora high over the skyline, past the floor edge.
		var aur := lm.get_node_or_null("Aurora") as MeshInstance3D
		if def.get("env", {}).has("stars"):
			var ab: AABB = aur.global_transform * aur.mesh.get_aabb() if aur else AABB()
			var flat_c := Vector2(ab.get_center().x, ab.get_center().z)
			_check("%s (night) has a data aurora high past the skyline" % id, aur != null
					and ab.position.y > 70.0 and flat_c.length() > maxf(fs.x, fs.y) * 0.5,
					"low %.0f m, %.0f m out" % [ab.position.y, flat_c.length()])
		else:
			_check("%s (day) has no aurora" % id, aur == null)
		var want := String(spec.get("sign", ""))
		var tag := lm.get_node_or_null("NameTag") as Label3D
		if want != "":
			_check("%s name tag reads %s" % [id, want], tag != null and tag.text == want)
		else:
			_check("%s has no name tag" % id, tag == null)
		lm.free()
	_check("open-sky levels covered", n_open >= 10, "%d" % n_open)

	# 6. Interior cores.
	_check("room height mirrors LevelBuilder", Landmark.ROOM_BASE_H == LevelBuilder.WALL_HEIGHT
			and Landmark.ROOM_CLEARANCE_M == LevelBuilder.PLAYER_CLEARANCE_M)
	var n_core := 0
	var n_screen := 0
	for id in LevelDefs._defs().keys():
		var d: Dictionary = LevelDefs.get_def(id)
		if d.get("open_sky", false) or String(d.get("landmark", {}).get("kind", "")) == "none":
			continue
		var core := Landmark.build_for(self, d, Color(0.6, 0.8, 1.0), false)
		var ceiling := Landmark._room_height(d) - 0.4
		var spot := Landmark._core_spot(d)
		var floor_top := spot.z
		_check("%s gets an interior landmark" % id, core != null)
		if core == null:
			continue
		_check_cables(id, d, core)
		if core.kind == "screen":
			_check("%s: a screen only when there is no room for the core" % id, spot == Vector3.INF
					or ceiling - floor_top - Landmark.CORE_HEADROOM < Landmark.CORE_MIN_R * 2.7,
					"ceiling %.1f, top %.1f" % [ceiling, floor_top])
			_check_screen(id, d, core)
			n_screen += 1
			core.free()
			continue
		_check("%s core is clear of the route gates" % id,
				not Landmark._near_gate(d, Vector2(core.position.x, core.position.z)))
		n_core += 1
		var r := core.core_radius
		var lo := core.position.y - r * 1.35
		var hi := core.position.y + r * 1.35
		_check("%s core clears the walkable tops and the ceiling" % id,
				lo >= floor_top + Landmark.CORE_HEADROOM - 0.01 and hi <= ceiling + 0.01,
				"r %.1f, %.1f..%.1f m (top %.1f, ceiling %.1f)" % [r, lo, hi, floor_top, ceiling])
		_check("%s core is scenery" % id, core.find_children("*", "CollisionObject3D", true, false).is_empty())
		core.free()
	_check("interior levels get a core", n_core >= 6, "%d" % n_core)
	_check("the rest get a screen", n_screen >= 3, "%d" % n_screen)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var eye_core := Landmark.build_for(self, LevelDefs.get_def("mistral"), Color.WHITE, false)
	_check("mistral builds a core for the eye check", eye_core != null)
	if eye_core:
		cam.global_position = eye_core.global_position + Vector3(9, -4, 3)
		for i in 90:
			await get_tree().process_frame
		var want: Vector3 = (cam.global_position - (eye_core.get_node("Eye") as Node3D).global_position).normalized()
		_check("the eye turns to the camera", eye_core.eye_forward().dot(want) > 0.97,
				"dot %.3f" % eye_core.eye_forward().dot(want))
		eye_core.free()
	var scr := Landmark.build_for(self, LevelDefs.get_def("guardrails"), Color.WHITE, false)
	_check("guardrails builds a screen for the pupil check", scr != null and scr.kind == "screen")
	if scr:
		var right := scr.global_basis.x
		cam.global_position = scr.global_position + scr.global_basis.z * 12.0 + right * 10.0
		for i in 60:
			await get_tree().process_frame
		var lr := scr.look.x
		cam.global_position = scr.global_position + scr.global_basis.z * 12.0 - right * 10.0
		for i in 60:
			await get_tree().process_frame
		_check("the pupil follows the camera", lr > 0.3 and scr.look.x < -0.3,
				"%.2f right, %.2f left" % [lr, scr.look.x])
		scr.free()
	cam.free()

	# 4. LOW: no particles, no searchlight sweep.
	var hi := Landmark.build_for(self, LevelDefs.get_def("lava_world"), Color.WHITE, false)
	var lo := Landmark.build_for(self, LevelDefs.get_def("lava_world"), Color.WHITE, true)
	var hi_fx := hi.find_children("*", "CPUParticles3D", true, false).size()
	var lo_fx := lo.find_children("*", "CPUParticles3D", true, false).size()
	_check("LOW drops the steam", hi_fx > 0 and lo_fx == 0, "%d -> %d" % [hi_fx, lo_fx])
	var night_hi := Landmark.build_for(self, LevelDefs.get_def("titan"), Color.WHITE, false)
	var night_lo := Landmark.build_for(self, LevelDefs.get_def("titan"), Color.WHITE, true)
	_check("LOW drops the aurora", night_hi.get_node_or_null("Aurora") != null and night_lo.get_node_or_null("Aurora") == null)
	night_hi.free()
	night_lo.free()
	_check("LOW drops the flocks", hi.find_children("Flock*", "MultiMeshInstance3D", true, false).size() >= 2
			and lo.find_children("Flock*", "MultiMeshInstance3D", true, false).is_empty())
	var p0 := hi.flock_point(0, 3)
	for i in 20:
		await get_tree().process_frame
	_check("the flocks wheel", hi.flock_point(0, 3).distance_to(p0) > 0.5, "%.2f m" % hi.flock_point(0, 3).distance_to(p0))
	hi.free()
	lo.free()

	# 5. Through the real builder.
	var lvl := (load("res://scenes/levels/level_gemini.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().process_frame
	var built := lvl.get_node_or_null("Landmark") as Landmark
	_check("level_gemini builds its landmark", built != null and built.kind == "twin")
	lvl.queue_free()
	await get_tree().process_frame
	var rng := (load("res://scenes/levels/level_range.tscn") as PackedScene).instantiate()
	add_child(rng)
	await get_tree().process_frame
	var rs := rng.get_node_or_null("Landmark") as Landmark
	var board := rng.find_child("Billboard", true, false) as Node3D
	_check("level_range builds its screen", rs != null and rs.kind == "screen")
	_check("the billboard is not on the screen's wall", rs != null and board != null
			and board.global_basis.z.dot(rs.global_basis.z) < 0.5)
	rng.queue_free()
	await get_tree().process_frame

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

## The wall screen's placement rules, against the scaled def.
func _check_screen(id: String, d: Dictionary, s: Landmark) -> void:
	var fs: Vector2 = d.get("floor_size", Vector2(40, 40))
	var n := s.global_basis.z # the screen faces into the room
	var half := Vector2(fs.x, fs.y) * 0.5
	# Distance from the wall's inner face (1 m walls centred on the floor edge).
	var face := (half.y if absf(n.z) > 0.5 else half.x) - 0.5
	var along_wall := s.global_position.z if absf(n.z) > 0.5 else s.global_position.x
	var off := face - absf(along_wall)
	_check("%s screen sits just off a perimeter wall" % id, absf(n.x) > 0.99 or absf(n.z) > 0.99, str(n))
	_check("%s screen within 0.6 m of the wall face" % id, off > 0.02 and off < 0.6, "%.2f" % off)
	var spawn: Vector3 = d.get("spawn", Vector3.ZERO)
	var target: Vector3 = d.get("exit", Vector3.ZERO) if d.get("exit") != null else Vector3.ZERO
	var heading := target - spawn
	heading.y = 0.0
	_check("%s screen is on a wall ahead of the spawn" % id, heading.normalized().dot(-n) > 0.3,
			"%.2f" % heading.normalized().dot(-n))
	var lo := s.global_position.y - s.screen_size.y * 0.5
	var hi := s.global_position.y + s.screen_size.y * 0.5
	_check("%s screen above head height, under the ceiling" % id,
			lo >= Landmark.SCREEN_BOTTOM - 0.01 and hi <= Landmark._room_height(d) - 0.2,
			"%.1f..%.1f m" % [lo, hi])
	# Along-wall span, in the world axis that runs along this wall.
	var x_wall := absf(n.z) > 0.5 # wall runs along x
	var c := s.global_position.x if x_wall else s.global_position.z
	var a0 := c - s.screen_size.x * 0.5
	var a1 := c + s.screen_size.x * 0.5
	var lim := (half.x if x_wall else half.y) - 0.5
	_check("%s screen fits the wall" % id, a0 > -lim and a1 < lim and s.screen_size.x >= Landmark.SCREEN_MIN_W,
			"%.1f..%.1f of +-%.1f" % [a0, a1, lim])
	for g in d.get("gates", []):
		# An "x" gate is a wall at x=at running along z: it meets the x-running walls.
		if (String(g.get("axis", "z")) == "x") == x_wall:
			var at := float(g.get("at", 0.0))
			_check("%s screen clear of the gate at %.1f" % [id, at], at < a0 - 0.5 or at > a1 + 0.5)
	for key in ["walls", "platforms"]:
		for w in d.get(key, []):
			var p: Vector3 = w.get("pos", Vector3.ZERO)
			var sz: Vector3 = w.get("size", Vector3.ONE)
			var reach := (absf(p.z) + sz.z * 0.5) if x_wall else (absf(p.x) + sz.x * 0.5)
			var same_side := signf(p.z if x_wall else p.x) == signf(along_wall)
			if not same_side or reach < face - 1.2 or p.y + sz.y * 0.5 <= lo:
				continue
			var b0 := (p.x if x_wall else p.z) - (sz.x if x_wall else sz.z) * 0.5
			var b1 := (p.x if x_wall else p.z) + (sz.x if x_wall else sz.z) * 0.5
			_check("%s screen clear of %s at %s" % [id, key, p], b1 < a0 or b0 > a1)
	_check("%s screen is scenery" % id, s.find_children("*", "CollisionObject3D", true, false).is_empty())

## The data conduits feeding an interior AI (rule 8), level-local.
func _check_cables(id: String, d: Dictionary, lm: Landmark) -> void:
	var ends := lm.cable_ends()
	_check("%s has its data conduits" % id, ends.size() >= Landmark.CABLES_MIN, "%d" % ends.size())
	var fs: Vector2 = d.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5 - 0.5
	var hz := fs.y * 0.5 - 0.5
	var room_h := Landmark._room_height(d)
	var anchor := lm.cable_anchor()
	var bad: Array = []
	for pair in ends:
		var a: Vector3 = pair[0]
		var b: Vector3 = pair[1]
		var at_wall := absf(absf(a.x) - hx) < 1.2 or absf(absf(a.z) - hz) < 1.2
		if not at_wall:
			bad.append("start %s off the walls" % a)
		if b.distance_to(anchor) > lm.cable_anchor_reach() + 0.05:
			bad.append("end %s off the AI" % b)
		if minf(a.y, b.y) < 4.0 or maxf(a.y, b.y) > room_h - 0.1:
			bad.append("height %.1f..%.1f" % [minf(a.y, b.y), maxf(a.y, b.y)])
		var steps := int(a.distance_to(b) / 0.4) + 1
		for k in steps + 1:
			var p := a.lerp(b, float(k) / float(steps))
			for key in ["walls", "platforms"]:
				for w in d.get(key, []):
					var c: Vector3 = w.get("pos", Vector3.ZERO)
					var sz: Vector3 = w.get("size", Vector3.ONE)
					if absf(p.x - c.x) < sz.x * 0.5 and absf(p.z - c.z) < sz.z * 0.5 							and absf(p.y - c.y) < sz.y * 0.5:
						bad.append("through %s at %s" % [key, c])
			for t in d.get("towers", []):
				var c: Vector3 = t.get("pos", Vector3.ZERO)
				if Vector2(p.x - c.x, p.z - c.z).length() < float(t.get("radius", 3.0)) 						and p.y < float(t.get("height", 8.0)):
					bad.append("through a tower at %s" % c)
	_check("%s conduits run wall to AI above the fight, through nothing" % id, bad.is_empty(),
			str(bad.slice(0, 3)))

