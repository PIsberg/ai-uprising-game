extends Node
## Probe (#339): every authored ramp ("stairs" in a level def) that tops out on a
## platform reaches that platform's edge at deck height. The builder lays the
## ramp's top face through the `to` point; a `to` authored INSIDE the platform's
## footprint means the ramp meets the platform's face below the deck, a lip the
## real player stops at (ramp_walk_triage: level 01's four rubble/slab ramps
## stopped 0.1 m from the face, 3 of 3 walks each). Pure geometry over every
## level def (scaled), so it is fast and deterministic.
## For each ramp, the higher end is the top. If it lies within a platform's
## footprint whose deck is at the top's height, the ramp's centre line is
## followed from the low end to where it crosses into that footprint, and the
## ramp height there must be within MAX_LIP of the deck.
## Also: no authored wall box (cover, posts) stands on a ramp's walking line.
## The line and 0.5 m either side are sampled every SAMPLE_STEP m; a wall
## whose footprint holds a sample, whose top is over STEP_UP above the ramp
## there and whose bottom is under head height blocks it (suburb's yard cover
## crate sat across the foot of the rooftop stair, a 3 of 3 stop).
## Also: no platform deck is buried inside a building (footprints overlap by
## over BURY_OVERLAP m on both axes and the building stands over STEP_UP above
## the deck). Buildings scale their position with the arena but not their
## size, so a deck authored at a house's front could end up inside it; the
## suburb_boss ramps climbed into the house walls (3 of 3 stops).
##   godot --headless --path . --audio-driver Dummy res://tests/stairs_landing_probe.tscn

const MAX_LIP := 0.1 ## metres the ramp may sit below the deck where it meets it
const DECK_TOL := 0.06 ## a platform counts as the landing if its deck is this close to the top
const STEP_UP := 0.3 ## the player's step-up assist clears this much
const SAMPLE_STEP := 0.25
const BURY_OVERLAP := 1.0
const EDGE_TOL := 0.05 ## a top this close outside the footprint still lands on it (ramps end on the edge)

var ok := true

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ramps := 0
	var landed := 0
	var bad: Array[String] = []
	var blocked: Array[String] = []
	var buried: Array[String] = []
	for id in LevelDefs._defs().keys():
		var def := LevelDefs.get_def(id)
		var plats: Array = def.get("platforms", [])
		var walls: Array = def.get("walls", [])
		for p in plats:
			if p.has("rot") or not p.has("size"):
				continue
			var pp: Vector3 = p["pos"]
			var ps: Vector3 = p["size"]
			var deck := pp.y + ps.y * 0.5
			for bld in def.get("buildings", []):
				if not bld.has("size") or bld.get("open", false):
					continue
				var bp: Vector3 = bld["pos"]
				var bs: Vector3 = bld["size"]
				var ox := minf(pp.x + ps.x * 0.5, bp.x + bs.x * 0.5) - maxf(pp.x - ps.x * 0.5, bp.x - bs.x * 0.5)
				var oz := minf(pp.z + ps.z * 0.5, bp.z + bs.z * 0.5) - maxf(pp.z - ps.z * 0.5, bp.z - bs.z * 0.5)
				var b_top := bp.y + bs.y * 0.5
				if ox > BURY_OVERLAP and oz > BURY_OVERLAP and b_top > deck + STEP_UP and bp.y - bs.y * 0.5 < deck:
					buried.append("%s deck at %s (top %.2f) inside the building at %s (top %.2f), overlap %.1f x %.1f m" % [id, pp, deck, bp, b_top, ox, oz])
		for s in def.get("stairs", []):
			ramps += 1
			var a: Vector3 = s["from"]
			var b: Vector3 = s["to"]
			var top := a if a.y > b.y else b
			var low := b if a.y > b.y else a
			var blocker := _wall_on(low, top, walls)
			if blocker != "":
				blocked.append("%s %s -> %s: %s" % [id, low, top, blocker])
			for p in plats:
				if p.has("rot") or not p.has("size"):
					continue
				var pos: Vector3 = p["pos"]
				var size: Vector3 = p["size"]
				var deck := pos.y + size.y * 0.5
				if absf(deck - top.y) > DECK_TOL or not _inside(top, pos, size):
					continue
				landed += 1
				var t := _entry_t(low, top, pos, size)
				var h := lerpf(low.y, top.y, t)
				var lip := deck - h
				if lip > MAX_LIP:
					bad.append("%s %s -> %s: meets the platform at %s with the ramp %.2f m below its deck" % [
						id, low, top, low.lerp(top, t), lip])
	print("ramps %d, %d topping out on a platform" % [ramps, landed])
	for line in bad:
		print("  LIP " + line)
	_check("ramps that top out on a platform were found", landed > 0)
	_check("every ramp meets its landing at deck height", bad.is_empty(), "%d lips" % bad.size())
	for line in blocked:
		print("  BLOCKED " + line)
	_check("no wall stands on a ramp", blocked.is_empty(), "%d blocked" % blocked.size())
	for line in buried:
		print("  BURIED " + line)
	_check("no platform deck is buried in a building", buried.is_empty(), "%d buried" % buried.size())
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

func _inside(v: Vector3, pos: Vector3, size: Vector3) -> bool:
	return absf(v.x - pos.x) <= size.x * 0.5 + EDGE_TOL and absf(v.z - pos.z) <= size.z * 0.5 + EDGE_TOL

## The first wall box standing on the low -> top walking line, described, or "".
func _wall_on(low: Vector3, top: Vector3, walls: Array) -> String:
	var run := Vector2(top.x - low.x, top.z - low.z)
	if run.length() < 0.01:
		return ""
	var side := Vector3(-run.y, 0.0, run.x).normalized() * 0.5
	var n := int(ceil(run.length() / SAMPLE_STEP))
	for i in range(n + 1):
		var t := float(i) / float(n)
		var c := low.lerp(top, t)
		for off in [Vector3.ZERO, side, -side]:
			var s: Vector3 = c + off
			for w in walls:
				if not w.has("size") or w.has("rot") or w.has("yaw"):
					continue
				var wp: Vector3 = w["pos"]
				var ws: Vector3 = w["size"]
				if not _inside(s, wp, ws - Vector3(EDGE_TOL, 0, EDGE_TOL) * 2.0):
					continue
				var w_top := wp.y + ws.y * 0.5
				var w_bot := wp.y - ws.y * 0.5
				if w_top > c.y + STEP_UP and w_bot < c.y + 1.8:
					return "wall at %s (top %.2f m) stands %.1f m up the ramp, where it is %.2f m high" % [wp, w_top, t * run.length(), c.y]
	return ""

## Fraction along low -> top where the XZ line first enters the platform footprint.
func _entry_t(low: Vector3, top: Vector3, pos: Vector3, size: Vector3) -> float:
	var t_in := 0.0
	for axis in [0, 2]:
		var lo: float = pos[axis] - size[axis] * 0.5
		var hi: float = pos[axis] + size[axis] * 0.5
		var d: float = top[axis] - low[axis]
		if absf(d) < 0.0001:
			continue
		var t0: float = (lo - low[axis]) / d
		var t1: float = (hi - low[axis]) / d
		t_in = maxf(t_in, minf(t0, t1))
	return clampf(t_in, 0.0, 1.0)

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false
