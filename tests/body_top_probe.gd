extends Node
## Probe: things placed "on the chassis" stay on it, for every enemy scene.
## Several skinned Quaternius GLBs (gunner, hunter, raptor, ravager, hive,
## deepfake, warmech, overfitter) report a bind-pose mesh AABB 50-230x the body,
## and three placements were measured off that top: the weak-point core and the
## damage-flare light (55% of the top, clamped to 3.2 m) and the <think> trace
## height (top + 0.45, clamped to 7 m). They floated in mid-air over those
## robots. For every non-boss enemy, against the body's real top (the higher of
## its collision shape and an AABB-free measure, below): the weak core and the
## flare sit inside it (0.8 m floor for small bots), the trace within 0.8 m over
## (1.2 m floor; the bone measure stops at the neck, so heads need the slack).
##   godot --headless --path . --audio-driver Dummy res://tests/body_top_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## The body's real top, independent of mesh AABBs: skinned meshes by their
## skeleton's posed bones (a bind-pose AABB can be 200x the body; the bones are
## where the body is), plus a head's clearance; rigid meshes by their AABB.
func _real_top(e: Node3D) -> float:
	var top := 0.0
	for n in e.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if mi.skin and sk:
			for b in sk.get_bone_count():
				var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(b).origin
				top = maxf(top, p.y - e.global_position.y)
		else:
			var box: AABB = mi.global_transform * mi.mesh.get_aabb()
			top = maxf(top, box.end.y - e.global_position.y)
	return top

func _run() -> void:
	var n := 0
	for f in DirAccess.get_files_at("res://scenes/enemies"):
		if not f.ends_with(".tscn"):
			continue
		var e = (load("res://scenes/enemies/" + f) as PackedScene).instantiate()
		if not e is EnemyBase:
			e.free()
			continue
		e.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(e)
		for i in 6: # fit_height models fit (and place their flare) a few frames in
			await get_tree().process_frame
		var col_top := 0.0
		for c in e.get_children():
			if c is CollisionShape3D and c.shape:
				var b: AABB = c.global_transform * c.shape.get_debug_mesh().get_aabb()
				col_top = maxf(col_top, b.end.y - e.global_position.y)
		var real := _real_top(e)
		if e.score_value < 1000:
			n += 1
			e._think("alert")
			var body := maxf(real, col_top)
			_check("%s: <think> height" % f, e._think_h <= maxf(1.2, body + 0.8) + 0.01,
					"%.2f over a %.2f m body" % [e._think_h, body])
			e._expose_weak_core()
			if is_instance_valid(e._weak_core):
				_check("%s: weak core on the body" % f, e._weak_core.position.y <= maxf(0.8, body) + 0.01,
						"%.2f in a %.2f m body" % [e._weak_core.position.y, body])
			var rm := e._visual_root as RobotModel
			if rm and is_instance_valid(rm._menace_light):
				var h: float = rm._menace_light.global_position.y - e.global_position.y
				_check("%s: damage flare on the body" % f, h <= maxf(0.8, body) + 0.01, "%.2f in a %.2f m body" % [h, body])
		e.queue_free()
		await get_tree().process_frame
	_check("checked the roster", n >= 30, str(n))
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
