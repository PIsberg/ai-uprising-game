extends Node3D
## Probe: every def "ramps" entry leads onto a deck (LevelBuilder.ramp_ends).
## A ramp's length is not scaled with the world but its deck is, so the shared
## vantage deck's ramp stopped 1.98 m short of the deck on 17 levels, and the
## ramps of horde, desert and range were authored climbing AWAY from their
## decks: 24 of the campaign's 256 ramps ended over open floor.
##   - in every level def, each ramp's top lands on a platform's edge at the
##     platform's top;
##   - the slide keeps the authored slope and length (gpt's vantage ramp);
##   - a ramp with no deck ahead, one already on a deck, one further than
##     RAMP_DECK_REACH from a deck and one under a deck too high above it are
##     laid as authored;
##   - built for real (gpt, horde, desert, range): the builder lays those ends,
##     there is a surface to step onto past every ramp's and stair's top, and
##     nothing solid stands on range's two deck stairs.
##   godot --headless --path . --audio-driver Dummy res://tests/ramp_landing_probe.tscn

const IDS := [
	"01", "gpt", "gemini", "claude", "grok", "suburb", "suburb_boss", "mistral",
	"overseer", "alien", "uplink", "assembly", "titan", "archon", "range",
	"horde", "sublevel", "crucible", "frostbreak", "neon", "lava_world",
	"water_world", "desert", "convoy", "guardrails", "hivemind",
]
const BUILT := ["gpt", "horde", "desert", "range"]

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## The platform whose top face `p` lies on (within `tol`), or {}.
func _deck_under(def: Dictionary, p: Vector3, tol: float) -> Dictionary:
	for pl: Dictionary in def.get("platforms", []):
		var pos: Vector3 = pl["pos"]
		var half: Vector3 = (pl["size"] as Vector3) * 0.5
		if absf(pos.y + half.y - p.y) <= tol and absf(p.x - pos.x) <= half.x + tol and absf(p.z - pos.z) <= half.z + tol:
			return pl
	return {}

func _run() -> void:
	# 1. Every def ramp lands on a deck.
	var ramps := 0
	var off: Array = []
	for id: String in IDS:
		var def := LevelDefs.get_def(id)
		if def.is_empty():
			_check("level def %s exists" % id, false)
		for r: Dictionary in def.get("ramps", []):
			ramps += 1
			var ends := LevelBuilder.ramp_ends(def, r)
			if _deck_under(def, ends[1], 0.05).is_empty():
				off.append("%s %s" % [id, ends[1]])
	_check("every def ramp's top lands on a deck's edge at its height", off.is_empty() and ramps >= 24,
			"%d ramps, %d off: %s" % [ramps, off.size(), ", ".join(off)])

	# 2. The slide keeps the slope and the length.
	var gpt := LevelDefs.get_def("gpt")
	var r0: Dictionary = gpt["ramps"][0]
	var e0 := LevelBuilder.ramp_ends(gpt, r0)
	var run := Vector2(e0[1].x - e0[0].x, e0[1].z - e0[0].z).length()
	var pitch := rad_to_deg(atan2(e0[1].y - e0[0].y, run))
	_check("gpt's vantage ramp keeps its authored pitch", absf(pitch - float(r0["pitch"])) < 1.0, "%.1f deg against %.1f" % [pitch, float(r0["pitch"])])
	var length: float = (e0[1] - e0[0]).length()
	_check("and its length", absf(length - (r0["size"] as Vector3).z) < 0.7, "%.2f m against %.2f" % [length, (r0["size"] as Vector3).z])

	# 3. What must be left alone. A 6 m, 20 deg ramp climbing -Z from z = 2.82 to
	# z = -2.82, top at y 2.29.
	var ramp := {"pos": Vector3(0, 1.0, 0), "size": Vector3(3, 0.5, 6), "pitch": 20.0, "yaw": 0.0}
	var bare := {"floor_size": Vector2(80, 80), "ramps": [ramp]}
	var plain := LevelBuilder.ramp_ends(bare, ramp)
	var top: Vector3 = plain[1]
	_check("the synthetic ramp climbs -Z to 2.26", absf(top.y - 2.26) < 0.05 and top.z < -2.7, str(top))
	# A 4 m deck centred 3 m ahead: its near edge is 1 m ahead, its top 0.05 above.
	var ahead := Vector3(0, top.y - 0.2, top.z - 3.0)
	var near := LevelBuilder.ramp_ends(_with_deck(bare, ahead), ramp)
	_check("a deck 1 m ahead pulls the top to its edge at its height",
			absf(near[1].z - (top.z - 1.0)) < 0.01 and absf(near[1].y - (top.y + 0.05)) < 0.01, str(near[1]))
	var foot_shift: float = near[0].z - plain[0].z
	_check("foot and top move together", absf((near[1].z - plain[1].z) - foot_shift) < 0.05, "foot %.2f m, top -1.00" % foot_shift)
	_check("a ramp already on a deck is laid as authored", _moved(bare, ramp, Vector3(0, top.y - 0.2, top.z - 1.5), plain) < 0.001)
	_check("a deck beyond RAMP_DECK_REACH is not reached for",
			_moved(bare, ramp, Vector3(0, top.y - 0.2, top.z - 2.0 - LevelBuilder.RAMP_DECK_REACH - 0.5), plain) < 0.001)
	_check("a deck 1 m above the top is not reached for", _moved(bare, ramp, Vector3(0, top.y + 0.8, top.z - 3.0), plain) < 0.001)
	_check("a deck off to the side is not reached for", _moved(bare, ramp, Vector3(6, top.y - 0.2, top.z - 3.0), plain) < 0.001)
	_check("a deck behind the ramp is not reached for", _moved(bare, ramp, Vector3(0, top.y - 0.2, 8.0), plain) < 0.001)

	# 4. Built for real.
	for id: String in BUILT:
		await _built(id)
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## `bare` with one 4 x 0.5 x 4 deck centred at `at` (its top 0.25 above).
func _with_deck(bare: Dictionary, at: Vector3) -> Dictionary:
	var d := bare.duplicate(true)
	d["platforms"] = [{"pos": at, "size": Vector3(4, 0.5, 4)}]
	return d

## How far the ramp's ends moved from `plain` with that deck in the def.
func _moved(bare: Dictionary, ramp: Dictionary, at: Vector3, plain: Array) -> float:
	var e := LevelBuilder.ramp_ends(_with_deck(bare, at), ramp)
	return (e[1] - plain[1]).length() + (e[0] - plain[0]).length()

func _built(id: String) -> void:
	seed(hash(id))
	var lvl: Node3D = (load("res://scenes/levels/level_%s.tscn" % id) as PackedScene).instantiate()
	add_child(lvl)
	for i in 30:
		await get_tree().physics_frame
	var def := LevelDefs.get_def(id)
	var space := lvl.get_world_3d().direct_space_state
	var bodies: Array = []
	for b in get_tree().get_nodes_in_group("ramp_surface"):
		if lvl.is_ancestor_of(b) and b.has_meta("ramp_from") and b.has_meta("ramp_to"):
			bodies.append(b)
	# The builder lays the ends ramp_ends gives.
	var def_ramps: Array = def.get("ramps", [])
	var laid := 0
	for r: Dictionary in def_ramps:
		var ends := LevelBuilder.ramp_ends(def, r)
		for b: Node in bodies:
			if (b.get_meta("ramp_to") as Vector3).distance_to(ends[1]) < 0.01 and (b.get_meta("ramp_from") as Vector3).distance_to(ends[0]) < 0.2:
				laid += 1
				break
	_check("%s: the builder lays ramp_ends for each def ramp" % id, laid == def_ramps.size(), "%d of %d" % [laid, def_ramps.size()])
	# A surface to step onto past every top.
	var dead: Array = []
	for b: Node in bodies:
		var from: Vector3 = b.get_meta("ramp_from")
		var to: Vector3 = b.get_meta("ramp_to")
		var d := Vector3(to.x - from.x, 0, to.z - from.z).normalized()
		var p := to + d * 0.6
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p - Vector3.UP * 0.4, 1)
		q.exclude = [(b as CollisionObject3D).get_rid()]
		if space.intersect_ray(q).is_empty():
			dead.append(str(to))
	_check("%s: a surface to step onto past every ramp's top" % id, dead.is_empty() and not bodies.is_empty(),
			"%d ramps, off: %s" % [bodies.size(), ", ".join(dead)])
	if id == "range":
		var stairs: Array = def.get("stairs", [])
		_check("range: two stairs up to the overwatch deck", stairs.size() == 2 and bodies.size() == 2,
				"%d stairs, %d bodies" % [stairs.size(), bodies.size()])
		for s: Dictionary in stairs:
			_check("range: the stair's top is on the deck's edge at its height", not _deck_under(def, s["to"], 0.05).is_empty(), str(s["to"]))
			# Shin and chest height along the walking line, both edges and the middle.
			var from: Vector3 = s["from"]
			var to: Vector3 = s["to"]
			var side := Vector3(to.x - from.x, 0, to.z - from.z).normalized().cross(Vector3.UP)
			var blocked := ""
			for lat: float in [-1.1, 0.0, 1.1]:
				for h: float in [0.45, 1.2]:
					var o: Vector3 = side * lat + Vector3.UP * h
					var q := PhysicsRayQueryParameters3D.create(from + o, to + o, 1)
					var hit := space.intersect_ray(q)
					if not hit.is_empty():
						blocked = "%s at %s" % [hit.collider.name, hit.position]
			_check("range: nothing solid stands on the stair", blocked == "", blocked)
	lvl.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame
