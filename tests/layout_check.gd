extends Node
## Static layout sanity check: for each level id, read its (scaled) def and flag
## any placed entity (enemy / prop / pickup / weapon / lore / objective / spawn /
## exit / hero) that sits INSIDE a wall or building AABB — i.e. would spawn stuck
## in geometry. Pure data check (no level instantiation), so it's instant.
## Run: godot --headless --path . --quit-after 30 res://tests/layout_check.tscn

const IDS := ["frostbreak", "neon", "sublevel", "crucible", "claude",
	"gpt", "mistral", "assembly", "titan", "archon", "gemini", "grok",
	"overseer", "uplink", "alien", "01", "suburb", "suburb_boss"]

const MARGIN := 0.15  # small: only flag a center genuinely buried in the box footprint

## Entity kinds the BUILDER relocates at load when it finds them buried:
##   tasks       — level_builder.gd `_clear_task_pos` (prints "relocated to ...")
##   enemies     — enemy_spawner.gd `_clear_spawn_pos` (push_warning + relocate)
## An overlap in one of these is untidy authoring, not a defect a player can
## meet, so it is REPORTED, not failed.
##
## Everything else — props, pickups, weapons, lore, holograms — is placed at its
## authored position verbatim, with no clearing pass. Those overlaps ARE defects:
## a prop inside a wall is invisible (and still carves navmesh), and a pickup
## inside solid cover can never be collected, because collection needs the player
## to overlap it. Those fail the check.
const RELOCATED_AT_LOAD := ["enemies", "task"]

static func _is_advisory(label: String) -> bool:
	for k in RELOCATED_AT_LOAD:
		if label == k or label.begins_with(k + ":"):
			return true
	return false

func _box_hit(p: Vector3, bpos: Vector3, bsize: Vector3) -> bool:
	# Only TALL boxes can trap a unit; low cover/decals don't.
	if bsize.y < 1.5:
		return false
	# Flyers/floating placements (y>=2) clear ground cover; ignore them.
	if p.y >= 2.0:
		return false
	var hx: float = bsize.x * 0.5 + MARGIN
	var hz: float = bsize.z * 0.5 + MARGIN
	return absf(p.x - bpos.x) <= hx and absf(p.z - bpos.z) <= hz

func _blockers(def: Dictionary) -> Array:
	var out: Array = []
	for w in def.get("walls", []):
		out.append(w)
	for b in def.get("buildings", []):
		out.append(b)
	return out

func _check_point(label: String, p: Vector3, blockers: Array, hits: Array) -> void:
	for b in blockers:
		if _box_hit(p, b["pos"], b["size"]):
			hits.append({
				"txt": "%s at %s inside box %s/%s" % [label, p, b["pos"], b["size"]],
				"advisory": _is_advisory(label),
			})
			return

func _ready() -> void:
	var total := 0
	var advisory := 0
	for id in IDS:
		var def: Dictionary = LevelDefs.get_def(id)
		if def.is_empty():
			continue
		var blockers := _blockers(def)
		var hits: Array = []
		_check_point("spawn", def.get("spawn", Vector3.ZERO), blockers, hits)
		_check_point("exit", def.get("exit", Vector3.ZERO), blockers, hits)
		for key in ["enemies", "props", "pickups", "extra_weapons", "lore", "targets", "holograms"]:
			for e in def.get(key, []):
				if e.has("pos"):
					_check_point(key, e["pos"], blockers, hits)
		if def.has("weapon") and (def["weapon"] as Dictionary).has("pos"):
			_check_point("weapon", def["weapon"]["pos"], blockers, hits)
		for t in def.get("tasks", []):
			if t.has("pos"):
				_check_point("task:" + str(t.get("type", "?")), t["pos"], blockers, hits)
			for pt in t.get("points", []):
				_check_point("shard", pt, blockers, hits)
		if def.has("hero"):
			_check_point("hero", def["hero"].get("pos", Vector3.ZERO), blockers, hits)
		var bad := 0
		for h in hits:
			if not h["advisory"]:
				bad += 1
		if hits.is_empty():
			print("OK  %s" % id)
		else:
			total += bad
			advisory += hits.size() - bad
			print("%s  %s — %d overlap(s), %d fatal:" % ["XX" if bad > 0 else "..", id, hits.size(), bad])
			for h in hits:
				print("      %s%s" % ["(relocated at load) " if h["advisory"] else "", h["txt"]])
	print("LAYOUT_CHECK fatal=%d advisory=%d" % [total, advisory])
	if advisory > 0:
		print("  advisory = an enemy spawn or task the builder moves clear at load; untidy, not player-visible")
	print("RESULT %s" % ("PASS" if total == 0 else "FAIL"))
	get_tree().quit()
