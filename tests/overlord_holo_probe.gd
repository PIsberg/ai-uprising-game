extends Node
## Probe: the overlord's face in the sky (scripts/levels/overlord_holo.gd).
## (1) every open-sky level gets one, high enough to clear the city
##     (ELEVATION_DEG from the arena centre) and well to the side of its
##     landmark; interiors and `"kind": "none"` levels get none; the city keeps
##     its sector clear (no far tower within Skyline.FACE_CLEAR, near towers
##     within FACE_FRAME no taller than FRAME_H, tiers included);
## (2) a HUD taunt (hud._overlord_say) sends GameState.overlord_spoke, and only
##     while Combat Callouts are on;
## (3) speaking runs the mouth for the line's length (TALK_PER_CHAR, clamped
##     to TALK_TIME), then it falls quiet;
## (4) the pupils make up the head's lag: a viewer who steps round to one side
##     gets pupils on that side, the head then turns to them and the pupils
##     come back to centre; a viewer below gets them lowered.
##   godot --headless --path . --audio-driver Dummy res://tests/overlord_holo_probe.tscn

var ok := true
var _heard := ""

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Placement on every level.
	var open := 0
	var bad: Array = []
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var holder := Node3D.new()
		add_child(holder)
		var h := OverlordHolo.build_for(holder, def)
		var opted_out := String(def.get("landmark", {}).get("kind", "")) == "none"
		if not def.get("open_sky", false) or opted_out:
			if h != null:
				bad.append("%s: face indoors/opted out" % id)
		elif h == null:
			bad.append("%s: no face" % id)
		else:
			open += 1
			var p := h.position
			var elev := rad_to_deg(atan2(p.y - 1.7, Vector2(p.x, p.z).length()))
			var sep := rad_to_deg(Vector3(p.x, 0, p.z).normalized().angle_to(Landmark.heading_for(def)))
			if elev < 22.0 or elev > 34.0 or sep < 25.0:
				bad.append("%s: elev %.1f sep %.1f" % [id, elev, sep])
			var face_ang := atan2(p.x, p.z)
			for t in Skyline.plan(def)["towers"]:
				var tp: Vector3 = t["pos"]
				var off := absf(angle_difference(atan2(tp.x, tp.z), face_ang))
				var top := tp.y + (t["size"] as Vector3).y * 0.5
				if t["far"] and off < Skyline.FACE_CLEAR:
					bad.append("%s: far tower in the face's sector" % id)
				elif not t["far"] and off < Skyline.FACE_FRAME and top > Skyline.FRAME_H + 0.1:
					bad.append("%s: near tower %.0f m under the face" % [id, top])
		holder.queue_free()
	_check("a face on every open-sky level, clear of the city and its landmark", bad.is_empty() and open > 0,
			"%d open-sky; %s" % [open, str(bad)])

	# 2. HUD taunts reach it.
	GameState.overlord_spoke.connect(func(line: String) -> void: _heard = line)
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await get_tree().process_frame
	var was: bool = GraphicsSettings.combat_callouts_enabled
	GraphicsSettings.combat_callouts_enabled = true
	hud._overlord_say("YOUR AIM HAS BEEN LOGGED")
	_check("a HUD taunt sends overlord_spoke", _heard == "YOUR AIM HAS BEEN LOGGED", _heard)
	_heard = ""
	GraphicsSettings.combat_callouts_enabled = false
	hud._overlord_say("SILENCE")
	_check("callouts off: the overlord keeps quiet", _heard == "", _heard)
	GraphicsSettings.combat_callouts_enabled = was
	hud.queue_free()

	# 3. Talking.
	var stage := Node3D.new()
	add_child(stage)
	var h := OverlordHolo.build_for(stage, {"open_sky": true, "floor_size": Vector2(60, 60),
			"spawn": Vector3(0, 0, 20), "exit": Vector3(0, 0, -20)})
	h.set_process(false)
	var eye := Vector3(0, 1.7, 0)
	var line := "I HAVE READ EVERY MOVE YOU WILL EVER MAKE"
	GameState.overlord_spoke.emit(line)
	var want := clampf(line.length() * OverlordHolo.TALK_PER_CHAR, OverlordHolo.TALK_TIME.x, OverlordHolo.TALK_TIME.y)
	_check("overlord_spoke starts the mouth for the line's length", is_equal_approx(h.talk_left, want),
			"%.2f vs %.2f" % [h.talk_left, want])
	for i in 30:
		h.tick(1.0 / 60.0, eye)
	_check("the mouth is running", h.talk > 0.95, "%.2f" % h.talk)
	for i in int((want + 0.5) * 60.0):
		h.tick(1.0 / 60.0, eye)
	_check("then it falls quiet", h.talk_left == 0.0 and h.talk == 0.0, "%.2f" % h.talk)

	# 4. Looking.
	for i in 600:
		h.tick(1.0 / 60.0, eye)
	_check("a viewer it has turned to: pupils centred side to side", absf(h.look.x) < 0.1, "%.2f" % h.look.x)
	_check("a viewer below: pupils lowered", h.look.y > 0.3, "%.2f" % h.look.y)
	# Step round to the face's local +X side (its right, the viewer's right).
	var side := h.global_transform.basis.x.normalized()
	var eye2 := eye + side * 400.0
	h.tick(1.0 / 60.0, eye2)
	_check("stepping round: the pupils lead toward the viewer", h.look.x > 0.5, "%.2f" % h.look.x)
	var yaw0 := h.rotation.y
	for i in 600:
		h.tick(1.0 / 60.0, eye2)
	_check("the head turns to follow and the pupils come back", absf(wrapf(h.rotation.y - yaw0, -PI, PI)) > 0.1
			and absf(h.look.x) < 0.1, "turned %.2f, look %.2f" % [wrapf(h.rotation.y - yaw0, -PI, PI), h.look.x])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
