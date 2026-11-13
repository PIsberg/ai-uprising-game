extends Node3D
## Probe (#436): an indoor luminaire never hangs in the headroom over something
## built under it, never stands inside a solid, and never floats.
##
## The builder places every indoor luminaire first, at the stock 6 m ceiling
## height, before any tower, deck, bridge or pillar exists; once the solids are
## in the physics space each fixture settles (ShootableLight.settle, from
## LevelBuilder._settle_luminaires). Measured before that pass, 11 fixtures on 8
## levels had a solid within LevelBuilder.PLAYER_CLEARANCE_M (2.2 m) under them:
## two over tower ramps (assembly, hivemind), seven buried in or just over the
## centre structure, two over wall tops; and every fixture in a room raised for
## a tower floated 4.5 to 5.5 m under the real ceiling.
##
## (1) Unit cases in a bare room, one fixture each:
##   - nothing near, flush under the ceiling: kept where it was, no rod;
##   - nothing near, 4 m under the ceiling: kept, with a rod up to the ceiling;
##   - a deck 1.25 m under it: lifted to CLEARANCE over the deck, rod to the ceiling;
##   - a ramp under it: lifted to CLEARANCE over the ramp's highest point under it;
##   - a deck under it in a room with no height to spare: removed, its light left on;
##   - buried in a pillar that reaches the ceiling: removed, its light left on;
##   - hanging under a bridge with nothing below: kept, its rod stops at the bridge.
## (2) Every indoor campaign level, built: no fixture has a solid within
##     CLEARANCE under its footprint, none stands inside one, every fixture under
##     open air has a rod reaching what is over it, and the builder's tally
##     accounts for every authored light.
## (3) A level left before its fixtures settle (taken out of the tree in the
##     frame it was built, and one physics frame later) settles nothing and
##     raises no script error. The settle waits two physics frames, and it used
##     to ask a node that had left the tree for its tree: `uprising_probe`, which
##     changes scene that fast, failed 1 CI run in 8 on it. A script error cannot
##     be caught here; the suite runner fails any probe that logs one.
##   godot --headless --path . --audio-driver Dummy res://tests/lamp_headroom_probe.tscn [-- levels=gpt,assembly]

const LevelIds := preload("res://tests/level_ids.gd")
const CLEARANCE_M := LevelBuilder.PLAYER_CLEARANCE_M

var ok := true
var _bays: Node3D

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await _unit_cases()
	await _campaign()
	await _left_early()
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

# ---------- (3) a level left before it settles ----------

func _left_early() -> void:
	for wait in [0, 1]:
		var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
		add_child(lvl)
		for i in wait:
			await get_tree().physics_frame
		remove_child(lvl)
		for i in 4:
			await get_tree().physics_frame
		var tally: Dictionary = lvl.get("luminaire_tally")
		_check("a level left %d physics frame(s) after it was built settles nothing" % wait, tally.is_empty(), str(tally))
		lvl.free()

# ---------- (1) unit cases ----------

func _unit_cases() -> void:
	# Seven bays 20 m apart along X, each its own little room, all under one
	# holder that is freed before the campaign sweep: left standing, the bays
	# share the physics space with every level built after them (the first
	# draft's sweep found each level's centre lamp "inside" bay 0's fixture).
	_bays = Node3D.new()
	add_child(_bays)
	var flush := _bay(0, 6.0)
	var floating := _bay(1, 10.0)
	var deck := _bay(2, 10.0)
	_box(Vector3(40, 4.25, 0), Vector3(4, 0.5, 4)) # top at 4.5, 1.25 m under the fixture's underside
	var ramp := _bay(3, 10.0)
	var slope := _box(Vector3(60, 4.2, 0), Vector3(6, 0.4, 3))
	slope.rotation.z = deg_to_rad(15.0) # rises toward +X
	var low_room := _bay(4, 6.0)
	_box(Vector3(80, 4.25, 0), Vector3(4, 0.5, 4))
	var buried := _bay(5, 10.0)
	_box(Vector3(100, 5.0, 0), Vector3(3, 10.0, 3)) # floor to ceiling
	var under_bridge := _bay(6, 10.0)
	_box(Vector3(120, 7.25, 0), Vector3(4, 0.5, 4)) # underside at 7.0, 1 m over the fixture
	for i in 3:
		await get_tree().physics_frame

	var r: String = flush.lamp.settle(CLEARANCE_M, 6.0)
	_check("a fixture flush under the ceiling with nothing near is kept where it was",
			r == "kept" and is_equal_approx(flush.lamp.position.y, 6.0) and flush.lamp.get_node_or_null("Rod") == null, r)

	r = floating.lamp.settle(CLEARANCE_M, 10.0)
	var rod := floating.lamp.get_node_or_null("Rod") as MeshInstance3D
	_check("a fixture 4 m under its ceiling is kept and hung on a rod that reaches the ceiling",
			r == "kept" and is_equal_approx(floating.lamp.position.y, 6.0) and rod != null and absf(_rod_top(rod) - 10.0) < 0.02,
			"%s, rod top %.2f" % [r, _rod_top(rod) if rod else -1.0])

	r = deck.lamp.settle(CLEARANCE_M, 10.0)
	var under: float = deck.lamp.position.y - ShootableLight.DEPTH
	_check("a fixture 1.25 m over a deck is lifted to CLEARANCE over it",
			r == "lifted" and under >= 4.5 + CLEARANCE_M and under < 4.5 + CLEARANCE_M + 0.1, "%s, underside %.2f" % [r, under])
	_check("the lifted fixture hangs on a rod to the ceiling, and its light stays where it was authored",
			deck.lamp.get_node_or_null("Rod") != null and absf(_rod_top(deck.lamp.get_node("Rod")) - 10.0) < 0.02
			and is_equal_approx(deck.light.position.y, 5.0))

	r = ramp.lamp.settle(CLEARANCE_M, 10.0)
	# The slab's top face under the fixture's +X edge (x = 60.6): the highest point under the footprint.
	var high := 4.2 + 0.6 * tan(deg_to_rad(15.0)) + 0.2 / cos(deg_to_rad(15.0))
	under = ramp.lamp.position.y - ShootableLight.DEPTH
	_check("a fixture over a ramp is lifted to CLEARANCE over the ramp's highest point under it",
			r == "lifted" and under >= high + CLEARANCE_M and under < high + CLEARANCE_M + 0.1,
			"%s, underside %.2f, ramp to %.2f" % [r, under, high])

	r = low_room.lamp.settle(CLEARANCE_M, 6.0)
	await get_tree().process_frame
	_check("with no height to spare the fixture is removed and its light left on",
			r == "removed" and not is_instance_valid(low_room.lamp) and is_instance_valid(low_room.light)
			and low_room.light.light_energy > 0.0 and low_room.light.visible, r)

	r = buried.lamp.settle(CLEARANCE_M, 10.0)
	await get_tree().process_frame
	_check("a fixture buried in a floor-to-ceiling pillar is removed and its light left on",
			r == "removed" and not is_instance_valid(buried.lamp) and is_instance_valid(buried.light), r)

	r = under_bridge.lamp.settle(CLEARANCE_M, 10.0)
	rod = under_bridge.lamp.get_node_or_null("Rod") as MeshInstance3D
	_check("a fixture under a bridge with nothing below is kept, its rod stopping at the bridge",
			r == "kept" and is_equal_approx(under_bridge.lamp.position.y, 6.0) and rod != null and absf(_rod_top(rod) - 7.0) < 0.02,
			"%s, rod top %.2f" % [r, _rod_top(rod) if rod else -1.0])

	_bays.queue_free()
	for i in 3:
		await get_tree().physics_frame

func _rod_top(rod: MeshInstance3D) -> float:
	return rod.global_position.y + (rod.mesh as BoxMesh).size.y * 0.5

## A floor, a ceiling whose underside is at `ceiling_y`, one light at 5 m and
## its fixture at the stock 6 m, `i` * 20 m along X.
func _bay(i: int, ceiling_y: float) -> Dictionary:
	var x := i * 20.0
	_box(Vector3(x, -0.2, 0), Vector3(16, 0.4, 16))
	_box(Vector3(x, ceiling_y + 0.2, 0), Vector3(16, 0.4, 16))
	var l := OmniLight3D.new()
	l.position = Vector3(x, 5.0, 0)
	l.light_energy = 2.0
	_bays.add_child(l)
	return {"lamp": ShootableLight.build(_bays, l, Color.WHITE, 6.0), "light": l}

func _box(at: Vector3, size: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	_bays.add_child(sb)
	sb.position = at
	return sb

# ---------- (2) the campaign ----------

func _campaign() -> void:
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("levels="):
			ids = Array(a.substr(7).split(",", false))
	if ids.is_empty():
		for id in LevelDefs._defs().keys():
			if not LevelDefs.get_def(id).get("open_sky", false):
				ids.append(id)
	var levels := 0
	var lamps := 0
	var low: Array[String] = []
	var inside: Array[String] = []
	var unhung: Array[String] = []
	var untallied: Array[String] = []
	var totals := {"kept": 0, "lifted": 0, "removed": 0}
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
		var authored: int = LevelDefs.get_def(id).get("lights", []).size()
		var ceiling_y := LevelBuilder.room_height(LevelDefs.get_def(id))
		var tally: Dictionary = lvl.get("luminaire_tally") if lvl.get("luminaire_tally") != null else {}
		var counted := 0
		for k in tally:
			counted += int(tally[k])
			totals[k] += int(tally[k])
		if counted != authored:
			untallied.append("%s: %d authored lights, tally %s" % [id, authored, tally])
		var space := (lvl as Node3D).get_world_3d().direct_space_state
		# Fixtures are not solids to one another (ShootableLight._fixtures).
		var fixtures: Array[RID] = []
		for n in get_tree().get_nodes_in_group("shootable_light"):
			if lvl.is_ancestor_of(n):
				fixtures.append((n as CollisionObject3D).get_rid())
		for n in get_tree().get_nodes_in_group("shootable_light"):
			if not lvl.is_ancestor_of(n) or n.is_queued_for_deletion():
				continue
			lamps += 1
			var sl := n as ShootableLight
			var at := sl.global_position
			var where := "%s lamp at %s" % [id, at.snappedf(0.01)]
			# Nothing solid in the CLEARANCE under the footprint.
			var box := BoxShape3D.new()
			box.size = Vector3(ShootableLight.SIZE.x, CLEARANCE_M - 0.02, ShootableLight.SIZE.z)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = box
			q.transform = Transform3D(Basis.IDENTITY, at + Vector3.DOWN * (ShootableLight.DEPTH + CLEARANCE_M * 0.5))
			q.collision_mask = 1
			q.exclude = fixtures
			for h in space.intersect_shape(q, 4):
				low.append("%s over %s%s" % [where, h.collider.name, h.collider.get_groups()])
			# Not inside a solid (below the plane it is mounted on).
			var body := BoxShape3D.new()
			body.size = Vector3(ShootableLight.SIZE.x - 0.04, ShootableLight.DEPTH - 0.05, ShootableLight.SIZE.z - 0.04)
			q.shape = body
			q.transform = Transform3D(Basis.IDENTITY, at + Vector3.DOWN * (ShootableLight.DEPTH * 0.5 + 0.01))
			for h in space.intersect_shape(q, 4):
				inside.append("%s inside %s%s" % [where, h.collider.name, h.collider.get_groups()])
			# Hung from what is over it.
			# (Up to the room's ceiling and no further: a ray started at a flush
			# fixture is inside the ceiling slab and would find the roof dressing.)
			var rq := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.06, Vector3(at.x, ceiling_y + 0.1, at.z), 1)
			rq.exclude = fixtures
			var up := space.intersect_ray(rq)
			var over_y: float = up.position.y if not up.is_empty() else ceiling_y
			if over_y - at.y > 0.1:
				var rod := sl.get_node_or_null("Rod") as MeshInstance3D
				if rod == null or absf(_rod_top(rod) - over_y) > 0.05:
					unhung.append("%s floats %.2f m under what is over it" % [where, over_y - at.y])
		print("%s: %d authored, settled %s" % [id, authored, tally])
		LevelIds.unload(lvl)
		for i in 5:
			await get_tree().physics_frame
	for line in low + inside + unhung + untallied:
		print("  BAD " + line)
	print("levels %d, fixtures standing %d, settled %s" % [levels, lamps, totals])
	_check("indoor levels were built and their fixtures counted", levels >= 8 or not OS.get_cmdline_user_args().is_empty() and levels > 0, "%d levels, %d fixtures" % [levels, lamps])
	_check("every authored indoor light's fixture was settled (kept, lifted or removed)", untallied.is_empty(), "%d levels off" % untallied.size())
	_check("no fixture has a solid within %.1f m under it" % CLEARANCE_M, low.is_empty(), "%d low" % low.size())
	_check("no fixture stands inside a solid", inside.is_empty(), "%d inside" % inside.size())
	_check("every fixture under open air hangs on a rod that reaches what is over it", unhung.is_empty(), "%d floating" % unhung.size())
