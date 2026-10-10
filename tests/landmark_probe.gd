extends Node3D
## Probe: hero landmarks (scripts/levels/landmark.gd, def key `landmark`).
## (1) every open-sky level def authors a landmark of a known kind;
## (2) built from the real (scaled) def it stands past the floor edge, on the
##     spawn-to-exit heading, and is pure scenery: no collision, no shadows;
## (3) a labelled landmark carries its name tag;
## (4) LOW drops the animated extras;
## (5) a real level scene built through LevelBuilder carries it;
## (6) every interior level gets the AI core, sized into the clear air between
##     the highest walkable top near the centre (+ headroom) and the ceiling,
##     its constants match LevelBuilder's, and its eye turns to the camera.
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
	for id in LevelDefs._defs().keys():
		var d: Dictionary = LevelDefs.get_def(id)
		if d.get("open_sky", false) or String(d.get("landmark", {}).get("kind", "")) == "none":
			continue
		var core := Landmark.build_for(self, d, Color(0.6, 0.8, 1.0), false)
		var ceiling := Landmark._room_height(d) - 0.4
		var spot := Landmark._core_spot(d)
		var floor_top := spot.z
		if core == null:
			_check("%s: no core only when there is no room" % id, spot == Vector3.INF
					or ceiling - floor_top - Landmark.CORE_HEADROOM < Landmark.CORE_MIN_R * 2.7,
					"ceiling %.1f, top %.1f" % [ceiling, floor_top])
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
	cam.free()

	# 4. LOW: no particles, no searchlight sweep.
	var hi := Landmark.build_for(self, LevelDefs.get_def("lava_world"), Color.WHITE, false)
	var lo := Landmark.build_for(self, LevelDefs.get_def("lava_world"), Color.WHITE, true)
	var hi_fx := hi.find_children("*", "CPUParticles3D", true, false).size()
	var lo_fx := lo.find_children("*", "CPUParticles3D", true, false).size()
	_check("LOW drops the steam", hi_fx > 0 and lo_fx == 0, "%d -> %d" % [hi_fx, lo_fx])
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

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
