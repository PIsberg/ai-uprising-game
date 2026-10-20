extends Node
## Report tool (#339): where a ramp passes over another ramp with less than
## player headroom. Every case found is a sky-bridge or approach stair running
## low over a tower spiral's segment, and the real player stops under it
## (ramp_walk_triage, 3 of 3 walks).
## The builder turns each spiral (its phase) away from bridges LEAVING the roof
## only. Counting arriving bridges too, and picking the phase with the most
## room, cleared 10 of the 14 spots this lists, but rotating a spiral moves its
## ground start and landings, and that disconnected sublevel's navmesh
## (mission_arc_probe: three shards and the hack terminal unreachable) and
## opened new stops elsewhere (mistral TwrRamp1, assembly TwrRamp3). Reverted
## twice now (2026-10-17, 2026-10-20). The clean fix is per level: move the
## bridge or stair, or the tower, so no stair crosses the spiral low.
## Not in the suite while it finds anything; it fails until the list is empty.
## Builds every level whose def has both towers and stairs, samples each ramp's
## centre line every SAMPLE_STEP m and casts up CLEARANCE_M; a hit on another
## ramp body is reported.
##   godot --headless --path . --audio-driver Dummy res://tests/bridge_headroom_probe.tscn

const CLEARANCE_M := 1.9 ## player capsule (1.8 m) + a hand's breadth
const SAMPLE_STEP := 0.25

var ok := true

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			ids = Array(a.substr(7).split(",", false))
	if ids.is_empty():
		for id in LevelDefs._defs().keys():
			var def := LevelDefs.get_def(id)
			if not def.get("towers", []).is_empty() and not def.get("stairs", []).is_empty():
				ids.append(id)
	var levels := 0
	var bad: Array[String] = []
	for id in ids:
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			continue
		seed(hash(id))
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		for i in 30:
			await get_tree().physics_frame
		levels += 1
		var space := get_viewport().get_world_3d().direct_space_state
		for b in get_tree().get_nodes_in_group("ramp_surface"):
			if not lvl.is_ancestor_of(b):
				continue
			var f: Vector3 = b.get_meta("ramp_from")
			var t: Vector3 = b.get_meta("ramp_to")
			var run := Vector2(t.x - f.x, t.z - f.z).length()
			if run < 0.5:
				continue
			var n := int(ceil(run / SAMPLE_STEP))
			var worst := INF
			var over: Node = null
			for i in range(n + 1):
				var p := f.lerp(t, float(i) / float(n))
				# The surface itself, then straight up from just above it.
				var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.3, p - Vector3.UP * 0.6, 1))
				if down.is_empty() or down.collider != b:
					continue
				var s: Vector3 = down.position
				var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(s + Vector3.UP * 0.05, s + Vector3.UP * CLEARANCE_M, 1))
				if up.is_empty() or not (up.collider as Node).is_in_group("ramp_surface") or up.collider == b:
					continue
				var room: float = up.position.y - s.y
				if room < worst:
					worst = room
					over = up.collider
			if over != null:
				bad.append("%s ramp %s -> %s runs under the ramp %s -> %s with %.2f m of headroom" % [
					id, f, t, over.get_meta("ramp_from"), over.get_meta("ramp_to"), worst])
		lvl.queue_free()
		for i in 5:
			await get_tree().physics_frame
	print("levels %d" % levels)
	for line in bad:
		print("  LOW " + line)
	_check("levels with towers and stairs were built", levels > 0)
	_check("no ramp runs under another with less than %.1f m of headroom" % CLEARANCE_M, bad.is_empty(), "%d low" % bad.size())
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false
