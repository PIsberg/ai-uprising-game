extends Node
## Probe (#339): nothing hangs over a ramp with less than player headroom.
## Red before: 14 spots, each a sky-bridge or approach stair landing
## on a tower roof low over the spiral's top segment, where the real player
## stopped (ramp_walk_triage, 3 of 3 walks).
## The builder turns each spiral (its phase) away from bridges LEAVING the roof
## only. Counting arriving bridges too, for every tower at once, moved spirals
## that needed no change, and that disconnected sublevel's navmesh
## (mission_arc_probe: three shards and the hack terminal unreachable). Reverted
## twice (2026-10-17, 2026-10-20). The fix is per tower instead: an authored
## "phase" in the def, chosen by building the level in each phase, plus one
## moved stair on sublevel, whose tower has bridges over two opposite faces.
## Builds every level whose def has both towers and stairs, samples each ramp's
## centre line every SAMPLE_STEP m and casts up CLEARANCE_M. Any body hit is
## reported, not only ramps (hanging lamps sat 0.66 m over gpt's sky-bridge).
## The room's ceiling and a house stair's slab (built CLEARANCE_M over its stair
## on purpose) are skipped, as in ramp_probe. Off the centre line it is blind:
## casting a capsule radius to the side flagged 40 more spots, nearly all a
## 3 cm brush with a tower's own roof edge that the real walker passes, so a
## lamp 0.35 m off the line (assembly, after a spiral turn) needs the walker.
##   godot --headless --path . --audio-driver Dummy res://tests/bridge_headroom_probe.tscn

## The builder's own clearance: player capsule (1.8 m) + margin. 1.9 m passed
## mistral's TwrRamp3 at 1.94 m, where the real walker stopped 3 of 3 times.
const CLEARANCE_M := LevelBuilder.PLAYER_CLEARANCE_M
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
		for line in scan(lvl):
			bad.append("%s %s" % [id, line])
		lvl.queue_free()
		for i in 5:
			await get_tree().physics_frame
	print("levels %d" % levels)
	for line in bad:
		print("  LOW " + line)
	_check("levels with towers and stairs were built", levels > 0)
	_check("nothing hangs over a ramp with less than %.1f m of headroom" % CLEARANCE_M, bad.is_empty(), "%d low" % bad.size())
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## One line per ramp of the built level `lvl` with something over it lower
## than CLEARANCE_M. Static so a phase sweep can run the same check.
static func scan(lvl: Node) -> Array[String]:
	var out: Array[String] = []
	var space := (lvl as Node3D).get_world_3d().direct_space_state
	for b in lvl.get_tree().get_nodes_in_group("ramp_surface"):
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
			var uq := PhysicsRayQueryParameters3D.create(s + Vector3.UP * 0.05, s + Vector3.UP * CLEARANCE_M, 1)
			uq.exclude = [(b as CollisionObject3D).get_rid()]
			var up := space.intersect_ray(uq)
			if up.is_empty() or _ignored(up.collider):
				continue
			var room: float = up.position.y - s.y
			if room < worst:
				worst = room
				over = up.collider
		if over != null:
			out.append("ramp %s -> %s runs under %s with %.2f m of headroom" % [f, t, _label(over), worst])
	return out

static func _ignored(n: Node) -> bool:
	return n.is_in_group("level_ceiling") or n.is_in_group("stair_ceiling")

static func _label(n: Node) -> String:
	if n.has_meta("ramp_from"):
		return "the ramp %s -> %s" % [n.get_meta("ramp_from"), n.get_meta("ramp_to")]
	var at := ""
	if n is Node3D:
		at = " at %s" % (n as Node3D).global_position
	return "%s%s %s" % [n.name, at, n.get_groups()]

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false
