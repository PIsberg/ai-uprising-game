extends Node3D
## Measures every regular enemy's IN-GAME visual height (world AABB of its
## meshes after RobotModel fitting) so under-scaled chassis stand out against
## their codex role. Prints one line per enemy.
##   godot --headless --path . --audio-driver Dummy res://tests/enemy_scale_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	for t in EnemyCodex.ORDER:
		var entry: Dictionary = EnemyCodex.ENTRIES.get(t, {})
		var path: String = entry.get("scene", "")
		if path == "" or not ResourceLoader.exists(path):
			continue
		var e := (load(path) as PackedScene).instantiate() as Node3D
		add_child(e)
		e.set_physics_process(false)
		# Let RobotModel run its deferred fit (bone AABB path needs a few frames;
		# skinned rigs need the idle clip to pose before the fit lands).
		await get_tree().create_timer(0.7).timeout
		var ab := AABB()
		var first := true
		# Skinned rigs report misleading rest-pose mesh AABBs — measure their
		# POSED bones instead (same trick the codex framing uses).
		var skel := e.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel and skel.get_bone_count() > 0:
			for b in skel.get_bone_count():
				var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b)).origin
				if first:
					ab = AABB(p, Vector3.ZERO); first = false
				else:
					ab = ab.expand(p)
			ab = ab.grow(ab.size.length() * 0.06)
		else:
			for mi in e.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				if m.mesh == null:
					continue
				var part: AABB = m.global_transform * m.mesh.get_aabb()
				if first:
					ab = part; first = false
				else:
					ab = ab.merge(part)
		var w := maxf(ab.size.x, ab.size.z)
		print("%-12s height=%5.2f width=%5.2f" % [t, ab.size.y, w])
		e.queue_free()
		await get_tree().process_frame
	print("RESULT PASS")
	get_tree().quit()
