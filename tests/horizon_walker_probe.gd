extends Node
## Probe: the war machine on the horizon (scripts/levels/horizon_walker.gd).
## (1) every open-sky level with a landmark gets one, out past the megacity's
##     far ring; interiors, `"kind": "none"` and LOW get none;
## (2) it walks: its walk clip plays and it moves round the arena on its ring
##     at about STRIDE_SPEED, facing along its path;
## (3) its eyes ride its head: high on the body, ahead of the head bone along
##     its facing, either side of it;
## (4) a night level gets the searchlight, reaching from its head down toward
##     the arena; a day level does not.
##   godot --headless --path . --audio-driver Dummy res://tests/horizon_walker_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# 1. Which levels.
	var bad: Array = []
	var open := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var holder := Node3D.new()
		add_child(holder)
		var w := HorizonWalker.build_for(holder, def, false)
		var want: bool = def.get("open_sky", false) and String(def.get("landmark", {}).get("kind", "")) != "none"
		if want != (w != null):
			bad.append(id)
		elif w:
			open += 1
			var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
			var far_ring := maxf(fs.x, fs.y) * 0.5 + Skyline.FAR_GAP.y + Skyline.FAR_W.y
			if Vector2(w.position.x, w.position.z).length() < far_ring:
				bad.append("%s inside the far ring" % id)
		if HorizonWalker.build_for(holder, def, true) != null:
			bad.append("%s on LOW" % id)
		holder.queue_free()
	_check("one on every open-sky level, past the far ring; none indoors or on LOW", bad.is_empty() and open > 0,
			"%d open-sky; %s" % [open, str(bad)])

	# 2. Walking.
	var stage := Node3D.new()
	add_child(stage)
	var night := HorizonWalker.build_for(stage, LevelDefs.get_def("titan"), false)
	night.set_process(false)
	for i in 3:
		await get_tree().process_frame
	_check("its walk clip plays", night._anim != null and night._anim.is_playing()
			and night._anim.current_animation == HorizonWalker.WALK)
	var p0 := night.global_position
	for i in 120:
		night.tick(1.0 / 60.0)
	var moved := night.global_position.distance_to(p0)
	_check("it covers about STRIDE_SPEED in 2 s", absf(moved - HorizonWalker.STRIDE_SPEED * 2.0) < 1.0, "%.1f m" % moved)
	_check("on its ring", absf(Vector2(night.global_position.x, night.global_position.z).length() - night.radius) < 0.5)
	var step := (night.global_position - p0).normalized()
	_check("facing along its path", night.global_transform.basis.z.normalized().dot(step) > 0.95)

	# 3. Eyes.
	var head := night.head_position()
	var fwd := night.global_transform.basis.z.normalized()
	print("head ", head, " walker ", night.global_position)
	var eyes_ok := night._eyes.size() == 2
	for e in night._eyes:
		var rel := e.global_position - head
		print("eye ", e.global_position, " rel ", rel)
		eyes_ok = eyes_ok and rel.dot(fwd) > 0.0 and e.global_position.y > night.global_position.y + HorizonWalker.SCALE * 2.0
	_check("two eyes, high, ahead of the head", eyes_ok)
	if night._eyes.size() == 2:
		_check("either side of it", night._eyes[0].global_position.distance_to(night._eyes[1].global_position) > HorizonWalker.EYE_R * 2.0)

	# 4. Searchlight.
	_check("a night level has the searchlight", is_instance_valid(night._beam))
	if is_instance_valid(night._beam):
		var xf := night._beam.global_transform
		var top := xf * Vector3(0, HorizonWalker.BEAM_LEN * 0.5, 0)
		var foot := xf * Vector3(0, -HorizonWalker.BEAM_LEN * 0.5, 0)
		_check("from its head toward the arena", top.distance_to(head) < 2.0
				and Vector2(foot.x, foot.z).length() < Vector2(head.x, head.z).length() - 50.0 and foot.y < 5.0,
				"top %s foot %s" % [top, foot])
	var day_id := ""
	for id in LevelDefs._defs().keys():
		var d: Dictionary = LevelDefs.get_def(id)
		if d.get("open_sky", false) and not d.get("env", {}).has("stars") and day_id == "":
			day_id = id
	var day := HorizonWalker.build_for(stage, LevelDefs.get_def(day_id), false) if day_id != "" else null
	_check("a day level does not", day != null and not is_instance_valid(day._beam), day_id)

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
