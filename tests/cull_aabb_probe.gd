extends Node
## Probe: every robot's culling box is the size of the robot (#207). Imported
## skinned Quaternius meshes carry a bind-pose AABB 50-300x the body; a box that
## size sits in the view (and the sun's shadow) frustum from almost anywhere on
## a level, so the robot draws and casts shadows behind the camera.
## RobotModel pins each sub-mesh's custom_aabb to the posed model, for fitted
## models in _apply_fit and for scene-sized ones in _clamp_after_pose (since
## ff8eda5; the table in #207 read the mesh AABB, which culling never sees once
## custom_aabb is set). For every enemy scene, a few frames after it spawns on a
## floor, each visible mesh's effective cull box (custom_aabb when set, else the
## mesh AABB), in world space, must top out within CULL_LIMIT x the body's
## collision top (MIN_EXTENT floor) and span at most twice that across. The
## clamp grows the posed box by >= 0.6 m and 10% of its diagonal for wide clips,
## so a box that fits sits at up to 3.1x a short hitbox (ravager 7.5 m on a
## 2.4 m capsule, shark 5.2 m on 0.7 m); the bloated class it guards against is
## 18-300 m (overfitter 18.3, gunner 298 with the clamp disabled).
##   godot --headless --path . --audio-driver Dummy res://tests/cull_aabb_probe.tscn

const CULL_LIMIT := 4.0
## Floor for small bots, whose clamp margin dwarfs their hitbox.
const MIN_EXTENT := 6.0

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	var n := 0
	var x := -180.0
	for f in DirAccess.get_files_at("res://scenes/enemies"):
		if not f.ends_with(".tscn"):
			continue
		var e = (load("res://scenes/enemies/" + f) as PackedScene).instantiate()
		if not e is EnemyBase:
			e.free()
			continue
		add_child(e)
		e.global_position = Vector3(x, 0.05, 0)
		x += 7.0
		e.set_physics_process(false) # stand still; RobotModel still poses and clamps
		for i in 8: # fitted models fit, scene-sized ones clamp, a few frames in
			await get_tree().process_frame
		var col_top := 0.0
		for c in e.get_children():
			if c is CollisionShape3D and c.shape:
				var b: AABB = c.global_transform * c.shape.get_debug_mesh().get_aabb()
				col_top = maxf(col_top, b.end.y - e.global_position.y)
		var top := 0.0
		var span := 0.0
		var raw := 0.0 # the imported mesh AABB, which culling would use unclamped
		for m in e.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var local: AABB = mi.custom_aabb if mi.custom_aabb.has_volume() else mi.mesh.get_aabb()
			var w: AABB = mi.global_transform * local
			top = maxf(top, w.end.y - e.global_position.y)
			raw = maxf(raw, (mi.global_transform * mi.mesh.get_aabb()).end.y - e.global_position.y)
			span = maxf(span, maxf(w.size.x, w.size.z))
		var limit := maxf(MIN_EXTENT, col_top * CULL_LIMIT)
		_check("%s cull box fits the robot" % f.get_basename(), top <= limit and span <= limit * 2.0,
			"top %.1f m, across %.1f m, collision top %.2f m (limit %.1f m; mesh AABB top %.1f m)" % [top, span, col_top, limit, raw])
		e.queue_free()
		n += 1
	_check("measured every enemy scene", n >= 40, "%d scenes" % n)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
