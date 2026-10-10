extends Node3D
## Probe: hero landmarks (scripts/levels/landmark.gd, def key `landmark`).
## (1) every open-sky level def authors a landmark of a known kind;
## (2) built from the real (scaled) def it stands past the floor edge, on the
##     spawn-to-exit heading, and is pure scenery: no collision, no shadows;
## (3) a labelled landmark carries its name tag;
## (4) an interior level gets none, and LOW drops the animated extras;
## (5) a real level scene built through LevelBuilder carries it.
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

	# 4. Interior: none. LOW: no particles, no searchlight sweep.
	var inner: Dictionary = LevelDefs.get_def("claude")
	_check("interior level gets none", not inner.get("open_sky", false)
			and Landmark.build_for(self, inner, Color.WHITE, false) == null)
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
