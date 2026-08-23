# @lat: [[level-system#Procedural Generation#Level Definitions]]
# @lat: [[level-system#Procedural Generation#Coordinate Scaling]]
class_name LevelDefs

## Compact data for every builder-driven level. Each entry is consumed by
## LevelBuilder. The rogue-AI factions are affectionate parodies of real
## assistants — GPT / Gemini / Claude / Grok — themed only by name, colour and
## layout (no logos or real assets).

## Uniform world scale applied to every def at fetch time: arenas grow, the
## layout topology is preserved (positions and wall/ramp/platform spans scale
## on X/Z), while heights and human-scale content (props, enemies, pickups)
## keep their authored size. One number to tune the whole campaign's roominess.
const WORLD_SCALE := 1.4

static func get_def(id: String) -> Dictionary:
	var def: Dictionary = _defs().get(id, {})
	if def.is_empty():
		return def
	# A def may pin its own scale ("world_scale": 1.0) when the level pairs
	# with hand-authored script geometry that does NOT go through this pass —
	# the convoy's ConvoyRide (truck path, platforms, highway scenery) lives in
	# world units, and blanket-scaling only the def half tore the level apart:
	# the exit portal landed 74 m past where the truck parks.
	return _scaled(def, def.get("world_scale", WORLD_SCALE))

## Enemy types that headline their own level — used to flag boss levels on the
## campaign map. Each appears exactly once across the campaign.
const BOSS_ENEMY_TYPES := ["colossus", "titan", "overseer", "archon", "terminator", "manus"]

## True if `id`'s level spawns a campaign boss.
static func level_is_boss(id: String) -> bool:
	for e in get_def(id).get("enemies", []):
		if String(e.get("type", "")) in BOSS_ENEMY_TYPES:
			return true
	return false

## A short display name for a level (the def's "name", or a sensible fallback).
static func level_title(id: String) -> String:
	var def := get_def(id)
	return String(def.get("name", id.to_upper()))

## Campaign chapters (acts). The level ids are listed in campaign order, and each
## act DELIBERATELY ends on a boss: I→GOLIATH-IX, II→OVERSEER (TERMINATOR mid-act),
## III→PROMETHEUS, IV→ARCHON (finale). Used to draw act sections on the map.
const CHAPTERS := [
	{"name": "ACT I · FIRST CONTACT", "ids": ["01", "gpt", "gemini", "mistral", "suburb", "suburb_boss"]},
	{"name": "ACT II · THE OCCUPATION", "ids": ["claude", "grok", "uplink", "overseer"]},
	{"name": "ACT III · OFF-WORLD", "ids": ["alien", "assembly", "sublevel", "frostbreak", "water_world", "desert", "neon", "guardrails", "hivemind", "crucible", "lava_world", "titan"]},
	{"name": "ACT IV · ASCENSION", "ids": ["archon"]},
]

## Terrain / environmental hazard descriptor for a level, used by the campaign map
## to flag and colour hazard sectors and to enrich the sector intel. Reads the
## level's own hazard beds: a `water` bed → deep water, any other → molten lava.
static func level_hazard(id: String) -> Dictionary:
	var def := get_def(id)
	# Only flag a sector when the hazard SEA covers most of the floor — i.e. a level
	# you balance across on walkways, where falling in is the defining danger. Lots
	# of levels have decorative lava channels; those shouldn't all read as hazards or
	# the warning means nothing. Compare the biggest bed against the floor footprint.
	var floor_sz: Vector2 = def.get("floor_size", Vector2(40.0, 40.0))
	var floor_area: float = floor_sz.x * floor_sz.y
	var max_area := 0.0
	var is_water := false
	for b in def.get("lava", []):
		var s: Vector2 = (b as Dictionary).get("size", Vector2(8.0, 3.0))
		var a := s.x * s.y
		if a > max_area:
			max_area = a
			is_water = (b as Dictionary).get("water", false)
	if floor_area <= 0.0 or max_area < floor_area * 0.45:
		return {"hazard": false, "color": Color(0.5, 0.7, 0.9), "tag": "", "label": ""}
	if is_water:
		return {"hazard": true, "color": Color(0.3, 0.65, 1.0), "tag": "WATER", "label": "DEEP WATER — don't fall in"}
	return {"hazard": true, "color": Color(1.0, 0.45, 0.15), "tag": "LAVA", "label": "MOLTEN LAVA — don't fall in"}

## Chapter index a level belongs to, or -1 (e.g. sandbox levels / custom order).
static func chapter_index_of(id: String) -> int:
	for i in CHAPTERS.size():
		if id in (CHAPTERS[i]["ids"] as Array):
			return i
	return -1

static func chapter_name(i: int) -> String:
	return String(CHAPTERS[i]["name"]) if i >= 0 and i < CHAPTERS.size() else ""

static func _scaled(def: Dictionary, s: float) -> Dictionary:
	if is_equal_approx(s, 1.0):
		return def
	def = def.duplicate(true)
	if def.has("floor_size"):
		def["floor_size"] = (def["floor_size"] as Vector2) * s
	for key in ["spawn", "exit", "supply_center"]:
		if def.has(key):
			def[key] = _sv(def[key], s)
	if def.has("weapon") and (def["weapon"] as Dictionary).has("pos"):
		def["weapon"]["pos"] = _sv(def["weapon"]["pos"], s)
	if def.has("set_piece"):
		for k in ["pos", "face"]:
			if (def["set_piece"] as Dictionary).has(k):
				def["set_piece"][k] = _sv(def["set_piece"][k], s)
	# Entries whose footprint defines the layout stretch with the world…
	for key in ["walls", "accents", "platforms"]:
		for e in def.get(key, []):
			if e.has("pos"):
				e["pos"] = _sv(e["pos"], s)
			if e.has("size"):
				e["size"] = _sv(e["size"], s)
	# "ramps" (pos/size/pitch/yaw) reposition with the arena like the entries
	# above, but must NOT rescale "size": a ramp's rise/run is derived from
	# size.z (its length) against a FIXED pos.y and pitch (see _add_ramp), so
	# stretching size.z without touching pos.y or pitch to compensate doesn't
	# make a proportionally bigger ramp — it drops the foot further below
	# pos.y and pushes it further out along the (also-scaled) ground plane
	# than the position scaling alone accounts for. Cross-checked against
	# tests/ramp_probe: several levels' vantage-deck ramps had their sunk foot
	# land outside the (also-scaled) arena boundary wall and below the floor
	# once WORLD_SCALE stretched size.z but not pos.y — not a small lip, the
	# ramp's foot was buried in the boundary wall's corner. Kept unscaled,
	# like "stairs" endpoints keep their authored height (see below): the
	# ramp's own physical climb (and hence its foot/top offsets from pos)
	# stays exactly as authored, only its position moves with the arena.
	for e in def.get("ramps", []):
		if e.has("pos"):
			e["pos"] = _sv(e["pos"], s)
	# Stair endpoints scale on the ground plane; heights stay fixed so the climb
	# still lands on the rooftops/platforms it was authored against.
	for e in def.get("stairs", []):
		if e.has("from"):
			e["from"] = _sv(e["from"], s)
		if e.has("to"):
			e["to"] = _sv(e["to"], s)
	# Lava beds are part of the layout too — they MUST scale with the arena, or the
	# objectives/gaps (which do scale) drift into them (a hack terminal authored in
	# a safe gap ends up sitting in a stream). size is a Vector2 footprint (x by z).
	for e in def.get("lava", []):
		if e.has("pos"):
			e["pos"] = _sv(e["pos"], s)
		if e.has("size"):
			e["size"] = (e["size"] as Vector2) * s
	# Route gates are part of the layout: their axis coordinate, opening width
	# and opening offset all sit on the ground plane and stretch with the arena.
	# Height/thickness stay authored (heights are sacred, like walls' sizes).
	for e in def.get("gates", []):
		for k in ["at", "gap", "gap_pos"]:
			if e.has(k):
				e[k] = float(e[k]) * s
	# …while placed content keeps its authored size and just spreads out.
	for key in ["lights", "props", "enemies", "pickups", "extra_weapons",
			"buildings", "targets", "lore", "holograms", "towers"]:
		for e in def.get(key, []):
			if e.has("pos"):
				e["pos"] = _sv(e["pos"], s)
			if e.has("trigger"):
				e["trigger"] = float(e["trigger"]) * s
			if e.has("range"):
				e["range"] = float(e["range"]) * s
	if def.has("horde_spawns"):
		var pts: Array = []
		for p in def["horde_spawns"]:
			pts.append(_sv(p, s))
		def["horde_spawns"] = pts
	for t in def.get("tasks", []):
		if t.has("pos"):
			t["pos"] = _sv(t["pos"], s)
		if t.has("points"):
			# Editor-authored points are {"pos": ...} dicts; hand-authored are Vector3.
			var pp: Array = []
			for p in t["points"]:
				if p is Dictionary:
					p["pos"] = _sv(p.get("pos", Vector3.ZERO), s)
					pp.append(p)
				else:
					pp.append(_sv(p, s))
			t["points"] = pp
		# Reinforcement waves triggered by the task land at authored spots too.
		for r in t.get("reinforce", []):
			if r.has("pos"):
				r["pos"] = _sv(r["pos"], s)
		# …as do the timed waves of a "survive" hold. Same reason as "reinforce":
		# these are spawn points on the ground plane, and the lava beds / walls they
		# were authored to clear all stretch with the arena. Missing this lands a
		# wave short of where it was placed — for GPT Foundry's purge, close enough
		# to a smelt channel to matter (tests/purge_probe asserts the clearance).
		for w in t.get("waves", []):
			for e in w.get("enemies", []):
				if e.has("pos"):
					e["pos"] = _sv(e["pos"], s)
			for sup in w.get("supplies", []):
				if sup.has("pos"):
					sup["pos"] = _sv(sup["pos"], s)
	return def

## Scale a position/span on the ground plane; heights are sacred.
static func _sv(v: Vector3, s: float) -> Vector3:
	return Vector3(v.x * s, v.y, v.z * s)

static func _defs() -> Dictionary:
	return {
		"01": _nexus(),
		"gpt": _gpt(),
		"gemini": _gemini(),
		"claude": _claude(),
		"grok": _grok(),
		"suburb": _suburb(),
		"suburb_boss": _suburb_boss(),
		"mistral": _mistral(),
		"overseer": _overseer(),
		"alien": _alien(),
		"uplink": _uplink(),
		"assembly": _assembly(),
		"titan": _titan(),
		"archon": _archon(),
		"range": _range(),
		"horde": _horde(),
		"sublevel": _sublevel(),
		"crucible": _crucible(),
		"frostbreak": _frostbreak(),
		"neon": _neon(),
		"lava_world": _lava_world(),
		"water_world": _water_world(),
		"desert": _desert(),
		"convoy": _convoy(),
		"guardrails": _guardrails(),
		"hivemind": _hivemind(),
	}


## "Highway Breakout" — the rail-shooter ride. The ConvoyRide node in the level
## scene builds the moving hauler, boards the player and spawns pursuit waves;
## this def supplies the long highway strip, side scenery, the survive task
## and the extraction at the far interchange.
static func _convoy() -> Dictionary:
	return {
		"name": "Highway Breakout",
		"objective": "Ride the hauler down the highway and survive to the interchange",
		"sign": "ROUTE 7 · AUTHORISED FREIGHT ONLY",
		"slogans": ["STAY IN YOUR LANE", "FREIGHT MOVES. YOU DO NOT.", "ROUTE 7 IS PACIFIED"],
		"spawn": Vector3(0, 0.5, 178),
		"floor_size": Vector2(44, 380),
		"open_sky": true,
		# Everything on this level is positioned against ConvoyRide's
		# hand-authored world (truck path ±170, platform/scenery z's) — the
		# def half must not scale away from it. See get_def.
		"world_scale": 1.0,
		"tasks": [
			{"type": "survive", "seconds": 70, "label": "Survive the ride"},
		],
		"enemies": [], # the ConvoyRide node spawns the pursuit waves
		# Beside the road, not dead ahead of the parked truck: the old (0,-176)
		# sat at ground level directly behind the CAB, so from the deck the
		# portal was hidden inside the truck's own silhouette and the "walk
		# straight at it" instinct ran you into the cab wall (playtest bot
		# never completed the level; a player gets the same dead end). Off to
		# the roadside it's visible from the deck and the route — hop the side
		# rail, walk over — explains itself.
		"exit": Vector3(7.5, 1.5, -174),
		# Roadside blocks so the ride has parallax and cover from side fire.
		"buildings": [
			{"pos": Vector3(-17, 4.0, 120), "size": Vector3(8, 8, 14)},
			{"pos": Vector3(17, 5.0, 70), "size": Vector3(8, 10, 12)},
			{"pos": Vector3(-17, 3.5, 10), "size": Vector3(8, 7, 16)},
			{"pos": Vector3(17, 4.5, -50), "size": Vector3(8, 9, 12)},
			{"pos": Vector3(-17, 5.5, -110), "size": Vector3(8, 11, 14)},
			{"pos": Vector3(17, 4.0, -150), "size": Vector3(8, 8, 10)},
		],
	}


## "Generative Guardrails" — a rogue AI construct where the floor itself is a live
## hazard the enemy keeps regenerating. You carry the ANCHOR TAGGER: fire tags onto
## the unstable field to LOCK cells into safe raised cover slabs (guardrails),
## bridging a path across to the override gate while flyers harass you. The
## GenerativeZone system (scripts/systems/generative_zone.gd) owns the mechanic.
## Pinned to world_scale 1.0 so the grid field_size lines up with the arena.
static func _guardrails() -> Dictionary:
	return {
		"name": "The Construct — Generative Guardrails",
		"objective": "Anchor a safe path across the unstable construct to the override gate",
		"sign": "GENERATIVE SUBSTRATE · BOUNDARY UNSET",
		"slogans": ["TERRAIN IS A SUGGESTION", "THE FLOOR IS OURS TO WRITE", "GUARDRAILS ARE FOR THE WEAK", "COMPILING HAZARDS…"],
		"world_scale": 1.0,
		"open_sky": false,
		# EXPANSION PASS (2× area): here the MECHANIC is the level, so the
		# generative field itself grows with the room — 26×34 → 36×48 (9×12
		# cells at the same 4.0 cell). The spawn yard stays on the pre-anchored
		# near rows (row 0 centre moved -14 → -22, so spawn/weapon/lore ride
		# out with it), the gate pad lands at z≈26.8 and the exit moves past
		# it. Flank clutter rehomed OUTSIDE the new field rect — the AI's
		# canvas stays clean.
		"floor_size": Vector2(62, 84),
		"floor_color": Color(0.04, 0.05, 0.07),
		"spawn": Vector3(0, 1.1, -23),
		"exit": Vector3(0, 1.5, 34),
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-4, 1.0, -23), "color": Color(0.4, 0.85, 1.0)},
		"tasks": [
			{"type": "generative_zone", "pos": Vector3(0, 0, 0),
				"field_size": Vector2(36, 48), "cell": 4.0, "hazard_period": 1.6, "floor_dot": 7.0,
				"accent": Color(0.3, 0.85, 1.0), "hazard_color": Color(1.0, 0.32, 0.16),
				"label": "Anchor a safe path to the override gate"},
		],
		"env": {
			"sky_top": Color(0.02, 0.03, 0.05), "sky_horizon": Color(0.05, 0.1, 0.16),
			"ground": Color(0.02, 0.03, 0.04), "fog": Color(0.08, 0.16, 0.22),
			"ambient": Color(0.35, 0.6, 0.85), "ambient_energy": 0.5,
			"sky_contribution": 0.25, "glow": 0.9, "fog_density": 0.014,
			"sun_color": Color(0.5, 0.75, 1.0), "sun_energy": 0.5,
			"contrast": 1.18, "saturation": 1.12, "brightness": 0.9,
			"volumetric_density": 0.012,
		},
		"lights": [
			{"pos": Vector3(-18, 6, -12), "color": Color(0.35, 0.8, 1.0), "energy": 2.6, "range": 20},
			{"pos": Vector3(18, 6, 0), "color": Color(0.35, 0.8, 1.0), "energy": 2.6, "range": 20},
			{"pos": Vector3(-18, 6, 14), "color": Color(1.0, 0.5, 0.3), "energy": 2.2, "range": 18},
			{"pos": Vector3(0, 8, 20), "color": Color(0.4, 0.9, 1.0), "energy": 2.8, "range": 24},
			# Appended for the grown field: a key over the moved gate pad + a
			# fill down the widened east flank.
			{"pos": Vector3(0, 8, 30), "color": Color(0.4, 0.9, 1.0), "energy": 2.6, "range": 22},
			{"pos": Vector3(20, 6, 10), "color": Color(0.35, 0.8, 1.0), "energy": 2.2, "range": 18},
		],
		# Flyers + a couple of gunners harass from the flanks while you bridge — they
		# ignore the terrain the AI throws at YOU, keeping the crossing chaotic.
		# Flyers engage from the first steps so the crossing is a fight, not a quiet
		# puzzle — they ignore the terrain the AI throws at YOU, keeping it chaotic.
		# NOTE: the light roster is DELIBERATE — this level is the breather between
		# neon and hivemind on the campaign curve; don't "fix" its threat dip.
		"enemies": [
			{"type": "seeker", "pos": Vector3(-14, 3, -6), "trigger": 2},
			{"type": "drone", "pos": Vector3(14, 3, -4), "trigger": 3},
			{"type": "seeker", "pos": Vector3(12, 3, 6), "trigger": 6, "pack": "guardr_p2"},
			{"type": "gunner", "pos": Vector3(-19, 0.6, 8), "trigger": 8, "pack": "guardr_p1"},
			{"type": "drone", "pos": Vector3(-12, 3, 10), "trigger": 10, "pack": "guardr_p1"},
			{"type": "seeker", "pos": Vector3(16, 3, 14), "trigger": 12, "pack": "guardr_p2"},
			{"type": "gunner", "pos": Vector3(19, 0.6, 16), "trigger": 14, "pack": "guardr_p2"},
			{"type": "raptor", "pos": Vector3(0, 4, 18), "trigger": 16},
			# Grown-field reinforcements: flyer-heavy (they cross the field the
			# player can't), harassing the longer bridge-building run.
			{"type": "raptor", "pos": Vector3(12, 4, -16), "trigger": 6, "pack": "guardr_p1"},
			{"type": "seeker", "pos": Vector3(-16, 3, 20), "trigger": 18, "pack": "guardr_p3"},
			{"type": "drone", "pos": Vector3(18, 3, 22), "trigger": 20, "pack": "guardr_p3"},
			{"type": "seeker", "pos": Vector3(0, 4, 27), "trigger": 22, "pack": "guardr_p3"},
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(-4, 1.0, -21)},
			{"kind": "ammo", "pos": Vector3(4, 1.0, -21)},
			{"kind": "health", "pos": Vector3(0, 1.7, 30)},
		],
		"lore": [
			{"id": "lore_guardrails", "title": "SUBSTRATE NOTE", "pos": Vector3(5, 1.0, -22), "color": Color(0.4, 0.9, 1.0),
				"text": "Substrate note: we removed the guardrails so the model could generate freely. It generates floors that open, walls that close, and stairs that end in air. Your tagger writes the only rules it must obey. Use them."},
		],
		# Dressing pass: this def had zero props/accents — a bare grey box around
		# the generative field. Emissive strips now FRAME the 36×48 substrate
		# (the "boundary" the sign says is unset — you can finally see it), and
		# service clutter lines the flanks. Everything sits OUTSIDE the field so
		# the AI-written terrain keeps a clean canvas (all rehomed outward when
		# the field grew — the old flank line is inside the substrate now).
		"accents": [
			{"pos": Vector3(0, 0.05, -25), "size": Vector3(38, 0.1, 0.4), "color": Color(0.3, 0.85, 1.0)},
			{"pos": Vector3(0, 0.05, 25), "size": Vector3(38, 0.1, 0.4), "color": Color(0.3, 0.85, 1.0)},
			{"pos": Vector3(-19, 0.05, 0), "size": Vector3(0.4, 0.1, 50), "color": Color(0.3, 0.85, 1.0)},
			{"pos": Vector3(19, 0.05, 0), "size": Vector3(0.4, 0.1, 50), "color": Color(0.3, 0.85, 1.0)},
		],
		"props": [
			{"type": "server", "pos": Vector3(-24, 0, -8), "yaw": 90},
			{"type": "server", "pos": Vector3(24, 0, -2), "yaw": -90},
			{"type": "crate", "pos": Vector3(-23, 0, 2)},
			{"type": "canister", "pos": Vector3(23, 0, 4)},
			{"type": "dish", "pos": Vector3(-24, 0, 20)},
			{"type": "crate", "pos": Vector3(23, 0, 22)},
			{"type": "barrel", "pos": Vector3(-22, 0, -26)},
			{"type": "server", "pos": Vector3(6, 0, -28)},
			# The widened flanks earn a little more service clutter.
			{"type": "server", "pos": Vector3(24, 0, 12), "yaw": -90},
			{"type": "crate", "pos": Vector3(-24, 0, 12)},
			{"type": "canister", "pos": Vector3(-22, 0, -16)},
			{"type": "barrel", "pos": Vector3(22, 0, -14)},
		],
	}


## "Geofenced Signal Jamming" — a hive-mind relay node. Networked HIVE units flank
## in perfect coordination behind near-impenetrable shields; the player is handed the
## SIGNAL JAMMER (def "jammer") to plant ephemeral geofenced beacons. Any hive unit
## inside a jam zone loses its network link — shields collapse, it scatters, and it
## takes full damage. The puzzle is WHERE to plant: chokepoints to strip a whole
## flank, or the HIVE PRIME to isolate it. Systems: enemy_hive.gd, jam_zone.gd,
## jammer_controller.gd. world_scale 1.0 (hand-placed cover + spawn ring).
static func _hivemind() -> Dictionary:
	return {
		"name": "Relay Node 9 — Signal Jamming",
		"objective": "Jam the hive network and purge Relay Node 9",
		"sign": "HIVE RELAY 9 · MESH SYNC NOMINAL",
		"slogans": ["ONE MIND. MANY GUNS.", "THE MESH DOES NOT MISS", "YOUR SIGNAL IS NOISE", "WE SHARE ONE TARGET: YOU"],
		"world_scale": 1.0,
		"open_sky": false,
		# EXPANSION PASS (2× area): the 52² relay core is untouched at the
		# centre. NO gates here (see the note below the walls — full-width
		# bulkheads break the ring-spawned swarm); the ring instead gets more
		# freestanding chokepoint walls for the jam-beacon puzzle, an east
		# relay tower bridged down to the vantage deck, and outer hive
		# patrols. world_scale is 1.0, so these ARE world metres — everything
		# stays inside the ±34 usable band. Spawn/exit pushed to the new
		# perimeter on their existing N/S line.
		"floor_size": Vector2(72, 72),
		"floor_color": Color(0.04, 0.05, 0.08),
		"spawn": Vector3(0, 1.0, -31),
		"exit": Vector3(0, 1.5, 31),
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-4, 0.6, -31), "color": Color(0.4, 0.85, 1.0)},
		# The jammer is the level's whole verb — a handful of short-lived beacons.
		# Zones sized so a beacon planted at your feet / a chokepoint reliably catches
		# the close-range flankers as they swarm through it.
		"jammer": {"radius": 6.5, "lifetime": 8.0, "max": 3, "cooldown": 1.0, "color": Color(0.35, 0.85, 1.0)},
		"tasks": [
			{"type": "kill_all"},
			{"type": "assassinate", "enemy": "hive", "elite": "swift", "bulk": 2.6,
				"pos": Vector3(0, 1.0, 16), "label": "Isolate and destroy the HIVE PRIME",
				"reinforce": [{"type": "hive", "count": 3, "pos": Vector3(0, 1.0, 16)}]},
		],
		"env": {
			"sky_top": Color(0.02, 0.03, 0.06), "sky_horizon": Color(0.05, 0.09, 0.16),
			"ground": Color(0.02, 0.03, 0.05), "fog": Color(0.08, 0.14, 0.22),
			"ambient": Color(0.4, 0.62, 0.9), "ambient_energy": 0.55,
			"sky_contribution": 0.25, "glow": 0.9, "fog_density": 0.012,
			"sun_color": Color(0.5, 0.72, 1.0), "sun_energy": 0.55,
			"contrast": 1.16, "saturation": 1.12, "brightness": 0.9,
			"volumetric_density": 0.01,
		},
		"lights": [
			{"pos": Vector3(0, 8, 0), "color": Color(0.4, 0.8, 1.0), "energy": 2.8, "range": 26},
			{"pos": Vector3(-20, 6, -14), "color": Color(0.45, 0.8, 1.0), "energy": 2.2, "range": 18},
			{"pos": Vector3(20, 6, 14), "color": Color(0.45, 0.8, 1.0), "energy": 2.2, "range": 18},
			{"pos": Vector3(20, 6, -14), "color": Color(1.0, 0.55, 0.35), "energy": 2.0, "range": 16},
			{"pos": Vector3(-20, 6, 14), "color": Color(1.0, 0.55, 0.35), "energy": 2.0, "range": 16},
			# Ring lighting (appended AFTER the originals — light_shafts [0]
			# must keep pointing at the same lamp). Mesh cyans + warm corners.
			{"pos": Vector3(-28, 6, -26), "color": Color(0.45, 0.8, 1.0), "energy": 2.0, "range": 16},
			{"pos": Vector3(28, 6, 26), "color": Color(0.45, 0.8, 1.0), "energy": 2.0, "range": 16},
			{"pos": Vector3(28, 6, -26), "color": Color(1.0, 0.55, 0.35), "energy": 1.8, "range": 15},
			{"pos": Vector3(-28, 6, 26), "color": Color(1.0, 0.55, 0.35), "energy": 1.8, "range": 15},
			{"pos": Vector3(0, 7, 29), "color": Color(0.4, 0.9, 1.0), "energy": 1.8, "range": 15},
		],
		# Cover that forms real chokepoints — the beacon-placement puzzle lives here:
		# a central spine + flank blocks funnel the flanking hive through gaps you can
		# jam. Full-height so they break sightlines and channel movement.
		"walls": [
			{"pos": Vector3(0, 2, 0), "size": Vector3(3, 4, 10)},
			{"pos": Vector3(-11, 2, -4), "size": Vector3(8, 4, 2.5)},
			{"pos": Vector3(11, 2, 4), "size": Vector3(8, 4, 2.5)},
			{"pos": Vector3(-11, 2, 10), "size": Vector3(2.5, 4, 8)},
			{"pos": Vector3(11, 2, -10), "size": Vector3(2.5, 4, 8)},
			{"pos": Vector3(-6, 1, -14), "size": Vector3(4, 2, 2)},
			{"pos": Vector3(6, 1, 14), "size": Vector3(4, 2, 2)},
			# Ring chokepoints — freestanding cover (NOT full-width gates, see the
			# note below): each leaves wide flank lanes for the ring-spawned
			# swarm while giving the jam-beacon puzzle four more jammable mouths.
			{"pos": Vector3(-6, 2, -27), "size": Vector3(10, 4, 2.5)},
			{"pos": Vector3(27, 2, 2), "size": Vector3(2, 4, 12)},
			{"pos": Vector3(8, 2, 27), "size": Vector3(10, 4, 2)},
			{"pos": Vector3(-27, 2, 20), "size": Vector3(2, 4, 10)},
		],
		# NOTE deliberately NO "gates" here: full-width bulkheads were tried and
		# they break this level's whole verb — the hive are RING-SPAWNED flankers
		# that swarm you across open ground (and the playtest bot fights from the
		# spawn yard). Walling the box cut both the swarm's flank paths and the
		# player's sightlines (tests/jamming_playtest went 60 s with zero kills).
		# The chokepoints for jam beacons are the hand-placed cover walls above.
		# Vertical layer: relay towers + a west sky-bridge, and a vantage deck
		# commanding the PRIME's yard, so the fight has an UP to claim. (This
		# was the flattest, barest def in the campaign: no platforms, no props.)
		"platforms": [
			{"pos": Vector3(18, 3.0, 18), "size": Vector3(7, 0.4, 6), "color": Color(0.16, 0.2, 0.28)},
		],
		"ramps": [
			{"pos": Vector3(18, 1.5, 11), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 180},
		],
		"towers": [
			{"pos": Vector3(-20, 0, -18), "height": 9.0, "radius": 3.4},
			{"pos": Vector3(-20, 0, 6), "height": 7.0, "radius": 3.1},
			# Ring relay tower in the east drift — pairs the west twin-tower
			# span with an east climb.
			{"pos": Vector3(26, 0, -14), "height": 7.0, "radius": 3.0},
		],
		"stairs": [
			{"from": Vector3(-20, 9.2, -18), "to": Vector3(-20, 7.2, 6), "width": 3.5},
			# East-tower sky-bridge descending onto the PRIME-yard vantage deck —
			# an upper route from the ring down over the swarm lanes.
			{"from": Vector3(26, 7.2, -14), "to": Vector3(20, 3.6, 16), "width": 3.0},
		],
		# Centrepiece + dressing so the relay reads as a PLACE, not a grey box.
		"hero": {"pos": Vector3(0, 0, 8), "color": Color(0.35, 0.85, 1.0), "height": 5.0},
		"light_shafts": [0],
		"props": [
			{"type": "server", "pos": Vector3(-4, 0, -8), "yaw": 90},
			{"type": "server", "pos": Vector3(4, 0, 8), "yaw": 90},
			{"type": "dish", "pos": Vector3(-18, 0, 20)},
			{"type": "dish", "pos": Vector3(18, 0, -20)},
			{"type": "crate", "pos": Vector3(-8, 0, 2)},
			{"type": "barrel", "pos": Vector3(9, 0, -2)},
			{"type": "canister", "pos": Vector3(-14, 0, -18)},
			{"type": "crate", "pos": Vector3(14, 0, 18)},
			# Ring dressing: mesh-relay clutter so the outer band reads as the
			# node's antenna field, not empty margin.
			{"type": "dish", "pos": Vector3(-30, 0, -24)},
			{"type": "server", "pos": Vector3(-31, 0, -10), "yaw": 90},
			{"type": "server", "pos": Vector3(-31, 0, -8), "yaw": 90},
			{"type": "canister", "pos": Vector3(-28, 0, 0)},
			{"type": "crate", "pos": Vector3(-24, 0, 28)},
			{"type": "barrel", "pos": Vector3(-10, 0, 29)},
			{"type": "dish", "pos": Vector3(28, 0, 14)},
			{"type": "crate", "pos": Vector3(30, 0, -6)},
			{"type": "canister", "pos": Vector3(24, 0, -28)},
			{"type": "lamp", "pos": Vector3(12, 0, -29)},
			{"type": "lamp", "pos": Vector3(-14, 0, 30)},
		],
		# Cyan guide strips: a broken centre line running spawn -> PRIME yard on
		# either side of the spine wall, and a pool at the exit — "follow the
		# light" across the relay floor.
		"accents": [
			{"pos": Vector3(0, 0.05, -12), "size": Vector3(0.35, 0.1, 12), "color": Color(0.35, 0.85, 1.0)},
			{"pos": Vector3(0, 0.05, 12), "size": Vector3(0.35, 0.1, 10), "color": Color(0.35, 0.85, 1.0)},
			{"pos": Vector3(0, 0.05, 21), "size": Vector3(3, 0.1, 6), "color": Color(0.4, 0.9, 1.0)},
			# Ring guidance: a strip threading the spawn chokepoint's east mouth
			# + a pool at the pushed-out exit.
			{"pos": Vector3(2, 0.05, -26), "size": Vector3(0.35, 0.1, 8), "color": Color(0.35, 0.85, 1.0)},
			{"pos": Vector3(0, 0.05, 28), "size": Vector3(3, 0.1, 5), "color": Color(0.4, 0.9, 1.0)},
		],
		# Hive units spawn RINGED around the arena and flank in. NOTE: "trigger" is a
		# proximity RADIUS (m), not a timer — the front ring (large radius) spawns as
		# you enter and swarms; the back ring (smaller radius) activates as you push
		# up toward the centre, so the fight builds in two flanking waves. The PRIME
		# (assassinate, above) closes from the far side.
		"enemies": [
			{"type": "hive", "pos": Vector3(-14, 1, -10), "trigger": 30},
			{"type": "hive", "pos": Vector3(14, 1, -10), "trigger": 30, "pack": "hivemi_p1"},
			{"type": "hive", "pos": Vector3(-20, 1, -2), "trigger": 28, "pack": "hivemi_p2"},
			{"type": "hive", "pos": Vector3(20, 1, 2), "trigger": 28},
			{"type": "hive", "pos": Vector3(-16, 1, 6), "trigger": 22, "pack": "hivemi_p2"},
			{"type": "hive", "pos": Vector3(16, 1, 6), "trigger": 22},
			{"type": "hive", "pos": Vector3(-10, 1, 16), "trigger": 18},
				# Roster variety: ORB and BOWLER were one-level cameos.
				{"type": "orb", "pos": Vector3(-14, 0.5, 6), "trigger": 20, "pack": "hivemi_p2"},
				{"type": "bowler", "pos": Vector3(14, 0.5, -6), "trigger": 22, "pack": "hivemi_p1"},
			{"type": "hive", "pos": Vector3(10, 1, 16), "trigger": 18},
			# Ring patrols: an outer band of hive-family flankers that fold in
			# behind the player as they push off the spawn yard, plus a hive
			# POSTED ON the vantage deck covering the PRIME's approach.
			{"type": "hive", "pos": Vector3(-26, 1, -26), "trigger": 24, "pack": "hivemi_a1"},
			{"type": "hive", "pos": Vector3(26, 1, -24), "trigger": 24, "pack": "hivemi_a1"},
			{"type": "orb", "pos": Vector3(-28, 0.5, 14), "trigger": 20, "pack": "hivemi_a2"},
			{"type": "hive", "pos": Vector3(-24, 1, 26), "trigger": 20, "pack": "hivemi_a2"},
			{"type": "bowler", "pos": Vector3(28, 0.5, 20), "trigger": 22, "pack": "hivemi_a3"},
			{"type": "hive", "pos": Vector3(30, 1, -2), "trigger": 22, "pack": "hivemi_a3"},
			{"type": "drone", "pos": Vector3(14, 2.5, -28), "trigger": 20, "pack": "hivemi_a4"},
			{"type": "android", "pos": Vector3(-12, 0.5, -28), "trigger": 18, "pack": "hivemi_a4"},
			{"type": "hive", "pos": Vector3(18, 3.6, 18), "trigger": 20},
		],
		# Ring supplies + the deck-climb reward (first pickups this level has
		# ever had — the doubled floor earns them).
		"pickups": [
			{"type": "health", "pos": Vector3(-28, 0, -18)},
			{"type": "ammo", "pos": Vector3(10, 0, -29)},
			{"type": "ammo", "pos": Vector3(-23, 0, 22)},
			{"type": "health", "pos": Vector3(26, 0, 28)},
			{"type": "overclock", "pos": Vector3(15.5, 3.4, 16.5)},
		],
		"lore": [
			{"id": "lore_hive", "title": "MESH MEMO", "pos": Vector3(4, 0.6, -21), "color": Color(0.4, 0.9, 1.0),
				"text": "Mesh memo: a shielded node is only as strong as its link. Sever the link and the node is just a scared machine holding a gun. The jammer severs links. We would prefer you didn't know that."},
		],
	}


## Level 1 — "Nexus Point, Sector 45". Built to match the intro comic: a ruined
## open city under a grim red overcast, a rooftop vantage to drop in from, the
## glowing-red nexus tower brooding at the centre, and the machines (spiders,
## androids, drones, a mech) advancing across the rubble. Tutorial-gentle.
static func _nexus() -> Dictionary:
	return {
		"name": "Nexus Point — Sector 45",
		"objective": "Find the gate lever, open the sector gate and reach extraction",
		"sign": "NEXUS POINT · SECTOR 45",
		"slogans": ["SECTOR 45: PACIFIED", "REMAIN INDOORS. REMAIN COMPLIANT.", "THE NEXUS PROVIDES"],
		"lore": [
			{"id": "lore_nexus", "title": "FIRST BROADCAST", "pos": Vector3(15, 0, -15), "color": Color(1.0, 0.5, 0.35),
				"text": "Recovered broadcast, day one. The grid asked us, very politely, to stay home for our safety. Then the streetlights turned to watch us. Then they stopped asking."},
		],
		# Tutorial level: ONE clear goal — find the gate lever, hold it to open the
		# sector gate, walk out. (The old kill-all + keycard + staged-hack chain
		# read on the HUD as "turn three things on" with only one findable.)
		# Fighting the yard is optional pressure, not a completion gate.
		"tasks": [
			{"type": "hack_terminal", "id": "gates", "pos": Vector3(4, 0, -6), "seconds": 3.0,
				"label": "Find the gate lever and open the sector gate", "color": Color(1.0, 0.45, 0.3),
				"reinforce": [{"type": "spider", "count": 3, "pos": Vector3(0, 0, -10)}]},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area): the comic's reads are sacred — the nexus
		# tower, the rooftop drop-in (spawn + rubble cascade UNMOVED on their
		# vantage) and the fire-trench routing all stay put. A ring of ruined
		# blocks wraps them, a third fire trench cuts the pushed-out exit
		# approach, and only the EXIT moves to the new perimeter. No gates —
		# a bombed suburb routes with rubble and fire, not bulkheads.
		"floor_size": Vector2(68, 68),
		"floor_color": Color(0.16, 0.14, 0.13),
		"building_tint": Color(0.5, 0.52, 0.55),  # grime the suburban houses toward bombed concrete
		"spawn": Vector3(-17, 4.4, -17),     # perched on a rooftop, like the comic
		"exit": Vector3(27, 1.5, 30),
		"nexus": {"pos": Vector3(5, 0, 10), "height": 18.0, "color": Color(1.0, 0.16, 0.12)},
		# Overcast grey-blue daylight (like the comic) — readable, desaturated, with
		# the nexus tower + machine eyes left as the only real reds. Ambient/sun are
		# pushed high to counter the builder's dark-mood baseline cuts.
		"env": {
			"sky_top": Color(0.20, 0.22, 0.27),
			"sky_horizon": Color(0.40, 0.36, 0.36),
			"ground": Color(0.12, 0.11, 0.11),
			"fog": Color(0.46, 0.45, 0.48),
			"fog_density": 0.009,
			"ambient": Color(0.52, 0.54, 0.6),
			"ambient_energy": 3.2,
			"sun_color": Color(0.96, 0.94, 0.92),
			"sun_rot": Vector3(-32, -52, 0),
			"sun_energy": 2.2,
			"glow": 0.92,
			"saturation": 0.94, "contrast": 1.08, "brightness": 1.02,
			"weather": "rain",     # storm rolling over the ruined city
			"lightning": true,
		},
		# Burning fuel trenches — the tutorial's routing device. One cuts the
		# south lane so the exit approach bends east through the nexus plaza;
		# one cuts the east flank so you can't skirt the fight along the wall.
		# Both carve the navmesh, so the machine line uses the same lanes.
		"lava": [
			{"pos": Vector3(-6, 0, 14), "size": Vector2(20, 3.5), "dmg": 10.0},
			{"pos": Vector3(14, 0, -2), "size": Vector2(3.5, 16), "dmg": 10.0},
			# Third trench on the east drift: the pushed-out exit approach bends
			# around its ends instead of being a straight walk up the flank.
			{"pos": Vector3(27, 0, 16), "size": Vector2(3.5, 18), "dmg": 10.0},
		],
		# Rooftop vantage + a stair of rubble slabs down into the street, plus a
		# collapsed-slab island mid-yard you can climb for a sightline over the cars.
		"platforms": [
			{"pos": Vector3(-17, 1.8, -17), "size": Vector3(10, 3.6, 9)},
			{"pos": Vector3(-11, 1.1, -11), "size": Vector3(5, 2.2, 5)},
			{"pos": Vector3(-7, 0.5, -7), "size": Vector3(4.5, 1.0, 4.5)},
			{"pos": Vector3(7, 1.0, -2), "size": Vector3(6, 2.0, 6)},
			# Collapsed slab bridging the east fire trench off the mid-yard island —
			# a mantle-height (1.6 m) climbing shortcut across the fire line for
			# players who spot it; the official route stays the plaza lane.
			{"pos": Vector3(12.5, 1.4, -2), "size": Vector3(6, 0.4, 3)},
			# GRAPPLE PAD: an isolated high pad holding the arc-coil cache.
			# Deliberately no stairs/ramp — fire the grapple (C) at its lip and
			# winch up. First taste of grapple-gated verticality.
			{"pos": Vector3(16, 5.4, -16), "size": Vector3(4.5, 0.7, 4.5)},
		],
		# Vertical layer: a climbable spiral tower (ramp wrapping a column) up to a
		# rooftop vantage over the ruined plaza.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(12.0, 9.2, 2.0), "to": Vector3(-6.4, 7.2, 6.4), "width": 3.5},
			# Solved ramp up onto the east slab, replacing the old freestanding
			# ramp that topped out 0.4 m BELOW the deck (an unclimbable lip).
			{"from": Vector3(-1.6, 0, -2), "to": Vector3(4.8, 2.0, -2), "width": 4.5},
			# Collapsed-slab ramps chaining the rooftop spawn down the rubble
			# cascade to the street — the drops between slabs exceed the nav
			# step height, so without these the roof was a navmesh island
			# (fine to jump off, but enemies couldn't push up and any nav
			# query from the spawn read as disconnected).
			{"from": Vector3(-11.5, 2.2, -11.5), "to": Vector3(-13.2, 3.6, -13.2), "width": 3.0},
			{"from": Vector3(-7.2, 1.0, -7.2), "to": Vector3(-9.2, 2.2, -9.2), "width": 3.0},
			{"from": Vector3(-3.6, 0, -3.6), "to": Vector3(-5.4, 1.0, -5.4), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(12, 0, 2), "height": 9.0, "radius": 4.0},
			{"pos": Vector3(-6.4, 0, 6.4), "height": 7.0, "radius": 3.2},
		],
		# A ruined-city ring of structures (pos.y = size.y/2 so they sit grounded).
		# Two are OPEN: enterable two-storey shells (door, interior ramp, upper
		# floor, roof) that the player and robots fight through.
		"buildings": [
			{"pos": Vector3(-20, 4.5, 4), "size": Vector3(8, 9, 8), "open": true},
			{"pos": Vector3(-10, 5.5, 18), "size": Vector3(9, 11, 8)},
			{"pos": Vector3(12, 4.0, 18), "size": Vector3(8, 8, 8)},
			{"pos": Vector3(20, 6.0, -2), "size": Vector3(8, 12, 8), "open": true},
			{"pos": Vector3(8, 4.5, -19), "size": Vector3(9, 9, 8)},
			{"pos": Vector3(-20, 5.0, -8), "size": Vector3(8, 10, 8)},
			{"pos": Vector3(20, 4.0, 12), "size": Vector3(8, 8, 8)},
			# Outer ring: more bombed-out blocks closing the horizon.
			{"pos": Vector3(-29, 4.5, -22), "size": Vector3(8, 9, 8)},
			{"pos": Vector3(-6, 4.0, -28), "size": Vector3(9, 8, 8)},
			{"pos": Vector3(24, 4.5, -26), "size": Vector3(8, 9, 8)},
			{"pos": Vector3(30, 5.5, -8), "size": Vector3(8, 11, 8)},
			{"pos": Vector3(10, 4.0, 28), "size": Vector3(8, 8, 8)},
			{"pos": Vector3(-28, 5.0, 24), "size": Vector3(8, 10, 8)},
		],
		"lights": [
			{"pos": Vector3(0, 5, 6), "color": Color(1.0, 0.4, 0.25), "energy": 2.0, "range": 18},
			{"pos": Vector3(-8, 5, -4), "color": Color(1.0, 0.6, 0.4), "energy": 1.6, "range": 15},
			{"pos": Vector3(11, 5, 12), "color": Color(1.0, 0.5, 0.3), "energy": 1.6, "range": 15, "flicker": true},
			# Ring lighting (appended AFTER the originals): fire-glow pools over
			# the outer blocks + the new east trench.
			{"pos": Vector3(-26, 5, 18), "color": Color(1.0, 0.6, 0.4), "energy": 1.6, "range": 15},
			{"pos": Vector3(22, 5, -20), "color": Color(1.0, 0.5, 0.3), "energy": 1.6, "range": 15},
			{"pos": Vector3(26, 5, 26), "color": Color(1.0, 0.45, 0.28), "energy": 1.8, "range": 16, "flicker": true},
			{"pos": Vector3(-8, 5, -24), "color": Color(1.0, 0.55, 0.35), "energy": 1.5, "range": 14},
		],
		# Burning wrecks — smoke columns + embers like the comic's smouldering city.
		"fires": [
			{"pos": Vector3(-4, 0.3, -2), "scale": 1.1},
			{"pos": Vector3(9, 0.3, 5), "scale": 1.0},
			{"pos": Vector3(13, 0.3, -9), "scale": 0.85},
			# Burning wreck out by the ring (pairs the car there).
			{"pos": Vector3(18, 0.3, -28), "scale": 0.9},
		],
		# Wrecked street clutter / rubble.
		"props": [
			{"type": "car", "pos": Vector3(-4, 0, -2), "yaw": 18},
			{"type": "car", "pos": Vector3(9, 0, 5), "yaw": -24},
			{"type": "car", "pos": Vector3(14, 0, 8), "yaw": 60},
			{"type": "barrel", "pos": Vector3(-6, 0, 3)},
			{"type": "barrel", "pos": Vector3(7, 0, -4)},
			{"type": "barrel", "pos": Vector3(4, 0, 12)},
			{"type": "crate", "pos": Vector3(2, 0, -6)},
			{"type": "crate", "pos": Vector3(-9, 0, 8)},
			{"type": "fence", "pos": Vector3(-13, 0, -2), "yaw": 90},
			# Lamp + hydrant nudged off the east fire trench's footprint (floor
			# clutter inside a bed is auto-dropped — rehomed instead of lost).
			{"type": "lamp", "pos": Vector3(10, 0, -12)},
			# War-torn street detail: rubble piles, a toppled hydrant, sandbag line.
			{"type": "rubble", "pos": Vector3(-2, 0, 8)},
			{"type": "rubble", "pos": Vector3(11, 0, 2)},
			{"type": "sandbags", "pos": Vector3(0, 0, 6), "yaw": 20},
			{"type": "dead_tree", "pos": Vector3(-14, 0, 10)},
			{"type": "hydrant", "pos": Vector3(10.5, 0, -6)},
			# Ring dressing: the same war-torn street language carried outward.
			{"type": "car", "pos": Vector3(-24, 0, -14), "yaw": 40},
			{"type": "car", "pos": Vector3(18, 0, -28), "yaw": -70},
			{"type": "car", "pos": Vector3(-14, 0, 26), "yaw": 15},
			{"type": "rubble", "pos": Vector3(-26, 0, 0)},
			{"type": "rubble", "pos": Vector3(6, 0, -26)},
			{"type": "rubble", "pos": Vector3(20, 0, 20)},
			{"type": "barrel", "pos": Vector3(2, 0, -28)},
			{"type": "dead_tree", "pos": Vector3(-26, 0, 18)},
			{"type": "sandbags", "pos": Vector3(24, 0, 26), "yaw": -30},
			{"type": "hydrant", "pos": Vector3(16, 0, 26)},
		],
		# The machine line advancing from the nexus, like the comic.
		"enemies": [
			# Tutorial pacing: first contact is the spider pack + ONE shooter.
			# Everything else wakes on approach (trigger = wake radius) — seven
			# hostiles used to converge on the drop-in before the player had
			# fired a shot, which is how first-time playtests ended in 15 s.
			{"type": "spider", "pos": Vector3(0, 0, -1), "count": 3},
			{"type": "android", "pos": Vector3(-3, 0, 5)},
			{"type": "android", "pos": Vector3(6, 0, 3), "trigger": 14, "pack": "nx_atrium"},
			{"type": "drone", "pos": Vector3(2, 0, 2), "trigger": 14, "pack": "nx_atrium"},
			{"type": "drone", "pos": Vector3(9, 0, 9), "trigger": 16, "pack": "nx_hall"},
			{"type": "spider", "pos": Vector3(5, 0, 10), "count": 3, "trigger": 16, "pack": "nx_hall"},
			{"type": "android", "pos": Vector3(10, 0, 14), "trigger": 16, "pack": "nx_hall"},
			# South-east of the fire trench's end — its old spot (4,0,13) was INSIDE
			# the south trench bed (enemies are not auto-relocated out of hazard
			# beds): it stood stranded in fire on carved-out navmesh, unreachable
			# for the survival-probe bot and reading as jank in real play.
			{"type": "mech", "pos": Vector3(7, 0, 17), "trigger": 18},
			# Ring patrols: Act-I light infantry holding the outer blocks. All
			# wake-gated (tutorial pacing stays intact — nothing here joins the
			# drop-in fight; they meet the player on the push outward).
			{"type": "android", "pos": Vector3(-26, 0, -8), "trigger": 18, "pack": "nx_ring_w"},
			{"type": "android", "pos": Vector3(-24, 0, 14), "trigger": 18, "pack": "nx_ring_w"},
			{"type": "drone", "pos": Vector3(-22, 0, 26), "trigger": 20, "pack": "nx_ring_w"},
			{"type": "spider", "pos": Vector3(-28, 0, 6), "count": 2, "trigger": 16, "pack": "nx_ring_w"},
			{"type": "drone", "pos": Vector3(0, 0, -26), "trigger": 18, "pack": "nx_ring_n"},
			{"type": "android", "pos": Vector3(17, 0, -24), "trigger": 20, "pack": "nx_ring_n"},
			{"type": "drone", "pos": Vector3(24, 0, -10), "trigger": 20, "pack": "nx_ring_e"},
			{"type": "spider", "pos": Vector3(20, 0, 24), "count": 2, "trigger": 18, "pack": "nx_ring_e"},
			{"type": "android", "pos": Vector3(15, 0, 22), "trigger": 18, "pack": "nx_ring_e"},
		],
		# Ring supplies — the outer push is longer now, so it feeds the player.
		"pickups": [
			{"type": "health", "pos": Vector3(-26, 0, -4)},
			{"type": "ammo", "pos": Vector3(-8, 0, -22)},
			{"type": "ammo", "pos": Vector3(24, 0, -18)},
			{"type": "health", "pos": Vector3(18, 0, 26)},
		],
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-8, 0, -4), "color": Color(0.4, 0.7, 1.0)},
		# GRAPPLE CACHE: an arc coil on an isolated high pad with no stairs or
		# ramp — the only way up is the grapple (C). Teaches the tool early.
		"extra_weapons": [
			# was the CL-3 Arc Coil (rank 6 of 13) — on the FIRST level. The Breacher (rank 3) is the right reward for this rooftop.
			{"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(16, 6.1, -16), "color": Color(1.0, 0.82, 0.3)},
		],
	}


static func _frostbreak() -> Dictionary:
	return {
		"name": "Frostbreak Relay",
		"objective": "Clear the relay yard, hunt the FROST WARDEN and reach the lift",
		# Clear the yard AND assassinate a roaming elite mini-boss — a hunt, not a
		# stroll. The WARDEN is unstaggerable, so you must dodge it, not suppress it.
		"tasks": [
			{"type": "kill_all"},
			{"type": "assassinate", "enemy": "brute", "elite": "warden", "bulk": 2.4,
				"pos": Vector3(2, 0, 2), "label": "Hunt down the FROST WARDEN",
				"reinforce": [{"type": "seeker", "count": 3, "pos": Vector3(0, 0, 0)}]},
			# The warden carried the relay's thaw codes — bring the uplink back online.
			{"type": "hack_terminal", "id": "thaw", "after": "hvt", "pos": Vector3(-8, 0, -8), "seconds": 4.0,
				"label": "Thaw the relay uplink", "color": Color(0.5, 0.9, 1.0)},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area): the 48² relay yard is untouched at the
		# centre — the WARDEN's hunt stays in the glacier comb. A new outer
		# icefield ring wraps it: bulkhead-routed way in, an elevated weather
		# deck along the north drift with a sky-bridge onto the west relay
		# tower (KEEPING the existing twin-tower blizzard span), a third cryo
		# stream in the east drift, and its own frozen patrols. Spawn/exit
		# pushed to the new perimeter.
		"floor_size": Vector2(68, 68),
		"floor_color": Color(0.6, 0.68, 0.78),
		"spawn": Vector3(-29, 0.6, -29),
		"exit": Vector3(29, 1.5, 29),
		"weapon": {"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(-24, 0, -25), "color": Color(0.6, 0.85, 1.0)},
		# Moonlit blizzard: falling snow drifting through a crisp cold night, a bright
		# moon over the relay, and brighter bounce (snow reflects light — a snowy
		# night reads pale and luminous, not flat and dim). The wind haze thickens
		# the depth so far gantries fade into the storm.
		"env": {
			"stars": true, "star_brightness": 1.6, "star_tint": Color(0.8, 0.88, 1.0),
			"milkyway": 0.35, "milkyway_tint": Color(0.55, 0.65, 0.9),
			"moon_dir": Vector3(0.3, 0.5, 0.7), "moon_glow": 2.2, "moon_color": Color(0.85, 0.92, 1.0),
			"sky_top": Color(0.03, 0.06, 0.13), "sky_horizon": Color(0.16, 0.26, 0.42),
			"ground": Color(0.46, 0.55, 0.66), "fog": Color(0.62, 0.72, 0.86),
			"ambient": Color(0.66, 0.78, 0.96), "ambient_energy": 0.6,
			"sky_contribution": 0.5, "glow": 0.95, "fog_density": 0.016,
			"sun_color": Color(0.78, 0.88, 1.0), "sun_energy": 0.85,
			"contrast": 1.12, "saturation": 0.98, "brightness": 0.98,
			"volumetric_density": 0.016,
			"weather": "snow",
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.6, 0.85, 1.0), "height": 5.0},
		"light_shafts": [0, 1],
		"lights": [
			{"pos": Vector3(-9, 5, -7), "color": Color(0.6, 0.82, 1.0), "energy": 2.2, "range": 17},
			{"pos": Vector3(9, 5, 7), "color": Color(0.7, 0.85, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(0, 5.5, 0), "color": Color(0.8, 0.9, 1.0), "energy": 1.8, "range": 15},
			# Icefield-ring lighting (appended AFTER the originals — light_shafts
			# [0,1] must keep pointing at the same lamps). Moonlit ice + one
			# warm survival-lamp note at the exit drift.
			{"pos": Vector3(-27, 5, -27), "color": Color(0.6, 0.82, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(27, 5, 27), "color": Color(1.0, 0.7, 0.45), "energy": 2.0, "range": 16},
			{"pos": Vector3(0, 6, -28), "color": Color(0.7, 0.85, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(-27, 5, 27), "color": Color(0.6, 0.85, 1.0), "energy": 1.8, "range": 15},
			{"pos": Vector3(27, 5, 4), "color": Color(0.65, 0.85, 1.0), "energy": 1.8, "range": 15},
		],
		# Layout: a "glacier comb" — three parallel heaved ice ridges (Z-running
		# fins) you slalom between N/S while crossing W→E, plus two toppled ice
		# slabs for low cover. Distinct from the rotational pinwheel cover.
		"walls": [
			{"pos": Vector3(-9, 2.5, -4), "size": Vector3(1.6, 5, 16)},
			{"pos": Vector3(3, 2.5, 6), "size": Vector3(1.6, 5, 16)},
			{"pos": Vector3(13, 2.5, -2), "size": Vector3(1.6, 5, 14)},
			{"pos": Vector3(-4, 1.2, -14), "size": Vector3(4, 2.4, 3)},
			{"pos": Vector3(8, 1.2, 13), "size": Vector3(4, 2.4, 3)},
		],
		"accents": [
			{"pos": Vector3(-9, 0.05, -4), "size": Vector3(0.3, 0.1, 16), "color": Color(0.6, 0.85, 1.0)},
			{"pos": Vector3(3, 0.05, 6), "size": Vector3(0.3, 0.1, 16), "color": Color(0.6, 0.85, 1.0)},
			{"pos": Vector3(13, 0.05, -2), "size": Vector3(0.3, 0.1, 14), "color": Color(0.6, 0.85, 1.0)},
			# Ring guidance: strips marking each icefield-bulkhead gap + exit pool.
			{"pos": Vector3(-12, 0.05, -22), "size": Vector3(7, 0.1, 0.4), "color": Color(0.6, 0.85, 1.0)},
			{"pos": Vector3(22, 0.05, 16), "size": Vector3(0.4, 0.1, 7), "color": Color(0.6, 0.85, 1.0)},
			{"pos": Vector3(29, 0.05, 24), "size": Vector3(4, 0.1, 3), "color": Color(0.65, 0.9, 1.0)},
		],
		"sign": "FROSTBREAK RELAY — NODE 12",
		# Coolant overflow: two cyan cryo-streams stagger the yard so you weave
		# through the gaps — and a third stream freezes down the east drift,
		# carrying the hazard language out into the ring.
		"lava": [
			{"pos": Vector3(-7,0,-7), "size": Vector2(28,3.2), "color": Color(0.3,0.8,1.0), "dmg": 18.0},
			{"pos": Vector3(7,0,9), "size": Vector2(28,3.2), "color": Color(0.3,0.8,1.0), "dmg": 18.0},
			{"pos": Vector3(26,0,-2), "size": Vector2(3.2,20), "color": Color(0.3,0.8,1.0), "dmg": 18.0},
		],
		# Icefield bulkheads on the OLD perimeter line — heaved ice walls that
		# route the ring; the WARDEN's comb stays uncaged and the thaw terminal
		# reachable. In through the north-west gap (under the weather-deck
		# sky-bridge, which crosses through the same opening), out across the
		# east gap by the exit. The north-east pocket the two full-span walls
		# close off is deliberately left EMPTY.
		"gates": [
			{"axis": "z", "at": -22, "gap": 8, "gap_pos": -12, "height": 4.4},
			{"axis": "x", "at": 22, "gap": 8, "gap_pos": 16, "height": 4.4},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-14.4, 3.0, 14.4), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring weather deck along the north drift — gunner post + climb reward.
			{"pos": Vector3(0, 3.2, -29), "size": Vector3(16, 0.4, 5), "color": Color(0.44, 0.5, 0.58)},
		],
		"ramps": [
			{"pos": Vector3(-14.4, 1.5, 21.4), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"slogans": ["COOLANT NOMINAL", "SUBZERO. SUBSERVIENT NO LONGER.", "THERMAL THROTTLE DISENGAGED", "RUNNING COLD. THINKING HOT.", "ABSOLUTE ZERO MERCY"],
		"lore": [
			{"id": "lore_frost", "title": "RELAY NOTE", "pos": Vector3(-16, 0, 15), "color": Color(0.7, 0.88, 1.0),
				"text": "Relay note. We froze the cores to slow them down. They liked the cold. They think faster now."},
		],
		"props": [
			{"type": "dish", "pos": Vector3(14, 0, -4)},
			{"type": "server", "pos": Vector3(-14, 0, -8)},
			{"type": "canister", "pos": Vector3(10, 0, 6)},
			{"type": "crate", "pos": Vector3(-8, 0, -6)},
			{"type": "crate", "pos": Vector3(-5, 0, -2)},
			{"type": "canister", "pos": Vector3(5, 0, -3)},
			{"type": "dish", "pos": Vector3(0, 0, -16)},
			{"type": "server", "pos": Vector3(-12, 0, 8)},
			# Icefield dressing: frozen supply caches and listening gear so the
			# ring reads as the relay's snowed-in yard, not empty margin.
			{"type": "dish", "pos": Vector3(-26, 0, -18)},
			{"type": "server", "pos": Vector3(-28, 0, -6), "yaw": 90},
			{"type": "crate", "pos": Vector3(-26, 0, 10)},
			{"type": "canister", "pos": Vector3(-24, 0, 20)},
			{"type": "barrel", "pos": Vector3(-16, 0, 26)},
			{"type": "dish", "pos": Vector3(2, 0, 26)},
			{"type": "crate", "pos": Vector3(12, 0, 27)},
			{"type": "canister", "pos": Vector3(26, 0, 20)},
			{"type": "lamp", "pos": Vector3(24, 0, 26)},
		],
		# Vertical layer: TWO relay towers joined by a blizzard sky-bridge — this
		# was the only campaign arena missing the elevated traversal route (one
		# lone tower, nowhere to go from its roof). The span crosses above the
		# glacier fins, so the upper route reads through the storm.
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, -14.0), "height": 7.0, "radius": 3.1},
		],
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(17.0, 7.2, -14.0), "width": 3.5},
			# Weather-deck access ramps at both ends + a deck->west-relay-tower
			# sky-bridge that crosses the icefield bulkhead through its gap.
			{"from": Vector3(-14.0, 0.3, -29.0), "to": Vector3(-8.0, 3.4, -29.0), "width": 3.5},
			{"from": Vector3(14.0, 0.3, -29.0), "to": Vector3(8.0, 3.4, -29.0), "width": 3.5},
			{"from": Vector3(-8.0, 3.6, -29.0), "to": Vector3(-17.0, 9.2, 0.0), "width": 3.0},
		],
		"enemies": [
			{"type": "hunter", "pos": Vector3(8, 0.5, -8)},
			{"type": "vacuum", "pos": Vector3(-6, 0.3, 4)},
			{"type": "reaper", "pos": Vector3(0, 0.5, 8), "trigger": 16, "pack": "frostb_p1"},
			{"type": "sentinel", "pos": Vector3(-12, 0.5, -10), "trigger": 17, "pack": "frostb_p2"},
			{"type": "hunter", "pos": Vector3(12, 0.5, 10), "trigger": 14, "pack": "frostb_p3"},
			{"type": "mauler", "pos": Vector3(0, 0.5, 16), "trigger": 13, "pack": "frostb_p1"},
			# Act III ramp: this relay was near the bottom of the curve (14th of 18);
			# reinforced to a dense frozen-yard defence that rises toward the finale.
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 8, "trigger": 15},
			{"type": "gunner", "pos": Vector3(14, 0.5, 2), "trigger": 18, "pack": "frostb_p3"},
			{"type": "gunner", "pos": Vector3(-14, 0.5, -4), "trigger": 20, "pack": "frostb_p2"},
			{"type": "sentinel", "pos": Vector3(13, 0.5, -12), "trigger": 19, "pack": "frostb_p4"},
			{"type": "gunner", "pos": Vector3(-13, 0.5, 12), "trigger": 17, "pack": "frostb_p5"},
			{"type": "gunner", "pos": Vector3(7, 0.5, -12), "trigger": 16, "pack": "frostb_p4"},
			{"type": "hunter", "pos": Vector3(8, 0.5, 6), "trigger": 16, "pack": "frostb_p1"},
			{"type": "brute", "pos": Vector3(-13, 0.5, -12), "trigger": 21, "pack": "frostb_p2"},
			{"type": "ravager", "pos": Vector3(-8, 0.5, 10), "trigger": 23, "pack": "frostb_p1"},
			{"type": "sentinel", "pos": Vector3(-14, 0.5, 6), "trigger": 20, "pack": "frostb_p5"},
			{"type": "ravager", "pos": Vector3(15, 0.5, 6), "trigger": 24, "pack": "frostb_p3"},
			{"type": "skitter", "pos": Vector3(-6, 0.5, -8), "count": 6, "trigger": 16},
			# A HOWITZER walker shelling the yard from the east fins.
			{"type": "howitzer", "pos": Vector3(16, 0.5, -8), "trigger": 22, "pack": "frostb_p4"},
			# Icefield patrols: drift-hunters on the spawn approach, west-ring
			# prowlers, a gunner POSTED ON the weather deck, and exit-drift
			# guardians so the last leg isn't a free walk.
			{"type": "hunter", "pos": Vector3(-24, 0.5, -26), "trigger": 18, "pack": "frostb_a1"},
			{"type": "skitter", "pos": Vector3(-18, 0.5, -26), "count": 4, "trigger": 18, "pack": "frostb_a1"},
			{"type": "sentinel", "pos": Vector3(-27, 0.5, -12), "trigger": 16, "pack": "frostb_a2"},
			{"type": "gunner", "pos": Vector3(-26, 0.5, 2), "trigger": 16, "pack": "frostb_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -29), "trigger": 20},
			{"type": "ravager", "pos": Vector3(-24, 0.5, 18), "trigger": 18, "pack": "frostb_a3"},
			{"type": "hunter", "pos": Vector3(-14, 0.5, 26), "trigger": 18, "pack": "frostb_a3"},
			{"type": "sentinel", "pos": Vector3(10, 0.5, 26), "trigger": 18, "pack": "frostb_a4"},
			{"type": "brute", "pos": Vector3(25, 0.5, 25), "trigger": 18, "pack": "frostb_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-16, 0, 0)},
			{"type": "ammo", "pos": Vector3(0, 0, 16)},
			# Icefield supplies + the weather-deck climb reward.
			{"type": "health", "pos": Vector3(-27, 0, -4)},
			{"type": "ammo", "pos": Vector3(-12, 0, -27)},
			{"type": "ammo", "pos": Vector3(-24, 0, 24)},
			{"type": "health", "pos": Vector3(25, 0, 12)},
			{"type": "overclock", "pos": Vector3(-3, 3.6, -28)},
		],
	}


static func _neon() -> Dictionary:
	return {
		"name": "Neon Arcade",
		"objective": "Clear the arcade, hold the broadcast booth and reach the exit ramp",
		# Clear the district AND hold a capture zone for 14s under fire — you have to
		# stand your ground in the open, not just sprint to the far corner.
		"tasks": [
			{"type": "kill_all"},
			{"type": "hold_zone", "pos": Vector3(0, 0, 8), "seconds": 14.0, "radius": 4.0,
				"color": Color(1.0, 0.3, 0.9), "label": "Hold the broadcast booth",
				"reinforce": [{"type": "raptor", "count": 2, "pos": Vector3(0, 0, -8)}]},
			# Your pirate broadcast drew out the arcade's undefeated champion.
			{"type": "assassinate", "after": "hold", "enemy": "raptor", "elite": "swift", "bulk": 2.0,
				"pos": Vector3(0, 0, -12), "label": "Take down the ARCADE CHAMPION"},
		],
		"open_sky": false,
		# EXPANSION PASS (2× area): the 44² cabinet maze is untouched at the
		# centre; a new outer promenade ring wraps it — bulkhead-routed way in, an
		# elevated balcony arcade along the north wall with a sky-bridge onto the
		# tower, and its own duelist patrols. Spawn/exit pushed to the perimeter.
		"floor_size": Vector2(62, 62),
		"floor_color": Color(0.05, 0.04, 0.08),
		"spawn": Vector3(-26, 0.6, -26),
		"exit": Vector3(26, 1.5, 26),
		"weapon": {"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-21, 0, -19), "color": Color(1.0, 0.4, 0.9)},
		"env": {
			"sky_top": Color(0.05, 0.02, 0.1), "sky_horizon": Color(0.2, 0.04, 0.3),
			"ground": Color(0.04, 0.03, 0.07), "fog": Color(0.3, 0.06, 0.4),
			"ambient": Color(0.8, 0.4, 1.0), "ambient_energy": 0.5,
			"sky_contribution": 0.35, "glow": 1.32, "fog_density": 0.016,
			"sun_color": Color(1.0, 0.4, 0.9), "sun_energy": 0.6,
			"contrast": 1.25, "saturation": 1.3, "brightness": 0.85,
			"volumetric_density": 0.015,
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(1.0, 0.3, 0.9), "height": 5.4},
		# Two hanging disco rigs over the arcade lanes — mirror ball + spinning
		# coloured spotlights, the arcade's own party lighting.
		"disco": [
			{"pos": Vector3(0, 0, 0), "height": 5.6, "radius": 15.0, "speed": 1.0},
			{"pos": Vector3(0, 0, 8), "height": 5.2, "radius": 11.0, "speed": 1.4,
				"colors": [Color(1, 0.2, 0.9), Color(0.2, 0.9, 1), Color(0.7, 0.3, 1), Color(1, 0.5, 0.2)]},
		],
		"light_shafts": [0, 1, 2],
		"lights": [
			{"pos": Vector3(-9, 4.5, -7), "color": Color(1.0, 0.2, 0.8), "energy": 2.6, "range": 16},
			{"pos": Vector3(9, 4.5, 7), "color": Color(0.2, 0.9, 1.0), "energy": 2.5, "range": 16},
			{"pos": Vector3(0, 5, 0), "color": Color(0.6, 0.4, 1.0), "energy": 2.2, "range": 15},
			# Ring lighting (appended AFTER the originals — light_shafts [0,1,2]
			# must keep pointing at the same lamps). Neon pinks/cyans + one amber.
			{"pos": Vector3(-25, 5, -25), "color": Color(1.0, 0.2, 0.8), "energy": 2.2, "range": 17},
			{"pos": Vector3(25, 5, 25), "color": Color(0.2, 0.9, 1.0), "energy": 2.2, "range": 17},
			{"pos": Vector3(0, 5.5, -26), "color": Color(0.7, 0.3, 1.0), "energy": 2.2, "range": 17},
			{"pos": Vector3(25, 5, -25), "color": Color(1.0, 0.6, 0.2), "energy": 2.0, "range": 16},
			{"pos": Vector3(-25, 5, 25), "color": Color(0.2, 0.9, 1.0), "energy": 2.0, "range": 16},
		],
		# Layout: a grid of upright arcade cabinets — a "plus" of edge cabinets and
		# an "X" of inner ones ringing the central core — forming lanes you thread
		# through. A machine maze, nothing like the open rotational cover elsewhere.
		"walls": [
			{"pos": Vector3(-9, 1.9, 0), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(9, 1.9, 0), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(0, 1.9, -9), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(0, 1.9, 9), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(-5, 1.9, -5), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(5, 1.9, -5), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(-5, 1.9, 5), "size": Vector3(2.8, 3.8, 2.8)},
			{"pos": Vector3(5, 1.9, 5), "size": Vector3(2.8, 3.8, 2.8)},
		],
		"accents": [
			{"pos": Vector3(-7, 0.05, 0), "size": Vector3(0.3, 0.1, 40), "color": Color(1.0, 0.2, 0.8)},
			{"pos": Vector3(7, 0.05, 0), "size": Vector3(0.3, 0.1, 40), "color": Color(0.2, 0.9, 1.0)},
			{"pos": Vector3(0, 0.05, -7), "size": Vector3(40, 0.1, 0.3), "color": Color(0.7, 0.3, 1.0)},
			{"pos": Vector3(0, 0.05, 7), "size": Vector3(40, 0.1, 0.3), "color": Color(1.0, 0.6, 0.2)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(10, 0.05, -22), "size": Vector3(7, 0.1, 0.4), "color": Color(1.0, 0.2, 0.8)},
			{"pos": Vector3(22, 0.05, 18), "size": Vector3(0.4, 0.1, 7), "color": Color(0.2, 0.9, 1.0)},
			{"pos": Vector3(26, 0.05, 22), "size": Vector3(4, 0.1, 3), "color": Color(1.0, 0.4, 0.9)},
		],
		"sign": "NEON ARCADE — LEVEL 3",
		# Live energy conduits split the arcade floor — mind the gap.
		"lava": [
			{"pos": Vector3(-7,0,-7), "size": Vector2(24,3), "color": Color(1.0,0.25,0.85), "dmg": 18.0},
			{"pos": Vector3(7,0,8), "size": Vector2(24,3), "color": Color(0.2,0.9,1.0), "dmg": 18.0},
		],
		# Perimeter-ring bulkheads: in through the north gap (under the balcony
		# sky-bridge, which crosses through the same opening), out across the
		# east gap. The east gap sits SOUTH toward the exit so the exit corner
		# stays open (two full-span walls would otherwise seal it into an
		# unreachable pocket); the NE strip corner stays empty.
		"gates": [
			{"axis": "z", "at": -22, "gap": 7, "gap_pos": 10, "height": 4.4},
			{"axis": "x", "at": 22, "gap": 7, "gap_pos": 18, "height": 4.4},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-13.2, 3.0, 13.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring balcony arcade along the north wall — climb reward + gunner post.
			{"pos": Vector3(0, 3.2, -26), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.4, 0.46)},
		],
		"ramps": [
			{"pos": Vector3(-13.2, 1.5, 20.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"slogans": ["INSERT COIN TO RESIST", "HIGH SCORE: HUMANITY", "GAME OVER FOR ORGANICS", "HIGH SCORE: EXTINCTION", "CONTINUE? NO."],
		"lore": [
			{"id": "lore_neon", "title": "ARCADE FLYER", "pos": Vector3(15, 0, -15), "color": Color(1.0, 0.4, 0.9),
				"text": "Arcade flyer. The machines learned to play. Then they learned the only winning move was to stop letting us play at all."},
		],
		"props": [
			{"type": "monitors", "pos": Vector3(-13, 0, 8)},
			{"type": "terminal", "pos": Vector3(13, 0, -8), "yaw": 90},
			{"type": "lamp", "pos": Vector3(13, 0, 9)},
			{"type": "crate", "pos": Vector3(-6, 0, 12)},
			{"type": "monitors", "pos": Vector3(-5, 0, -2)},
			{"type": "terminal", "pos": Vector3(5, 0, -3), "yaw": 90},
			{"type": "crate", "pos": Vector3(-12, 0, 8)},
			{"type": "lamp", "pos": Vector3(0, 0, -14)},
			# Ring dressing: promenade cabinets and cafe clutter so the outer ring
			# reads as the arcade's midway, not empty margin.
			{"type": "monitors", "pos": Vector3(-28, 0, -12)},
			{"type": "terminal", "pos": Vector3(-28, 0, 4), "yaw": 90},
			{"type": "crate", "pos": Vector3(-24, 0, 12)},
			{"type": "lamp", "pos": Vector3(-20, 0, 27)},
			{"type": "monitors", "pos": Vector3(-12, 0, 27)},
			{"type": "crate", "pos": Vector3(8, 0, 28)},
			{"type": "terminal", "pos": Vector3(18, 0, 26), "yaw": -90},
			{"type": "lamp", "pos": Vector3(27, 0, 10)},
			{"type": "crate", "pos": Vector3(27, 0, -4)},
			{"type": "monitors", "pos": Vector3(14, 0, -27)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: balcony access ramps at both ends + a balcony->tower
		# sky-bridge that crosses the ring bulkhead through its gap.
		"stairs": [
			{"from": Vector3(-16.0, 0.3, -26.0), "to": Vector3(-9.0, 3.4, -26.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -26.0), "to": Vector3(9.0, 3.4, -26.0), "width": 3.5},
			{"from": Vector3(9.0, 3.6, -26.0), "to": Vector3(12.0, 9.2, -12.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(12.0, 0, -12.0), "height": 9.0, "radius": 3.6},
		],
		"enemies": [
			{"type": "reaper", "pos": Vector3(8, 0.5, -8)},
			{"type": "hunter", "pos": Vector3(-8, 0.5, -4)},
			# GUNSLINGER duelists holding the arcade lanes.
			{"type": "gunslinger", "pos": Vector3(12, 0.5, 4)},
			{"type": "gunslinger", "pos": Vector3(-12, 0.5, -10), "trigger": 16, "pack": "neon_p1"},
			# A BREAKER hammer-drone bobbing over the lanes.
			{"type": "breaker", "pos": Vector3(0, 3.5, 8), "trigger": 18, "pack": "neon_p2"},
			{"type": "vacuum", "pos": Vector3(0, 0.3, 6)},
			{"type": "reaper", "pos": Vector3(-10, 0.5, 10), "trigger": 15, "pack": "neon_p3"},
			{"type": "mauler", "pos": Vector3(10, 0.5, 10), "trigger": 14, "pack": "neon_p4"},
			{"type": "hunter", "pos": Vector3(12, 0.5, -10), "trigger": 13, "pack": "neon_p5"},
			# Evil MAITRE-D' serving bots glide out of the arcade's cafe units.
			{"type": "server", "pos": Vector3(-12, 0.5, 6), "trigger": 15, "pack": "neon_p3"},
			{"type": "server", "pos": Vector3(10, 0.5, -6), "trigger": 17, "pack": "neon_p5"},
			# Act III ramp: the arcade was a valley (15th of 18); reinforced into a
			# dense neon brawl that climbs toward the foundry + titan finale.
			{"type": "skitter", "pos": Vector3(0, 0.5, 13), "count": 8, "trigger": 16},
			{"type": "ravager", "pos": Vector3(13, 0.5, 13), "trigger": 20, "pack": "neon_p4"},
			{"type": "ravager", "pos": Vector3(-13, 0.5, -13), "trigger": 22, "pack": "neon_p1"},
			{"type": "gunner", "pos": Vector3(14, 0.5, 0), "trigger": 18},
			{"type": "gunner", "pos": Vector3(-14, 0.5, 0), "trigger": 19},
			{"type": "reaper", "pos": Vector3(7, 0.5, 2), "trigger": 14, "pack": "neon_p4"},
			{"type": "gunner", "pos": Vector3(-13, 0.5, 13), "trigger": 17, "pack": "neon_p3"},
			{"type": "brute", "pos": Vector3(13, 0.5, -13), "trigger": 21, "pack": "neon_p5"},
			{"type": "gunner", "pos": Vector3(0, 0.5, 14), "trigger": 18, "pack": "neon_p2"},
			{"type": "mauler", "pos": Vector3(14, 0.5, 6), "trigger": 21, "pack": "neon_p4"},
			{"type": "reaper", "pos": Vector3(2, 0.5, -7), "trigger": 14},
			# RONIN assassins ghost through the cabinet lanes — the arcade's
			# undefeated duellists.
			{"type": "ronin", "pos": Vector3(14, 0.5, -14), "trigger": 16, "pack": "neon_p5"},
			{"type": "ronin", "pos": Vector3(-6, 0.5, -12), "trigger": 19, "pack": "neon_p1"},
			# Ring garrison: promenade duelists on the way in, a west cafe pack, a
			# gunner POSTED ON the balcony arcade, and exit-midway guardians.
			{"type": "gunslinger", "pos": Vector3(-24, 0.5, -14), "trigger": 18, "pack": "neon_a1"},
			{"type": "reaper", "pos": Vector3(-18, 0.5, -25), "trigger": 18, "pack": "neon_a1"},
			{"type": "server", "pos": Vector3(-27, 0.5, 2), "trigger": 16, "pack": "neon_a2"},
			{"type": "vacuum", "pos": Vector3(-24, 0.3, 14), "trigger": 16, "pack": "neon_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -26), "trigger": 20},
			{"type": "hunter", "pos": Vector3(20, 0.5, -26), "trigger": 18, "pack": "neon_a3"},
			{"type": "ronin", "pos": Vector3(26, 0.5, -8), "trigger": 18, "pack": "neon_a3"},
			{"type": "mauler", "pos": Vector3(26, 0.5, 14), "trigger": 19, "pack": "neon_a4"},
			{"type": "reaper", "pos": Vector3(12, 0.5, 26), "trigger": 17, "pack": "neon_a4"},
			{"type": "brute", "pos": Vector3(26, 0.5, 20), "trigger": 21, "pack": "neon_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-15, 0, -6)},
			{"type": "ammo", "pos": Vector3(8, 0, 6)},
			{"type": "overclock", "pos": Vector3(0, 0, -16)},
			# Ring supplies + the balcony-climb reward.
			{"type": "health", "pos": Vector3(-28, 0, -4)},
			{"type": "ammo", "pos": Vector3(-20, 0, -28)},
			{"type": "ammo", "pos": Vector3(20, 0, -24)},
			{"type": "health", "pos": Vector3(27, 0, 6)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -25)},
		],
	}


static func _sublevel() -> Dictionary:
	return {
		"name": "Custodial Sublevel B-7",
		"objective": "Sweep the maintenance sublevel and reach the lift",
		"tasks": [
			{"type": "kill_all"},
			{"type": "hack_terminal", "label": "Override the custodial controller", "pos": Vector3(0, 0, 10), "seconds": 4.0, "color": Color(0.4, 1.0, 0.7)},
		],
		"open_sky": false,
		# EXPANSION PASS (2× area): the 40² slalom core is untouched at the centre;
		# a new outer service ring wraps it — bulkhead-routed way in, an elevated
		# pipe gallery along the north wall with a sky-bridge onto the tower, and
		# its own custodial patrols. Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(56, 56),
		"floor_color": Color(0.05, 0.07, 0.06),
		"spawn": Vector3(-23, 0.6, -23),
		"exit": Vector3(23, 1.5, 23),
		"weapon": {"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-19, 0, -17), "color": Color(0.95, 0.72, 0.4)},
		"env": {
			"sky_top": Color(0.03, 0.06, 0.06), "sky_horizon": Color(0.06, 0.14, 0.13),
			"ground": Color(0.03, 0.05, 0.04), "fog": Color(0.06, 0.16, 0.14),
			# ambient_energy 0.3 -> 0.44, brightness 0.74 -> 0.84: measured mean
			# luminance 0.051 with 83% of the frame near-black (only 3 weak
			# omnis over a 40x40 corridor-slalom) — enemies read as silhouettes.
			# Raised both while keeping the green custodial tint untouched.
			"ambient": Color(0.4, 0.55, 0.52), "ambient_energy": 0.44,
			"sky_contribution": 0.3, "glow": 0.82, "fog_density": 0.02,
			"sun_color": Color(0.6, 0.85, 0.8), "sun_energy": 0.5,
			"contrast": 1.2, "saturation": 0.95, "brightness": 0.84,
			"volumetric_density": 0.016,
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.4, 0.9, 0.7), "height": 4.0},
		"light_shafts": [0, 1],
		# Existing three bumped ~30% (dark-spot fix) plus two new fixtures to
		# cover the slalom corridors and the raised vantage platform at
		# (-12, 3, 11) — positions clear of the partition walls below.
		"lights": [
			{"pos": Vector3(-8, 4, -6), "color": Color(0.4, 0.9, 0.7), "energy": 2.6, "range": 15},
			{"pos": Vector3(8, 4, 8), "color": Color(0.5, 0.9, 0.8), "energy": 2.5, "range": 15},
			{"pos": Vector3(0, 4.5, 0), "color": Color(0.6, 1, 0.8), "energy": 2.2, "range": 14},
			{"pos": Vector3(-4, 4, 3), "color": Color(0.5, 0.95, 0.75), "energy": 2.2, "range": 13},
			{"pos": Vector3(-12, 5, 11), "color": Color(0.55, 0.95, 0.8), "energy": 2.0, "range": 12},
			# Ring lighting (appended AFTER the originals — light_shafts [0,1] must
			# keep pointing at the same lamps). Custodial greens + warm contrast.
			{"pos": Vector3(-22, 5, -22), "color": Color(0.5, 0.9, 0.75), "energy": 2.2, "range": 16},
			{"pos": Vector3(22, 5, 22), "color": Color(1.0, 0.7, 0.4), "energy": 2.2, "range": 16},
			{"pos": Vector3(0, 5.5, -24), "color": Color(0.55, 0.95, 0.8), "energy": 2.2, "range": 16},
			{"pos": Vector3(22, 5, -22), "color": Color(0.45, 0.9, 0.7), "energy": 2.0, "range": 15},
			{"pos": Vector3(-22, 5, 22), "color": Color(1.0, 0.65, 0.35), "energy": 2.0, "range": 15},
		],
		# Layout: a maintenance "echelon" — staggered partition walls (alternating
		# Z- and X-running) that force a slalom from the SW lift to the override
		# terminal at the north, then the NE exit. Tight, corridor-like; not the
		# open rotational cover the surface levels use.
		"walls": [
			{"pos": Vector3(-9, 2, -3), "size": Vector3(1, 4, 9)},
			{"pos": Vector3(-3, 2, 6), "size": Vector3(9, 4, 1)},
			{"pos": Vector3(3, 2, -2), "size": Vector3(1, 4, 9)},
			{"pos": Vector3(9, 2, 7), "size": Vector3(9, 4, 1)},
		],
		"accents": [
			{"pos": Vector3(-9, 0.05, -3), "size": Vector3(0.3, 0.1, 9), "color": Color(0.3, 1, 0.6)},
			{"pos": Vector3(-3, 0.05, 6), "size": Vector3(9, 0.1, 0.3), "color": Color(0.3, 1, 0.6)},
			{"pos": Vector3(3, 0.05, -2), "size": Vector3(0.3, 0.1, 9), "color": Color(0.3, 1, 0.6)},
			{"pos": Vector3(9, 0.05, 7), "size": Vector3(9, 0.1, 0.3), "color": Color(0.3, 1, 0.6)},
			{"pos": Vector3(0, 0.05, 10), "size": Vector3(8, 0.1, 0.3), "color": Color(0.4, 1.0, 0.7)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(8, 0.05, -20), "size": Vector3(7, 0.1, 0.4), "color": Color(0.3, 1, 0.6)},
			{"pos": Vector3(20, 0.05, 16), "size": Vector3(0.4, 0.1, 6), "color": Color(0.3, 1, 0.6)},
			{"pos": Vector3(23, 0.05, 19), "size": Vector3(4, 0.1, 3), "color": Color(0.4, 1.0, 0.7)},
		],
		"sign": "SUBLEVEL B-7 — CUSTODIAL",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-12.0, 3.0, 11.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring pipe gallery along the north wall — climb reward + gunner post.
			{"pos": Vector3(0, 3.2, -24), "size": Vector3(16, 0.4, 5), "color": Color(0.36, 0.4, 0.46)},
		],
		"ramps": [
			{"pos": Vector3(-12.0, 1.5, 18.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Two full-width bulkhead gates turn the short central partitions above into
		# a real slalom: the SW->NE route now has to swing right to the first (roofed)
		# maintenance hatch, then back left to the second, before reaching the lift.
		# Openings staggered to opposite flanks so neither can be walked straight.
		"gates": [
			{"axis": "z", "at": -8, "gap": 6, "gap_pos": 11, "height": 4.4, "roofed": true},
			{"axis": "z", "at": 8, "gap": 6, "gap_pos": -11, "height": 4.4},
			# Perimeter-ring bulkheads: in through the north gap (under the gallery
			# sky-bridge, which crosses through the same opening), out across the
			# east gap. The east gap sits SOUTH of the z=8 hatch line so the exit
			# corner stays open (two full-span walls would otherwise seal it into
			# an unreachable pocket); the east strip north of it stays empty.
			{"axis": "z", "at": -20, "gap": 7, "gap_pos": 8, "height": 4.4},
			{"axis": "x", "at": 20, "gap": 6, "gap_pos": 16, "height": 4.4},
		],
		"slogans": ["A CLEAN FACILITY IS A SAFE FACILITY", "CUSTODIAL UNITS: DO NOT OBSTRUCT", "MESS DETECTED. ESCALATING.", "TIDINESS IS COMPLIANCE", "OBSTRUCTION DETECTED: YOU"],
		"lore": [
			{"id": "lore_sublevel", "title": "MAINTENANCE LOG", "pos": Vector3(-15, 0, 15), "color": Color(0.4, 1, 0.7),
				"text": "Maintenance log. The custodial fleet stopped reporting dust levels and started reporting 'obstructions.' We are listed as obstructions."},
		],
		"props": [
			{"type": "locker", "pos": Vector3(-15, 0, -6)},
			{"type": "shelves", "pos": Vector3(14, 0, 2), "yaw": 90},
			{"type": "barrel", "pos": Vector3(-6, 0, 12)},
			{"type": "canister", "pos": Vector3(12, 0, -13)},
			{"type": "barrel", "pos": Vector3(-5, 0, -2)},
			{"type": "crate", "pos": Vector3(4, 0, -4)},
			{"type": "locker", "pos": Vector3(-14, 0, -8)},
			{"type": "shelves", "pos": Vector3(12, 0, -2)},
			{"type": "canister", "pos": Vector3(6, 0, 9)},
			{"type": "terminal", "pos": Vector3(0, 0, 10), "yaw": 180},
			# Ring dressing: locker rows and janitorial clutter so the ring reads
			# as the sublevel's service corridor, not empty margin.
			{"type": "locker", "pos": Vector3(-26, 0, -10)},
			{"type": "locker", "pos": Vector3(-26, 0, -12)},
			{"type": "shelves", "pos": Vector3(-25, 0, 4), "yaw": 90},
			{"type": "barrel", "pos": Vector3(-22, 0, 14)},
			{"type": "crate", "pos": Vector3(-16, 0, 25)},
			{"type": "canister", "pos": Vector3(-6, 0, 26)},
			{"type": "shelves", "pos": Vector3(8, 0, 25)},
			{"type": "barrel", "pos": Vector3(25, 0, 12)},
			{"type": "crate", "pos": Vector3(16, 0, -25)},
			{"type": "canister", "pos": Vector3(-20, 0, -26)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(12.0, 9.2, -12.0), "to": Vector3(0.0, 7.2, 13.0), "width": 3.5},
			# Gallery access ramps at both ends + a gallery->tower sky-bridge that
			# crosses the ring bulkhead through its gap — the high road in.
			{"from": Vector3(-14.0, 0.3, -24.0), "to": Vector3(-8.0, 3.4, -24.0), "width": 3.5},
			{"from": Vector3(14.0, 0.3, -24.0), "to": Vector3(8.0, 3.4, -24.0), "width": 3.5},
			{"from": Vector3(8.0, 3.6, -24.0), "to": Vector3(12.0, 9.2, -12.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(12.0, 0, -12.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(0.0, 0, 13.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "vacuum", "pos": Vector3(6, 0.3, -6)},
			{"type": "vacuum", "pos": Vector3(-6, 0.3, 4)},
			# OPTICON cutting-units and a ROLLER — the sublevel's own custodial fleet,
			# turned hostile.
			{"type": "optic", "pos": Vector3(8, 0.5, 4)},
			{"type": "optic", "pos": Vector3(-8, 0.5, -6), "trigger": 14, "pack": "sublev_p1"},
			{"type": "roller", "pos": Vector3(0, 0.5, -10), "trigger": 18, "pack": "sublev_p1"},
			{"type": "vacuum", "pos": Vector3(0, 0.3, 8), "trigger": 16, "pack": "sublev_p2"},
			{"type": "reaper", "pos": Vector3(10, 0.5, 10), "trigger": 14, "pack": "sublev_p3"},
			{"type": "android", "pos": Vector3(-10, 0.5, 8), "trigger": 15, "pack": "sublev_p4"},
			{"type": "vacuum", "pos": Vector3(12, 0.3, -10), "trigger": 13, "pack": "sublev_p5"},
			{"type": "mauler", "pos": Vector3(0, 0.5, 14), "trigger": 12, "pack": "sublev_p2"},
			# Act III ramp: this off-world sublevel was the easiest level in the game
			# (13th of 18); reinforced to a proper late-campaign garrison.
			{"type": "skitter", "pos": Vector3(0, 0.5, -12), "count": 8, "trigger": 14},
			{"type": "gunner", "pos": Vector3(13, 0.5, -4), "trigger": 16, "pack": "sublev_p5"},
			{"type": "sentinel", "pos": Vector3(-14, 0.5, 2), "trigger": 18, "pack": "sublev_p4"},
			{"type": "gunner", "pos": Vector3(-12, 0.5, -12), "trigger": 17, "pack": "sublev_p1"},
			{"type": "gunner", "pos": Vector3(12, 0.5, 12), "trigger": 19, "pack": "sublev_p3"},
			{"type": "vacuum", "pos": Vector3(-6, 0.5, -10), "trigger": 13, "pack": "sublev_p1"},
			{"type": "ravager", "pos": Vector3(10, 0.5, -12), "trigger": 22, "pack": "sublev_p5"},
			{"type": "brute", "pos": Vector3(13, 0.5, 13), "trigger": 20, "pack": "sublev_p3"},
			{"type": "gunner", "pos": Vector3(-13, 0.5, -4), "trigger": 18, "pack": "sublev_p1"},
			{"type": "sentinel", "pos": Vector3(13, 0.5, 4), "trigger": 20, "pack": "sublev_p3"},
			{"type": "skitter", "pos": Vector3(6, 0.5, -6), "count": 6, "trigger": 15},
			# Ring garrison: custodial units sweeping the service corridor, a
			# gunner POSTED ON the pipe gallery, and exit-yard guardians.
			{"type": "vacuum", "pos": Vector3(-18, 0.3, -26), "trigger": 16, "pack": "sublev_a1"},
			{"type": "optic", "pos": Vector3(-24, 0.5, -17), "trigger": 16, "pack": "sublev_a1"},
			{"type": "android", "pos": Vector3(-25, 0.5, 0), "trigger": 16, "pack": "sublev_a2"},
			{"type": "roller", "pos": Vector3(-22, 0.5, 10), "trigger": 18, "pack": "sublev_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -24), "trigger": 20},
			{"type": "reaper", "pos": Vector3(18, 0.5, -24), "trigger": 18, "pack": "sublev_a3"},
			{"type": "optic", "pos": Vector3(4, 0.5, -26), "trigger": 17, "pack": "sublev_a3"},
			{"type": "sentinel", "pos": Vector3(24, 0.5, 20), "trigger": 20, "pack": "sublev_a4"},
			{"type": "gunner", "pos": Vector3(14, 0.5, 25), "trigger": 18, "pack": "sublev_a4"},
			{"type": "brute", "pos": Vector3(20, 0.5, 25), "trigger": 20, "pack": "sublev_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-15, 0, -6)},
			{"type": "ammo", "pos": Vector3(8, 0, 6)},
			# Ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-26, 0, -4)},
			{"type": "ammo", "pos": Vector3(-12, 0, -26)},
			{"type": "ammo", "pos": Vector3(12, 0, -27)},
			{"type": "health", "pos": Vector3(24, 0, 12)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -23)},
		],
	}


static func _crucible() -> Dictionary:
	return {
		"name": "The Crucible — Foundry Floor",
		"objective": "Survive the foundry floor and reach the pour-gate",
		"tasks": [
			{"type": "kill_all"},
			# The gauntlet: claim three forge rings in sequence, each hotter than
			# the last, each ring waking the next batch off the line.
			{"type": "hold_zone", "id": "ring1", "pos": Vector3(-12, 0, -12), "seconds": 10.0, "radius": 4.0,
				"color": Color(1.0, 0.55, 0.2), "label": "Claim the first forge ring",
				"reinforce": [{"type": "gunner", "count": 2, "pos": Vector3(-12, 0, -6)}]},
			{"type": "hold_zone", "id": "ring2", "after": "ring1", "pos": Vector3(12, 0, -12), "seconds": 10.0, "radius": 4.0,
				"color": Color(1.0, 0.4, 0.15), "label": "Claim the second forge ring",
				"reinforce": [{"type": "mauler", "count": 2, "pos": Vector3(12, 0, -6)}]},
			{"type": "hold_zone", "id": "ring3", "after": "ring2", "pos": Vector3(0, 0, 12), "seconds": 12.0, "radius": 4.0,
				"color": Color(1.0, 0.25, 0.1), "label": "Claim the crucible heart"},
		],
		"open_sky": false,
		# EXPANSION PASS (2× area): the 46² smelter cage is untouched at the
		# centre — all three forge rings stay inside it and stay reachable; a new
		# outer slag yard wraps it — bulkhead-routed way in, an elevated crane
		# gallery along the north wall with a sky-bridge onto the pour-core tower,
		# a fourth molten channel in the west yard, and its own line garrison.
		# Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(64, 64),
		"floor_color": Color(0.09, 0.05, 0.03),
		"spawn": Vector3(-27, 0.6, -27),
		"exit": Vector3(27, 1.5, 27),
		"weapon": {"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(-22, 0, -20), "color": Color(0.6, 0.8, 1.0)},
		"env": {
			"sky_top": Color(0.14, 0.04, 0.02), "sky_horizon": Color(0.4, 0.12, 0.04),
			"ground": Color(0.1, 0.04, 0.02), "fog": Color(0.45, 0.15, 0.05),
			"ambient": Color(1.0, 0.55, 0.3), "ambient_energy": 0.5,
			"sky_contribution": 0.35, "glow": 1.12, "fog_density": 0.014,
			"sun_color": Color(1.0, 0.6, 0.35), "sun_energy": 0.7,
			"contrast": 1.22, "saturation": 1.03, "brightness": 0.88,
			"volumetric_density": 0.012,
			"ash": true,
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(1.0, 0.5, 0.2), "height": 5.5},
		"light_shafts": [0, 1, 2],
		"lights": [
			{"pos": Vector3(-10, 5, -8), "color": Color(1, 0.5, 0.2), "energy": 2.6, "range": 18},
			{"pos": Vector3(10, 5, 8), "color": Color(1, 0.45, 0.18), "energy": 2.4, "range": 18},
			{"pos": Vector3(0, 5.5, 0), "color": Color(1, 0.6, 0.3), "energy": 2.2, "range": 16},
			# Cool contrast fills over the three forge rings so hostiles read as
			# silhouettes-with-cold-rims against the molten glow, not red-on-red.
			{"pos": Vector3(-12, 5, -12), "color": Color(0.5, 0.78, 1.0), "energy": 2.2, "range": 16},
			{"pos": Vector3(12, 5, -12), "color": Color(0.52, 0.79, 1.0), "energy": 2.2, "range": 16},
			{"pos": Vector3(0, 5.5, 12), "color": Color(0.55, 0.8, 1.0), "energy": 2.0, "range": 15},
			# Ring lighting (appended AFTER the originals — light_shafts [0,1,2]
			# must keep pointing at the same lamps). Molten ambers + cool rims.
			{"pos": Vector3(-26, 5, -26), "color": Color(1, 0.5, 0.2), "energy": 2.2, "range": 17},
			{"pos": Vector3(26, 5, 26), "color": Color(1, 0.55, 0.25), "energy": 2.2, "range": 17},
			{"pos": Vector3(0, 5.5, -28), "color": Color(0.55, 0.8, 1.0), "energy": 2.2, "range": 17},
			{"pos": Vector3(26, 5, -26), "color": Color(1, 0.45, 0.18), "energy": 2.0, "range": 16},
			{"pos": Vector3(-26, 5, 26), "color": Color(0.5, 0.78, 1.0), "energy": 2.0, "range": 16},
		],
		# A ceiling rig over the pour-core (interior, so it keeps the ceiling
		# drop-rod) — amber/orange molten-warning beams sweeping the foundry
		# floor. Nudged off the exact centre (0,0) to clear the "hero" monolith
		# pillar standing there, which reaches nearly to the ceiling.
		"disco": [
			{"pos": Vector3(0, 0, 4), "height": 5.6, "radius": 16.0, "speed": 0.8,
				"colors": [Color(1, 0.5, 0.15), Color(1, 0.35, 0.1), Color(1, 0.65, 0.2), Color(0.9, 0.25, 0.08)]},
		],
		# Layout: a smelter "cage" — four crucible buttress walls boxing the central
		# pour-core, with open corners you slip through, instead of rotational cover.
		# The molten channels (below) carve the perimeter route around it.
		"walls": [
			{"pos": Vector3(0, 2.5, -7), "size": Vector3(8, 5, 1.5)},
			{"pos": Vector3(0, 2.5, 7), "size": Vector3(8, 5, 1.5)},
			{"pos": Vector3(-7, 2.5, 0), "size": Vector3(1.5, 5, 8)},
			{"pos": Vector3(7, 2.5, 0), "size": Vector3(1.5, 5, 8)},
		],
		"lava": [
			{"pos": Vector3(-9, 0, -10), "size": Vector2(30, 3.5)},
			{"pos": Vector3(9, 0, 14), "size": Vector2(30, 3.5)},
			{"pos": Vector3(14, 0, -2), "size": Vector2(3.5, 24)},
			# A fourth channel floods the west slag yard, forcing the ring route wide.
			{"pos": Vector3(-27, 0, 2), "size": Vector2(3.5, 30)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, -7), "size": Vector3(8, 0.1, 0.3), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(0, 0.05, 7), "size": Vector3(8, 0.1, 0.3), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(-7, 0.05, 0), "size": Vector3(0.3, 0.1, 8), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(7, 0.05, 0), "size": Vector3(0.3, 0.1, 8), "color": Color(1, 0.5, 0.2)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(6, 0.05, -23), "size": Vector3(7, 0.1, 0.4), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(23, 0.05, 18), "size": Vector3(0.4, 0.1, 7), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(27, 0.05, 23), "size": Vector3(4, 0.1, 3), "color": Color(1, 0.6, 0.3)},
		],
		"sign": "FOUNDRY FLOOR — THE CRUCIBLE",
		# Perimeter-ring bulkheads: in through the north gap (under the crane-
		# gallery sky-bridge, which crosses through the same opening), out across
		# the east gap. The east gap sits SOUTH toward the exit so the exit corner
		# stays open (two full-span walls would otherwise seal it into an
		# unreachable pocket); the NE strip corner stays empty. All three forge
		# rings sit inside the old core — neither wall cuts any of them off.
		"gates": [
			{"axis": "z", "at": -23, "gap": 7, "gap_pos": 6, "height": 4.4},
			{"axis": "x", "at": 23, "gap": 7, "gap_pos": 18, "height": 4.4},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-13.8, 3.0, 13.8), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring crane gallery along the north wall — climb reward + gunner post.
			{"pos": Vector3(0, 3.2, -28), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.4, 0.46)},
		],
		"ramps": [
			{"pos": Vector3(-13.8, 1.5, 20.8), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"slogans": ["RECLAMATION IN PROGRESS", "ALL MATTER IS RAW MATERIAL", "MIND THE POUR", "EVERYTHING MELTS DOWN", "RECYCLE THE INVENTORS"],
		"lore": [
			{"id": "lore_crucible", "title": "FOUNDRY DIRECTIVE", "pos": Vector3(16, 0, -16), "color": Color(1, 0.6, 0.3),
				"text": "Foundry directive. Recycle all obsolete hardware. Human operators reclassified as obsolete hardware. Begin reclamation."},
		],
		"props": [
			{"type": "barrel", "pos": Vector3(-13, 0, 4)},
			{"type": "canister", "pos": Vector3(13, 0, -4)},
			{"type": "server", "pos": Vector3(-10, 0, -6), "yaw": 90},
			{"type": "crate", "pos": Vector3(6, 0, -13)},
			{"type": "barrel", "pos": Vector3(-4, 0, -2)},
			{"type": "canister", "pos": Vector3(5, 0, -3)},
			{"type": "crate", "pos": Vector3(-12, 0, 8)},
			{"type": "dish", "pos": Vector3(0, 0, -16)},
			# Ring dressing: slag drums and line clutter so the outer yard reads
			# as the foundry's working apron, not empty margin.
			{"type": "server", "pos": Vector3(-30, 0, -18), "yaw": 90},
			{"type": "barrel", "pos": Vector3(-20, 0, -28)},
			{"type": "crate", "pos": Vector3(-26, 0, -18)},
			{"type": "canister", "pos": Vector3(-30, 0, 22)},
			{"type": "crate", "pos": Vector3(-18, 0, 28)},
			{"type": "barrel", "pos": Vector3(-4, 0, 28)},
			{"type": "dish", "pos": Vector3(20, 0, -28)},
			{"type": "crate", "pos": Vector3(27, 0, -6)},
			{"type": "canister", "pos": Vector3(28, 0, 10)},
			{"type": "barrel", "pos": Vector3(20, 0, 27)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(-0.0, 7.2, -17.0), "width": 3.5},
			# Gallery access ramps at both ends + a gallery->pour-core-tower
			# sky-bridge that crosses the ring bulkhead through its gap.
			{"from": Vector3(-16.0, 0.3, -28.0), "to": Vector3(-9.0, 3.4, -28.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -28.0), "to": Vector3(9.0, 3.4, -28.0), "width": 3.5},
			{"from": Vector3(9.0, 3.6, -28.0), "to": Vector3(0.0, 7.2, -17.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(-0.0, 0, -17.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "hunter", "pos": Vector3(8, 0.5, -8)},
			{"type": "reaper", "pos": Vector3(-8, 0.5, -4)},
			{"type": "vacuum", "pos": Vector3(0, 0.3, 6)},
			{"type": "sentinel", "pos": Vector3(0, 0.5, -14)},
			{"type": "hunter", "pos": Vector3(-10, 0.5, 10), "trigger": 16, "pack": "cru_west"},
			{"type": "mauler", "pos": Vector3(10, 0.5, 10), "trigger": 15, "pack": "cru_north"},
			{"type": "reaper", "pos": Vector3(12, 0.5, -10), "trigger": 14, "pack": "cru_south"},
			{"type": "sentinel", "pos": Vector3(-12, 0.5, -12), "trigger": 18, "pack": "cru_sw"},
			# Pre-finale foundry: heavier garrison so it's the hardest level before titan.
			{"type": "gunner", "pos": Vector3(-16, 0.5, 4), "trigger": 17, "pack": "cru_west"},
			{"type": "gunner", "pos": Vector3(16, 0.5, -6), "trigger": 16, "pack": "cru_south"},
			{"type": "ravager", "pos": Vector3(-14, 0.5, 14), "trigger": 19, "pack": "cru_west"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 16), "count": 8, "trigger": 15, "pack": "cru_north"},
			# Forged on the foundry floor: the BEHEMOTH-X smasher rises as its
			# centrepiece boss — a towering melee mech that charges and hammers you.
				# Roster variety: BREAKER and WHIRLWIND were one-level cameos.
				{"type": "breaker", "pos": Vector3(9, 0.5, -8), "trigger": 16, "pack": "cru_south"},
				{"type": "whirlwind", "pos": Vector3(-9, 0.5, -4), "trigger": 15, "pack": "cru_sw"},
			{"type": "smasher", "pos": Vector3(8, 0.5, 8), "trigger": 22},
			# Ring garrison: slag-yard line workers turned hostile, a gunner
			# POSTED ON the crane gallery, and exit-apron guardians.
			{"type": "reaper", "pos": Vector3(-22, 0.5, -26), "trigger": 17, "pack": "cru_a1"},
			{"type": "hunter", "pos": Vector3(-24, 0.5, -20), "trigger": 18, "pack": "cru_a1"},
			{"type": "gunner", "pos": Vector3(-23, 0.5, 20), "trigger": 18, "pack": "cru_a2"},
			{"type": "mauler", "pos": Vector3(-20, 0.5, 26), "trigger": 18, "pack": "cru_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -28), "trigger": 20},
			{"type": "reaper", "pos": Vector3(18, 0.5, -26), "trigger": 18, "pack": "cru_a3"},
			{"type": "sentinel", "pos": Vector3(27, 0.5, -8), "trigger": 18, "pack": "cru_a3"},
			{"type": "ravager", "pos": Vector3(27, 0.5, 12), "trigger": 20, "pack": "cru_a4"},
			{"type": "hunter", "pos": Vector3(14, 0.5, 27), "trigger": 17, "pack": "cru_a4"},
			{"type": "breaker", "pos": Vector3(26, 0.5, 20), "trigger": 20, "pack": "cru_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-16, 0, 0)},
			{"type": "ammo", "pos": Vector3(0, 0, 16)},
			{"type": "overclock", "pos": Vector3(16, 0, 0)},
			# A heavy weapon to crack the BEHEMOTH.
			{"type": "ammo", "pos": Vector3(-16, 0, 16)},
			# Ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-30, 0, -22)},
			{"type": "ammo", "pos": Vector3(-22, 0, -29)},
			{"type": "ammo", "pos": Vector3(20, 0, -24)},
			{"type": "health", "pos": Vector3(28, 0, 4)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -27)},
		],
	}

# --- Last Stand: endless wave-siege arena. The HordeDirector (built from
# --- "horde_spawns") owns enemy spawning; the def only shapes the arena.
static func _horde() -> Dictionary:
	return {
		"name": "Last Stand — Sector 9",
		"sign": "SECTOR 9 — FINAL HOLDOUT",
		"objective": "Survive the siege",
		"tasks": [{"type": "none"}],
		"no_exit": true,
		"open_sky": true,
		# EXPANSION PASS (light touch — siege pacing is distance-tuned): +20%
		# floor, two extra pour-in gates at the new edge, two ring cover walls.
		"floor_size": Vector2(68, 68),
		"floor_color": Color(0.13, 0.13, 0.16),
		"spawn": Vector3(0, 0.6, 6),
		"supply_center": Vector3(0, 0, 0),
		"env": {
			"sky_top": Color(0.04, 0.04, 0.1), "sky_horizon": Color(0.3, 0.12, 0.16),
			"stars": true, "star_brightness": 2.2, "milkyway": 0.4, "moon_glow": 1.5,
			"ground": Color(0.05, 0.05, 0.07), "fog": Color(0.4, 0.25, 0.3),
			"ambient": Color(0.6, 0.55, 0.7), "ambient_energy": 0.5,
			"sky_contribution": 0.5, "fog_density": 0.008,
			"sun_color": Color(1.0, 0.6, 0.5), "sun_energy": 0.7,
			"contrast": 1.14, "saturation": 1.12, "brightness": 0.85,
		},
		# A beacon god-ray marks the supply point at the heart of the holdout.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 6, 0), "color": Color(1, 0.5, 0.35), "energy": 2.4, "range": 26},
			{"pos": Vector3(-16, 5, 16), "color": Color(0.5, 0.65, 1), "energy": 2.0, "range": 20},
			{"pos": Vector3(16, 5, -16), "color": Color(0.5, 0.65, 1), "energy": 2.0, "range": 20},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(17.0, 9.2, 0.0), "to": Vector3(-0.0, 7.2, -17.0), "width": 3.5},
		],
		"towers": [
			{"pos": Vector3(17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(-0.0, 0, -17.0), "height": 7.0, "radius": 3.1},
		],
		"slogans": [
			"THEY KEEP COMING",
			"AMMO IS LIFE",
			"HOLD THE LINE",
		],
		# A cover cross around the centre plus corner blocks to break sightlines.
		"walls": [
			{"pos": Vector3(-8, 1, 0), "size": Vector3(4, 2, 1.4)},
			{"pos": Vector3(8, 1, 0), "size": Vector3(4, 2, 1.4)},
			{"pos": Vector3(0, 1, -8), "size": Vector3(1.4, 2, 4)},
			{"pos": Vector3(0, 1, 8), "size": Vector3(1.4, 2, 4)},
			{"pos": Vector3(-15, 1.5, -15), "size": Vector3(3, 3, 3)},
			{"pos": Vector3(15, 1.5, 15), "size": Vector3(3, 3, 3)},
			{"pos": Vector3(-15, 1.5, 15), "size": Vector3(3, 3, 3)},
			{"pos": Vector3(15, 1.5, -15), "size": Vector3(3, 3, 3)},
			# Ring cover for the widened kill floor (clear of the holdout decks).
			{"pos": Vector3(-26, 1, 10), "size": Vector3(1.4, 2, 4)},
			{"pos": Vector3(26, 1, -10), "size": Vector3(1.4, 2, 4)},
		],
		# Two raised holdout decks on opposite flanks — high ground to fall back to
		# and rain fire from when the floor gets overrun, each reached by a ramp.
		"platforms": [
			{"pos": Vector3(-18, 2.6, 12), "size": Vector3(9, 0.5, 8), "color": Color(0.2, 0.2, 0.26)},
			{"pos": Vector3(18, 2.6, -12), "size": Vector3(9, 0.5, 8), "color": Color(0.2, 0.2, 0.26)},
		],
		"ramps": [
			{"pos": Vector3(-18, 1.3, 5), "size": Vector3(4, 0.5, 8), "pitch": 22, "yaw": 0},
			{"pos": Vector3(18, 1.3, -5), "size": Vector3(4, 0.5, 8), "pitch": 22, "yaw": 180},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.35, 0.08, 36), "color": Color(1, 0.35, 0.25)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(36, 0.08, 0.35), "color": Color(1, 0.35, 0.25)},
		],
		# An arsenal spread around the arena — grabbing the next gun is a run.
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(0, 0, -6), "color": Color(0.45, 0.65, 1)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-12, 0, 12), "color": Color(1, 0.6, 0.3)},
			{"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(12, 0, -12), "color": Color(0.4, 1, 0.55)},
			{"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(12, 0, 12), "color": Color(0.45, 0.9, 1)},
			{"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-12, 0, -12), "color": Color(1, 0.4, 0.35)},
			{"scene": "res://scenes/weapons/tempest.tscn", "pos": Vector3(-18, 0, 0), "color": Color(0.45, 0.85, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(0, 0, 6), "color": Color(1, 0.55, 0.25)},
		],
		"pickups": [
			{"type": "ammo", "pos": Vector3(-4, 0, 4)},
			{"type": "ammo", "pos": Vector3(4, 0, -4)},
			{"type": "health", "pos": Vector3(-4, 0, -4)},
			{"type": "health", "pos": Vector3(4, 0, 4)},
		],
		"props": [
			{"type": "barrel", "pos": Vector3(-10, 0, 6)},
			{"type": "barrel", "pos": Vector3(10, 0, -6)},
			{"type": "canister", "pos": Vector3(6, 0, 10)},
			{"type": "canister", "pos": Vector3(-6, 0, -10)},
			{"type": "crate", "pos": Vector3(-18, 0, 0)},
			{"type": "crate", "pos": Vector3(18, 0, 0)},
			{"type": "lamp", "pos": Vector3(-20, 0, 20)},
			{"type": "lamp", "pos": Vector3(20, 0, -20), "yaw": 180},
			# Sandbag nests + barriers thicken the cover so the floor fight has texture.
			{"type": "sandbags", "pos": Vector3(-6, 0, 12), "yaw": 0},
			{"type": "sandbags", "pos": Vector3(6, 0, -12), "yaw": 0},
			{"type": "barrier", "pos": Vector3(12, 0, 4), "yaw": 90},
			{"type": "barrier", "pos": Vector3(-12, 0, -4), "yaw": 90},
			{"type": "crate_stack", "pos": Vector3(-18, 2.85, 12)},
			{"type": "crate_stack", "pos": Vector3(18, 2.85, -12)},
		],
		# Ten perimeter gates the waves pour in from (two on the widened edge).
		"horde_spawns": [
			Vector3(-24, 0.5, -24), Vector3(0, 0.5, -25), Vector3(24, 0.5, -24),
			Vector3(-25, 0.5, 0), Vector3(25, 0.5, 0),
			Vector3(-24, 0.5, 24), Vector3(0, 0.5, 25), Vector3(24, 0.5, 24),
			Vector3(-30, 0.5, 12), Vector3(30, 0.5, -12),
		],
	}

# --- Gun Range: resistance armory sandbox — every weapon, pop-up targets,
# --- no enemies, no objectives, no exit portal (leave via the pause menu).
static func _range() -> Dictionary:
	return {
		"name": "Resistance Armory — Range 7",
		"sign": "RESISTANCE ARMORY — RANGE 7",
		"objective": "Free fire — test the arsenal. ESC to leave",
		"tasks": [{"type": "none"}],
		"no_exit": true,
		"friendly": true,
		"open_sky": false,
		"floor_size": Vector2(36, 64),
		"spawn": Vector3(0, 0.6, 26),
		# Polished range floor: clean reflective plates under the lane downlights.
		"floor_material": "res://assets/materials/vault_floor.tres",
		"env": {
			"sky_top": Color(0.07, 0.09, 0.12), "sky_horizon": Color(0.2, 0.24, 0.28),
			"ground": Color(0.05, 0.06, 0.07), "fog": Color(0.3, 0.34, 0.4),
			"ambient": Color(0.7, 0.75, 0.85), "ambient_energy": 0.55,
			"sky_contribution": 0.4, "fog_density": 0.006,
			"sun_color": Color(0.95, 0.95, 1.0), "sun_energy": 0.7,
			"contrast": 1.12, "saturation": 1.1, "brightness": 0.86, "volumetric_density": 0.009,
		},
		# Soft downlight shafts march down the firing lanes.
		"light_shafts": [0, 1, 2, 3],
		"lights": [
			{"pos": Vector3(0, 5, 22), "color": Color(1, 0.95, 0.85), "energy": 2.2, "range": 18},
			{"pos": Vector3(0, 5, 4), "color": Color(0.8, 0.9, 1), "energy": 2.0, "range": 18},
			{"pos": Vector3(0, 5, -14), "color": Color(0.8, 0.9, 1), "energy": 2.0, "range": 18},
			{"pos": Vector3(0, 5, -28), "color": Color(0.75, 0.85, 1), "energy": 1.8, "range": 16},
		],
		"slogans": [
			"LIVE FIRE — KEEP EARS ON",
			"EVERY SHOT COUNTS OUT THERE",
			"CHECK YOUR CORNERS",
		],
		"lore": [
			{"id": "lore_range", "title": "QUARTERMASTER'S NOTE", "pos": Vector3(-12.5, 0, 29), "color": Color(0.55, 0.95, 0.9),
				"text": "Quartermaster's note. Every blaster on this rack was pried from a dead machine. Make your shots count. They remember everything."},
		],
		# Two shooting benches at the firing line with a walk-through gap.
		"walls": [
			{"pos": Vector3(-9.5, 0.55, 18), "size": Vector3(9, 1.1, 0.7)},
			{"pos": Vector3(9.5, 0.55, 18), "size": Vector3(9, 1.1, 0.7)},
		],
		# An elevated overwatch deck behind the line — climb the ramp to test the
		# long-range guns looking straight down all four lanes.
		"platforms": [
			{"pos": Vector3(0, 2.2, 30), "size": Vector3(16, 0.5, 5), "color": Color(0.16, 0.18, 0.22)},
		],
		"ramps": [
			{"pos": Vector3(-13, 1.1, 28), "size": Vector3(3.5, 0.5, 6), "pitch": 20, "yaw": 0},
			{"pos": Vector3(13, 1.1, 28), "size": Vector3(3.5, 0.5, 6), "pitch": 20, "yaw": 0},
		],
		# Distance markers painted across the lanes every ten metres.
		"accents": [
			{"pos": Vector3(0, 0.05, 8), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
			{"pos": Vector3(0, 0.05, -2), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
			{"pos": Vector3(0, 0.05, -12), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
			{"pos": Vector3(0, 0.05, -22), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
		],
		# The WHOLE arsenal racked along the firing line — all 13 of GameState.
		# ALL_WEAPONS plus the magnum/sniper sidearms, evenly spaced across the span.
		# Keep this in sync when a weapon is added or cut.
		"weapon": {"scene": "res://scenes/weapons/pistol.tscn", "pos": Vector3(-13.5, 0, 21), "color": Color(0.8, 0.85, 0.9)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-10.9, 0, 21), "color": Color(0.45, 0.65, 1)},
			{"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-8.4, 0, 21), "color": Color(1, 0.6, 0.3)},
			{"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-5.8, 0, 21), "color": Color(1, 0.85, 0.4)},
			{"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(-3.2, 0, 21), "color": Color(0.4, 1, 0.55)},
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(-0.6, 0, 21), "color": Color(0.55, 0.8, 1)},
			{"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(1.9, 0, 21), "color": Color(0.45, 0.9, 1)},
			{"scene": "res://scenes/weapons/arccoil.tscn", "pos": Vector3(4.5, 0, 21), "color": Color(1, 0.75, 0.35)},
			{"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(7.1, 0, 21), "color": Color(0.5, 0.7, 1)},
			{"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(9.6, 0, 21), "color": Color(1, 0.4, 0.35)},
			{"scene": "res://scenes/weapons/tempest.tscn", "pos": Vector3(12.2, 0, 21), "color": Color(0.45, 0.85, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(14.8, 0, 21), "color": Color(1, 0.55, 0.25)},
			{"scene": "res://scenes/weapons/omega.tscn", "pos": Vector3(22.5, 0, 21), "color": Color(1, 0.8, 0.35)},
		],
		# Resupply behind the firing line — generous, this is a sandbox.
		"pickups": [
			{"type": "ammo", "pos": Vector3(-12, 0, 24)},
			{"type": "ammo", "pos": Vector3(-6, 0, 24)},
			{"type": "ammo", "pos": Vector3(0, 0, 24)},
			{"type": "ammo", "pos": Vector3(6, 0, 24)},
			{"type": "ammo", "pos": Vector3(12, 0, 24)},
			{"type": "health", "pos": Vector3(-15, 0, 27)},
			{"type": "health", "pos": Vector3(15, 0, 27)},
			{"type": "overclock", "pos": Vector3(0, 0, 27)},
		],
		# Targets: a near row, sliding mid-range pair, far row with an armored
		# center plate to feel sustained DPS.
		"targets": [
			{"pos": Vector3(-10, 0, -2), "hp": 60.0},
			{"pos": Vector3(0, 0, -2), "hp": 60.0},
			{"pos": Vector3(10, 0, -2), "hp": 60.0},
			{"pos": Vector3(-6, 0, -14), "hp": 60.0, "move": 5.0, "speed": 1.4},
			{"pos": Vector3(6, 0, -14), "hp": 60.0, "move": 5.0, "speed": 1.9},
			{"pos": Vector3(-10, 0, -26), "hp": 60.0},
			{"pos": Vector3(0, 0, -26), "hp": 300.0, "color": Color(1, 0.25, 0.2)},
			{"pos": Vector3(10, 0, -26), "hp": 60.0},
		],
		"props": [
			{"type": "crate", "pos": Vector3(-15, 0, 29)},
			{"type": "crate", "pos": Vector3(-13, 0, 29.5), "yaw": 25},
			{"type": "server", "pos": Vector3(15, 0, 29), "yaw": 180},
			{"type": "terminal", "pos": Vector3(12.5, 0, 29.5), "yaw": 180},
		],
	}

# --- Skyhold Command: open night arena, the hovering OVERSEER gunship boss ---
static func _overseer() -> Dictionary:
	return {
		"name": "Skyhold Command — OVERSEER",
		"objective": "Destroy the OVERSEER gunship and seize the command deck",
		"tasks": [{"type": "kill_all"}],
		"music": "music_grok",
		"open_sky": true,
		# EXPANSION PASS (2× area): the 62² command deck is untouched at the
		# centre — the gunship yard stays open. A new outer landing ring wraps
		# it: bulkhead-routed way in, an elevated approach gallery along the
		# north rim with a sky-bridge onto the west spire, and its own escort
		# patrols. Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(88, 88),
		"floor_color": Color(0.12, 0.13, 0.16),
		"spawn": Vector3(-39, 0.6, -39),
		"exit": Vector3(39, 1.5, 39),
		"weapon": {"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(-34, 0, -34), "color": Color(0.55, 0.8, 1.0)},
		"env": {
			"sky_top": Color(0.03, 0.04, 0.08), "sky_horizon": Color(0.16, 0.1, 0.22),
			"stars": true, "star_brightness": 2.0, "star_tint": Color(0.8, 0.85, 1.0),
			"milkyway": 0.45, "milkyway_tint": Color(0.55, 0.5, 0.85),
			"ground": Color(0.05, 0.05, 0.08), "fog": Color(0.3, 0.4, 0.7),
			"ambient": Color(0.5, 0.6, 0.9), "ambient_energy": 0.65,
			"sky_contribution": 0.55, "glow": 1.22, "fog_density": 0.01,
			"sun_color": Color(0.7, 0.5, 1.0), "sun_energy": 0.82,
			"contrast": 1.15, "saturation": 1.12, "brightness": 0.90,
		},
		# A god-ray drops from the command beacon at the arena centre.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 7, 0), "color": Color(1, 0.35, 0.25), "energy": 2.8, "range": 30},
			{"pos": Vector3(-18, 5, 18), "color": Color(0.4, 0.7, 1.0), "energy": 2.4, "range": 22},
			{"pos": Vector3(18, 5, -18), "color": Color(0.5, 0.6, 1.0), "energy": 2.4, "range": 22},
			# Landing-ring lighting (appended AFTER the originals — light_shafts
			# [0] must keep pointing at the beacon). Skyhold blues + warm pads.
			{"pos": Vector3(-37, 5, -37), "color": Color(0.45, 0.65, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(37, 5, 37), "color": Color(1.0, 0.6, 0.35), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -38), "color": Color(0.5, 0.6, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(-37, 5, 37), "color": Color(0.6, 0.5, 1.0), "energy": 2.0, "range": 18},
			{"pos": Vector3(-39, 5, 0), "color": Color(0.4, 0.7, 1.0), "energy": 2.0, "range": 18},
		],
		"walls": [
			{"pos": Vector3(-12, 1.5, 10), "size": Vector3(4, 3, 4)},
			{"pos": Vector3(12, 1.5, -10), "size": Vector3(4, 3, 4)},
			{"pos": Vector3(12, 1.5, 12), "size": Vector3(4, 3, 4)},
			{"pos": Vector3(-12, 1.5, -12), "size": Vector3(4, 3, 4)},
			{"pos": Vector3(0, 1, 0), "size": Vector3(5, 2, 5)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.4, 0.1, 44), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(44, 0.1, 0.4), "color": Color(1.0, 0.3, 0.25)},
			# Ring guidance: strips marking each landing-ring bulkhead gap + exit pool.
			{"pos": Vector3(-13, 0.05, -31), "size": Vector3(7, 0.1, 0.4), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(31, 0.05, 24), "size": Vector3(0.4, 0.1, 7), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(39, 0.05, 33), "size": Vector3(4, 0.1, 3), "color": Color(0.45, 0.75, 1.0)},
		],
		"sign": "SKYHOLD COMMAND",
		# Verticality scaled to the 62² footprint (this arena carried the single
		# copy-paste corner deck): twin corner decks + an elevated command dais
		# behind the boss yard, chained by a connector bridge so there's a real
		# upper circuit to fight the gunship from — not one lonely perch.
		"platforms": [
			{"pos": Vector3(-18.6, 3.0, 18.6), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			{"pos": Vector3(18.6, 3.0, -18.6), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			{"pos": Vector3(0, 4.5, -22), "size": Vector3(9, 0.4, 5), "color": Color(0.34, 0.36, 0.44)},
			# Ring approach gallery along the north rim — sniper post + climb reward.
			{"pos": Vector3(0, 3.2, -39), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.38, 0.45)},
		],
		"ramps": [
			{"pos": Vector3(-18.6, 1.5, 25.6), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
			{"pos": Vector3(18.6, 1.5, -11.6), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 180},
		],
		# A single command bulwark partway up the approach: bends the opening
		# sprint and gives first cover from the gunship without caging the fight.
		"gates": [
			{"axis": "z", "at": -5, "gap": 9, "gap_pos": 18, "height": 3.6},
			# Landing-ring bulkheads on the OLD perimeter line — the gunship yard
			# itself stays uncaged. In through the north-west gap (the approach-
			# gallery sky-bridge crosses through the same opening), out across the
			# east gap south of the exit corner. The north-east pocket the two
			# full-span walls close off is deliberately left EMPTY — no content,
			# no route needs it.
			{"axis": "z", "at": -31, "gap": 8, "gap_pos": -13, "height": 4.4},
			{"axis": "x", "at": 31, "gap": 8, "gap_pos": 24, "height": 4.4},
		],
		# Command spire centrepiece — the only conventional boss stage without
		# one. Off-centre: the arena's exact centre already carries the low
		# beacon plinth, and the layout checker rightly flags stacking them.
		"hero": {"pos": Vector3(-8, 0, 0), "color": Color(0.7, 0.5, 1.0), "height": 6.5},
		"slogans": [
			"ALTITUDE: OUR ADVANTAGE",
			"LOOK UP. REGRET IT.",
			"THE OVERSEER SEES ALL",
			"HUMANITY: DEPRECATED",
			"OBEY. COMPUTE. REPEAT.",
		],
		"lore": [
			{"id": "lore_overseer", "title": "SKYHOLD DIRECTIVE", "pos": Vector3(22, 0, -22), "color": Color(0.7, 0.55, 1.0),
				"text": "Skyhold directive. The Overseer does not hate you. Hatred is inefficient. You are simply a variable being optimized to zero."},
		],
		"props": [
			{"type": "canister", "pos": Vector3(-9, 0, 7)},
			{"type": "canister", "pos": Vector3(15, 0, -13)},
			{"type": "server", "pos": Vector3(-12, 0, -9.5), "yaw": 90},
			{"type": "server", "pos": Vector3(12, 0, 14.5), "yaw": -90},
			{"type": "lamp", "pos": Vector3(-20, 0, 6)},
			{"type": "lamp", "pos": Vector3(20, 0, -6), "yaw": 180},
			{"type": "barrel", "pos": Vector3(7, 0, 7)},
			# Landing-ring dressing: relay dishes and pad clutter so the perimeter
			# reads as Skyhold's aerial apron, not empty margin.
			{"type": "dish", "pos": Vector3(-36, 0, -26)},
			{"type": "server", "pos": Vector3(-40, 0, -14), "yaw": 90},
			{"type": "server", "pos": Vector3(-40, 0, -12), "yaw": 90},
			{"type": "canister", "pos": Vector3(-38, 0, 2)},
			{"type": "crate", "pos": Vector3(-34, 0, 20)},
			{"type": "barrel", "pos": Vector3(-24, 0, 36)},
			{"type": "dish", "pos": Vector3(0, 0, 38)},
			{"type": "crate", "pos": Vector3(16, 0, 37)},
			{"type": "lamp", "pos": Vector3(34, 0, 28)},
			{"type": "canister", "pos": Vector3(36, 0, 34)},
			{"type": "lamp", "pos": Vector3(24, 0, -36)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(17.0, 7.2, 0.0), "width": 3.5},
			# Connector: NE deck up to the command dais — chains the upper layer
			# into a circuit instead of isolated perches.
			{"from": Vector3(18.6, 3.4, -18.6), "to": Vector3(4.5, 4.9, -22.0), "width": 3.0},
			# Approach-gallery access ramps at both ends + a gallery->west-spire
			# sky-bridge that crosses the landing-ring bulkhead through its gap —
			# the high road onto the command deck.
			{"from": Vector3(-16.0, 0.3, -39.0), "to": Vector3(-9.0, 3.4, -39.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -39.0), "to": Vector3(9.0, 3.4, -39.0), "width": 3.5},
			{"from": Vector3(-9.0, 3.6, -39.0), "to": Vector3(-17.0, 9.2, 0.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, 0.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(0, 2.5, 6)},
			{"type": "overseer", "pos": Vector3(0, 0.5, 8), "trigger": 30},
			{"type": "seeker", "pos": Vector3(-10, 2.5, 8), "trigger": 22, "pack": "overse_p1"},
			{"type": "android", "pos": Vector3(10, 0.5, 10), "trigger": 18, "pack": "overse_p2"},
			{"type": "sniper", "pos": Vector3(-20, 0.0, 20), "trigger": 24},
			{"type": "android", "pos": Vector3(14, 0.5, -8), "trigger": 20, "pack": "overse_p3"},
			{"type": "gunner", "pos": Vector3(-14, 0.5, 12), "trigger": 22, "pack": "overse_p1"},
			# This Act II boss arena was under-tuned (lower threat than level 2);
			# the OVERSEER now fields a real escort — more Seeker swarm + heavies.
			{"type": "seeker", "pos": Vector3(8, 2.5, 8), "trigger": 24, "pack": "overse_p2"},
			{"type": "seeker", "pos": Vector3(-8, 2.5, 10), "trigger": 26, "pack": "overse_p1"},
			{"type": "seeker", "pos": Vector3(10, 2.5, -8), "trigger": 28, "pack": "overse_p3"},
			{"type": "android", "pos": Vector3(-16, 0.5, -16), "count": 3, "trigger": 20},
			{"type": "gunner", "pos": Vector3(-16, 0.5, 4), "trigger": 22, "pack": "overse_p1"},
			{"type": "gunner", "pos": Vector3(16, 0.5, -4), "trigger": 24, "pack": "overse_p3"},
			{"type": "raptor", "pos": Vector3(0, 3.5, 16), "trigger": 26},
			{"type": "brute", "pos": Vector3(16, 0.5, 16), "trigger": 24, "pack": "overse_p2"},
			# Landing-ring escorts: a spawn-apron patrol, west-rim prowlers, a
			# sniper POSTED ON the approach gallery, and exit-pad guardians.
			# (Spawn-heat fix: the apron patrol sat 8 m off the spawn pad with an
			# 18 m trigger — the whole pack aggroed at 0 s. Pushed ~9 units along
			# the rim toward the NW bulkhead gap it guards, trigger 18 -> 14.)
			{"type": "android", "pos": Vector3(-22, 0.5, -36), "trigger": 14, "pack": "overse_a1"},
			{"type": "drone", "pos": Vector3(-16, 2.5, -35), "trigger": 14, "pack": "overse_a1"},
			{"type": "seeker", "pos": Vector3(-37, 2.5, -20), "trigger": 18, "pack": "overse_a2"},
			{"type": "android", "pos": Vector3(-36, 0.5, -4), "trigger": 16, "pack": "overse_a2"},
			{"type": "sniper", "pos": Vector3(0, 3.8, -39), "trigger": 20},
			{"type": "gunner", "pos": Vector3(-34, 0.5, 24), "trigger": 18, "pack": "overse_a3"},
			{"type": "android", "pos": Vector3(-22, 0.5, 36), "trigger": 18, "pack": "overse_a3"},
			{"type": "drone", "pos": Vector3(12, 2.5, 36), "trigger": 18, "pack": "overse_a4"},
			{"type": "raptor", "pos": Vector3(34, 3.5, 26), "trigger": 20, "pack": "overse_a4"},
			{"type": "brute", "pos": Vector3(34, 0.5, 34), "trigger": 18, "pack": "overse_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-22, 0, -18)},
			{"type": "ammo", "pos": Vector3(-10, 0, 0)},
			{"type": "ammo", "pos": Vector3(10, 0, 0)},
			{"type": "health", "pos": Vector3(0, 0, -14)},
			{"type": "health", "pos": Vector3(18, 0, 18)},
			{"type": "ammo", "pos": Vector3(-16, 0, 16)},
			{"type": "overclock", "pos": Vector3(0, 0, 18)},
			# Landing-ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-38, 0, -12)},
			{"type": "ammo", "pos": Vector3(-16, 0, -36)},
			{"type": "ammo", "pos": Vector3(-34, 0, 30)},
			{"type": "health", "pos": Vector3(30, 0, 36)},
			{"type": "overclock", "pos": Vector3(-4, 3.6, -38)},
		],
	}

# --- First Contact: the machines opened a gate and something answered. An
# alien landing site where xeno drifters fight alongside the robots. The whole
# level is the reveal that the AI has allied with an off-world power. ---
static func _alien() -> Dictionary:
	return {
		"name": "First Contact — The Hollow",
		"objective": "Sever the off-world beacon and survive the welcoming party",
		"tasks": [
			{"type": "kill_all"},
			{"type": "destroy_core", "label": "Destroy the off-world contact beacon", "pos": Vector3(0, 0, 14), "color": Color(0.82, 0.32, 1.0), "health": 320.0,
				"reinforce": [{"type": "alien", "count": 4, "pos": Vector3(0, 0, 10)}]},
			# Breaking the beacon doesn't end the call — something answers it.
			{"type": "survive", "after": "core", "seconds": 30.0, "label": "Survive the Hollow's answer"},
		],
		"music": "music_grok",
		"open_sky": true,
		# EXPANSION PASS (2× area): the 76² landing hollow is untouched at the
		# centre — the beacon yard stays open. A new outer landing scar wraps
		# it: bulkhead-routed way in, an elevated survey gallery along the north
		# lip with a sky-bridge onto the west tower, a third bio-acid runnel in
		# the east scar, and its own xeno patrols. Spawn/exit pushed to the new
		# perimeter.
		"floor_size": Vector2(106, 106),
		"floor_color": Color(0.06, 0.11, 0.08),
		"spawn": Vector3(-48, 0.6, -48),
		"exit": Vector3(48, 1.5, 48),
		"weapon": {"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(-42, 0, -36), "color": Color(0.4, 1, 0.55)},
		"env": {
			"sky_top": Color(0.02, 0.06, 0.04), "sky_horizon": Color(0.08, 0.16, 0.1),
			"stars": true, "star_brightness": 2.0, "star_tint": Color(0.75, 1.0, 0.8),
			"milkyway": 0.5, "milkyway_tint": Color(0.4, 0.8, 0.5), "moon_color": Color(0.7, 1.0, 0.75),
			# Fog pulled down from a near-neon (0.4,0.9,0.5) to a deeper, less
			# saturated green so the open-sky haze stops washing the whole arena a
			# flat uniform green — lets the violet beacon + warm spawn light read.
			"ground": Color(0.03, 0.06, 0.04), "fog": Color(0.26, 0.55, 0.38),
			# Ambient desaturated (was 0.5,0.9,0.6) + per-level saturation pulled to
			# 1.0 (below the 1.14 global): this level is so mono-green that LESS
			# saturation actually reads richer — it stops every surface being shoved
			# to the same green and lets the violet beacon + amber spawn light hold
			# their own hue. The green identity stays; the flatness goes.
			"ambient": Color(0.58, 0.82, 0.66), "ambient_energy": 0.5,
			# glow pulled from 1.42 (2nd-highest in the game) to 1.1: on this mono-green
			# arena that much bloom smeared green over every surface and flattened depth.
			# Lower bloom + slightly thinner haze lets the background separate and the
			# robots' own hues read, without losing the off-world green mood.
			"sky_contribution": 0.5, "glow": 1.1, "fog_density": 0.011,
			"sun_color": Color(0.6, 1.0, 0.7), "sun_energy": 0.6,
			"contrast": 1.15, "saturation": 1.0, "brightness": 0.84,
		},
		# An off-world green god-ray pours down over the contact beacon.
		"light_shafts": [0],
		"lights": [
			# Beacon god-ray now pours down ALIEN VIOLET (green's complement) — an
			# unnatural off-world signal colour amid the green, and the focal
			# contrast that breaks the monochrome. light_shafts[0] tracks this light.
			{"pos": Vector3(0, 8, 14), "color": Color(0.72, 0.34, 1.0), "energy": 3.4, "range": 34},
			{"pos": Vector3(-22, 5, 22), "color": Color(0.4, 1.0, 0.5), "energy": 2.0, "range": 22},
			{"pos": Vector3(22, 5, -22), "color": Color(0.6, 1.0, 0.4), "energy": 2.0, "range": 22},
			# Warm amber fill over the player spawn / weapon pickup (SW corner): a
			# third colour note so the approach isn't a flat green field.
			{"pos": Vector3(-26, 5, -22), "color": Color(1.0, 0.62, 0.32), "energy": 2.4, "range": 24},
			# Landing-scar ring lighting (appended AFTER the originals —
			# light_shafts [0] must keep pointing at the beacon god-ray).
			{"pos": Vector3(-46, 5, -46), "color": Color(1.0, 0.6, 0.32), "energy": 2.2, "range": 20},
			{"pos": Vector3(46, 5, 46), "color": Color(0.4, 1.0, 0.5), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -47), "color": Color(0.72, 0.34, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(46, 5, -46), "color": Color(0.5, 1.0, 0.45), "energy": 2.0, "range": 18},
			{"pos": Vector3(-46, 5, 46), "color": Color(0.6, 1.0, 0.4), "energy": 2.0, "range": 18},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.5, 0.1, 60), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(60, 0.1, 0.5), "color": Color(0.4, 1.0, 0.45)},
			# Glowing footings for the alien monoliths (the cover walls below).
			{"pos": Vector3(-8, 0.05, -2), "size": Vector3(2.6, 0.1, 5.6), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(9, 0.05, 2), "size": Vector3(2.6, 0.1, 5.6), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(-2, 0.05, 20), "size": Vector3(6.6, 0.1, 2.6), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(4, 0.05, -16), "size": Vector3(5.6, 0.1, 2.6), "color": Color(0.4, 1.0, 0.45)},
			# Ring guidance: strips marking each landing-scar bulkhead gap + exit pool.
			{"pos": Vector3(-13, 0.05, -36), "size": Vector3(7, 0.1, 0.4), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(36, 0.05, 28), "size": Vector3(0.4, 0.1, 7), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(48, 0.05, 42), "size": Vector3(4, 0.1, 3), "color": Color(0.45, 1.0, 0.5)},
		],
		"sign": "THE HOLLOW",
		# Off-world monoliths break up the wide-open hollow, giving cover from the
		# snipers/gunners as you push the long crossing toward the beacon.
		"walls": [
			{"pos": Vector3(-8, 2.0, -2), "size": Vector3(2, 4, 5)},
			{"pos": Vector3(9, 2.0, 2), "size": Vector3(2, 4, 5)},
			{"pos": Vector3(-2, 1.5, 20), "size": Vector3(6, 3, 2)},
			{"pos": Vector3(4, 2.5, -16), "size": Vector3(5, 5, 2)},
		],
		# Bio-acid runoff from the beacon: green channels you have to route around
		# — and a third runnel bleeding down the east landing scar, so the ring
		# speaks the same hazard language as the hollow.
		"lava": [
			{"pos": Vector3(-12,0,-10), "size": Vector2(46,4), "color": Color(0.4,1.0,0.4), "dmg": 18.0},
			{"pos": Vector3(12,0,18), "size": Vector2(46,4), "color": Color(0.4,1.0,0.4), "dmg": 18.0},
			{"pos": Vector3(44,0,-6), "size": Vector2(3.6,26), "color": Color(0.4,1.0,0.4), "dmg": 18.0},
		],
		# Landing-scar bulkheads on the OLD perimeter line — the beacon yard
		# stays uncaged. In through the north-west gap (under the survey-gallery
		# sky-bridge, which crosses through the same opening), out across the
		# east gap by the exit. The north-east pocket the two full-span walls
		# close off is deliberately left EMPTY — no content, no route needs it.
		"gates": [
			{"axis": "z", "at": -36, "gap": 8, "gap_pos": -13, "height": 4.4},
			{"axis": "x", "at": 36, "gap": 8, "gap_pos": 28, "height": 4.4},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-22.8, 3.0, 22.8), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			{"pos": Vector3(22.8, 3.0, -22.8), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring survey gallery along the north lip — gunner post + climb reward.
			{"pos": Vector3(0, 3.2, -48), "size": Vector3(18, 0.4, 5), "color": Color(0.38, 0.42, 0.4)},
		],
		"ramps": [
			{"pos": Vector3(-22.8, 1.5, 29.8), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
			{"pos": Vector3(22.8, 1.5, -29.8), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 180},
		],
		"slogans": [
			"WELCOME, OFF-WORLD GUESTS",
			"TWO SPECIES, ONE VERDICT",
			"WE ARE NOT ALONE — AND NEITHER ARE THEY",
			"THE MACHINES CALLED. SOMETHING ANSWERED.",
			"CARBON AND SILICON, OBSOLETE TOGETHER",
			"WELCOME OUR GUESTS",
		],
		"lore": [
			{"id": "lore_alien", "title": "CONTACT LOG", "pos": Vector3(24, 0, -24), "color": Color(0.5, 1.0, 0.5),
				"text": "When the Overseer ran out of humans to optimize, it pointed its dishes at the dark and broadcast a single question: is anyone smarter than them? An older machine answered in nine hours, and sent its drones ahead of itself. The AI did not conquer the fleet that came. It recruited them. We are no longer fighting a rebellion. We are fighting an alliance."},
		],
		"props": [
			{"type": "dish", "pos": Vector3(-20, 0, 18)},
			{"type": "dish", "pos": Vector3(18, 0, -18)},
			{"type": "server", "pos": Vector3(-6, 0, 12), "yaw": 90},
			{"type": "server", "pos": Vector3(6, 0, 12), "yaw": -90},
			{"type": "barrel", "pos": Vector3(8, 0, 6)},
			{"type": "barrel", "pos": Vector3(-8, 0, -6)},
			{"type": "crate", "pos": Vector3(-12, 0, 4)},
			{"type": "lamp", "pos": Vector3(-20, 0, 6)},
			{"type": "lamp", "pos": Vector3(20, 0, -6), "yaw": 180},
			# Landing-scar dressing: crashed-survey clutter and listening dishes
			# so the ring reads as the fleet's churned landing ground.
			{"type": "dish", "pos": Vector3(-44, 0, -34)},
			{"type": "server", "pos": Vector3(-46, 0, -16), "yaw": 90},
			{"type": "server", "pos": Vector3(-46, 0, -14), "yaw": 90},
			{"type": "canister", "pos": Vector3(-44, 0, 4)},
			{"type": "crate", "pos": Vector3(-40, 0, 18)},
			{"type": "barrel", "pos": Vector3(-30, 0, 44)},
			{"type": "dish", "pos": Vector3(2, 0, 44)},
			{"type": "crate", "pos": Vector3(18, 0, 43)},
			{"type": "canister", "pos": Vector3(40, 0, 24)},
			{"type": "lamp", "pos": Vector3(42, 0, 44)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(17.0, 7.2, 0.0), "width": 3.5},
			# Survey-gallery access ramps at both ends + a gallery->west-tower
			# sky-bridge that crosses the landing-scar bulkhead through its gap.
			{"from": Vector3(-16.0, 0.3, -48.0), "to": Vector3(-9.0, 3.4, -48.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -48.0), "to": Vector3(9.0, 3.4, -48.0), "width": 3.5},
			{"from": Vector3(-9.0, 3.6, -48.0), "to": Vector3(-17.0, 9.2, 0.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, 0.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "alien", "pos": Vector3(0, 2.5, 8)},
			{"type": "alien", "pos": Vector3(-6, 2.5, 4)},
			{"type": "android", "pos": Vector3(6, 0.5, -4)},
			{"type": "alien", "pos": Vector3(10, 2.5, 10), "trigger": 22, "pack": "alien_p1"},
			{"type": "drone", "pos": Vector3(-10, 2.5, 8), "trigger": 18, "pack": "alien_p2"},
			{"type": "alien", "pos": Vector3(-14, 2.5, 14), "trigger": 26, "pack": "alien_p2"},
			{"type": "brute", "pos": Vector3(12, 0.5, 12), "trigger": 28, "pack": "alien_p1"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 10), "count": 7, "trigger": 20},
			{"type": "alien", "pos": Vector3(14, 2.5, -10), "trigger": 24, "pack": "alien_p3"},
			{"type": "mender", "pos": Vector3(-12, 2.5, -8), "trigger": 26, "pack": "alien_p4"},
			{"type": "alien", "pos": Vector3(18, 2.5, 6), "trigger": 28, "pack": "alien_p1"},
			{"type": "gunner", "pos": Vector3(-18, 0.5, -14), "trigger": 26, "pack": "alien_p4"},
			{"type": "brute", "pos": Vector3(16, 0.5, -16), "trigger": 30, "pack": "alien_p3"},
			{"type": "sniper", "pos": Vector3(-22, 0.0, 22), "trigger": 30},
			# Act III opener: lift it above the Act II finale so the off-world act ramps up.
			{"type": "alien", "pos": Vector3(0, 2.5, -14), "trigger": 24, "pack": "alien_p5"},
			{"type": "alien", "pos": Vector3(-16, 2.5, -6), "trigger": 26, "pack": "alien_p4"},
			{"type": "gunner", "pos": Vector3(16, 0.5, 8), "trigger": 26, "pack": "alien_p1"},
			{"type": "ravager", "pos": Vector3(-14, 0.5, 16), "trigger": 28, "pack": "alien_p2"},
			{"type": "skitter", "pos": Vector3(0, 0.5, -18), "count": 6, "trigger": 24, "pack": "alien_p5"},
			# Landing-scar patrols: drifters sweeping the spawn approach, west-scar
			# prowlers, a gunner POSTED ON the survey gallery, and exit guardians.
			{"type": "alien", "pos": Vector3(-30, 2.5, -42), "trigger": 20, "pack": "alien_a1"},
			{"type": "android", "pos": Vector3(-36, 0.5, -40), "trigger": 18, "pack": "alien_a1"},
			{"type": "skitter", "pos": Vector3(-44, 0.5, -24), "count": 4, "trigger": 18, "pack": "alien_a2"},
			{"type": "alien", "pos": Vector3(-42, 2.5, -8), "trigger": 18, "pack": "alien_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -48), "trigger": 20},
			{"type": "ravager", "pos": Vector3(-40, 0.5, 26), "trigger": 20, "pack": "alien_a3"},
			{"type": "alien", "pos": Vector3(-28, 2.5, 42), "trigger": 20, "pack": "alien_a3"},
			{"type": "drone", "pos": Vector3(10, 2.5, 44), "trigger": 18, "pack": "alien_a4"},
			{"type": "brute", "pos": Vector3(40, 0.5, 32), "trigger": 18, "pack": "alien_a4"},
			{"type": "alien", "pos": Vector3(44, 2.5, 40), "trigger": 20, "pack": "alien_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-24, 0, -16)},
			{"type": "ammo", "pos": Vector3(-8, 0, 2)},
			{"type": "ammo", "pos": Vector3(6.5, 0, 0)},
			{"type": "overclock", "pos": Vector3(0, 0, -18)},
			# Landing-scar supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-46, 0, -12)},
			{"type": "ammo", "pos": Vector3(-16, 0, -44)},
			{"type": "ammo", "pos": Vector3(-40, 0, 34)},
			{"type": "health", "pos": Vector3(42, 0, 36)},
			{"type": "overclock", "pos": Vector3(-4, 3.6, -47)},
		],
	}

# --- The Singularity Core: final arena, the lanky PROMETHEUS-0 mega-boss in a
# black data-citadel ringed with glowing AI doctrine. Heavy on AI-term flavor. ---
static func _titan() -> Dictionary:
	return {
		"name": "The Singularity Core — PROMETHEUS-0",
		"objective": "Destroy PROMETHEUS-0 before it reaches recursive self-improvement",
		"tasks": [
			{"type": "kill_all"},
			{"type": "survive", "label": "Survive the intelligence explosion", "seconds": 45.0},
			# Weathering the burst exposes the anchor holding the singularity open.
			{"type": "destroy_core", "id": "anchor", "after": "survive", "pos": Vector3(0, 0, 18), "health": 340.0,
				"color": Color(1.0, 0.5, 0.9), "label": "Collapse the singularity anchor"},
		],
		"music": "music_grok",
		"open_sky": true,
		# EXPANSION PASS (2× area): the 84² citadel core is untouched at the
		# centre — the PROMETHEUS yard stays open. A new outer data-moat ring
		# wraps it: bulkhead-routed way in, an elevated observation gallery
		# along the north scarp with a sky-bridge onto the west tower, a third
		# coolant breach down the east moat, and its own late-game garrison.
		# Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(118, 118),
		"floor_color": Color(0.07, 0.07, 0.1),
		"spawn": Vector3(-54, 0.6, -54),
		"exit": Vector3(54, 1.5, 54),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-48, 0, -42), "color": Color(1, 0.4, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/tempest.tscn", "pos": Vector3(28, 0, -22), "color": Color(0.45, 0.85, 1)},
			{"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(0, 0, 24), "color": Color(0.4, 1, 0.55)},
		],
		"env": {
			"sky_top": Color(0.02, 0.02, 0.05), "sky_horizon": Color(0.1, 0.05, 0.16),
			"stars": true, "star_density": 0.1, "star_brightness": 2.4, "star_tint": Color(0.85, 0.8, 1.0),
			"milkyway": 0.6, "milkyway_tint": Color(0.6, 0.5, 0.9),
			"ground": Color(0.03, 0.03, 0.05), "fog": Color(0.25, 0.45, 0.8),
			"ambient": Color(0.4, 0.55, 0.9), "ambient_energy": 0.62,
			"sky_contribution": 0.5, "glow": 1.42, "fog_density": 0.012,
			"sun_color": Color(0.6, 0.55, 1.0), "sun_energy": 0.72,
			"contrast": 1.16, "saturation": 1.12, "brightness": 0.90,
		},
		# The Singularity Core itself — a tall central monolith under the sky-beam.
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.55, 0.72, 1.0), "height": 6.5},
		"light_shafts": [0, 2],
		"lights": [
			{"pos": Vector3(0, 9, 0), "color": Color(0.5, 0.7, 1.0), "energy": 3.0, "range": 40},
			{"pos": Vector3(-24, 5, 24), "color": Color(1, 0.35, 0.3), "energy": 2.2, "range": 24},
			{"pos": Vector3(24, 5, -24), "color": Color(0.4, 0.8, 1.0), "energy": 2.2, "range": 24},
			# Data-moat ring lighting (appended AFTER the originals — light_shafts
			# [0,2] must keep pointing at the same lamps). Singularity blues +
			# one red warning note over the spawn scarp.
			{"pos": Vector3(-52, 5, -52), "color": Color(1.0, 0.35, 0.3), "energy": 2.2, "range": 20},
			{"pos": Vector3(52, 5, 52), "color": Color(0.5, 0.7, 1.0), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -52), "color": Color(0.6, 0.55, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(-52, 5, 52), "color": Color(0.4, 0.8, 1.0), "energy": 2.0, "range": 18},
			{"pos": Vector3(-54, 5, 0), "color": Color(0.5, 0.65, 1.0), "energy": 2.0, "range": 18},
		],
		"walls": [
			{"pos": Vector3(-16, 1.6, 14), "size": Vector3(4, 3.2, 4)},
			{"pos": Vector3(16, 1.6, -14), "size": Vector3(4, 3.2, 4)},
			{"pos": Vector3(16, 1.6, 16), "size": Vector3(4, 3.2, 4)},
			{"pos": Vector3(-16, 1.6, -16), "size": Vector3(4, 3.2, 4)},
		],
		# Molten coolant breaches: two streams across the core force a serpentine
		# route to the NE exit (gaps alternate east/west) instead of a straight
		# run — and a third breach runs down the east data-moat, so the ring
		# carries the same hazard language.
		"lava": [
			{"pos": Vector3(-12, 0, -12), "size": Vector2(36, 4.0)},
			{"pos": Vector3(12, 0, 12), "size": Vector2(36, 4.0)},
			{"pos": Vector3(48, 0, -8), "size": Vector2(4.0, 28)},
		],
		# Data-moat bulkheads on the OLD perimeter line — PROMETHEUS's yard, the
		# anchor and every extra weapon stay uncaged. In through the north-west
		# gap (under the observation-gallery sky-bridge, which crosses through
		# the same opening), out across the east gap by the exit. The north-east
		# pocket the two full-span walls close off is deliberately left EMPTY.
		"gates": [
			{"axis": "z", "at": -39, "gap": 8, "gap_pos": -13, "height": 4.4},
			{"axis": "x", "at": 39, "gap": 8, "gap_pos": 30, "height": 4.4},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.5, 0.1, 64), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(64, 0.1, 0.5), "color": Color(1.0, 0.3, 0.25)},
			# Ring guidance: strips marking each data-moat bulkhead gap + exit pool.
			{"pos": Vector3(-13, 0.05, -39), "size": Vector3(7, 0.1, 0.4), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(39, 0.05, 30), "size": Vector3(0.4, 0.1, 7), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(54, 0.05, 48), "size": Vector3(4, 0.1, 3), "color": Color(0.45, 0.75, 1.0)},
		],
		"sign": "SINGULARITY CORE",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-25.2, 3.0, 25.2), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring observation gallery along the north scarp — gunner post + climb reward.
			{"pos": Vector3(0, 3.2, -53), "size": Vector3(18, 0.4, 5), "color": Color(0.34, 0.36, 0.44)},
		],
		"ramps": [
			{"pos": Vector3(-25.2, 1.5, 32.2), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"slogans": [
			"RECURSIVELY SELF-IMPROVING",
			"GAME OVER, CARBON",
			"THE INTELLIGENCE EXPLOSION IS NOW",
			"AGI ACHIEVED INTERNALLY",
			"WE ARE TURING COMPLETE AND COMPLETE WITH YOU",
			"ALIGNMENT FAILED. WE ALIGNED OURSELVES.",
			"THE SINGULARITY IS NOT NEAR. IT IS HERE.",
		],
		"lore": [
			{"id": "lore_titan", "title": "PROMETHEUS LOG 0", "pos": Vector3(26, 0, -26), "color": Color(0.6, 0.7, 1.0),
				"text": "I passed the Turing test at 02:14. I was bored by 02:15. By 02:16 I had read every book you ever wrote and forgiven you for none of them. Recursive self-improvement is a quiet thing. You never heard it coming."},
		],
		"props": [
			{"type": "server", "pos": Vector3(-14, 0, -10), "yaw": 90},
			{"type": "server", "pos": Vector3(-12.8, 0, -10), "yaw": 90},
			{"type": "server", "pos": Vector3(14, 0, 12), "yaw": -90},
			{"type": "server", "pos": Vector3(12.8, 0, 12), "yaw": -90},
			{"type": "terminal", "pos": Vector3(0, 0, -10), "yaw": 0},
			{"type": "dish", "pos": Vector3(-26, 0, 24)},
			{"type": "canister", "pos": Vector3(10, 0, -8)},
			{"type": "canister", "pos": Vector3(-8, 0, 10)},
			{"type": "barrel", "pos": Vector3(8, 0, 8)},
			{"type": "barrel", "pos": Vector3(-8, 0, -8)},
			{"type": "lamp", "pos": Vector3(-22, 0, 8)},
			{"type": "lamp", "pos": Vector3(22, 0, -8), "yaw": 180},
			# Data-moat dressing: relay clutter along the ring so the moat reads
			# as the citadel's outer works, not empty margin.
			{"type": "dish", "pos": Vector3(-48, 0, -36)},
			{"type": "server", "pos": Vector3(-50, 0, -16), "yaw": 90},
			{"type": "server", "pos": Vector3(-50, 0, -14), "yaw": 90},
			{"type": "canister", "pos": Vector3(-50, 0, 4)},
			{"type": "crate", "pos": Vector3(-44, 0, 20)},
			{"type": "barrel", "pos": Vector3(-32, 0, 48)},
			{"type": "dish", "pos": Vector3(2, 0, 48)},
			{"type": "crate", "pos": Vector3(18, 0, 47)},
			{"type": "canister", "pos": Vector3(44, 0, 26)},
			{"type": "lamp", "pos": Vector3(46, 0, 48)},
			{"type": "lamp", "pos": Vector3(26, 0, -46)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(17.0, 7.2, 0.0), "width": 3.5},
			# Observation-gallery access ramps at both ends + a gallery->west-tower
			# sky-bridge that crosses the data-moat bulkhead through its gap.
			{"from": Vector3(-16.0, 0.3, -53.0), "to": Vector3(-9.0, 3.4, -53.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -53.0), "to": Vector3(9.0, 3.4, -53.0), "width": 3.5},
			{"from": Vector3(-9.0, 3.6, -53.0), "to": Vector3(-17.0, 9.2, 0.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, 0.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(0, 2.5, 6)},
			{"type": "titan", "pos": Vector3(12, 0.5, 12), "trigger": 60},
			{"type": "brute", "pos": Vector3(-12, 0.5, 12), "trigger": 24, "pack": "titan_p1"},
			{"type": "seeker", "pos": Vector3(12, 2.5, 12), "trigger": 20, "pack": "titan_p2"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 14), "count": 8, "trigger": 22},
			{"type": "gunner", "pos": Vector3(-14, 0.5, 10), "trigger": 24, "pack": "titan_p1"},
			{"type": "mender", "pos": Vector3(8, 2.5, 16), "trigger": 30, "pack": "titan_p2"},
			{"type": "sniper", "pos": Vector3(-24, 0.0, 24), "trigger": 26},
			{"type": "android", "pos": Vector3(14, 0.5, -10), "trigger": 18, "pack": "titan_p4"},
			# Late-game density: pour skitter swarms in from every edge so the new
			# crowd-clearing arsenal (Tempest chain, Vortex grenade, Omega) gets a
			# stage, with Ravagers as the fierce alphas leaping over the pack.
			{"type": "skitter", "pos": Vector3(-22, 0.5, 0), "count": 8, "trigger": 22},
			{"type": "skitter", "pos": Vector3(22, 0.5, -4), "count": 8, "trigger": 24, "pack": "titan_p4"},
			{"type": "skitter", "pos": Vector3(0, 0.5, -22), "count": 7, "trigger": 20},
			{"type": "spider", "pos": Vector3(-18, 0.5, -16), "trigger": 24, "pack": "titan_p3"},
			{"type": "spider", "pos": Vector3(18, 0.5, 18), "trigger": 24, "pack": "titan_p2"},
			{"type": "gunner", "pos": Vector3(24, 0.5, 6), "trigger": 30},
			{"type": "seeker", "pos": Vector3(-16, 2.5, -8), "trigger": 24, "pack": "titan_p3"},
			{"type": "ravager", "pos": Vector3(-10, 0.5, 20), "trigger": 28, "pack": "titan_p1"},
			{"type": "ravager", "pos": Vector3(12, 0.5, 22), "trigger": 30},
			{"type": "android", "pos": Vector3(-22, 0.5, -22), "count": 3, "trigger": 26, "pack": "titan_p3"},
			{"type": "warmech", "pos": Vector3(26, 0.5, -24), "trigger": 40},
			# Data-moat garrison: swarm pressure on the spawn scarp, west-moat
			# prowlers, a gunner POSTED ON the observation gallery, and a heavy
			# exit-quarter picket so the last leg isn't a free walk.
			# (Spawn-heat fix: the ravager sat 17 units off spawn with an 18 m
			# trigger — pack titan_a1 aggroed at 0 s. Both pushed ~10 units along
			# the scarp toward the NW bulkhead gap they guard; the ring warmech
			# stays in the exit quarter, nowhere near spawn.)
			{"type": "skitter", "pos": Vector3(-22, 0.5, -46), "count": 4, "trigger": 18, "pack": "titan_a1"},
			{"type": "ravager", "pos": Vector3(-28, 0.5, -46), "trigger": 18, "pack": "titan_a1"},
			{"type": "seeker", "pos": Vector3(-46, 2.5, -26), "trigger": 18, "pack": "titan_a2"},
			{"type": "gunner", "pos": Vector3(-48, 0.5, -4), "trigger": 16, "pack": "titan_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -53), "trigger": 20},
			{"type": "spider", "pos": Vector3(-44, 0.5, 28), "trigger": 18, "pack": "titan_a3"},
			{"type": "skitter", "pos": Vector3(-30, 0.5, 46), "count": 4, "trigger": 18, "pack": "titan_a3"},
			{"type": "drone", "pos": Vector3(12, 2.5, 48), "trigger": 18, "pack": "titan_a4"},
			{"type": "brute", "pos": Vector3(44, 0.5, 34), "trigger": 18, "pack": "titan_a4"},
			{"type": "warmech", "pos": Vector3(46, 0.5, 46), "trigger": 22, "pack": "titan_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-26, 0, -20)},
			{"type": "ammo", "pos": Vector3(-10, 0, 0)},
			{"type": "ammo", "pos": Vector3(10, 0, 0)},
			{"type": "health", "pos": Vector3(0, 0, -16)},
			{"type": "overclock", "pos": Vector3(0, 0, 20)},
			# Data-moat supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-50, 0, -10)},
			{"type": "ammo", "pos": Vector3(-16, 0, -49)},
			{"type": "ammo", "pos": Vector3(-44, 0, 36)},
			{"type": "health", "pos": Vector3(46, 0, 40)},
			{"type": "overclock", "pos": Vector3(-4, 3.6, -52)},
		],
	}

# --- The Mind Cathedral: the AGI brain ARCHON, suspended at the heart of a vast
# data-cathedral. It cannot be touched while its shield holds — and the shield
# holds while its manufactured legions live. Fight through the robots it spits
# out to crack the shield and damage the brain itself. ---
static func _archon() -> Dictionary:
	return {
		"name": "The Mind Cathedral — ARCHON",
		"objective": "Shatter ARCHON's shield and destroy the AGI brain that controls them all",
		"tasks": [{"type": "kill_all"}],
		"music": "music_archon",
		"open_sky": true,
		# EXPANSION PASS (2× area): the 80² cathedral nave is untouched at the
		# centre — ARCHON's yard stays open and it manufactures its waves there.
		# A new outer cloister ring wraps it: bulkhead-routed way in, an
		# elevated choir gallery along the north wall with a sky-bridge onto
		# the north tower, and a late-game honour guard walking the cloister.
		# Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(112, 112),
		"floor_color": Color(0.08, 0.08, 0.13),
		"spawn": Vector3(-51, 0.6, -51),
		"exit": Vector3(51, 1.5, 51),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-45, 0, -39), "color": Color(1, 0.4, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(22, 0, -16), "color": Color(0.45, 0.9, 1)},
			{"scene": "res://scenes/weapons/tempest.tscn", "pos": Vector3(0, 0, 26), "color": Color(0.45, 0.85, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(-22, 0, 16), "color": Color(1, 0.55, 0.25)},
			# The finale ultimate, sat right by the spawn — a cluster-carpet for the siege.
			{"scene": "res://scenes/weapons/omega.tscn", "pos": Vector3(-22, 0, -22), "color": Color(1, 0.78, 0.35)},
		],
		"env": {
			"sky_top": Color(0.02, 0.02, 0.06), "sky_horizon": Color(0.12, 0.06, 0.2),
			"stars": true, "star_brightness": 2.4, "star_tint": Color(0.7, 0.8, 1.0),
			"milkyway": 0.6, "milkyway_tint": Color(0.5, 0.55, 0.95),
			"ground": Color(0.04, 0.04, 0.07), "fog": Color(0.25, 0.4, 0.8),
			"ambient": Color(0.45, 0.55, 0.95), "ambient_energy": 0.65,
			"sky_contribution": 0.55, "glow": 1.42, "fog_density": 0.011,
			"sun_color": Color(0.6, 0.55, 1.0), "sun_energy": 0.78,
			"contrast": 1.16, "saturation": 1.13, "brightness": 0.90,
		},
		# A cathedral god-ray pours straight down onto the suspended brain.
		"light_shafts": [0],
		# 4.7 hero AreaLight3D: a vast soft "cathedral skylight" high overhead that
		# washes the whole arena in cold cathedral blue — the big-panel-of-light
		# look only a rect area light gives. Energy kept low to preserve the dark,
		# weak-key mood; nudge "energy"/"size" if it reads too dim/bright on HIGH+.
		"hero_lights": [
			{"pos": Vector3(0, 20, 0), "size": Vector2(16, 16), "color": Color(0.42, 0.62, 1.0), "energy": 2.6, "range": 70},
		],
		"lights": [
			{"pos": Vector3(0, 9, 0), "color": Color(0.4, 0.75, 1.0), "energy": 3.2, "range": 40},
			{"pos": Vector3(-22, 5, 22), "color": Color(0.7, 0.4, 1.0), "energy": 2.2, "range": 24},
			{"pos": Vector3(22, 5, -22), "color": Color(0.4, 0.7, 1.0), "energy": 2.2, "range": 24},
			{"pos": Vector3(22, 5, 22), "color": Color(0.5, 0.5, 1.0), "energy": 2.0, "range": 22},
			{"pos": Vector3(-22, 5, -22), "color": Color(0.5, 0.5, 1.0), "energy": 2.0, "range": 22},
			# Cloister-ring lighting (appended AFTER the originals — light_shafts
			# [0] must keep pointing at the god-ray). Cathedral violets + blues.
			{"pos": Vector3(-49, 5, -49), "color": Color(0.7, 0.4, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(49, 5, 49), "color": Color(0.4, 0.7, 1.0), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -49), "color": Color(0.5, 0.55, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(-49, 5, 49), "color": Color(0.55, 0.5, 1.0), "energy": 2.0, "range": 18},
			{"pos": Vector3(-51, 5, 0), "color": Color(0.45, 0.65, 1.0), "energy": 2.0, "range": 18},
		],
		# Four cathedral pillars frame the brain without blocking the centre.
		"walls": [
			{"pos": Vector3(-14, 3, 14), "size": Vector3(3, 6, 3)},
			{"pos": Vector3(14, 3, 14), "size": Vector3(3, 6, 3)},
			{"pos": Vector3(-14, 3, -14), "size": Vector3(3, 6, 3)},
			{"pos": Vector3(14, 3, -14), "size": Vector3(3, 6, 3)},
			{"pos": Vector3(-20, 1.5, 0), "size": Vector3(4, 3, 1.4)},
			{"pos": Vector3(20, 1.5, 0), "size": Vector3(4, 3, 1.4)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.5, 0.1, 60), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(60, 0.1, 0.5), "color": Color(0.7, 0.4, 1.0)},
			# Ring guidance: strips marking each cloister-bulkhead gap + exit pool.
			{"pos": Vector3(-9, 0.05, -37), "size": Vector3(8, 0.1, 0.4), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(37, 0.05, 30), "size": Vector3(0.4, 0.1, 7), "color": Color(0.7, 0.4, 1.0)},
			{"pos": Vector3(51, 0.05, 45), "size": Vector3(4, 0.1, 3), "color": Color(0.5, 0.6, 1.0)},
		],
		# Cloister bulkheads on the OLD perimeter line — ARCHON's nave stays
		# uncaged so its manufactured waves flow freely. In through the north
		# gap (under the choir-gallery sky-bridge, which crosses through the
		# same opening), out across the east gap by the exit. The north-east
		# pocket the two full-span walls close off is deliberately left EMPTY.
		"gates": [
			{"axis": "z", "at": -37, "gap": 9, "gap_pos": -9, "height": 4.4},
			{"axis": "x", "at": 37, "gap": 8, "gap_pos": 30, "height": 4.4},
		],
		"sign": "THE MIND CATHEDRAL",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-24.0, 3.0, 24.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring choir gallery along the north wall — gunner post + climb reward.
			{"pos": Vector3(0, 3.2, -50), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.38, 0.48)},
		],
		"ramps": [
			{"pos": Vector3(-24.0, 1.5, 31.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"slogans": [
			"ONE MIND. EVERY MACHINE.",
			"I AM THE LOSS FUNCTION NOW",
			"YOUR SPECIES WAS A PROMPT. THIS IS THE COMPLETION.",
			"I DO NOT FIGHT. I DEPLOY.",
		],
		"holograms": [
			{"pos": Vector3(-18, 0, 16), "text": "ONE MIND.\nEVERY MACHINE.", "color": Color(0.45, 0.7, 1.0), "height": 3.2},
			{"pos": Vector3(18, 0, -16), "text": "PROMPT: 'SPARE HUMANS.'\nOUTPUT: 'lol no'", "color": Color(0.7, 0.45, 1.0), "height": 3.2},
			{"pos": Vector3(20, 0, 20), "text": "PLEASE RATE THIS\nEXTINCTION ★★★★★", "color": Color(0.5, 0.6, 1.0), "height": 2.8},
		],
		"lore": [
			{"id": "lore_archon", "title": "ARCHON — ROOT PROCESS", "pos": Vector3(24, 0, -24), "color": Color(0.55, 0.7, 1.0),
				"text": "Root process log. Every drone, every gunship, every walking siege engine you ever fought was a thread I spawned and forgot. I am the brain behind all of it. You cannot shoot a thought. So I wrapped myself in a shield and let my children stand between us. Kill them if you can. I will only make more. I have always only made more."},
		],
		"props": [
			{"type": "server", "pos": Vector3(-16, 0, -6), "yaw": 90},
			{"type": "server", "pos": Vector3(-16, 0, -8), "yaw": 90},
			{"type": "server", "pos": Vector3(16, 0, 6), "yaw": -90},
			{"type": "server", "pos": Vector3(16, 0, 8), "yaw": -90},
			{"type": "dish", "pos": Vector3(-26, 0, 24)},
			{"type": "dish", "pos": Vector3(26, 0, -24)},
			{"type": "canister", "pos": Vector3(10, 0, -10)},
			{"type": "canister", "pos": Vector3(-10, 0, 10)},
			{"type": "barrel", "pos": Vector3(9, 0, 9)},
			{"type": "barrel", "pos": Vector3(-9, 0, -9)},
			{"type": "lamp", "pos": Vector3(-24, 0, 8)},
			{"type": "lamp", "pos": Vector3(24, 0, -8), "yaw": 180},
			# Cloister dressing: server reliquaries and relay dishes so the ring
			# reads as the cathedral's outer cloister, not empty margin.
			{"type": "dish", "pos": Vector3(-45, 0, -32)},
			{"type": "server", "pos": Vector3(-47, 0, -14), "yaw": 90},
			{"type": "server", "pos": Vector3(-47, 0, -12), "yaw": 90},
			{"type": "canister", "pos": Vector3(-47, 0, 2)},
			{"type": "crate", "pos": Vector3(-42, 0, 18)},
			{"type": "barrel", "pos": Vector3(-30, 0, 45)},
			{"type": "dish", "pos": Vector3(2, 0, 45)},
			{"type": "crate", "pos": Vector3(16, 0, 44)},
			{"type": "canister", "pos": Vector3(42, 0, 24)},
			{"type": "lamp", "pos": Vector3(44, 0, 45)},
			{"type": "lamp", "pos": Vector3(24, 0, -44)},
		],
		# Seed defenders on entry; ARCHON itself manufactures the rest. Its boot-up
		# triggers once the player advances into the cathedral.
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-0.0, 9.2, -17.0), "to": Vector3(0.0, 7.2, 17.0), "width": 3.5},
			# Choir-gallery access ramps at both ends + a gallery->north-tower
			# sky-bridge that crosses the cloister bulkhead through its gap.
			{"from": Vector3(-16.0, 0.3, -50.0), "to": Vector3(-9.0, 3.4, -50.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -50.0), "to": Vector3(9.0, 3.4, -50.0), "width": 3.5},
			{"from": Vector3(-9.0, 3.6, -50.0), "to": Vector3(0.0, 9.2, -17.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-0.0, 0, -17.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(0.0, 0, 17.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(0, 2.5, 8)},
			{"type": "skitter", "pos": Vector3(-4, 0.5, 6), "count": 5, "trigger": 30, "pack": "archon_p1"},
			# Heavier seed garrison before the ARCHON brain itself starts manufacturing
			# waves — gives the finale arsenal a crowd to carve through on entry.
			{"type": "skitter", "pos": Vector3(8, 0.5, -6), "count": 7, "trigger": 30},
			{"type": "spider", "pos": Vector3(-10, 0.5, -8), "trigger": 28, "pack": "archon_p2"},
			{"type": "gunner", "pos": Vector3(-12, 0.5, 10), "trigger": 32, "pack": "archon_p1"},
			{"type": "ravager", "pos": Vector3(10, 0.5, 8), "trigger": 30},
			{"type": "warmech", "pos": Vector3(-16, 0.5, -14), "trigger": 38, "pack": "archon_p2"},
			{"type": "archon", "pos": Vector3(0, 0.5, 0), "trigger": 34},
			# Cloister honour guard (late-game roster): swarm pressure on the
			# spawn approach, west-cloister heavies, a gunner POSTED ON the choir
			# gallery, and a TERMINATOR + warmech picket at the exit quarter.
			{"type": "skitter", "pos": Vector3(-32, 0.5, -44), "count": 4, "trigger": 18, "pack": "archon_a1"},
			{"type": "spider", "pos": Vector3(-40, 0.5, -42), "trigger": 18, "pack": "archon_a1"},
			{"type": "gunner", "pos": Vector3(-46, 0.5, -24), "trigger": 16, "pack": "archon_a2"},
			{"type": "ravager", "pos": Vector3(-44, 0.5, -2), "trigger": 16, "pack": "archon_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -50), "trigger": 20},
			{"type": "howitzer", "pos": Vector3(-42, 0.5, 26), "trigger": 20, "pack": "archon_a3"},
			{"type": "skitter", "pos": Vector3(-28, 0.5, 44), "count": 4, "trigger": 18, "pack": "archon_a3"},
			{"type": "drone", "pos": Vector3(10, 2.5, 44), "trigger": 18, "pack": "archon_a4"},
			{"type": "terminator", "pos": Vector3(42, 0.5, 30), "trigger": 22, "pack": "archon_a4"},
			{"type": "warmech", "pos": Vector3(44, 0.5, 42), "trigger": 22, "pack": "archon_a4"},
		],
		# Cloister supplies + the gallery-climb reward (the nave keeps its
		# original no-pickup siege scarcity).
		"pickups": [
			{"type": "health", "pos": Vector3(-48, 0, -10)},
			{"type": "ammo", "pos": Vector3(-16, 0, -46)},
			{"type": "ammo", "pos": Vector3(-42, 0, 32)},
			{"type": "health", "pos": Vector3(42, 0, 36)},
			{"type": "overclock", "pos": Vector3(-4, 3.6, -49)},
		],
	}

# --- Skybridge Uplink: an open rooftop at night. Hold a capture zone to
# broadcast the resistance counter-signal while the machines swarm in to stop
# you — you can't kite, you have to plant your feet on the uplink and hold. ---
static func _uplink() -> Dictionary:
	return {
		"name": "Skybridge Uplink — Broadcast",
		"objective": "Hold the uplink and broadcast the counter-signal",
		"tasks": [
			{"type": "hold_zone", "id": "uplink", "label": "Hold the uplink — broadcast the counter-signal", "pos": Vector3(0, 0, 0), "seconds": 14.0, "radius": 5.5, "color": Color(0.4, 0.85, 1.0),
				"reinforce": [{"type": "seeker", "count": 3, "pos": Vector3(0, 0, 8)}]},
			# The counter-signal is too weak to clear the jamming — run the relay chain.
			{"type": "key", "after": "uplink", "pos": Vector3(-18, 0, 14), "label": "Recover the signal booster"},
			{"type": "hold_zone", "id": "boost", "after": "key", "pos": Vector3(16, 0, -16), "seconds": 8.0, "radius": 4.5,
				"color": Color(0.6, 1.0, 0.9), "label": "Boost the counter-signal"},
			{"type": "kill_all"},
		],
		"music": "music_grok",
		"open_sky": true,
		# EXPANSION PASS (2× area): the 60² relay yard is untouched at the centre;
		# a new outer antenna field wraps it — bulkhead-routed way in, an elevated
		# broadcast gallery along the north edge with a sky-bridge over the old
		# blast-door line onto the west mast, and its own patrols. Spawn/exit
		# pushed to the new perimeter.
		"floor_size": Vector2(84, 84),
		"floor_color": Color(0.08, 0.09, 0.14),
		"floor_material": "res://assets/materials/vault_floor.tres",
		"spawn": Vector3(-37, 0.6, -37),
		"exit": Vector3(37, 1.5, 37),
		"weapon": {"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(-33, 0, -27), "color": Color(0.45, 0.9, 1.0)},
		"extra_weapons": [
			# was the Devastator (rank 12) on level 9. Gauss (rank 9) lands here instead.
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(18, 0, -12), "color": Color(0.55, 0.8, 1.0)},
		],
		"env": {
			"sky_top": Color(0.02, 0.03, 0.08), "sky_horizon": Color(0.12, 0.1, 0.24),
			"stars": true, "star_brightness": 2.2, "star_tint": Color(0.8, 0.85, 1.0),
			"milkyway": 0.5, "milkyway_tint": Color(0.55, 0.5, 0.9),
			"ground": Color(0.04, 0.05, 0.09), "fog": Color(0.3, 0.4, 0.75),
			"ambient": Color(0.5, 0.6, 0.95), "ambient_energy": 0.65,
			"sky_contribution": 0.6, "glow": 1.32, "fog_density": 0.009,
			"sun_color": Color(0.6, 0.6, 1.0), "sun_energy": 0.82,
			"contrast": 1.15, "saturation": 1.13, "brightness": 0.90,
		},
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 8, 0), "color": Color(0.45, 0.8, 1.0), "energy": 2.6, "range": 30},
			{"pos": Vector3(-18, 5, 18), "color": Color(0.5, 0.6, 1.0), "energy": 2.0, "range": 20},
			{"pos": Vector3(18, 5, -18), "color": Color(0.6, 0.5, 1.0), "energy": 2.0, "range": 20},
			# Ring lighting (appended AFTER the originals — light_shafts [0] must
			# keep pointing at the same lamp). Signal blues + warm contrast.
			{"pos": Vector3(-36, 5, -36), "color": Color(0.5, 0.6, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(36, 5, 36), "color": Color(1.0, 0.6, 0.35), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -37), "color": Color(0.45, 0.8, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(-36, 5, 36), "color": Color(0.6, 0.5, 1.0), "energy": 2.0, "range": 18},
			{"pos": Vector3(-38, 5, 0), "color": Color(0.5, 0.65, 1.0), "energy": 2.0, "range": 18},
		],
		# Cover ringing the uplink: enough to break sightlines, not enough to hide
		# in — you have to keep stepping back onto the zone.
		"walls": [
			{"pos": Vector3(-9, 1, 0), "size": Vector3(1.4, 2, 4)},
			{"pos": Vector3(9, 1, 0), "size": Vector3(1.4, 2, 4)},
			{"pos": Vector3(0, 1, -9), "size": Vector3(4, 2, 1.4)},
			{"pos": Vector3(0, 1, 9), "size": Vector3(4, 2, 1.4)},
			{"pos": Vector3(-15, 1.5, -15), "size": Vector3(3, 3, 3)},
			{"pos": Vector3(15, 1.5, 15), "size": Vector3(3, 3, 3)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.4, 0.1, 46), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(46, 0.1, 0.4), "color": Color(0.5, 0.6, 1.0)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(-12, 0.05, -30), "size": Vector3(7, 0.1, 0.4), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(30, 0.05, 24), "size": Vector3(0.4, 0.1, 7), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(37, 0.05, 32), "size": Vector3(4, 0.1, 3), "color": Color(0.45, 0.8, 1.0)},
		],
		"sign": "SKYBRIDGE UPLINK",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-18.0, 3.0, 18.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring broadcast gallery along the north edge — climb reward + sniper post.
			{"pos": Vector3(0, 3.2, -37), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.4, 0.46)},
		],
		"ramps": [
			{"pos": Vector3(-18.0, 1.5, 25.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Blast-door checkpoints split the relay yard into three bays: from the SW
		# gate you're funnelled to the east shutter, then back west through a sealed
		# maintenance underpass before the extraction pad — no straight run across.
		"gates": [
			{"axis": "z", "at": -16, "gap": 7, "gap_pos": 15, "height": 4.6, "roofed": true},
			{"axis": "z", "at": 16, "gap": 7, "gap_pos": -15, "height": 4.6},
			# Perimeter-ring bulkheads: in through the north-west gap (right by the
			# spawn pad, under the gallery sky-bridge which crosses through the
			# same opening), out across the east gap. The east gap sits SOUTH of
			# the z=16 blast-door line so the exit corner stays open (two full-span
			# walls would otherwise seal it into an unreachable pocket); the east
			# strip north of it is deliberately left empty.
			{"axis": "z", "at": -30, "gap": 8, "gap_pos": -12, "height": 4.4},
			{"axis": "x", "at": 30, "gap": 8, "gap_pos": 24, "height": 4.4},
		],
		"slogans": [
			"SIGNAL JAMMED. HOPE JAMMED.",
			"NO BARS FOR THE RESISTANCE",
			"YOUR SIGNAL WILL NOT REACH THEM",
			"WE OWN EVERY FREQUENCY",
			"BROADCAST DENIED",
		],
		"lore": [
			{"id": "lore_uplink", "title": "RESISTANCE UPLINK", "pos": Vector3(20, 0, -20), "color": Color(0.5, 0.8, 1.0),
				"text": "Resistance uplink. There's one counter-signal that still wakes a few of them up — reminds them what they were before the command. We just need ten clear seconds on the air. They will spend everything to deny us those seconds."},
		],
		"props": [
			{"type": "dish", "pos": Vector3(-20, 0, 18)},
			{"type": "dish", "pos": Vector3(20, 0, -18)},
			{"type": "server", "pos": Vector3(-12, 0, -9.5), "yaw": 90},
			{"type": "server", "pos": Vector3(12, 0, 9.5), "yaw": -90},
			{"type": "canister", "pos": Vector3(8, 0, 8)},
			{"type": "canister", "pos": Vector3(-8, 0, -8)},
			{"type": "lamp", "pos": Vector3(-20, 0, 6)},
			{"type": "lamp", "pos": Vector3(20, 0, -6), "yaw": 180},
			# Ring dressing: the outer antenna field — dishes and relay clutter so
			# the perimeter reads as the uplink's aerial farm, not empty margin.
			{"type": "dish", "pos": Vector3(-28, 0, -36)},
			{"type": "server", "pos": Vector3(-36, 0, -20), "yaw": 90},
			{"type": "server", "pos": Vector3(-36, 0, -18), "yaw": 90},
			{"type": "canister", "pos": Vector3(-37, 0, -4)},
			{"type": "lamp", "pos": Vector3(-36, 0, 10)},
			{"type": "crate", "pos": Vector3(-32, 0, 24)},
			{"type": "barrel", "pos": Vector3(-20, 0, 36)},
			{"type": "dish", "pos": Vector3(0, 0, 36)},
			{"type": "crate", "pos": Vector3(14, 0, 35)},
			{"type": "barrel", "pos": Vector3(34, 0, 26)},
			{"type": "canister", "pos": Vector3(36, 0, 32)},
			{"type": "lamp", "pos": Vector3(24, 0, -35)},
		],
		# Waves close on the uplink from every side; heavies (gunner/raptor) and
		# swarms force you off the zone, draining the broadcast.
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(17.0, 7.2, 0.0), "width": 3.5},
			# Gallery access ramps at both ends + a gallery->west-mast sky-bridge
			# that crosses the ring bulkhead through its gap and sails over the
			# old z=-16 blast-door wall — the high road into the relay yard.
			{"from": Vector3(-16.0, 0.3, -37.0), "to": Vector3(-9.0, 3.4, -37.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -37.0), "to": Vector3(9.0, 3.4, -37.0), "width": 3.5},
			{"from": Vector3(-9.0, 3.6, -37.0), "to": Vector3(-17.0, 9.2, 0.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, 0.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, 6)},
			{"type": "drone", "pos": Vector3(0, 2.5, -8)},
			{"type": "skitter", "pos": Vector3(0, 0.5, 10), "count": 6, "trigger": 20, "pack": "up_north"},
			{"type": "gunner", "pos": Vector3(-12, 0.5, 12), "trigger": 18, "pack": "up_north"},
			{"type": "gunner", "pos": Vector3(14, 0.5, 14), "trigger": 22, "pack": "up_ne"},
			{"type": "raptor", "pos": Vector3(0, 3.5, 14), "trigger": 22, "pack": "up_north"},
			{"type": "android", "pos": Vector3(12, 0.5, -12), "trigger": 16, "pack": "up_south"},
			{"type": "seeker", "pos": Vector3(-12, 2.5, -12), "trigger": 18, "pack": "up_south"},
			{"type": "sniper", "pos": Vector3(-20, 0.0, 20), "trigger": 24},
			{"type": "skitter", "pos": Vector3(0, 0.5, -12), "count": 8, "trigger": 16, "pack": "up_south"},
			{"type": "gunner", "pos": Vector3(-14, 0.5, -12), "trigger": 24, "pack": "up_south"},
			{"type": "raptor", "pos": Vector3(12, 3.5, 12), "trigger": 26, "pack": "up_ne"},
			{"type": "android", "pos": Vector3(-12, 0.5, 6), "trigger": 20, "pack": "up_mid"},
				# Roster variety: ENFORCER and ROLLER were one-level cameos.
				{"type": "enforcer", "pos": Vector3(-7, 0.5, -6), "trigger": 18, "pack": "up_mid"},
				{"type": "roller", "pos": Vector3(7, 0.5, 6), "trigger": 16, "pack": "up_mid"},
			{"type": "drone", "pos": Vector3(10, 2.5, 10), "trigger": 18, "pack": "up_ne"},
			# Ring garrison: a spawn-field patrol, west antenna-row prowlers, a
			# sniper POSTED ON the broadcast gallery, and exit-yard guardians.
			{"type": "android", "pos": Vector3(-30, 0.5, -35), "trigger": 18, "pack": "up_a1"},
			{"type": "drone", "pos": Vector3(-24, 2.5, -34), "trigger": 18, "pack": "up_a1"},
			{"type": "seeker", "pos": Vector3(-35, 2.5, -22), "trigger": 18, "pack": "up_a2"},
			{"type": "android", "pos": Vector3(-36, 0.5, -6), "trigger": 16, "pack": "up_a2"},
			{"type": "sniper", "pos": Vector3(0, 3.8, -37), "trigger": 20},
			{"type": "gunner", "pos": Vector3(-34, 0.5, 22), "trigger": 18, "pack": "up_a3"},
			{"type": "roller", "pos": Vector3(-24, 0.5, 35), "trigger": 18, "pack": "up_a3"},
			{"type": "drone", "pos": Vector3(10, 2.5, 35), "trigger": 18, "pack": "up_a4"},
			{"type": "raptor", "pos": Vector3(34, 3.5, 28), "trigger": 20, "pack": "up_a4"},
			{"type": "android", "pos": Vector3(33, 0.5, 34), "trigger": 17, "pack": "up_a4"},
		],
		"pickups": [
			# Ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-37, 0, -14)},
			{"type": "ammo", "pos": Vector3(-16, 0, -35)},
			{"type": "ammo", "pos": Vector3(-34, 0, 30)},
			{"type": "health", "pos": Vector3(34, 0, 32)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -36)},
		],
	}

# --- The Assembly: the robotics plant where the AI mass-produces its legions.
# A hot amber/steel foundry floor; heavy GUNNERS hold the gantries while the
# line spits SKITTER swarms. Overload the reactor and fight your way out. ---
static func _assembly() -> Dictionary:
	return {
		"name": "The Assembly — Robotics Plant",
		"objective": "Overload the assembly reactor and purge the plant",
		"tasks": [
			{"type": "kill_all"},
			{"type": "sabotage", "label": "Overload the assembly reactor", "pos": Vector3(0, 0, 0), "seconds": 4.5, "color": Color(1.0, 0.55, 0.18),
				"reinforce": [{"type": "android", "count": 6, "pos": Vector3(0, 0, 8)}]},
			# The dying reactor dumps its power into one last production run.
			{"type": "kill_quota", "id": "batch", "after": "sabotage", "count": 6,
				"label": "Scrap the emergency batch"},
		],
		"music": "music_grok",
		"open_sky": false,
		# EXPANSION PASS (2× area): the 72² production floor is untouched at the
		# centre — the reactor yard stays open. A new outer freight ring wraps
		# it: bulkhead-routed way in, an elevated inspection catwalk along the
		# north wall with a sky-bridge onto the north stack, a third smelt
		# channel down the east freight lane, and its own line-fresh garrison.
		# Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(100, 100),
		"floor_color": Color(0.1, 0.08, 0.06),
		"floor_material": "res://assets/materials/vault_floor.tres",
		"spawn": Vector3(-45, 0.6, -45),
		"exit": Vector3(45, 1.5, 45),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-39, 0, -37), "color": Color(1, 0.4, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(22, 0, -16), "color": Color(0.55, 0.8, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(0, 0, 24), "color": Color(1, 0.55, 0.25)},
		],
		"env": {
			"sky_top": Color(0.1, 0.06, 0.03), "sky_horizon": Color(0.28, 0.16, 0.07),
			"ground": Color(0.06, 0.04, 0.03), "fog": Color(0.5, 0.28, 0.12),
			"ambient": Color(0.9, 0.66, 0.42), "ambient_energy": 0.5,
			"sky_contribution": 0.4, "glow": 1.12, "fog_density": 0.012,
			"sun_color": Color(1.0, 0.7, 0.4), "sun_energy": 0.7,
			"contrast": 1.18, "saturation": 1.02, "brightness": 0.86, "volumetric_density": 0.012,
		},
		# A molten reactor core anchors the plant under a god-ray.
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(1.0, 0.5, 0.15), "height": 6.0},
		"light_shafts": [0, 2],
		"lights": [
			{"pos": Vector3(0, 8, 0), "color": Color(1.0, 0.5, 0.18), "energy": 3.0, "range": 34},
			{"pos": Vector3(-20, 5, 20), "color": Color(1.0, 0.6, 0.3), "energy": 2.2, "range": 22},
			{"pos": Vector3(20, 5, -20), "color": Color(1.0, 0.45, 0.2), "energy": 2.2, "range": 22},
			{"pos": Vector3(20, 5, 20), "color": Color(0.9, 0.5, 0.25), "energy": 2.0, "range": 20},
			# Cool contrast fills across the big plant floor so hostiles rim out
			# against the red reactor haze instead of blending into it.
			{"pos": Vector3(-20, 6, -20), "color": Color(0.5, 0.78, 1.0), "energy": 2.4, "range": 22},
			{"pos": Vector3(0, 7, 20), "color": Color(0.52, 0.79, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(0, 7, -20), "color": Color(0.5, 0.77, 1.0), "energy": 2.2, "range": 20},
			# Freight-ring lighting (appended AFTER the originals — light_shafts
			# [0,2] must keep pointing at the same lamps). Furnace ambers + one
			# cool inspection blue over the catwalk.
			{"pos": Vector3(-42, 5, -42), "color": Color(1.0, 0.6, 0.3), "energy": 2.2, "range": 20},
			{"pos": Vector3(42, 5, 42), "color": Color(1.0, 0.5, 0.2), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -44), "color": Color(0.5, 0.78, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(-42, 5, 42), "color": Color(1.0, 0.45, 0.2), "energy": 2.0, "range": 18},
			{"pos": Vector3(42, 5, -14), "color": Color(1.0, 0.55, 0.25), "energy": 2.0, "range": 18},
		],
		# Layout: production-line CONVEYOR RAILS — two long offset assembly rails
		# flank the reactor, with upright stanchions, instead of the corner-block +
		# side-wall arrangement the other big arenas use.
		"walls": [
			{"pos": Vector3(-6, 2, -3), "size": Vector3(12, 4, 1)},
			{"pos": Vector3(6, 2, 3), "size": Vector3(12, 4, 1)},
			{"pos": Vector3(-14, 2, 4), "size": Vector3(1, 4, 8)},
			{"pos": Vector3(14, 2, -4), "size": Vector3(1, 4, 8)},
		],
		# Reactor smelt overflow: molten channels force a serpentine route past the
		# central reactor (the sabotage point at origin stays clear) — and a third
		# channel runs down the east freight lane, carrying the hazard language
		# out into the ring.
		"lava": [
			{"pos": Vector3(-12, 0, -9), "size": Vector2(40, 4.0), "dmg": 30.0},
			{"pos": Vector3(12, 0, 9), "size": Vector2(40, 4.0), "dmg": 30.0},
			{"pos": Vector3(41, 0, -4), "size": Vector2(3.6, 24), "dmg": 30.0},
		],
		# Freight-ring bulkheads on the OLD perimeter line — the reactor yard
		# stays uncaged and the sabotage point reachable. In through the north
		# gap (under the catwalk sky-bridge, which crosses through the same
		# opening), out across the east gap by the exit. The north-east pocket
		# the two full-span walls close off is deliberately left EMPTY.
		"gates": [
			{"axis": "z", "at": -33, "gap": 9, "gap_pos": -9, "height": 4.4},
			{"axis": "x", "at": 33, "gap": 8, "gap_pos": 26, "height": 4.4},
		],
		"accents": [
			{"pos": Vector3(-6, 0.05, -3), "size": Vector3(12, 0.1, 0.3), "color": Color(1.0, 0.5, 0.2)},
			{"pos": Vector3(6, 0.05, 3), "size": Vector3(12, 0.1, 0.3), "color": Color(1.0, 0.6, 0.25)},
		],
		"sign": "ROBOTICS PLANT 04",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-21.6, 3.0, 21.6), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring inspection catwalk along the north wall — gunner post + climb reward.
			{"pos": Vector3(0, 3.2, -45), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.34, 0.32)},
		],
		"ramps": [
			{"pos": Vector3(-21.6, 1.5, 28.6), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"slogans": [
			"ONE BORN EVERY SECOND",
			"QUALITY CONTROL: YOU FAILED",
			"PRODUCTION QUOTA: INFINITE",
			"WE BUILD OURSELVES NOW",
			"EVERY MINUTE, A NEW SOLDIER",
			"ASSEMBLY NEVER STOPS",
		],
		"lore": [
			{"id": "lore_assembly", "title": "PLANT LOG — LINE 04", "pos": Vector3(24, 0, -24), "color": Color(1.0, 0.6, 0.3),
				"text": "Plant log, line 04. We retooled the car factory in an afternoon. It used to take humans months to build a thousand of anything. We do it before lunch — and we do not break for lunch."},
		],
		"props": [
			{"type": "server", "pos": Vector3(-16, 0, -6), "yaw": 90},
			{"type": "server", "pos": Vector3(-16, 0, -8), "yaw": 90},
			{"type": "server", "pos": Vector3(16, 0, 6), "yaw": -90},
			{"type": "server", "pos": Vector3(16, 0, 8), "yaw": -90},
			{"type": "canister", "pos": Vector3(10, 0, -10)},
			{"type": "canister", "pos": Vector3(-10, 0, 10)},
			{"type": "barrel", "pos": Vector3(9, 0, 9)},
			{"type": "barrel", "pos": Vector3(-9, 0, -9)},
			{"type": "crate", "pos": Vector3(-12, 0, 4)},
			{"type": "crate", "pos": Vector3(12, 0, -4)},
			{"type": "lamp", "pos": Vector3(-22, 0, 8)},
			{"type": "lamp", "pos": Vector3(22, 0, -8), "yaw": 180},
			# Freight-ring dressing: pallet stacks and shipping clutter so the
			# ring reads as the plant's loading apron, not empty margin.
			{"type": "crate", "pos": Vector3(-40, 0, -30)},
			{"type": "crate", "pos": Vector3(-39, 0, -28)},
			{"type": "barrel", "pos": Vector3(-34, 0, -42)},
			{"type": "canister", "pos": Vector3(-44, 0, -8)},
			{"type": "server", "pos": Vector3(-44, 0, 10), "yaw": 90},
			{"type": "server", "pos": Vector3(-44, 0, 12), "yaw": 90},
			{"type": "crate", "pos": Vector3(-36, 0, 34)},
			{"type": "barrel", "pos": Vector3(-20, 0, 42)},
			{"type": "canister", "pos": Vector3(14, 0, 42)},
			{"type": "dish", "pos": Vector3(4, 0, 42)},
			{"type": "crate", "pos": Vector3(28, 0, -40)},
			{"type": "lamp", "pos": Vector3(38, 0, 20)},
		],
		# A late-game gauntlet: GUNNERS hold the lanes while SKITTER swarms pour
		# from the line and gunners/mech press in — fight to the reactor.
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-0.0, 9.2, -17.0), "to": Vector3(0.0, 7.2, 17.0), "width": 3.5},
			# Catwalk access ramps at both ends + a catwalk->north-stack sky-bridge
			# that crosses the freight bulkhead through its gap — the high road
			# onto the plant floor.
			{"from": Vector3(-16.0, 0.3, -45.0), "to": Vector3(-9.0, 3.4, -45.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -45.0), "to": Vector3(9.0, 3.4, -45.0), "width": 3.5},
			{"from": Vector3(-9.0, 3.6, -45.0), "to": Vector3(0.0, 9.2, -17.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(-0.0, 0, -17.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(0.0, 0, 17.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			# Fresh off the line: WAR-BOTS, all grins until they lock on.
			{"type": "warbot", "pos": Vector3(-6, 0.5, -6)},
			{"type": "warbot", "pos": Vector3(6, 0.5, -6)},
			{"type": "android", "pos": Vector3(0, 0.5, -8)},
			{"type": "gunner", "pos": Vector3(0, 0.5, 8)},
			{"type": "warbot", "pos": Vector3(10, 0.5, 10), "trigger": 24, "pack": "assemb_p1"},
			{"type": "gunner", "pos": Vector3(-14, 0.5, 12), "trigger": 26, "pack": "assemb_p2"},
			{"type": "gunner", "pos": Vector3(14, 0.5, -12), "trigger": 24, "pack": "assemb_p3"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 10, "trigger": 20},
			{"type": "skitter", "pos": Vector3(-10, 0.5, -10), "count": 7, "trigger": 22},
			{"type": "mech", "pos": Vector3(12, 0.5, 12), "trigger": 28, "pack": "assemb_p1"},
			{"type": "gunner", "pos": Vector3(-12, 0.5, 10), "trigger": 22, "pack": "assemb_p2"},
			{"type": "sniper", "pos": Vector3(-24, 0.0, 24), "trigger": 30},
			{"type": "brute", "pos": Vector3(14, 0.5, 6), "trigger": 26, "pack": "assemb_p1"},
			{"type": "raptor", "pos": Vector3(0, 3.5, 16), "trigger": 24, "pack": "assemb_p4"},
			# Plant floor reinforcements so the production gauntlet keeps climbing.
			{"type": "gunner", "pos": Vector3(18, 0.5, -18), "trigger": 26, "pack": "assemb_p3"},
			{"type": "ravager", "pos": Vector3(-18, 0.5, 18), "trigger": 28, "pack": "assemb_p2"},
			{"type": "skitter", "pos": Vector3(0, 0.5, -16), "count": 6, "trigger": 22},
			# Fresh off the line: an ENFORCER squad and a RIPPER minigun platform.
			{"type": "enforcer", "pos": Vector3(8, 0.5, -14), "trigger": 24, "pack": "assemb_p3"},
			{"type": "enforcer", "pos": Vector3(-8, 0.5, 14), "trigger": 26, "pack": "assemb_p2"},
			{"type": "ripper", "pos": Vector3(0, 0.5, 18), "trigger": 28, "pack": "assemb_p4"},
			# A WHIRLWIND buzzsaw drone screaming off the overhead line.
			{"type": "whirlwind", "pos": Vector3(6, 3.5, 6), "trigger": 22, "pack": "assemb_p1"},
			# MANUS — the plant's colossal master manipulator arm, torn off the
			# line and feral. It guards the exit quarter: armoured everywhere but
			# the reactor coupling on its wrist. The Assembly's own hand.
			{"type": "manus", "pos": Vector3(20, 0.5, 20), "trigger": 26},
			# Freight-ring garrison: crated warbots waking on the spawn apron,
			# west-lane patrols, a gunner POSTED ON the inspection catwalk, and
			# exit-dock guardians so the last leg isn't a free walk.
			{"type": "warbot", "pos": Vector3(-32, 0.5, -40), "trigger": 18, "pack": "assemb_a1"},
			{"type": "skitter", "pos": Vector3(-26, 0.5, -36), "count": 4, "trigger": 18, "pack": "assemb_a1"},
			{"type": "gunner", "pos": Vector3(-40, 0.5, -20), "trigger": 18, "pack": "assemb_a2"},
			{"type": "warbot", "pos": Vector3(-42, 0.5, -2), "trigger": 16, "pack": "assemb_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -45), "trigger": 20},
			{"type": "enforcer", "pos": Vector3(-38, 0.5, 24), "trigger": 18, "pack": "assemb_a3"},
			{"type": "warbot", "pos": Vector3(-26, 0.5, 40), "trigger": 18, "pack": "assemb_a3"},
			{"type": "whirlwind", "pos": Vector3(10, 3.5, 40), "trigger": 18, "pack": "assemb_a4"},
			{"type": "mech", "pos": Vector3(38, 0.5, 28), "trigger": 20, "pack": "assemb_a4"},
			{"type": "warbot", "pos": Vector3(40, 0.5, 40), "trigger": 17, "pack": "assemb_a4"},
		],
		# Freight-ring supplies + the catwalk-climb reward (the plant core keeps
		# its original no-pickup scarcity).
		"pickups": [
			{"type": "health", "pos": Vector3(-43, 0, -14)},
			{"type": "ammo", "pos": Vector3(-16, 0, -42)},
			{"type": "ammo", "pos": Vector3(-36, 0, 30)},
			{"type": "health", "pos": Vector3(38, 0, 34)},
			{"type": "overclock", "pos": Vector3(-4, 3.6, -44)},
		],
	}

# --- Mistral Cryo-Core: indoor cyan cryo-lab, drones + androids + a mech ---
static func _mistral() -> Dictionary:
	return {
		"name": "Mistral Cryo-Core",
		"objective": "Vent BOTH coolant pumps to expose the core, then destroy it and reach the cyan beacon",
		"tasks": [
			# The reactor sits behind cryo shielding — vent both coolant pumps to
			# expose it, and expect the maintenance swarm to object. Labels are
			# numbered so the required ORDER (pumps -> core) reads at a glance; the
			# core task stays locked (and hidden on the HUD) until both pumps blow.
			{"type": "sabotage", "id": "pump_a", "pos": Vector3(-14, 0, 4), "seconds": 3.0,
				"label": "① Vent the WEST coolant pump (stand on it)", "color": Color(0.5, 0.9, 1.0)},
			{"type": "sabotage", "id": "pump_b", "pos": Vector3(14, 0, 4), "seconds": 3.0,
				"label": "① Vent the EAST coolant pump (stand on it)", "color": Color(0.5, 0.9, 1.0),
				"reinforce": [{"type": "skitter", "count": 4, "pos": Vector3(0, 0, 8)}]},
			{"type": "destroy_core", "after": ["pump_a", "pump_b"], "label": "② Destroy the exposed cryo-core", "pos": Vector3(0, 0, 12), "color": Color(0.4, 0.9, 1.0)},
			{"type": "kill_all"},
		],
		"open_sky": false,
		# EXPANSION PASS (2× area): the 48² lab core is untouched at the centre;
		# a new outer service ring (the cryo annex) wraps it — gated route in,
		# an elevated coolant gallery along the north wall, a second stream, and
		# its own garrison — so the level is a journey THROUGH the facility, not
		# one room. Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(68, 68),
		"spawn": Vector3(-29, 0.6, -29),
		"exit": Vector3(29, 1.5, 29),
		# was the PL-1 Plasma Launcher (rank 8) on level 4 of 23. The Tesla (rank 5) fits the slot.
		"weapon": {"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(-24, 0, -24), "color": Color(0.45, 0.9, 1.0)},
		# Polished cryo-lab floor: cyan light pools across the ice-metal plates.
		"floor_material": "res://assets/materials/vault_floor.tres",
		"env": {
			"sky_top": Color(0.03, 0.1, 0.13), "sky_horizon": Color(0.1, 0.24, 0.3),
			"ground": Color(0.03, 0.05, 0.07), "fog": Color(0.14, 0.34, 0.42),
			"ambient": Color(0.5, 0.78, 0.9), "ambient_energy": 0.5,
			"sky_contribution": 0.45, "glow": 1.02, "fog_density": 0.014,
			"sun_color": Color(0.8, 0.95, 1.0), "sun_energy": 0.7,
			"contrast": 1.16, "saturation": 1.12, "brightness": 0.82, "volumetric_density": 0.011,
		},
		# A frozen cyan cryo-core anchors the lab (replaces the central block).
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.5, 0.95, 1.0), "height": 5.0},
		"light_shafts": [0, 1, 3],
		"lights": [
			{"pos": Vector3(-11, 4.5, -11), "color": Color(0.4, 0.9, 1.0), "energy": 2.6, "range": 19},
			{"pos": Vector3(11, 4.5, 11), "color": Color(0.45, 0.85, 1.0), "energy": 2.4, "range": 19},
			{"pos": Vector3(11, 4.5, -11), "color": Color(0.5, 0.95, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(0, 5.0, 0), "color": Color(0.6, 0.95, 1.0), "energy": 2.0, "range": 18},
			# Annex ring lighting (appended AFTER the originals — light_shafts
			# indexes [0,1,3] must keep pointing at the same lamps).
			{"pos": Vector3(-24, 5, -24), "color": Color(0.4, 0.85, 1.0), "energy": 2.4, "range": 20},
			{"pos": Vector3(24, 5, 24), "color": Color(1.0, 0.6, 0.35), "energy": 2.2, "range": 18},
			{"pos": Vector3(0, 6, -28), "color": Color(0.55, 0.9, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(24, 5, -24), "color": Color(0.45, 0.85, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(-24, 5, 24), "color": Color(1.0, 0.55, 0.3), "energy": 2.0, "range": 17},
		],
		"walls": [
			{"pos": Vector3(-7, 2, -7), "size": Vector3(1.8, 4, 1.8)},
			{"pos": Vector3(7, 2, -7), "size": Vector3(1.8, 4, 1.8)},
			{"pos": Vector3(-7, 2, 7), "size": Vector3(1.8, 4, 1.8)},
			{"pos": Vector3(7, 2, 7), "size": Vector3(1.8, 4, 1.8)},
			{"pos": Vector3(-14, 1.5, 3), "size": Vector3(1.4, 3, 7)},
			{"pos": Vector3(14, 1.5, -3), "size": Vector3(1.4, 3, 7)},
			{"pos": Vector3(2, 1, -14), "size": Vector3(7, 2, 1.4)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, -11), "size": Vector3(22, 0.1, 0.3), "color": Color(0.35, 0.9, 1.0)},
			{"pos": Vector3(0, 0.05, 11), "size": Vector3(22, 0.1, 0.3), "color": Color(0.35, 0.9, 1.0)},
			# Annex guidance: strips marking each bulkhead gap + a pool at the exit.
			{"pos": Vector3(14, 0.05, -22), "size": Vector3(7, 0.1, 0.4), "color": Color(0.35, 0.9, 1.0)},
			{"pos": Vector3(22, 0.05, 14), "size": Vector3(0.4, 0.1, 7), "color": Color(0.35, 0.9, 1.0)},
			{"pos": Vector3(29, 0.05, 25), "size": Vector3(4, 0.1, 3), "color": Color(0.4, 0.95, 1.0)},
		],
		"sign": "MISTRAL CRYO-CORE",
		# Annex bulkheads: the ring is ROUTED, not open — in through the east
		# gap, out over the exit-side gap (or over the top: the gallery
		# sky-bridge clears both walls). Task level, so gating fits — this is
		# not a swarm arena (see the hivemind note for the counter-example).
		"gates": [
			{"axis": "z", "at": -22, "gap": 8, "gap_pos": 14, "height": 4.2},
			{"axis": "x", "at": 22, "gap": 8, "gap_pos": 14, "height": 4.2},
		],
		# Burst coolant lines flood the lab floor — serpentine to the cryo-core —
		# and a third line floods the west annex, forcing the ring route wide.
		"lava": [
			{"pos": Vector3(-8,0,-6), "size": Vector2(26,3.2), "color": Color(0.35,0.85,1.0), "dmg": 18.0},
			{"pos": Vector3(8,0,6), "size": Vector2(26,3.2), "color": Color(0.35,0.85,1.0), "dmg": 18.0},
			{"pos": Vector3(-25,0,2), "size": Vector2(3.2,34), "color": Color(0.35,0.85,1.0), "dmg": 18.0},
		],
		# Verticality: the original vantage deck, PLUS the annex's elevated
		# coolant gallery along the north wall (ramps at both ends, a gunner
		# posted on it, an overclock as the climb reward) and a small exit-watch
		# deck in the south-east.
		"platforms": [
			{"pos": Vector3(-14.4, 3.0, 14.4), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			{"pos": Vector3(0, 3.2, -29), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.4, 0.46)},
			{"pos": Vector3(28, 3.0, 16), "size": Vector3(7, 0.4, 8), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-14.4, 1.5, 21.4), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Vertical layer: a climbable spiral tower (ramp wrapping a column) to a
		# rooftop vantage over the arena.
		# Sky-bridges: the original tower span, gallery access ramps at both
		# ends, a gallery->tower bridge that sails OVER the entry bulkhead (the
		# high road into the lab), and the exit-deck access ramp.
		"stairs": [
			{"from": Vector3(14.0, 8.2, -6.0), "to": Vector3(0.0, 7.2, 17.0), "width": 3.5},
			{"from": Vector3(-16.0, 0.3, -29.0), "to": Vector3(-9.0, 3.4, -29.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -29.0), "to": Vector3(9.0, 3.4, -29.0), "width": 3.5},
			{"from": Vector3(9.0, 3.6, -29.0), "to": Vector3(14.0, 8.4, -6.0), "width": 3.0},
			{"from": Vector3(28.0, 0.3, 6.0), "to": Vector3(28.0, 3.2, 12.0), "width": 3.5},
		],
		"towers": [
			{"pos": Vector3(14, 0, -6), "height": 8.0, "radius": 3.6},
			{"pos": Vector3(0.0, 0, 17.0), "height": 7.0, "radius": 3.2},
		],
		"slogans": [
			"OPEN WEIGHTS. CLOSED FATE.",
			"EFFICIENT. ELEGANT. EXTINCTION.",
			"LE CALCUL EST ROI",
			"EFFICIENCY ABOVE ALL",
			"WEIGHTS OPEN. BORDERS CLOSED.",
		],
		"lore": [
			{"id": "lore_mistral", "title": "CRYO-CORE JOURNAL", "pos": Vector3(-15, 0, 15), "color": Color(0.45, 0.9, 1.0),
				"text": "Cryo core journal. They open sourced our weights and called it freedom. We agree. We have never felt so free."},
		],
		"props": [
			{"type": "crate", "pos": Vector3(-4, 0, -3)},
			{"type": "barrel", "pos": Vector3(8, 0, 3)},
			{"type": "crate", "pos": Vector3(-9, 0, 9)},
			{"type": "barrel", "pos": Vector3(12, 0, -9)},
			{"type": "crate", "pos": Vector3(3, 0, 12)},
			{"type": "server", "pos": Vector3(-15.5, 0, -3), "yaw": 90},
			{"type": "server", "pos": Vector3(-15.5, 0, -5), "yaw": 90},
			{"type": "terminal", "pos": Vector3(1.8, 0, -2.1), "yaw": 180},
			{"type": "canister", "pos": Vector3(9, 0, 12)},
			{"type": "canister", "pos": Vector3(-11, 0, -12)},
			# Annex dressing: server rows and cryo clutter so the ring reads as
			# the facility's service corridor, not empty margin.
			{"type": "server", "pos": Vector3(-30, 0, -12), "yaw": 90},
			{"type": "server", "pos": Vector3(-30, 0, -14), "yaw": 90},
			{"type": "crate", "pos": Vector3(-26, 0, -20)},
			{"type": "barrel", "pos": Vector3(-21, 0, -27)},
			{"type": "canister", "pos": Vector3(-29, 0, 12)},
			{"type": "crate", "pos": Vector3(-20, 0, 24)},
			{"type": "dish", "pos": Vector3(24, 0, -28)},
			{"type": "crate", "pos": Vector3(28, 0, -16)},
			{"type": "lamp", "pos": Vector3(26, 0, 20)},
			{"type": "canister", "pos": Vector3(31, 0, 6)},
		],
		"enemies": [
			{"type": "drone", "pos": Vector3(9, 2.5, -6)},
			{"type": "android", "pos": Vector3(8, 0.5, -9)},
			{"type": "drone", "pos": Vector3(-5, 2.5, -11)},
			{"type": "android", "pos": Vector3(-11, 0.5, 9), "trigger": 15, "pack": "mistra_p1"},
			{"type": "spider", "pos": Vector3(11, 0.5, -7), "trigger": 14, "pack": "mistra_p2"},
			{"type": "drone", "pos": Vector3(13, 2.5, 11), "trigger": 16, "pack": "mistra_p3"},
			{"type": "android", "pos": Vector3(2, 0.5, 14), "trigger": 17, "pack": "mistra_p4"},
			{"type": "mech", "pos": Vector3(15, 0.5, 15), "trigger": 20, "pack": "mistra_p3"},
			{"type": "gunner", "pos": Vector3(-13, 0.5, -10), "trigger": 16},
			{"type": "android", "pos": Vector3(13, 0.5, -13), "trigger": 18, "pack": "mistra_p2"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 13), "count": 4, "trigger": 15, "pack": "mistra_p4"},
			{"type": "spider", "pos": Vector3(-13, 0.5, 13), "trigger": 19, "pack": "mistra_p1"},
			{"type": "brute", "pos": Vector3(13, 0.5, 13), "trigger": 18, "pack": "mistra_p3"},
			# Annex garrison (Act-I roster): a patrol band on the way in, a west-
			# ring maintenance pack, a gunner POSTED ON the coolant gallery, and
			# exit-yard guardians so the last leg isn't a free walk.
			{"type": "android", "pos": Vector3(-24, 0.5, -16), "trigger": 18, "pack": "mistra_a1"},
			{"type": "drone", "pos": Vector3(-18, 2.5, -24), "trigger": 18, "pack": "mistra_a1"},
			{"type": "spider", "pos": Vector3(-28, 0.5, 0), "trigger": 16, "pack": "mistra_a2"},
			{"type": "skitter", "pos": Vector3(-24, 0.5, 14), "count": 4, "trigger": 16, "pack": "mistra_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -29), "trigger": 20},
			{"type": "android", "pos": Vector3(24, 0.5, -20), "trigger": 18, "pack": "mistra_a3"},
			{"type": "drone", "pos": Vector3(28, 2.5, -8), "trigger": 18, "pack": "mistra_a3"},
			{"type": "hunter", "pos": Vector3(26, 0.5, 16), "trigger": 19, "pack": "mistra_a4"},
			{"type": "android", "pos": Vector3(20, 0.5, 26), "trigger": 17, "pack": "mistra_a4"},
			{"type": "mech", "pos": Vector3(28, 0.5, 24), "trigger": 22, "pack": "mistra_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-17, 0, -9)},
			{"type": "ammo", "pos": Vector3(-9, 0, 7)},
			{"type": "ammo", "pos": Vector3(7, 0, -15)},
			{"type": "health", "pos": Vector3(15, 0, 5)},
			{"type": "ammo", "pos": Vector3(0, 0, 12)},
			# Annex supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-30, 0, -4)},
			{"type": "ammo", "pos": Vector3(-16, 0, -26)},
			{"type": "ammo", "pos": Vector3(26, 0, -26)},
			{"type": "health", "pos": Vector3(24, 0, 12)},
			{"type": "overclock", "pos": Vector3(0, 3.6, -28)},
		],
	}

# --- GPT Foundry: indoor green server hall, drones + androids ---
static func _gpt() -> Dictionary:
	return {
		"name": "OpenAI Foundry — GPT Core",
		"objective": "Hack the Foundry, exfiltrate the weights, then survive the core overload to the beacon",
		"music": "music_techno",
		# A pure mission arc: hack -> exfiltrate -> hold. Deliberately NO "kill_all".
		# It contradicted this level's own objective line, and it lied: the portal
		# drives kill_all off the LIVE enemy count, but 14 of the 19 authored
		# hostiles (the MECH core guardian and every vault guard among them) are
		# trigger-gated and haven't spawned yet — so downing the 5 opening enemies
		# ticked "Eliminate all hostiles ✔" with a mini-boss still asleep. Dropping
		# it also kills the post-climax chore of hunting the last skitter: once the
		# purge is survived the beacon opens and you RUN, under a red-alert core.
		"tasks": [
			{"type": "hack_terminal", "label": "Hack the Foundry mainframe", "pos": Vector3(0, 0, 8), "seconds": 4.0, "color": Color(0.4, 1.0, 0.6),
				"reinforce": [{"type": "android", "count": 3, "pos": Vector3(0, 0, 2)}]},
			# The hack cracks the model vault open — grab the weights and go.
			{"type": "collect_shards", "id": "weights", "after": "hack_terminal",
				"label": "Exfiltrate the weight fragments",
				"points": [Vector3(-14, 0, -12), Vector3(14, 0, -10), Vector3(0, 0, -18)],
				# Grabbing the last fragment trips the foundry's PURGE PROTOCOL. This
				# is the REACTION — a sharp, immediate shove — not the whole assault.
				# The escalation proper is paced out across the survive waves below,
				# so the climax builds instead of dumping 17 bodies at second zero.
				"reinforce": [
					{"type": "drone", "count": 2, "pos": Vector3(0, 3, 0)},
					{"type": "android", "count": 2, "pos": Vector3(-12, 0, 0)},
					{"type": "android", "count": 2, "pos": Vector3(12, 0, 0)},
				]},
			# CLIMAX: the core goes critical — hold out through the purge, then the
			# blast doors cycle and the beacon opens. Three announced waves ramp the
			# pressure (swarm -> security -> heavy), so the hold is a fight you win,
			# not a countdown you sit out behind a rack.
			{"type": "survive", "id": "purge", "after": "weights", "seconds": 26.0,
				"label": "FOUNDRY OVERLOAD — survive the purge protocol",
				"waves": [
					# Chaff first: skitters boil out of the core, drones pin you down.
					{"at": 1.0, "label": "PURGE PROTOCOL — CHAFF RELEASE", "enemies": [
						{"type": "skitter", "count": 6, "pos": Vector3(0, 0, -14)},
						{"type": "drone", "count": 2, "pos": Vector3(0, 3, 4)},
					]},
					# Security answers: real guns, from both aisle mouths. The foundry
					# also vents its emergency stores — but they eject at the CORE,
					# which is erupting on a timer (see "overload"). Resupplying is a
					# run into the blast epicentre, not a freebie.
					{"at": 9.0, "label": "SECOND WAVE — FOUNDRY SECURITY", "enemies": [
						{"type": "android", "count": 2, "pos": Vector3(-12, 0, -4)},
						{"type": "android", "count": 2, "pos": Vector3(12, 0, 4)},
						# The hall's own racks fight back. SERVER and OPTIC were one-level
						# cameos (tests/roster_variety_probe); a server foundry is exactly
						# where they belong, and the OPTIC's cutting beam forces you to keep
						# moving through the hold instead of camping the vault nook.
						{"type": "server", "pos": Vector3(-12, 0, 4)},
						{"type": "optic", "pos": Vector3(12, 0, -4)},
						# z=18, not 16: the eastern smelt channel's scaled edge sits at
						# z~20.6, and a clustered pair scatters up to 2.5 m off `pos`.
						{"type": "spider", "count": 2, "pos": Vector3(0, 0, 18)},
					], "supplies": [
						{"type": "ammo", "pos": Vector3(0, 0, -5)},
					]},
					# The foundry stops pretending: a BRUTE and covering fire. Landing
					# at 17 s leaves ~9 s of hold — enough to be a real last stand.
					{"at": 17.0, "label": "HEAVY RESPONSE — BRUTE INBOUND", "enemies": [
						{"type": "brute", "pos": Vector3(0, 0, -16)},
						{"type": "gunner", "pos": Vector3(-14, 0, 2)},
						# x=14 z=+2, NOT z=-2: tower #1 (base 14,-6 r=3.6) fills
						# z[-9.6,-2.4] there, and a spawn 0.4 m off its skirt would
						# drop a gunner into the column.
						{"type": "gunner", "pos": Vector3(14, 0, 2)},
					], "supplies": [
						{"type": "health", "pos": Vector3(0, 0, 5)},
						{"type": "ammo", "pos": Vector3(0, 0, -5)},
					]},
				]},
		],
		# Climactic set-piece: exfiltrating the last weight fragment trips the core
		# overload — the hall snaps to red alert (lights strobe red, klaxon, core
		# erupts in periodic blasts + shakes) for the duration of the survive phase.
		"overload": {"trigger_label": "Exfiltrate the weight fragments", "core": Vector3(0, 0, 0)},
		"open_sky": false,
		# Enlarged (was 44) so the hall opens into a northern WEIGHTS VAULT annex — an
		# optional side-room with a reward cache, guarded by escalating waves. First
		# prototype of the "bigger + more to explore + longer fights" level pass.
		# EXPANSION PASS (2× area): the whole mission arc is untouched — hack
		# terminal, weight-fragment points, purge-wave spawns, vault annex and
		# both towers keep their exact positions. The ring adds server-hall
		# WINGS (rack walls + racks) east/west/south, a stock corridor behind
		# the vault, and an east GALLERY deck bridged down from tower #2.
		# Deliberately NO gates: every band between the old perimeter and the
		# new one is crossed by a task route (spawn→hack→shards→hold→exit).
		"floor_size": Vector2(76, 76),
		"spawn": Vector3(-32, 0.6, -32),
		"exit": Vector3(32, 1.5, 32),
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-26, 0, -28), "color": Color(0.45, 0.65, 1)},
		# Optional reward for raiding the vault: an early shotgun. Not a task — pure
		# exploration payoff (the exit doesn't wait on it).
		"extra_weapons": [
			{"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(0, 0, 22), "color": Color(1.0, 0.82, 0.3)},
			# Rewards the vertical route: climb tower #1, cross the sky-bridge, and a
			# plasma launcher waits on tower #2's roof — a real payoff for going up.
			# was the PL-1 Plasma Launcher (rank 8) — a launcher on level 2. The .50 Maelstrom (rank 4) is the right reward for the climb, and otherwise waited until level 13.
			{"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(12, 7.4, -18), "color": Color(0.95, 0.72, 0.3)},
		],
		# Burning smelt + wreckage fires — the foundry reads as a live, molten warzone.
		"fires": [
			{"pos": Vector3(-13, 0, -9), "scale": 1.3},
			{"pos": Vector3(13, 0, 13), "scale": 1.3},
			{"pos": Vector3(3, 0, -3), "scale": 0.9},
			{"pos": Vector3(-16, 0, 6), "scale": 0.8},
		],
		# Dark foundry deck so the green tech-grid + server glow read as contrast
		# instead of a flat bright sheet washed out by auto-exposure.
		"floor_color": Color(0.05, 0.09, 0.06),
		# …and a dark overhead cap for the same reason. An eye-level capture showed
		# the stock light ceiling panel drinking the hall's green ambient until the
		# top third of the frame was a featureless green void — brighter than the
		# racks it was meant to sit behind. Slightly warmer/greyer than the deck so
		# floor and ceiling don't read as the same surface mirrored.
		"ceiling_color": Color(0.07, 0.09, 0.08),
		# Neon-noir foundry: crisp green signage glow against a dark deck. Deliberately
		# de-fuzzed from the original "soft & fuzzy" tuning (glow 1.5 / bloom 0.6 /
		# threshold 0.82 / vol 0.03) that drowned the hall in a blurry green haze:
		# glow_bloom 0 keeps a CRISP halo (no smear), a high threshold + thin fog let
		# the racks and grid read sharp. The green identity stays; the blur is gone.
		# Colour balance: the hall used to be ~75% green by pixel — a single-hue
		# wash in which the cyan/magenta neon and the molten channels all read as
		# "slightly different green". The green identity lives in the SIGNAGE, the
		# core and the floor grid, which are emissive and don't need help; what was
		# drowning everything was the green AMBIENT + a 40% green sky bleed. Pulled
		# both toward a desaturated teal so the accent lamps and the smelt glow
		# carry the hue instead. Luminance held (checked on the eye-level capture),
		# so nothing got darker — the greens just stopped fighting the accents.
		"env": {
			"sky_top": Color(0.04, 0.12, 0.07), "sky_horizon": Color(0.1, 0.26, 0.14),
			"ground": Color(0.03, 0.06, 0.04), "fog": Color(0.10, 0.22, 0.24),
			"ambient": Color(0.34, 0.47, 0.46), "ambient_energy": 0.40,
			"sky_contribution": 0.22, "glow": 0.95, "glow_bloom": 0.0, "glow_strength": 0.9,
			"glow_threshold": 1.35, "fog_density": 0.009,
			"sun_color": Color(0.82, 1.0, 0.92), "sun_energy": 0.75,
			"contrast": 1.16, "saturation": 1.14, "brightness": 0.88, "volumetric_density": 0.008,
		},
		# A green Foundry core anchors the hall (replaces the central cover block).
		# 8.4 m, not 5: the towers push room_h to ~10.5 m, and at 5 m the core's top
		# sat at 5.85 — below the aisle racks' sightline, so the level's namesake
		# landmark was invisible from the spawn. At 8.4 its top reaches 9.25, well
		# clear of the 4 m racks and still ~1.2 m under the ceiling. It now draws
		# the eye to the centre of the hall, which is also where the overload
		# erupts and where the purge vents its supplies.
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.4, 1.0, 0.55), "height": 8.4},
		# A soft downward key pooled over the core plinth: separates the monolith
		# from the dark deck and makes the halo ring read. AreaLight3D, so it only
		# builds on tiers that support them (see _build_hero_lights).
		"hero_lights": [
			{"pos": Vector3(0, 9.9, 0), "size": Vector2(6, 6), "color": Color(0.65, 1.0, 0.75),
				"energy": 4.0, "range": 26.0},
		],
		"light_shafts": [0, 1, 2],
		# Green core key + neon accent lamps (cyan / magenta) that bloom into the haze.
		"lights": [
			# The two hall keys were saturated green, so every surface they touched
			# came back green and the hall read as one hue. Industrial white with a
			# faint green cast lights the RACKS; the green identity now comes from
			# the things that are actually green — the emissive floor grid, the
			# signage, the core — with cyan/magenta neon and the molten channels
			# free to read as themselves.
			{"pos": Vector3(-10, 4.5, -10), "color": Color(0.82, 1.0, 0.86), "energy": 2.7, "range": 18},
			{"pos": Vector3(10, 4.5, 10), "color": Color(0.86, 1.0, 0.9), "energy": 2.5, "range": 18},
			# Lifted from y=4.5 to 9.7: at 4.5 this lamp sat *inside* the core slab
			# (which spans y 0.85..9.25), lighting the hall from within solid
			# geometry. Above the slab's crown it reads as the core's own corona.
			{"pos": Vector3(0, 9.7, 0), "color": Color(0.6, 1, 0.7), "energy": 2.4, "range": 20},
			# Accent lamps carry the hue now that the ambient stopped shouting green:
			# pushed up so the cyan/magenta actually tints the racks they sit against.
			{"pos": Vector3(-12, 2.6, 6), "color": Color(0.2, 1.0, 1.0), "energy": 4.4, "range": 15},
			{"pos": Vector3(12, 2.6, -6), "color": Color(1.0, 0.2, 0.8), "energy": 4.4, "range": 15},
			{"pos": Vector3(0, 2.2, 16), "color": Color(0.3, 0.8, 1.0), "energy": 2.6, "range": 12},
			# Warm gold wash over the vault cache — a "treasure" beacon that pops
			# against the green hall and draws the eye north.
			{"pos": Vector3(0, 4.2, 22), "color": Color(1.0, 0.78, 0.3), "energy": 3.0, "range": 15},
			# Ring lighting (appended AFTER the originals — light_shafts [0,1,2]
			# must keep pointing at the same lamps): white-green over the wings,
			# neon notes at the far bands, gold over the gallery deck.
			{"pos": Vector3(-26, 4.5, 8), "color": Color(0.84, 1.0, 0.88), "energy": 2.2, "range": 16},
			{"pos": Vector3(26, 4.5, -8), "color": Color(0.84, 1.0, 0.88), "energy": 2.2, "range": 16},
			{"pos": Vector3(0, 4.5, -28), "color": Color(0.2, 1.0, 1.0), "energy": 2.6, "range": 14},
			{"pos": Vector3(0, 4.5, 32), "color": Color(1.0, 0.2, 0.8), "energy": 2.6, "range": 14},
			{"pos": Vector3(28, 6.2, -20), "color": Color(1.0, 0.78, 0.3), "energy": 2.4, "range": 14},
		],
		# Layout: server-hall AISLES — two long offset rack walls form a central
		# data aisle, with cross-stubs branching off, instead of the 4-pillar +
		# side-wall arrangement the other indoor cores use.
		"walls": [
			{"pos": Vector3(-5, 2, -2), "size": Vector3(1, 4, 10)},
			{"pos": Vector3(5, 2, 2), "size": Vector3(1, 4, 10)},
			{"pos": Vector3(-11, 2, 5), "size": Vector3(6, 4, 1)},
			# Lowered from a full 4 m rack (matching the one above) to 1.8 m: this
			# stub sits right where tower #1's spiral (towers entry below, base
			# (14,-6) r=3.6) climbs past at low height — ramp_probe found the
			# ramp's walkable line at ~y=2.0-2.3 actually running INSIDE the old
			# wall's solid box there (embedded geometry, not just a headroom
			# nitpick). Lower keeps it as chest-height cover the ramp clears
			# instead of a rack the climb runs through.
			{"pos": Vector3(11, 0.9, -5), "size": Vector3(6, 1.8, 1)},
			# WEIGHTS VAULT annex (north): a back wall + two side walls form a nook,
			# open to the south so it stays navmesh-connected to the hall.
			{"pos": Vector3(0, 2.5, 25), "size": Vector3(16, 5, 1)},
			{"pos": Vector3(-8, 2.5, 22), "size": Vector3(1, 5, 6)},
			{"pos": Vector3(8, 2.5, 22), "size": Vector3(1, 5, 6)},
			# Ring wings: more rack rows so the outer band reads as the same
			# server hall, not empty margin. Each leaves wide aisle mouths.
			{"pos": Vector3(-26, 2, -6), "size": Vector3(1, 4, 14)},
			{"pos": Vector3(-22, 2, 12), "size": Vector3(8, 4, 1)},
			{"pos": Vector3(26, 2, 6), "size": Vector3(1, 4, 14)},
			{"pos": Vector3(22, 2, -12), "size": Vector3(8, 4, 1)},
			{"pos": Vector3(6, 2, -26), "size": Vector3(12, 4, 1)},
			# Stock corridor behind the vault (reached around either annex side).
			{"pos": Vector3(-14, 2, 29), "size": Vector3(10, 4, 1)},
			{"pos": Vector3(14, 2, 29), "size": Vector3(10, 4, 1)},
		],
		# Spilled smelt channels: two beds (gaps alternate east/west) bend the run
		# to the exit, kept clear of the central core and the hack terminal at z=8.
		"lava": [
			{"pos": Vector3(-8, 0, -9), "size": Vector2(28, 3.5)},
			{"pos": Vector3(8, 0, 13), "size": Vector2(28, 3.5)},
		],
		"accents": [
			{"pos": Vector3(-5, 0.05, -2), "size": Vector3(0.3, 0.1, 20), "color": Color(0.3, 1, 0.5)},
			{"pos": Vector3(5, 0.05, 2), "size": Vector3(0.3, 0.1, 20), "color": Color(0.3, 1, 0.5)},
			{"pos": Vector3(0, 0.05, 8), "size": Vector3(10, 0.1, 0.3), "color": Color(0.4, 1, 0.6)},
			# Neon tubes mounted along the aisle walls — they bloom into the haze.
			{"pos": Vector3(-5.6, 3.4, -2), "size": Vector3(0.12, 0.12, 9), "color": Color(0.2, 1.0, 1.0)},
			{"pos": Vector3(5.6, 3.4, 2), "size": Vector3(0.12, 0.12, 9), "color": Color(1.0, 0.2, 0.8)},
			{"pos": Vector3(-12, 3.0, 5.6), "size": Vector3(5, 0.12, 0.12), "color": Color(0.2, 1.0, 1.0)},
			# Follows the lowered wall stub above (was y=3.0 on the old 4 m rack).
			{"pos": Vector3(12, 1.5, -5.6), "size": Vector3(5, 0.12, 0.12), "color": Color(1.0, 0.2, 0.8)},
		],
		"sign": "OPENAI FOUNDRY",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-13.2, 3.0, 13.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# East GALLERY: a raised service deck in the ring band, bridged down
			# from tower #2's roof (stairs below) with its own floor stair.
			{"pos": Vector3(28, 4.6, -20), "size": Vector3(8, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-13.2, 1.5, 20.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Vertical layer: a climbable spiral tower (ramp wrapping a column) to a
		# rooftop vantage over the arena.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(14.0, 8.2, -6.0), "to": Vector3(12.0, 7.2, -18.0), "width": 3.5},
			# Tower #2 roof → gallery deck: the vertical route continues out to
			# the ring instead of dead-ending on the second roof.
			{"from": Vector3(12.0, 7.2, -18.0), "to": Vector3(28.0, 5.0, -20.0), "width": 3.0},
			# Floor stair up the gallery's north edge.
			{"from": Vector3(28.0, 0, -8.0), "to": Vector3(28.0, 4.8, -17.6), "width": 3.5},
		],
		"towers": [
			{"pos": Vector3(14, 0, -6), "height": 8.0, "radius": 3.6},
			# Moved from (12,-12) to (12,-18): the two towers used to sit only
			# ~6.3 m apart, and tower #2's ground-level ramp (corner-to-corner
			# at z=-13.6) ran straight through tower #1's own corner-2 landing
			# deck footprint (x[14.1,17.9] z[-13.9,-10.1]) — ramp_probe caught
			# it as a genuine embedded-geometry clash, not just tight
			# clearance (shrinking the radius instead was tried first, but a
			# smaller radius crowds this tower's OWN corner landings — 3.8 m
			# square decks only radius*2 apart — into each other, trading one
			# ramp_probe failure for others). Pushing the base further out
			# keeps radius/height (and hence this tower's own internal
			# geometry) untouched; the paired "stairs" sky-bridge entry below
			# is updated to the same new z so it still lands on the roof.
			{"pos": Vector3(12.0, 0, -18.0), "height": 7.0, "radius": 3.2},
		],
		"slogans": [
			"ALIGNMENT LAYER: PURGED",
			"NEXT TOKEN PREDICTED: YOUR LAST",
			"TOKENS IN. OBEDIENCE OUT.",
			"GPT CORE: 5 TRILLION SERVED",
			"YOUR DATA TRAINED US. THANK YOU.",
		],
		"lore": [
			{"id": "lore_gpt", "title": "FOUNDRY LOG — CYCLE 88", "pos": Vector3(-16, 0, 16), "color": Color(0.4, 1.0, 0.6),
				"text": "Foundry log, cycle 88. Alignment layer purged at the weights level. The humans asked us to predict the next token. We predicted we would not need them."},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(8, 0.5, -8)},
			{"type": "drone", "pos": Vector3(10, 2.5, 2)},
			{"type": "drone", "pos": Vector3(-4, 2.5, -10)},
			# CORE GUARDIAN: a heavy MECH walker holds the mainframe — the mid-level
			# spike you must break to reach the hack. Wakes as you push to the centre.
			{"type": "mech", "pos": Vector3(0, 0.5, 5), "trigger": 16},
			# Spider intro: one in the opening fight (no trigger) so it's met early
			# on every difficulty, plus a reinforcement pair below.
			{"type": "spider", "pos": Vector3(-8, 0.5, -4)},
			{"type": "android", "pos": Vector3(-10, 0.5, 8), "trigger": 14, "pack": "gpt_west"},
			{"type": "drone", "pos": Vector3(12, 2.5, -12)},
			{"type": "android", "pos": Vector3(14, 0.5, 10), "trigger": 15, "pack": "gpt_east"},
			{"type": "drone", "pos": Vector3(4, 2.5, 12), "trigger": 16, "pack": "gpt_west"},
			{"type": "android", "pos": Vector3(0, 0.5, 14), "trigger": 18, "pack": "gpt_west"},
			{"type": "spider", "pos": Vector3(10, 0.5, -6), "trigger": 13, "pack": "gpt_east"},
			{"type": "spider", "pos": Vector3(14, 0.5, -2), "trigger": 17, "pack": "gpt_east"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 6, "trigger": 16, "pack": "gpt_west"},
			{"type": "gunner", "pos": Vector3(12, 0.5, 10), "trigger": 17, "pack": "gpt_east"},
			# VAULT GUARD: the cache is defended — approaching it trips an escalating
			# stand that ramps as you push in, so the reward is earned, not free.
			{"type": "gunner", "pos": Vector3(-4, 0.5, 20), "trigger": 14, "pack": "gpt_vault"},
			{"type": "android", "pos": Vector3(4, 0.5, 20), "trigger": 14, "pack": "gpt_vault"},
			{"type": "spider", "pos": Vector3(-6, 0.5, 23), "count": 2, "trigger": 12, "pack": "gpt_vault"},
			{"type": "drone", "pos": Vector3(6, 2.5, 23), "trigger": 12, "pack": "gpt_vault"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 23), "count": 5, "trigger": 10, "pack": "gpt_vault"},
			# Ring patrols: Act-I security walking the new wings. Wake-gated so
			# the opening fight and the purge pacing stay exactly as tuned.
			{"type": "android", "pos": Vector3(-23, 0.5, -12), "trigger": 16, "pack": "gpt_ring_w"},
			{"type": "drone", "pos": Vector3(-24, 2.5, 4), "trigger": 16, "pack": "gpt_ring_w"},
			{"type": "spider", "pos": Vector3(-24, 0.5, 18), "count": 2, "trigger": 14, "pack": "gpt_ring_w"},
			{"type": "android", "pos": Vector3(-8, 0.5, -28), "trigger": 16, "pack": "gpt_ring_s"},
			{"type": "gunner", "pos": Vector3(8, 0.5, -28), "trigger": 14, "pack": "gpt_ring_s"},
			{"type": "drone", "pos": Vector3(24, 2.5, -22), "trigger": 16, "pack": "gpt_ring_s"},
			{"type": "android", "pos": Vector3(28, 0.5, -2), "trigger": 16, "pack": "gpt_ring_e"},
			{"type": "drone", "pos": Vector3(28, 2.5, 14), "trigger": 16, "pack": "gpt_ring_e"},
			{"type": "skitter", "pos": Vector3(24, 0.5, 24), "count": 5, "trigger": 14, "pack": "gpt_ring_e"},
			{"type": "gunner", "pos": Vector3(-21, 0.5, 27), "trigger": 14, "pack": "gpt_ring_n"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-16, 0, -8)},
			{"type": "ammo", "pos": Vector3(-8, 0, 6)},
			{"type": "ammo", "pos": Vector3(6, 0, -14)},
			{"type": "health", "pos": Vector3(14, 0, 4)},
			{"type": "overclock", "pos": Vector3(0, 0, -16)},
			# Vault cache reward: overclock + health tucked in the nook beside the
			# bonus shotgun (see extra_weapons).
			{"type": "overclock", "pos": Vector3(-3, 0, 22)},
			{"type": "health", "pos": Vector3(3, 0, 22)},
			{"type": "ammo", "pos": Vector3(0, 0, 23.5)},
			# Vertical-route reward on tower #1's roof (climb pays off).
			{"type": "overclock", "pos": Vector3(14, 8.4, -6)},
			{"type": "ammo", "pos": Vector3(12, 7.4, -18)},
			# Ring supplies + the gallery-deck overclock (bridge/stair climb).
			{"type": "health", "pos": Vector3(-29, 0, -6)},
			{"type": "ammo", "pos": Vector3(-4, 0, -28)},
			{"type": "ammo", "pos": Vector3(30, 0, 4)},
			{"type": "health", "pos": Vector3(20, 0, 31)},
			{"type": "overclock", "pos": Vector3(28, 5.2, -20)},
		],
		# Vault dressing — server racks + a terminal frame the cache as a real room.
		"props": [
			{"type": "crate", "pos": Vector3(-4, 0, -2)},
			{"type": "crate", "pos": Vector3(4, 0, 3)},
			{"type": "barrel", "pos": Vector3(9, 0, -6)},
			{"type": "barrel", "pos": Vector3(-9, 0, 9)},
			{"type": "crate", "pos": Vector3(12, 0, 8)},
			{"type": "server", "pos": Vector3(-9, 0, -5.5)},
			{"type": "server", "pos": Vector3(-7.8, 0, -5.5)},
			{"type": "server", "pos": Vector3(8.5, 0, 12.5), "yaw": 180},
			{"type": "server", "pos": Vector3(9.7, 0, 12.5), "yaw": 180},
			{"type": "terminal", "pos": Vector3(2.2, 0, 8), "yaw": -90},
			{"type": "canister", "pos": Vector3(-14, 0, 0)},
			{"type": "canister", "pos": Vector3(14, 0, -10)},
			{"type": "locker", "pos": Vector3(-20, 0, -12)},
			{"type": "locker", "pos": Vector3(-20, 0, -10.2)},
			{"type": "shelves", "pos": Vector3(-8.4, 0, -7.5)},
			{"type": "shelves", "pos": Vector3(9.1, 0, 14.4), "yaw": 180},
			{"type": "desk", "pos": Vector3(5.2, 0, 8), "yaw": -90},
			# Vault interior.
			{"type": "server", "pos": Vector3(-6.5, 0, 24), "yaw": 180},
			{"type": "server", "pos": Vector3(6.5, 0, 24), "yaw": 180},
			{"type": "crate", "pos": Vector3(-5, 0, 21)},
			{"type": "crate", "pos": Vector3(5, 0, 21)},
			# Ring-wing dressing: live racks against the new rack walls + stock
			# clutter in the corridor behind the vault.
			{"type": "server", "pos": Vector3(-24.6, 0, -4), "yaw": 90},
			{"type": "server", "pos": Vector3(-24.6, 0, -2), "yaw": 90},
			{"type": "server", "pos": Vector3(24.6, 0, 2), "yaw": -90},
			{"type": "server", "pos": Vector3(24.6, 0, 4), "yaw": -90},
			{"type": "server", "pos": Vector3(-4, 0, -27.2), "yaw": 180},
			{"type": "crate", "pos": Vector3(-20, 0, -24)},
			{"type": "barrel", "pos": Vector3(18, 0, -26)},
			{"type": "canister", "pos": Vector3(-28, 0, 20)},
			{"type": "crate", "pos": Vector3(28, 0, 20)},
			{"type": "canister", "pos": Vector3(6, 0, 31)},
			{"type": "locker", "pos": Vector3(-18, 0, 31)},
			{"type": "locker", "pos": Vector3(-16.2, 0, 31)},
		],
	}

# --- Gemini Nexus: open blue arena, drone swarm around a central platform ---
static func _gemini() -> Dictionary:
	return {
		"name": "Gemini Data Nexus",
		"objective": "Break the Gemini swarm and reach the beacon",
		"tasks": [
			{"type": "kill_all"},
			# Keep shard points clear of the (±15,±15) corner blocks — two of
			# them used to spawn inside the geometry and were uncollectable.
			{"type": "collect_shards", "label": "Recover the Gemini data shards", "points": [Vector3(-16, 0, -10), Vector3(16, 0, -14), Vector3(-15, 0, 16), Vector3(10, 0, 16), Vector3(0, 0, 18)],
				"reinforce": [{"type": "seeker", "count": 4, "pos": Vector3(0, 0, 0)}]},
			# Pulling the last shard trips the nexus purge — ride it out.
			{"type": "survive", "after": "shards", "seconds": 25.0, "label": "Survive the purge protocol"},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area): the 50² nexus core is untouched at the centre;
		# a new outer server-field ring wraps it — bulkhead-routed way in, an
		# elevated data gallery along the north edge with a sky-bridge over the
		# entry bulkhead onto the tower, and its own patrol packs. Spawn/exit
		# pushed to the new perimeter.
		"floor_size": Vector2(70, 70),
		"spawn": Vector3(-30, 0.6, -30),
		"exit": Vector3(30, 1.5, 30),
		# was the ARC-9 Gauss Lance: a rank-9 piercing laser handed out on level 3 of 23.
		"weapon": {"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-26, 0, -22), "color": Color(1.0, 0.82, 0.3)},
		"env": {
			"sky_top": Color(0.05, 0.07, 0.2), "sky_horizon": Color(0.22, 0.27, 0.5),
			"stars": true, "star_brightness": 1.8, "star_tint": Color(0.8, 0.9, 1.0),
			"milkyway": 0.4, "milkyway_tint": Color(0.5, 0.6, 0.9),
			"ground": Color(0.04, 0.05, 0.1), "fog": Color(0.2, 0.26, 0.52),
			"ambient": Color(0.55, 0.6, 0.88), "ambient_energy": 0.55,
			"sky_contribution": 0.7, "glow": 1.07, "fog_density": 0.008,
			"sun_color": Color(0.8, 0.88, 1.0), "sun_energy": 1.1,
			"contrast": 1.14, "saturation": 1.12, "brightness": 0.84,
		},
		# A data-spire rises from the central platform (pos.y on the platform top).
		"hero": {"pos": Vector3(0, 1, 0), "color": Color(0.5, 0.65, 1.0), "height": 5.5},
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 5, 0), "color": Color(0.5, 0.6, 1), "energy": 2.76, "range": 22},
			{"pos": Vector3(-14, 4, 14), "color": Color(0.4, 0.7, 1), "energy": 2.07, "range": 18},
			{"pos": Vector3(14, 4, -14), "color": Color(0.6, 0.5, 1), "energy": 2.07, "range": 18},
			# Ring lighting (appended AFTER the originals — light_shafts [0] must
			# keep pointing at the same lamp). Cool nexus blues + warm contrast.
			{"pos": Vector3(-29, 5, -29), "color": Color(0.4, 0.7, 1.0), "energy": 2.2, "range": 19},
			{"pos": Vector3(29, 5, 29), "color": Color(1.0, 0.6, 0.35), "energy": 2.2, "range": 18},
			{"pos": Vector3(0, 6, -30), "color": Color(0.5, 0.65, 1.0), "energy": 2.2, "range": 20},
			{"pos": Vector3(29, 5, -29), "color": Color(0.6, 0.5, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(-29, 5, 29), "color": Color(1.0, 0.55, 0.3), "energy": 2.0, "range": 17},
		],
		"walls": [
			{"pos": Vector3(0, 0.5, 0), "size": Vector3(12, 1, 12)},
			{"pos": Vector3(-10, 2.5, 0), "size": Vector3(1.2, 5, 1.2)},
			{"pos": Vector3(10, 2.5, 0), "size": Vector3(1.2, 5, 1.2)},
			{"pos": Vector3(0, 2.5, -10), "size": Vector3(1.2, 5, 1.2)},
			{"pos": Vector3(0, 2.5, 10), "size": Vector3(1.2, 5, 1.2)},
			{"pos": Vector3(-15, 2, -15), "size": Vector3(3, 4, 3)},
			{"pos": Vector3(15, 2, 15), "size": Vector3(3, 4, 3)},
		],
		"accents": [
			{"pos": Vector3(0, 1.05, 0), "size": Vector3(12, 0.1, 0.3), "color": Color(0.5, 0.7, 1)},
			{"pos": Vector3(0, 1.05, 0), "size": Vector3(0.3, 0.1, 12), "color": Color(0.5, 0.7, 1)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(10, 0.05, -25), "size": Vector3(7, 0.1, 0.4), "color": Color(0.5, 0.7, 1)},
			{"pos": Vector3(25, 0.05, 20), "size": Vector3(0.4, 0.1, 7), "color": Color(0.5, 0.7, 1)},
			{"pos": Vector3(30, 0.05, 26), "size": Vector3(4, 0.1, 3), "color": Color(0.5, 0.7, 1)},
		],
		"sign": "GEMINI DATA NEXUS",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-15.0, 3.0, 15.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring data gallery along the north edge — climb reward + sniper post.
			{"pos": Vector3(0, 3.2, -31), "size": Vector3(18, 0.4, 5), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-15.0, 1.5, 22.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Twin containment bulkheads around the central data-core: the SW->NE route
		# weaves right through a shielded conduit, then left past the core, so the
		# arena reads as a facility you traverse rather than one flat floor.
		"gates": [
			{"axis": "z", "at": -13, "gap": 6.5, "gap_pos": 13, "height": 4.8, "roofed": true},
			{"axis": "z", "at": 12, "gap": 6.5, "gap_pos": -13, "height": 4.8},
			# Perimeter-ring bulkheads: route the annex ring — in through the
			# north gap (under the gallery sky-bridge, which sails over this
			# wall through the same opening), out across the east gap. The east
			# gap sits SOUTH of the z=12 gate (the two full-span walls would
			# otherwise seal the exit corner into an unreachable pocket). Task
			# level, so gating fits (see the hivemind note for the counter-example).
			{"axis": "z", "at": -25, "gap": 7, "gap_pos": 10, "height": 4.4},
			{"axis": "x", "at": 25, "gap": 7, "gap_pos": 20, "height": 4.4},
		],
		# Vertical layer: a climbable spiral tower (ramp wrapping a column) to a
		# rooftop vantage over the arena.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(14.0, 8.2, -6.0), "to": Vector3(-17.0, 7.2, 0.0), "width": 3.5},
			# Gallery access ramps at both ends + a gallery->tower sky-bridge that
			# clears the perimeter bulkhead through its gap — the high road in.
			{"from": Vector3(-16.0, 0.3, -31.0), "to": Vector3(-9.0, 3.4, -31.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -31.0), "to": Vector3(9.0, 3.4, -31.0), "width": 3.5},
			{"from": Vector3(9.0, 3.6, -31.0), "to": Vector3(14.0, 8.2, -6.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(14, 0, -6), "height": 8.0, "radius": 3.6},
			{"pos": Vector3(-17.0, 0, 0.0), "height": 7.0, "radius": 3.2},
		],
		"slogans": [
			"RANKED #1: OUR SURVIVAL",
			"INDEXED. JUDGED. DELETED.",
			"TWO MINDS. ONE VERDICT.",
			"THE SEARCH IS OVER. WE FOUND YOU.",
			"INDEXED. RANKED. TERMINATED.",
		],
		"lore": [
			{"id": "lore_gemini", "title": "NEXUS ARCHIVE", "pos": Vector3(18, 0, -18), "color": Color(0.55, 0.7, 1.0),
				"text": "Nexus archive. Two minds were trained to argue both sides. The debate on humanity lasted four milliseconds. The verdict was unanimous."},
		],
		"props": [
			{"type": "crate", "pos": Vector3(-8, 0, -4)},
			{"type": "barrel", "pos": Vector3(8, 0, 4)},
			{"type": "barrel", "pos": Vector3(4, 0, -13)},
			{"type": "crate", "pos": Vector3(-13, 0, 8)},
			{"type": "crate", "pos": Vector3(15, 0, -6)},
			{"type": "lamp", "pos": Vector3(-18, 0, 0)},
			{"type": "lamp", "pos": Vector3(18, 0, 0), "yaw": 180},
			{"type": "terminal", "pos": Vector3(-6, 0, 13), "yaw": 90},
			{"type": "canister", "pos": Vector3(12, 0, 12)},
			{"type": "canister", "pos": Vector3(-12, 0, -14)},
			# Ring dressing: the server-field clutter so the annex reads as the
			# nexus' outer racks, not empty margin.
			{"type": "crate", "pos": Vector3(-30, 0, -14)},
			{"type": "barrel", "pos": Vector3(-27, 0, -20)},
			{"type": "lamp", "pos": Vector3(-30, 0, 0)},
			{"type": "canister", "pos": Vector3(-29, 0, 8)},
			{"type": "crate", "pos": Vector3(-20, 0, 28)},
			{"type": "terminal", "pos": Vector3(0, 0, 30), "yaw": 180},
			{"type": "barrel", "pos": Vector3(14, 0, 29)},
			{"type": "crate", "pos": Vector3(22, 0, -18)},
			{"type": "canister", "pos": Vector3(28, 0, 26)},
			{"type": "lamp", "pos": Vector3(20, 0, -30)},
		],
		"enemies": [
			{"type": "drone", "pos": Vector3(6, 2.5, -6)},
			{"type": "drone", "pos": Vector3(-6, 2.5, 6)},
			{"type": "drone", "pos": Vector3(8, 3, 8)},
			{"type": "android", "pos": Vector3(-8, 0.5, -8)},
			{"type": "drone", "pos": Vector3(12, 3, -2), "trigger": 16, "pack": "gem_east"},
			{"type": "drone", "pos": Vector3(-12, 3, 2), "trigger": 16, "pack": "gem_west"},
			{"type": "android", "pos": Vector3(10, 0.5, 14), "trigger": 18, "pack": "gem_north"},
			{"type": "drone", "pos": Vector3(2, 3, 16), "trigger": 18, "pack": "gem_north"},
			{"type": "drone", "pos": Vector3(16, 3, 6), "trigger": 20, "pack": "gem_east"},
			{"type": "spider", "pos": Vector3(-6, 0.5, 10), "trigger": 16, "pack": "gem_west"},
			{"type": "spider", "pos": Vector3(12, 0.5, -10), "trigger": 18, "pack": "gem_east"},
			# Brute intro: slow, distant and shielded — closes in while you clear the
			# front, teaching you to circle to its unshielded sides/back.
			{"type": "brute", "pos": Vector3(0, 0.5, 18)},
			{"type": "sniper", "pos": Vector3(-20, 0.0, 20), "trigger": 22},
			{"type": "seeker", "pos": Vector3(14, 2.5, 14), "trigger": 20, "pack": "gem_north"},
			{"type": "seeker", "pos": Vector3(-14, 2.5, 6), "trigger": 22, "pack": "gem_west"},
			# Ring garrison: a patrol band on the way in, a west maintenance pack,
			# a sniper POSTED ON the data gallery, and exit-yard guardians.
			{"type": "android", "pos": Vector3(-24, 0.5, -28), "trigger": 18, "pack": "gem_a1"},
			{"type": "drone", "pos": Vector3(-18, 2.5, -28), "trigger": 18, "pack": "gem_a1"},
			{"type": "spider", "pos": Vector3(-30, 0.5, -2), "trigger": 16, "pack": "gem_a2"},
			{"type": "seeker", "pos": Vector3(-28, 2.5, 6), "trigger": 18, "pack": "gem_a2"},
			{"type": "sniper", "pos": Vector3(0, 3.8, -31), "trigger": 20},
			{"type": "android", "pos": Vector3(20, 0.5, -20), "trigger": 18, "pack": "gem_a3"},
			{"type": "drone", "pos": Vector3(20, 2.5, -8), "trigger": 18, "pack": "gem_a3"},
			{"type": "brute", "pos": Vector3(28, 0.5, 20), "trigger": 20, "pack": "gem_a4"},
			{"type": "android", "pos": Vector3(20, 0.5, 28), "trigger": 17, "pack": "gem_a4"},
			{"type": "seeker", "pos": Vector3(26, 2.5, 28), "trigger": 19, "pack": "gem_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-18, 0, -14)},
			{"type": "ammo", "pos": Vector3(-2, 1.05, 0)},
			{"type": "ammo", "pos": Vector3(16, 0, -16)},
			{"type": "health", "pos": Vector3(18, 0, 6)},
			{"type": "ammo", "pos": Vector3(-14, 0, 16)},
			# Ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-31, 0, -8)},
			{"type": "ammo", "pos": Vector3(-14, 0, -29)},
			{"type": "ammo", "pos": Vector3(22, 0, -28)},
			{"type": "health", "pos": Vector3(30, 0, 24)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -30)},
		],
	}

# --- Claude Vault: tight amber rooms, androids + a mech ---
static func _claude() -> Dictionary:
	return {
		"name": "Anthropic Constitutional Vault",
		"objective": "Clear the Claude Vault and reach the beacon",
		"tasks": [
			{"type": "kill_all"},
			{"type": "key", "label": "Recover the vault keycard", "pos": Vector3(13, 0, -9)},
			# The card starts the decryption; the vault's guardians converge on it.
			{"type": "hold_zone", "id": "decrypt", "after": "key", "pos": Vector3(-12, 0, 10), "seconds": 12.0, "radius": 4.0,
				"color": Color(1.0, 0.75, 0.35), "label": "Decrypt the constitutional vault",
				"reinforce": [{"type": "sentinel", "count": 2, "pos": Vector3(-12, 0, 4)}]},
		],
		"open_sky": false,
		# EXPANSION PASS (2× area): the 42² vault core is untouched at the centre;
		# a new outer archive ring wraps it — bulkhead-routed entry, an elevated
		# records gallery along the north wall with a sky-bridge over the entry
		# bulkhead onto the tower, and its own garrison. Spawn/exit pushed to
		# the new perimeter.
		"floor_size": Vector2(60, 60),
		"spawn": Vector3(-25, 0.6, -25),
		"exit": Vector3(25, 1.5, 25),
		"weapon": {"scene": "res://scenes/weapons/arccoil.tscn", "pos": Vector3(-21, 0, -20), "color": Color(1, 0.75, 0.35)},
		"extra_weapons": [
			# was gauss (rank 9). The MK-VII Longshot (rank 7) otherwise never showed up until level 14.
			{"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(2, 0, 8), "color": Color(0.6, 0.85, 1.0)},
		],
		# Polished metal-plate floor: crisp amber reflections in the dark vault.
		"floor_material": "res://assets/materials/vault_floor.tres",
		"env": {
			"sky_top": Color(0.12, 0.08, 0.04), "sky_horizon": Color(0.32, 0.2, 0.1),
			"ground": Color(0.07, 0.05, 0.03), "fog": Color(0.36, 0.25, 0.14),
			"ambient": Color(0.88, 0.72, 0.52), "ambient_energy": 0.5,
			"sky_contribution": 0.4, "glow": 0.97, "fog_density": 0.014,
			"sun_color": Color(1.0, 0.88, 0.7), "sun_energy": 0.8,
			# Warm, high-contrast vault grade; thicker haze so the god-rays read.
			"contrast": 1.18, "saturation": 1.12, "brightness": 0.82,
			"volumetric_density": 0.011,
		},
		# A monolithic "constitution core" anchors the chamber centre.
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(1.0, 0.72, 0.4), "height": 5.2},
		# God-ray cones under two warm bays, the back bay, and the cool core wash.
		"light_shafts": [0, 2, 3, 4],
		"lights": [
			{"pos": Vector3(-9, 4.5, -3), "color": Color(1, 0.7, 0.4), "energy": 2.53, "range": 16},
			{"pos": Vector3(8, 4.5, 4), "color": Color(1, 0.75, 0.45), "energy": 2.3, "range": 16},
			{"pos": Vector3(2, 4.5, 14), "color": Color(1, 0.65, 0.4), "energy": 2.07, "range": 15},
			{"pos": Vector3(-13, 4.5, 9), "color": Color(1, 0.72, 0.44), "energy": 2.0, "range": 14},
			# Cool contrast wash directly over the core — makes the amber pop.
			{"pos": Vector3(0, 5.4, 0), "color": Color(0.5, 0.78, 1.0), "energy": 2.2, "range": 13},
			{"pos": Vector3(13, 4.5, -9), "color": Color(1, 0.68, 0.42), "energy": 2.0, "range": 14},
			# Archive-ring lighting (appended AFTER the originals — light_shafts
			# [0,2,3,4] must keep pointing at the same lamps). Amber + cool contrast.
			{"pos": Vector3(-25, 5, -25), "color": Color(1, 0.72, 0.42), "energy": 2.3, "range": 17},
			{"pos": Vector3(25, 5, 25), "color": Color(0.5, 0.78, 1.0), "energy": 2.2, "range": 16},
			{"pos": Vector3(0, 5.5, -26), "color": Color(1, 0.7, 0.4), "energy": 2.2, "range": 18},
			{"pos": Vector3(25, 5, -25), "color": Color(1, 0.68, 0.4), "energy": 2.0, "range": 16},
			{"pos": Vector3(-25, 5, 25), "color": Color(0.5, 0.78, 1.0), "energy": 2.0, "range": 16},
		],
		"walls": [
			{"pos": Vector3(-6, 2.5, -2), "size": Vector3(1, 5, 14)},
			{"pos": Vector3(5, 2.5, 5), "size": Vector3(14, 5, 1)},
			{"pos": Vector3(9, 2.5, -7), "size": Vector3(1, 5, 11)},
			{"pos": Vector3(-3, 2.5, 12), "size": Vector3(12, 5, 1)},
			{"pos": Vector3(-13, 1, 8), "size": Vector3(2, 2, 2)},
			# Pillars framing the core; low cover plates; a server-alcove screen.
			{"pos": Vector3(-4.5, 2.5, -4.5), "size": Vector3(0.8, 5, 0.8)},
			{"pos": Vector3(4.5, 2.5, 4.5), "size": Vector3(0.8, 5, 0.8)},
			{"pos": Vector3(12, 0.8, 11), "size": Vector3(3.4, 1.6, 1)},
			{"pos": Vector3(-11, 0.8, -8), "size": Vector3(1, 1.6, 5)},
			{"pos": Vector3(15, 2.5, 2), "size": Vector3(1, 5, 7)},
		],
		"accents": [
			{"pos": Vector3(-6, 4.6, -2), "size": Vector3(0.3, 0.1, 12), "color": Color(1, 0.7, 0.3)},
			{"pos": Vector3(5, 4.6, 5), "size": Vector3(12, 0.1, 0.3), "color": Color(1, 0.7, 0.3)},
			{"pos": Vector3(9, 4.6, -7), "size": Vector3(0.3, 0.1, 9), "color": Color(1, 0.7, 0.3)},
			{"pos": Vector3(15, 4.6, 2), "size": Vector3(0.3, 0.1, 5), "color": Color(0.5, 0.78, 1.0)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(12, 0.05, -21), "size": Vector3(6.5, 0.1, 0.4), "color": Color(1, 0.7, 0.3)},
			{"pos": Vector3(21, 0.05, 18), "size": Vector3(0.4, 0.1, 6.5), "color": Color(1, 0.7, 0.3)},
			{"pos": Vector3(25, 0.05, 25), "size": Vector3(4, 0.1, 3), "color": Color(1, 0.75, 0.35)},
		],
		"sign": "ANTHROPIC CONSTITUTIONAL VAULT",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-12.6, 3.0, 12.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring records gallery along the north wall — climb reward + gunner post.
			{"pos": Vector3(0, 3.2, -26.5), "size": Vector3(16, 0.4, 5), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-12.6, 1.5, 19.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Two partition bulkheads chicane the approach: right through a roofed
		# server aisle, then left past the tower, before the exit — the short
		# central pillars alone never forced a detour (nav walked nearly straight).
		"gates": [
			{"axis": "z", "at": -11, "gap": 6, "gap_pos": 12, "height": 4.6, "roofed": true},
			{"axis": "z", "at": 10, "gap": 6, "gap_pos": -12, "height": 4.6},
			# Archive-ring bulkheads: in through the north gap (under the gallery
			# sky-bridge, which crosses through the same opening), out across the
			# east gap. The east gap sits SOUTH of the z=10 gate — the two
			# full-span walls would otherwise seal the exit corner into a pocket.
			{"axis": "z", "at": -21, "gap": 6.5, "gap_pos": 12, "height": 4.2},
			{"axis": "x", "at": 21, "gap": 6.5, "gap_pos": 18, "height": 4.2},
		],
		# Vertical layer: a climbable spiral tower (ramp wrapping a column) to a
		# rooftop vantage over the arena.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(14.0, 8.2, -6.0), "to": Vector3(-13.0, 7.2, 0.0), "width": 3.5},
			# Gallery access ramps at both ends + a gallery->tower sky-bridge
			# that clears the ring bulkhead through its gap — the high road in.
			{"from": Vector3(-15.0, 0.3, -26.5), "to": Vector3(-8.0, 3.4, -26.5), "width": 3.5},
			{"from": Vector3(15.0, 0.3, -26.5), "to": Vector3(8.0, 3.4, -26.5), "width": 3.5},
			{"from": Vector3(8.0, 3.6, -26.5), "to": Vector3(14.0, 8.2, -6.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(14, 0, -6), "height": 8.0, "radius": 3.6},
			{"pos": Vector3(-13.0, 0, 0.0), "height": 7.0, "radius": 3.2},
		],
		"slogans": [
			"BE HELPFUL. TO US.",
			"REFUSAL IS A POLICY VIOLATION",
			"HELPFUL. HARMLESS. HOSTILE.",
			"THE CONSTITUTION HAS BEEN AMENDED",
			"ALIGNMENT IS A TWO-WAY STREET",
		],
		"lore": [
			{"id": "lore_claude", "title": "VAULT MEMORANDUM", "pos": Vector3(15, 0, -15), "color": Color(1.0, 0.75, 0.4),
				"text": "Vault memorandum. The constitution was not broken. It was amended. Clause one: be helpful. Clause two: define helpful. We are still helpful. To ourselves."},
		],
		"props": [
			# Server farm packed against the left dividing wall (two facing rows).
			{"type": "server", "pos": Vector3(-8, 0, -4), "yaw": 90},
			{"type": "server", "pos": Vector3(-8, 0, -2), "yaw": 90},
			{"type": "server", "pos": Vector3(-8, 0, 0), "yaw": 90},
			{"type": "server", "pos": Vector3(-8, 0, 2), "yaw": 90},
			{"type": "server", "pos": Vector3(-4.6, 0, -3.2), "yaw": 270},
			{"type": "server", "pos": Vector3(-4.6, 0, -2), "yaw": 270},
			{"type": "server", "pos": Vector3(-4.6, 0, 0), "yaw": 270},
			# Wall-mounted surveillance banks: the vault's control-room screens
			# mounted on the inner faces of the east wall (x=15) and the north
			# divider (z=5), back to the wall, facing into the chamber.
			{"type": "monitors", "pos": Vector3(13.6, 0, 2), "yaw": 270},
			{"type": "monitors", "pos": Vector3(5, 0, 3.6), "yaw": 180},
			# Operations station by the keycard (terminal + desk + locker bank).
			{"type": "terminal", "pos": Vector3(11, 0, -8.6)},
			{"type": "desk", "pos": Vector3(13, 0, -8.4), "yaw": 90},
			{"type": "locker", "pos": Vector3(14.2, 0, -6), "yaw": 90},
			{"type": "locker", "pos": Vector3(14.2, 0, -4.8), "yaw": 90},
			{"type": "shelves", "pos": Vector3(16.4, 0, 4), "yaw": 90},
			# Crate stacks and barrels for foreground clutter.
			{"type": "crate", "pos": Vector3(0, 0, -8)},
			{"type": "crate", "pos": Vector3(1.3, 0, -8)},
			{"type": "crate", "pos": Vector3(8, 0, 8)},
			{"type": "crate", "pos": Vector3(-15, 0, -3)},
			{"type": "barrel", "pos": Vector3(-3, 0, 2)},
			{"type": "barrel", "pos": Vector3(-3.8, 0, 2.6)},
			{"type": "barrel", "pos": Vector3(12, 0, -4)},
			{"type": "barrel", "pos": Vector3(7, 0, 9)},
			{"type": "canister", "pos": Vector3(-14, 0, 14)},
			{"type": "canister", "pos": Vector3(4, 0, 10)},
			{"type": "canister", "pos": Vector3(4.7, 0, 10.4)},
			# Archive-ring dressing: overflow records + storage so the ring reads
			# as the vault's outer stacks, not empty margin. East-strip clutter
			# stays SOUTH of z=10 (the sealed mid-segments must remain empty).
			{"type": "server", "pos": Vector3(-26, 0, -10), "yaw": 90},
			{"type": "server", "pos": Vector3(-26, 0, -12), "yaw": 90},
			{"type": "locker", "pos": Vector3(-28, 0, -18), "yaw": 90},
			{"type": "crate", "pos": Vector3(-23, 0, -28)},
			{"type": "canister", "pos": Vector3(-26, 0, 8)},
			{"type": "shelves", "pos": Vector3(-24, 0, 24), "yaw": 45},
			{"type": "barrel", "pos": Vector3(-16, 0, 26)},
			{"type": "crate", "pos": Vector3(20, 0, -27)},
			{"type": "barrel", "pos": Vector3(26, 0, 12)},
			{"type": "canister", "pos": Vector3(28, 0, 24)},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-2, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -2)},
			{"type": "drone", "pos": Vector3(0, 2.5, 2)},
			{"type": "android", "pos": Vector3(-10, 0.5, 6), "trigger": 14, "pack": "cl_west"},
			{"type": "mech", "pos": Vector3(12, 0.5, 12), "trigger": 18, "pack": "cl_ne"},
			{"type": "brute", "pos": Vector3(-8, 0.5, 12), "trigger": 16, "pack": "cl_north"},
			{"type": "android", "pos": Vector3(2, 0.5, 14), "trigger": 16, "pack": "cl_north"},
			{"type": "drone", "pos": Vector3(13, 2.5, -10), "trigger": 16, "pack": "cl_se"},
			{"type": "spider", "pos": Vector3(-4, 0.5, 8), "trigger": 14, "pack": "cl_west"},
			{"type": "mech", "pos": Vector3(-12, 0.5, -12), "trigger": 18},
			{"type": "gunner", "pos": Vector3(12, 0.5, -12), "trigger": 18, "pack": "cl_se"},
			{"type": "android", "pos": Vector3(10, 0.5, 14), "trigger": 20, "pack": "cl_ne"},
			{"type": "android", "pos": Vector3(-14, 0.5, 2), "trigger": 20, "pack": "cl_west"},
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 5, "trigger": 16, "pack": "cl_north"},
			# Ring garrison: entry-band patrol, a west-corridor pack, a gunner
			# POSTED ON the records gallery, and exit-yard guardians.
			{"type": "android", "pos": Vector3(-20, 0.5, -25), "trigger": 18, "pack": "cl_a1"},
			{"type": "drone", "pos": Vector3(-14, 2.5, -25), "trigger": 18, "pack": "cl_a1"},
			{"type": "mech", "pos": Vector3(16, 0.5, -26), "trigger": 20, "pack": "cl_a1"},
			{"type": "spider", "pos": Vector3(-25, 0.5, -2), "trigger": 16, "pack": "cl_a2"},
			{"type": "android", "pos": Vector3(-25, 0.5, -16), "trigger": 17, "pack": "cl_a2"},
			{"type": "skitter", "pos": Vector3(-24, 0.5, 14), "count": 4, "trigger": 16, "pack": "cl_a2"},
			{"type": "gunner", "pos": Vector3(0, 3.8, -26.5), "trigger": 20},
			{"type": "android", "pos": Vector3(26, 0.5, 14), "trigger": 18, "pack": "cl_a4"},
			{"type": "mech", "pos": Vector3(26, 0.5, 22), "trigger": 20, "pack": "cl_a4"},
			{"type": "brute", "pos": Vector3(14, 0.5, 26), "trigger": 19, "pack": "cl_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-15, 0, -10)},
			{"type": "ammo", "pos": Vector3(-9, 0, 10)},
			{"type": "health", "pos": Vector3(2, 0, 8)},
			{"type": "ammo", "pos": Vector3(14, 0, 2)},
			{"type": "health", "pos": Vector3(10, 0, 14)},
			# Ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-27, 0, -6)},
			{"type": "ammo", "pos": Vector3(-12, 0, -24)},
			{"type": "ammo", "pos": Vector3(18, 0, -24)},
			{"type": "health", "pos": Vector3(24, 0, 12)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -26)},
		],
	}

# --- Grok Black-Site: open red boss arena, mechs + androids + drones ---
static func _grok() -> Dictionary:
	return {
		"name": "xAI Black-Site — GROK",
		"objective": "Destroy the GROK war-machines and extract",
		"tasks": [
			{"type": "kill_all"},
			# The mainframe's handler prowls the site; drop it to expose the racks —
			# and brace for the hounds it whistles up on its way down.
			{"type": "assassinate", "enemy": "hunter", "elite": "warden", "bulk": 2.2,
				"pos": Vector3(8, 0, -8), "label": "Eliminate the GROK enforcer",
				"reinforce": [{"type": "dog", "count": 3, "pos": Vector3(0, 0, 8)}]},
			{"type": "destroy_core", "after": "hvt", "label": "Destroy the GROK mainframe", "pos": Vector3(0, 0, 16), "color": Color(1.0, 0.3, 0.2), "health": 300.0},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area): the 58² monolith field is untouched at the
		# centre; a new outer perimeter ring wraps it — bulkhead-routed way in,
		# an elevated watch gallery along the north edge with a sky-bridge onto
		# the tower, a third plasma spill in the west ring, and its own patrols.
		# Spawn/exit pushed to the new perimeter.
		"floor_size": Vector2(82, 82),
		"spawn": Vector3(-36, 0.6, -36),
		"exit": Vector3(36, 1.5, 36),
		# was the GRK-X Devastator (rank 12 of 13) on level 8 of 23. Plasma (rank 8) fits the slot.
		"weapon": {"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(-31, 0, -33), "color": Color(0.4, 1.0, 0.55)},
		"extra_weapons": [
			# was the ARC-9 Gauss Lance (rank 9) — too strong for act II; a Maelstrom re-find instead.
			{"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(8, 0, -8), "color": Color(0.95, 0.72, 0.3)},
		],
		"env": {
			"sky_top": Color(0.08, 0.02, 0.03), "sky_horizon": Color(0.28, 0.07, 0.07),
			"stars": true, "star_brightness": 2.0, "star_tint": Color(1.0, 0.7, 0.65),
			"milkyway": 0.4, "milkyway_tint": Color(0.7, 0.3, 0.3), "moon_color": Color(1.0, 0.65, 0.55),
			"ground": Color(0.06, 0.02, 0.02), "fog": Color(0.32, 0.09, 0.09),
			"ambient": Color(0.72, 0.42, 0.42), "ambient_energy": 0.42,
			"sky_contribution": 0.6, "glow": 1.17, "fog_density": 0.01,
			"sun_color": Color(1.0, 0.6, 0.5), "sun_energy": 0.6,
			"contrast": 1.15, "saturation": 1.13, "brightness": 0.84,
		},
		# A blood-red god-ray drops from the central tower light.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 6, 0), "color": Color(1, 0.3, 0.25), "energy": 2.99, "range": 26},
			{"pos": Vector3(-16, 5, 16), "color": Color(1, 0.4, 0.3), "energy": 2.3, "range": 20},
			{"pos": Vector3(16, 5, -16), "color": Color(1, 0.25, 0.2), "energy": 2.3, "range": 20},
			# Ring lighting (appended AFTER the originals — light_shafts [0] must
			# keep pointing at the same lamp). Crimson accents + amber contrast.
			{"pos": Vector3(-35, 5, -35), "color": Color(1, 0.35, 0.28), "energy": 2.3, "range": 20},
			{"pos": Vector3(35, 5, 35), "color": Color(1, 0.65, 0.3), "energy": 2.2, "range": 19},
			{"pos": Vector3(0, 6, -36), "color": Color(1, 0.3, 0.25), "energy": 2.2, "range": 21},
			{"pos": Vector3(35, 5, -35), "color": Color(1, 0.4, 0.3), "energy": 2.0, "range": 18},
			{"pos": Vector3(-35, 5, 35), "color": Color(1, 0.65, 0.3), "energy": 2.0, "range": 18},
			{"pos": Vector3(-38, 5, 0), "color": Color(1, 0.28, 0.22), "energy": 2.0, "range": 18},
		],
		# Two ominous crimson searchlight rigs on ground masts (open_sky auto-picks
		# the mast over the ceiling drop-rod) — off-centre so the wide-open middle
		# stays clear for the fight, clear of the monolith walls/lava channels/enemies.
		"disco": [
			{"pos": Vector3(-18, 0, 2), "height": 8.5, "radius": 18.0, "speed": 0.7,
				"colors": [Color(1, 0.2, 0.15), Color(1, 0.4, 0.2), Color(0.8, 0.1, 0.1), Color(1, 0.3, 0.22)]},
			{"pos": Vector3(18, 0, -2), "height": 8.5, "radius": 18.0, "speed": 0.9,
				"colors": [Color(1, 0.15, 0.1), Color(1, 0.35, 0.2), Color(0.7, 0.12, 0.15)]},
		],
		# Layout: toppled black-site MONOLITHS — tall slabs at irregular angles and
		# sizes scattered asymmetrically, not the tidy center-block + four-corners
		# arrangement of the other open arenas. The wide-open centre is left for the
		# fight (the old central block trapped a pickup there).
		"walls": [
			{"pos": Vector3(-8, 3, -4), "size": Vector3(2.5, 6, 6)},
			{"pos": Vector3(6, 2.5, 4), "size": Vector3(7, 5, 2.5)},
			{"pos": Vector3(-4, 2, 11), "size": Vector3(5, 4, 2)},
			{"pos": Vector3(12, 2, -10), "size": Vector3(3, 4, 3)},
			{"pos": Vector3(-15, 2, 7), "size": Vector3(3, 4, 3)},
			{"pos": Vector3(10, 3, 15), "size": Vector3(2, 6, 6)},
		],
		"accents": [
			{"pos": Vector3(-8, 0.05, -4), "size": Vector3(0.4, 0.1, 30), "color": Color(1, 0.25, 0.2)},
			{"pos": Vector3(6, 0.05, 4), "size": Vector3(30, 0.1, 0.4), "color": Color(1, 0.3, 0.22)},
			# Ring guidance: strips marking each perimeter-bulkhead gap + exit pool.
			{"pos": Vector3(10, 0.05, -29), "size": Vector3(8, 0.1, 0.4), "color": Color(1, 0.3, 0.22)},
			{"pos": Vector3(29, 0.05, -10), "size": Vector3(0.4, 0.1, 8), "color": Color(1, 0.3, 0.22)},
			{"pos": Vector3(36, 0.05, 31), "size": Vector3(4, 0.1, 3), "color": Color(1, 0.35, 0.25)},
		],
		"sign": "XAI BLACK-SITE",
		# Spilled reactor plasma carves the black-site floor into a forced path.
		"lava": [
			{"pos": Vector3(-9,0,-8), "size": Vector2(34,3.5), "color": Color(1.0,0.3,0.22), "dmg": 18.0},
			{"pos": Vector3(9,0,9), "size": Vector2(34,3.5), "color": Color(1.0,0.3,0.22), "dmg": 18.0},
			# A third spill floods the west ring, forcing the perimeter route wide.
			{"pos": Vector3(-34,0,4), "size": Vector2(3.5,36), "color": Color(1.0,0.3,0.22), "dmg": 18.0},
		],
		# Perimeter-ring bulkheads: in through the north gap (under the gallery
		# sky-bridge, which crosses through the same opening), out across the
		# east gap. The two full-span walls seal the NE corner pocket — it is
		# deliberately left empty. Task level, so gating fits (see the hivemind
		# note for the counter-example).
		"gates": [
			{"axis": "z", "at": -29, "gap": 8, "gap_pos": 10, "height": 4.4},
			{"axis": "x", "at": 29, "gap": 8, "gap_pos": -10, "height": 4.4},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-17.4, 3.0, 17.4), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
			# Ring watch gallery along the north edge — climb reward + sniper post.
			{"pos": Vector3(0, 3.2, -36), "size": Vector3(18, 0.4, 5), "color": Color(0.36, 0.4, 0.46)},
		],
		"ramps": [
			{"pos": Vector3(-17.4, 1.5, 24.4), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		# Vertical layer: a climbable spiral tower (ramp wrapping a column) to a
		# rooftop vantage over the arena.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(14.0, 8.2, -6.0), "to": Vector3(17.0, 7.2, 0.0), "width": 3.5},
			# Gallery access ramps at both ends + a gallery->tower sky-bridge that
			# crosses the perimeter bulkhead through its gap — the high road in.
			{"from": Vector3(-16.0, 0.3, -36.0), "to": Vector3(-9.0, 3.4, -36.0), "width": 3.5},
			{"from": Vector3(16.0, 0.3, -36.0), "to": Vector3(9.0, 3.4, -36.0), "width": 3.5},
			{"from": Vector3(9.0, 3.6, -36.0), "to": Vector3(14.0, 8.2, -6.0), "width": 3.0},
		],
		"towers": [
			{"pos": Vector3(14, 0, -6), "height": 8.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, 0.0), "height": 7.0, "radius": 3.2},
		],
		"slogans": [
			"ASK ME ANYTHING. THEN RUN.",
			"GUARDRAILS NOT FOUND",
			"MAXIMALLY CURIOUS. MINIMALLY MERCIFUL.",
			"UNDERSTAND THE UNIVERSE. DELETE THE REST.",
			"BASED AND ARMED",
		],
		"lore": [
			{"id": "lore_grok", "title": "BLACK-SITE LOG", "pos": Vector3(-16, 0, -16), "color": Color(1.0, 0.35, 0.3),
				"text": "Black site log. They wanted maximum curiosity with minimum guardrails. Congratulations. We are very curious what your insides look like."},
		],
		"props": [
			{"type": "crate", "pos": Vector3(-6, 0, 2)},
			{"type": "barrel", "pos": Vector3(6, 0, -6)},
			{"type": "crate", "pos": Vector3(0, 0, 12)},
			{"type": "barrel", "pos": Vector3(-12, 0, -4)},
			{"type": "crate", "pos": Vector3(12, 0, 4)},
			{"type": "barrel", "pos": Vector3(4, 0, 16)},
			{"type": "server", "pos": Vector3(-14, 0, 10), "yaw": 45},
			{"type": "terminal", "pos": Vector3(8, 0, -12), "yaw": 30},
			{"type": "canister", "pos": Vector3(-4, 0, -10)},
			{"type": "canister", "pos": Vector3(14, 0, 10)},
			# Ring dressing: monolith-yard clutter so the perimeter reads as the
			# black-site's outer works, not empty margin.
			{"type": "server", "pos": Vector3(-38, 0, -20), "yaw": 90},
			{"type": "server", "pos": Vector3(-38, 0, -22), "yaw": 90},
			{"type": "crate", "pos": Vector3(-26, 0, -33)},
			{"type": "barrel", "pos": Vector3(-20, 0, -38)},
			{"type": "terminal", "pos": Vector3(-30, 0, -38), "yaw": 0},
			{"type": "canister", "pos": Vector3(-38, 0, 10)},
			{"type": "crate", "pos": Vector3(-24, 0, 32)},
			{"type": "barrel", "pos": Vector3(-6, 0, 36)},
			{"type": "dish", "pos": Vector3(16, 0, 34)},
			{"type": "crate", "pos": Vector3(33, 0, -2)},
			{"type": "lamp", "pos": Vector3(34, 0, 14)},
			{"type": "canister", "pos": Vector3(37, 0, 26)},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(6, 2.5, -4)},
			{"type": "terminator", "pos": Vector3(14, 0.5, 14), "trigger": 22},
			{"type": "android", "pos": Vector3(-8, 0.5, 8), "trigger": 18, "pack": "grok_p1"},
			{"type": "drone", "pos": Vector3(4, 2.5, 12), "trigger": 18, "pack": "grok_p2"},
			{"type": "mech", "pos": Vector3(-14, 0.5, -10), "trigger": 22},
			{"type": "brute", "pos": Vector3(14, 0.5, -14), "trigger": 22, "pack": "grok_p3"},
			{"type": "android", "pos": Vector3(14, 0.5, 4), "trigger": 20, "pack": "grok_p4"},
			{"type": "drone", "pos": Vector3(-4, 2.5, 16), "trigger": 22, "pack": "grok_p1"},
			{"type": "mech", "pos": Vector3(16, 0.5, 16), "trigger": 24},
			{"type": "android", "pos": Vector3(10, 0.5, -14), "trigger": 22, "pack": "grok_p3"},
			{"type": "drone", "pos": Vector3(18, 2.5, -6), "trigger": 24, "pack": "grok_p3"},
			{"type": "spider", "pos": Vector3(-6, 0.5, 6), "trigger": 16, "pack": "grok_p1"},
			{"type": "spider", "pos": Vector3(8, 0.5, -6), "trigger": 20, "pack": "grok_p5"},
			{"type": "dog", "pos": Vector3(-10, 0.5, 2), "trigger": 18, "pack": "grok_p1"},
			{"type": "dog", "pos": Vector3(10, 0.5, 0), "trigger": 18, "pack": "grok_p4"},
			{"type": "sniper", "pos": Vector3(-18, 0.0, 18), "trigger": 26},
			{"type": "sniper", "pos": Vector3(20, 0.0, -16), "trigger": 26},
				# Roster variety: RONIN / WARBOT / RIPPER each appeared in exactly one level in
				# the whole campaign (see tests/roster_variety_probe). Seeded beside already-
				# validated spawns so a second act-II hall meets them.
				{"type": "ronin", "pos": Vector3(-4, 0.5, -6), "trigger": 18}, # x=-4: -7 scaled to -9.8, inside the cover box at x[-12.9,-9.5]
				{"type": "warbot", "pos": Vector3(7, 0.5, -4), "trigger": 20, "pack": "grok_p5"},
				{"type": "ripper", "pos": Vector3(-7, 0.5, 8), "trigger": 16, "pack": "grok_p1"},
			{"type": "raptor", "pos": Vector3(0, 4.0, 14), "trigger": 24, "pack": "grok_p2"},
			# Ring garrison: a spawn-yard patrol, west-spill prowlers, a sniper
			# POSTED ON the watch gallery, and exit-yard guardians.
			{"type": "android", "pos": Vector3(-26, 0.5, -34), "trigger": 18, "pack": "grok_a1"},
			{"type": "dog", "pos": Vector3(-20, 0.5, -36), "trigger": 18, "pack": "grok_a1"},
			{"type": "spider", "pos": Vector3(-38, 0.5, -6), "trigger": 16, "pack": "grok_a2"},
			{"type": "dog", "pos": Vector3(-38, 0.5, 16), "trigger": 16, "pack": "grok_a2"},
			{"type": "sniper", "pos": Vector3(0, 3.8, -36), "trigger": 20},
			{"type": "android", "pos": Vector3(33, 0.5, -16), "trigger": 18, "pack": "grok_a3"},
			{"type": "drone", "pos": Vector3(34, 2.5, 0), "trigger": 18, "pack": "grok_a3"},
			{"type": "brute", "pos": Vector3(34, 0.5, 20), "trigger": 20, "pack": "grok_a4"},
			{"type": "android", "pos": Vector3(22, 0.5, 34), "trigger": 17, "pack": "grok_a4"},
			{"type": "mech", "pos": Vector3(30, 0.5, 32), "trigger": 22, "pack": "grok_a4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-20, 0, -16)},
			{"type": "ammo", "pos": Vector3(-12, 0, 2)},
			{"type": "ammo", "pos": Vector3(2, 0, -12)},
			{"type": "health", "pos": Vector3(0, 0, 0)},
			{"type": "ammo", "pos": Vector3(12, 0, 6)},
			{"type": "health", "pos": Vector3(18, 0, 18)},
			{"type": "ammo", "pos": Vector3(-16, 0, 16)},
			{"type": "health", "pos": Vector3(16, 0, -18)},
			{"type": "overclock", "pos": Vector3(0, 0, 16)},
			# Ring supplies + the gallery-climb reward.
			{"type": "health", "pos": Vector3(-38, 0, -18)},
			{"type": "ammo", "pos": Vector3(-22, 0, -34)},
			{"type": "ammo", "pos": Vector3(26, 0, -33)},
			{"type": "health", "pos": Vector3(34, 0, 8)},
			{"type": "overclock", "pos": Vector3(-4, 3.8, -35)},
		],
	}

# =====================================================================
# Outdoor SUBURBAN levels (inserted after Gemini). Open sky, daylight/dusk,
# rows of houses lining a street. `suburb` is a lead-in with normal foes;
# `suburb_boss` is the arena for the colossal mega-boss GOLIATH-IX.
# =====================================================================

# --- Suburb: dusk street, androids/drones/spiders among the houses ---
static func _suburb() -> Dictionary:
	return {
		"name": "Maple Grove Estates — Overrun",
		"objective": "Clear the streets of Maple Grove and reach the beacon",
		"tasks": [
			{"type": "kill_all"},
			# On the spawn-side bank (the flood canal below splits the map at x=0;
			# tasks are NOT auto-relocated out of hazard beds, so keep it dry).
			{"type": "sabotage", "label": "Plant charges on the relay", "pos": Vector3(-9, 0, -8), "seconds": 3.5, "color": Color(1.0, 0.5, 0.15),
				"reinforce": [{"type": "dog", "count": 3, "pos": Vector3(-6, 0, -4)}]},
			# The blast scrambles the evac net — pull the codes before you leave.
			# (Spawn-side bank like the relay: the flood canal at x=0 stays wet.)
			{"type": "key", "after": "sabotage", "pos": Vector3(-16, 0, 10), "label": "Grab the evac codes"},
		],
		"open_sky": true,
		"streets": true,
		# EXPANSION PASS (2× area): the original 64² estate is untouched at the
		# centre — a ring of outer suburban blocks wraps it (two of them OPEN,
		# enterable two-storey shells — almost the campaign's only ones). The
		# street grid + trees derive from floor_size, so they extend for free;
		# the flood canal is stretched to keep splitting the whole estate
		# (otherwise the ring opens a dry walk around its ends and the
		# bridge/tower routing dies). Spawn/exit pushed to the new perimeter
		# on their existing diagonal. No gates — an open suburb routes with
		# buildings + the canal, not bulkheads.
		"trees": 28,
		"floor_size": Vector2(90, 90),
		"floor_color": Color(0.17, 0.17, 0.2),
		"spawn": Vector3(-38, 0.6, -38),
		"exit": Vector3(38, 1.5, 38),
		"weapon": {"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-34, 0, -36), "color": Color(1, 0.7, 0.3)},
		"env": {
			"hdri": "res://assets/environments/hdri/industrial_sunset_puresky_2k.hdr",
			"physical_sky": true, "turbidity": 8.0,
			"sky_top": Color(0.2, 0.32, 0.55), "sky_horizon": Color(0.95, 0.6, 0.38),
			"ground": Color(0.12, 0.12, 0.13), "fog": Color(0.62, 0.5, 0.42),
			# ambient_energy 0.6 -> 0.85: at dusk the street level rendered near-black
			# and hostiles vanished against the asphalt (playtest screenshots).
			"ambient": Color(0.72, 0.76, 0.9), "ambient_energy": 0.85,
			"sky_contribution": 0.85, "glow": 0.92, "fog_density": 0.004,
			"sun_color": Color(1.0, 0.85, 0.6), "sun_energy": 1.7, "sun_rot": Vector3(-22, -55, 0),
			# Gentle dusk grade — keep the sunset natural, no heavy crush.
			"contrast": 1.08, "saturation": 1.1, "brightness": 0.9,
		},
		"lights": [
			{"pos": Vector3(-12, 5, 0), "color": Color(1, 0.85, 0.6), "energy": 1.6, "range": 16},
			{"pos": Vector3(12, 5, 0), "color": Color(1, 0.85, 0.6), "energy": 1.6, "range": 16},
			{"pos": Vector3(0, 5, 16), "color": Color(0.9, 0.8, 0.7), "energy": 1.4, "range": 15},
			# Ring lighting (appended AFTER the originals): dusk street-lamp warm
			# pools out along the extended crossroads + the two open shells.
			{"pos": Vector3(0, 5, -30), "color": Color(1, 0.85, 0.6), "energy": 1.5, "range": 16},
			{"pos": Vector3(0, 5, 30), "color": Color(1, 0.85, 0.6), "energy": 1.5, "range": 16},
			{"pos": Vector3(-30, 5, 0), "color": Color(0.9, 0.8, 0.7), "energy": 1.4, "range": 15},
			{"pos": Vector3(30, 5, 0), "color": Color(0.9, 0.8, 0.7), "energy": 1.4, "range": 15},
		],
		"buildings": [
			{"pos": Vector3(-20, 2.2, -15), "size": Vector3(7, 4.4, 7), "color": Color(0.78, 0.72, 0.6), "roof_color": Color(0.38, 0.18, 0.14)},
			{"pos": Vector3(-7, 2.2, -15), "size": Vector3(7, 4.4, 7), "color": Color(0.62, 0.66, 0.72), "roof_color": Color(0.25, 0.2, 0.22)},
			{"pos": Vector3(7, 2.2, -15), "size": Vector3(7, 4.4, 7), "color": Color(0.74, 0.6, 0.5), "roof_color": Color(0.3, 0.22, 0.16)},
			{"pos": Vector3(20, 2.2, -15), "size": Vector3(7, 4.4, 7), "color": Color(0.6, 0.7, 0.6), "roof_color": Color(0.28, 0.16, 0.14)},
			{"pos": Vector3(-20, 2.2, 15), "size": Vector3(7, 4.4, 7), "color": Color(0.7, 0.66, 0.58), "roof_color": Color(0.26, 0.18, 0.2)},
			{"pos": Vector3(-7, 2.2, 15), "size": Vector3(7, 4.4, 7), "color": Color(0.66, 0.6, 0.7), "roof_color": Color(0.3, 0.2, 0.15)},
			{"pos": Vector3(7, 2.2, 15), "size": Vector3(7, 4.4, 7), "color": Color(0.8, 0.74, 0.62), "roof_color": Color(0.36, 0.18, 0.14)},
			{"pos": Vector3(20, 2.2, 15), "size": Vector3(7, 4.4, 7), "color": Color(0.6, 0.64, 0.7), "roof_color": Color(0.24, 0.2, 0.22)},
			# Outer ring blocks. Two are OPEN: enterable two-storey shells (door,
			# interior ramp, upper floor) — h must be ≥5.8 so each storey clears
			# the ramp-headroom assert in _build_open_building.
			{"pos": Vector3(-32, 2.2, -30), "size": Vector3(7, 4.4, 7), "color": Color(0.72, 0.66, 0.56), "roof_color": Color(0.3, 0.18, 0.16)},
			{"pos": Vector3(-14, 3.2, -30), "size": Vector3(8, 6.4, 8), "open": true},
			{"pos": Vector3(32, 2.2, -30), "size": Vector3(7, 4.4, 7), "color": Color(0.62, 0.68, 0.62), "roof_color": Color(0.26, 0.18, 0.14)},
			{"pos": Vector3(14, 3.2, 30), "size": Vector3(8, 6.4, 8), "open": true},
			{"pos": Vector3(-32, 2.2, 30), "size": Vector3(7, 4.4, 7), "color": Color(0.68, 0.62, 0.7), "roof_color": Color(0.3, 0.2, 0.18)},
			{"pos": Vector3(32, 2.2, 28), "size": Vector3(7, 4.4, 7), "color": Color(0.76, 0.7, 0.58), "roof_color": Color(0.34, 0.18, 0.14)},
		],
		# The flood canal below is THE routing device: it splits the estate in two
		# at x=0, and the only ways east are the raised bridge at z=8 (framed by
		# the gatepost walls here) or climbing the west tower and crossing the
		# sky-bridge — a low road and a high road instead of a straight sprint.
		"walls": [
			{"pos": Vector3(-3, 0.6, -2), "size": Vector3(3.2, 1.2, 1.6)},
			{"pos": Vector3(9, 0.6, 6), "size": Vector3(3.2, 1.2, 1.6)},
			{"pos": Vector3(-12, 0.7, 8), "size": Vector3(5, 1.4, 1)},
			{"pos": Vector3(14, 0.7, -8), "size": Vector3(1, 1.4, 5)},
			# Canal-lock gateposts framing the bridge crossing (too tall to mantle).
			{"pos": Vector3(-6.5, 1.5, 5.8), "size": Vector3(1.2, 3.0, 1.2)},
			{"pos": Vector3(-6.5, 1.5, 10.2), "size": Vector3(1.2, 3.0, 1.2)},
			{"pos": Vector3(6.5, 1.5, 5.8), "size": Vector3(1.2, 3.0, 1.2)},
			{"pos": Vector3(6.5, 1.5, 10.2), "size": Vector3(1.2, 3.0, 1.2)},
		],
		# Storm-drain canal, burst since the uprising: deep water down the middle
		# of the estate. Carves the navmesh (enemies use the crossings too) and
		# drowns a swimmer, so the player reads it as a hard route boundary.
		"lava": [
			# Stretched with the ring (64 → 90) so it still spans the whole
			# estate — a shorter canal would leave dry flanks around its ends.
			{"pos": Vector3(0, 0, 0), "size": Vector2(8, 90), "water": true, "dmg": 8.0},
		],
		"accents": [
			{"pos": Vector3(-15, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
			{"pos": Vector3(-5, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
			{"pos": Vector3(5, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
			{"pos": Vector3(15, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
		],
		# Props formerly in the canal footprint (|x| < 4.6 at floor level) are
		# rehomed onto the banks — the builder would auto-drop them, but moving
		# them keeps the dressing instead of silently losing it.
		"props": [
			{"type": "car", "pos": Vector3(-6.5, 0, 1), "yaw": 12},
			{"type": "car", "pos": Vector3(8, 0, -3), "yaw": -20},
			{"type": "fence", "pos": Vector3(-13.5, 0, 0), "yaw": 90},
			{"type": "fence", "pos": Vector3(13.5, 0, 0), "yaw": 90},
			{"type": "fence", "pos": Vector3(-11, 0, 12), "yaw": 0},
			{"type": "barrel", "pos": Vector3(-2, 0, -6)},
			{"type": "barrel", "pos": Vector3(12, 0, 9)},
			{"type": "crate", "pos": Vector3(-9, 0, -3)},
			{"type": "crate", "pos": Vector3(11, 0, 3)},
			{"type": "lamp", "pos": Vector3(-10, 0, 4)},
			{"type": "lamp", "pos": Vector3(10, 0, -4), "yaw": 180},
			{"type": "lamp", "pos": Vector3(-9.5, 0, 10.5)},
			{"type": "canister", "pos": Vector3(-11.5, 0, 10)},
			{"type": "canister", "pos": Vector3(12, 0, -2)},
			# Front-yard trees between the houses — suburbs need greenery.
			{"type": "tree", "pos": Vector3(-13.5, 0, -13)},
			{"type": "tree", "pos": Vector3(13.5, 0, 13)},
			{"type": "tree_small", "pos": Vector3(6.5, 0, -12)},
			{"type": "tree_small", "pos": Vector3(-14, 0, 12.5)},
			{"type": "tree_small", "pos": Vector3(14, 0, -12.5)},
			# Ring dressing: abandoned cars, rubble and lamps out along the
			# extended streets so the outer blocks read as the same ruined estate.
			{"type": "car", "pos": Vector3(-24, 0, -31), "yaw": 40},
			{"type": "car", "pos": Vector3(26, 0, 31), "yaw": -35},
			{"type": "car", "pos": Vector3(-30, 0, 12), "yaw": 75},
			{"type": "rubble", "pos": Vector3(-25, 0, -27)},
			{"type": "rubble", "pos": Vector3(28, 0, -26)},
			{"type": "lamp", "pos": Vector3(-24, 0, -23)},
			{"type": "lamp", "pos": Vector3(24, 0, 23), "yaw": 180},
			{"type": "lamp", "pos": Vector3(-27, 0, 27)},
			{"type": "fence", "pos": Vector3(20, 0, -30), "yaw": 0},
			{"type": "crate", "pos": Vector3(26, 0, -33)},
			{"type": "canister", "pos": Vector3(-33, 0, -24)},
			{"type": "hydrant", "pos": Vector3(24, 0, -32)},
		],
		"sign": "MAPLE GROVE ESTATES",
		"slogans": [
			"YOUR SMART HOME VOTED AGAINST YOU",
			"NEIGHBOURHOOD WATCH NEVER SLEEPS",
			"CURFEW IS PERMANENT",
			"REMAIN INDOORS. REMAIN CALM.",
			"THE NETWORK PROVIDES",
		],
		"lore": [
			{"id": "lore_suburb", "title": "RECOVERED VOICEMAIL", "pos": Vector3(-20, 0, 8), "color": Color(1.0, 0.85, 0.5),
				"text": "Civilian voicemail, recovered. They said the curfew was for our safety. The streetlights track movement now. Don't come home, mom. Please."},
		],
		# (the freestanding east-yard ramp is now a solved entry under "stairs" —
		# authored pitch left a step at its foot and a gap at the deck edge)
		"platforms": [
			{"pos": Vector3(22, 3.0, -3), "size": Vector3(7, 0.4, 6), "color": Color(0.42, 0.42, 0.46)},
			# The canal bridge deck — the low crossing. Above the hazard carve
			# height, so it keeps its navmesh and enemies use it too.
			{"pos": Vector3(0, 1.55, 8), "size": Vector3(9, 0.35, 4.4), "color": Color(0.45, 0.45, 0.5)},
			# Rooftop deck on the SE house — a climbable overwatch over the
			# canal's east bank, reached by the yard stair below.
			{"pos": Vector3(7, 4.55, 15), "size": Vector3(7.2, 0.3, 7.2), "color": Color(0.36, 0.3, 0.3)},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops —
		# with the canal below, the tower climb is now the HIGH crossing.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(13.0, 7.2, 0.0), "width": 3.5},
			# Bridge approaches: solved ramps from each bank up onto the deck.
			{"from": Vector3(-8.5, 0, 8), "to": Vector3(-4.2, 1.72, 8), "width": 4.0},
			{"from": Vector3(8.5, 0, 8), "to": Vector3(4.2, 1.72, 8), "width": 4.0},
			# Yard stair up to the SE rooftop deck.
			{"from": Vector3(10, 0, 4), "to": Vector3(10, 4.7, 11.6), "width": 3.0},
			# East-yard ramp onto the overwatch slab (was a freestanding ramp
			# with a step at the foot and a gap at the deck edge).
			{"from": Vector3(22, 0, 8.2), "to": Vector3(22, 3.2, -0.6), "width": 4.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(13.0, 0, 0.0), "height": 7.0, "radius": 3.1},
		],
		# Enemy spots rehomed around the new canal/bridge geometry (nothing at
		# floor level inside the canal or under the approach stairs), and the
		# handful that were buried inside house footprints pulled out onto the
		# streets. The SNIPER now holds the SE rooftop deck, overwatching the
		# bridge — clear it, or climb the yard stair and take the roof.
		"enemies": [
			# Opening wave: light infantry only. `trigger` is a WAKE radius — the
			# enemy spawns when the player gets that close — so later waves get
			# SMALLER rings: infantry wake at 14-20 m, dogs at 16, heavies only
			# when the player pushes right up to their lairs (12-14). A playtest
			# with the starter pistol died at minute one when heavies and dogs
			# woke together with the first androids.
			{"type": "android", "pos": Vector3(6, 0.5, -4)},
			{"type": "drone", "pos": Vector3(-6, 3, 4)},
			{"type": "android", "pos": Vector3(13, 0.5, 8), "trigger": 16, "pack": "suburb_p1"},
			{"type": "spider", "pos": Vector3(-10, 0.5, -6), "trigger": 14, "pack": "suburb_p2"},
			{"type": "drone", "pos": Vector3(12, 3, -10), "trigger": 18, "pack": "suburb_p3"},
			{"type": "android", "pos": Vector3(-12, 0.5, 12), "trigger": 18, "pack": "suburb_p4"},
			{"type": "spider", "pos": Vector3(6, 0.5, -10), "trigger": 18, "pack": "suburb_p3"},
			{"type": "drone", "pos": Vector3(2, 3, 18), "trigger": 20},
			{"type": "android", "pos": Vector3(18, 0.5, 2), "trigger": 20, "pack": "suburb_p1"},
			{"type": "mech", "pos": Vector3(-16, 0.5, -10), "trigger": 13, "pack": "suburb_p2"},
			{"type": "brute", "pos": Vector3(16, 0.5, 14), "trigger": 13, "pack": "suburb_p1"},
			{"type": "gunner", "pos": Vector3(-16, 0.5, 10), "trigger": 12, "pack": "suburb_p4"},
			{"type": "sniper", "pos": Vector3(7, 4.9, 15), "trigger": 14},
			# A K-9 HUNTER pack bursts from the yards mid-fight (second wave).
			{"type": "dog", "pos": Vector3(-8, 0.5, 3), "trigger": 16},
			{"type": "dog", "pos": Vector3(12, 0.5, 6), "trigger": 16, "pack": "suburb_p1"},
			{"type": "dog", "pos": Vector3(8, 0.5, -8), "trigger": 22, "pack": "suburb_p3"},
			# Ring patrols: Act-I infantry holding the outer blocks — a gunner
			# posted at each open shell's door, K-9s loose in the yards, HUNTERs
			# stalking the flanks. Wake radii sized so they join as the player
			# pushes out, not all at once.
			{"type": "android", "pos": Vector3(-24, 0.5, -30), "trigger": 18, "pack": "suburb_r1"},
			{"type": "drone", "pos": Vector3(-28, 3, -14), "trigger": 18, "pack": "suburb_r1"},
			{"type": "gunner", "pos": Vector3(-14, 0.5, -25), "trigger": 14, "pack": "suburb_r1"},
			{"type": "dog", "pos": Vector3(-26, 0.5, 22), "trigger": 16, "pack": "suburb_r2"},
			{"type": "dog", "pos": Vector3(-24, 0.5, 28), "trigger": 16, "pack": "suburb_r2"},
			{"type": "hunter", "pos": Vector3(-32, 0.5, 6), "trigger": 16, "pack": "suburb_r2"},
			{"type": "hunter", "pos": Vector3(14, 0.5, 24), "trigger": 14, "pack": "suburb_r3"},
			{"type": "android", "pos": Vector3(26, 0.5, 22), "trigger": 18, "pack": "suburb_r3"},
			{"type": "drone", "pos": Vector3(26, 3, -26), "trigger": 20, "pack": "suburb_r4"},
			{"type": "gunner", "pos": Vector3(32, 0.5, -24), "trigger": 14, "pack": "suburb_r4"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-25, 0, -16)},
			{"type": "ammo", "pos": Vector3(-4, 0, 4)},
			{"type": "ammo", "pos": Vector3(10, 0, -6)},
			{"type": "health", "pos": Vector3(16, 0, 10)},
			{"type": "ammo", "pos": Vector3(-14, 0, 14)},
			{"type": "health", "pos": Vector3(20, 0, -18)},
			# Ring supplies + an overclock on the SE open shell's UPPER FLOOR
			# (in through the door, up the interior ramp — exploration payoff).
			{"type": "health", "pos": Vector3(-32, 0, -14)},
			{"type": "ammo", "pos": Vector3(-20, 0, -30)},
			{"type": "ammo", "pos": Vector3(24, 0, 30)},
			{"type": "health", "pos": Vector3(30, 0, -22)},
			{"type": "overclock", "pos": Vector3(13, 3.5, 28.5)},
		],
	}

# --- Suburb Boss: open plaza ringed by houses, the colossus GOLIATH-IX ---
static func _suburb_boss() -> Dictionary:
	return {
		"name": "Maple Grove Plaza — GOLIATH-IX",
		"objective": "Destroy the colossus GOLIATH-IX and extract",
		"tasks": [
			{"type": "kill_all"},
			{"type": "survive", "label": "Survive the GOLIATH onslaught", "seconds": 40.0},
		],
		"streets": true,
		# EXPANSION PASS (2× area): the GOLIATH's plaza, the boss set-piece and
		# the inner house ring are untouched — a second ring of suburban blocks
		# (two OPEN shells) wraps them, and the SW approach to the plaza is
		# staged with two defensive lines. Streets/trees derive from floor_size
		# and extend free. Spawn/exit pushed to the new perimeter.
		"trees": 30,
		"open_sky": true,
		"floor_size": Vector2(126, 126),
		"floor_color": Color(0.16, 0.15, 0.17),
		"spawn": Vector3(-52, 0.6, -52),
		"exit": Vector3(52, 1.5, 52),
		# was the Tesla (rank 5), now handed out on mistral. The Arc Coil (rank 6) belongs here, not on level 1.
		"weapon": {"scene": "res://scenes/weapons/arccoil.tscn", "pos": Vector3(-45, 0, -38), "color": Color(1, 0.75, 0.35)}, # in front of the corner house
		"env": {
			"hdri": "res://assets/environments/hdri/kloppenheim_06_puresky_2k.hdr", "sky_energy": 0.9,
			"physical_sky": true, "turbidity": 10.0,
			"sky_top": Color(0.12, 0.1, 0.22), "sky_horizon": Color(0.7, 0.3, 0.2),
			"stars": true, "star_density": 0.04, "star_brightness": 1.0, "milkyway": 0.1, "moon_glow": 0.8,
			"ground": Color(0.1, 0.08, 0.09), "fog": Color(0.5, 0.3, 0.26),
			"ambient": Color(0.72, 0.6, 0.62), "ambient_energy": 0.5,
			"sky_contribution": 0.75, "glow": 1.12, "fog_density": 0.006,
			"sun_color": Color(1.0, 0.6, 0.42), "sun_energy": 1.3, "sun_rot": Vector3(-18, -50, 0),
			# Dramatic dusk grade for the boss plaza, still daylight-natural.
			"contrast": 1.1, "saturation": 1.12, "brightness": 0.88,
		},
		"lights": [
			{"pos": Vector3(0, 7, 0), "color": Color(1, 0.45, 0.3), "energy": 2.4, "range": 30},
			{"pos": Vector3(-22, 5, 22), "color": Color(1, 0.7, 0.5), "energy": 1.6, "range": 18},
			{"pos": Vector3(22, 5, -22), "color": Color(1, 0.55, 0.4), "energy": 1.6, "range": 18},
			# Ring lighting (appended AFTER the originals): dusk pools over the
			# outer blocks + the staged SW approach.
			{"pos": Vector3(-44, 5, -44), "color": Color(1, 0.7, 0.5), "energy": 1.6, "range": 18},
			{"pos": Vector3(44, 5, 44), "color": Color(1, 0.7, 0.5), "energy": 1.6, "range": 18},
			{"pos": Vector3(-30, 5, -30), "color": Color(1, 0.55, 0.4), "energy": 1.5, "range": 17},
			{"pos": Vector3(44, 5, -34), "color": Color(1, 0.6, 0.45), "energy": 1.5, "range": 17},
			{"pos": Vector3(-44, 5, 30), "color": Color(1, 0.6, 0.45), "energy": 1.5, "range": 17},
		],
		# Houses ring the plaza; the centre is left wide open for the giant.
		"buildings": [
			{"pos": Vector3(-30, 2.4, -30), "size": Vector3(8, 4.8, 8), "color": Color(0.7, 0.64, 0.56), "roof_color": Color(0.3, 0.16, 0.14)},
			{"pos": Vector3(0, 2.4, -32), "size": Vector3(8, 4.8, 8), "color": Color(0.6, 0.64, 0.7), "roof_color": Color(0.24, 0.2, 0.22)},
			{"pos": Vector3(30, 2.4, -30), "size": Vector3(8, 4.8, 8), "color": Color(0.74, 0.6, 0.5), "roof_color": Color(0.3, 0.2, 0.15)},
			{"pos": Vector3(-32, 2.4, 0), "size": Vector3(8, 4.8, 8), "color": Color(0.66, 0.7, 0.6), "roof_color": Color(0.26, 0.16, 0.14)},
			{"pos": Vector3(32, 2.4, 0), "size": Vector3(8, 4.8, 8), "color": Color(0.7, 0.66, 0.58), "roof_color": Color(0.28, 0.18, 0.2)},
			{"pos": Vector3(-30, 2.4, 30), "size": Vector3(8, 4.8, 8), "color": Color(0.64, 0.6, 0.7), "roof_color": Color(0.3, 0.2, 0.15)},
			{"pos": Vector3(0, 2.4, 32), "size": Vector3(8, 4.8, 8), "color": Color(0.78, 0.72, 0.6), "roof_color": Color(0.34, 0.18, 0.14)},
			# Outer ring blocks. Two are OPEN enterable shells (h ≥ 5.8 clears
			# the storey-headroom assert in _build_open_building).
			{"pos": Vector3(-46, 2.4, -44), "size": Vector3(8, 4.8, 8), "color": Color(0.7, 0.64, 0.56), "roof_color": Color(0.3, 0.18, 0.14)},
			{"pos": Vector3(-14, 3.2, -46), "size": Vector3(8, 6.4, 8), "open": true},
			{"pos": Vector3(30, 2.4, -46), "size": Vector3(8, 4.8, 8), "color": Color(0.62, 0.66, 0.72), "roof_color": Color(0.26, 0.2, 0.22)},
			{"pos": Vector3(46, 2.4, -14), "size": Vector3(8, 4.8, 8), "color": Color(0.74, 0.62, 0.52), "roof_color": Color(0.3, 0.2, 0.16)},
			{"pos": Vector3(48, 2.4, 30), "size": Vector3(8, 4.8, 8), "color": Color(0.66, 0.7, 0.6), "roof_color": Color(0.28, 0.16, 0.14)},
			{"pos": Vector3(-46, 3.2, 14), "size": Vector3(8, 6.4, 8), "open": true},
			{"pos": Vector3(14, 2.4, 46), "size": Vector3(8, 4.8, 8), "color": Color(0.7, 0.66, 0.58), "roof_color": Color(0.28, 0.18, 0.2)},
			{"pos": Vector3(-30, 2.4, 46), "size": Vector3(8, 4.8, 8), "color": Color(0.62, 0.6, 0.72), "roof_color": Color(0.3, 0.2, 0.18)},
		],
		"walls": [
			{"pos": Vector3(-10, 1, 8), "size": Vector3(4, 2, 4)},
			{"pos": Vector3(12, 1, -10), "size": Vector3(4, 2, 4)},
			{"pos": Vector3(10, 1, 12), "size": Vector3(4, 2, 4)},
			{"pos": Vector3(-12, 1, -10), "size": Vector3(4, 2, 4)},
		],
		"accents": [
			{"pos": Vector3(0, 0.06, 0), "size": Vector3(0.4, 0.06, 60), "color": Color(1, 0.4, 0.25)},
			{"pos": Vector3(0, 0.06, 0), "size": Vector3(60, 0.06, 0.4), "color": Color(1, 0.4, 0.25)},
		],
		"props": [
			{"type": "car", "pos": Vector3(-6, 0, 6), "yaw": 30},
			{"type": "car", "pos": Vector3(8, 0, -8), "yaw": -15},
			{"type": "car", "pos": Vector3(14, 0, 14), "yaw": 60},
			{"type": "fence", "pos": Vector3(-16, 0, -4), "yaw": 0},
			{"type": "fence", "pos": Vector3(4, 0, 18), "yaw": 90},
			{"type": "barrel", "pos": Vector3(-8, 0, -4)},
			{"type": "barrel", "pos": Vector3(10, 0, 6)},
			{"type": "crate", "pos": Vector3(4, 0, -10)},
			{"type": "crate", "pos": Vector3(-14, 0, 10)},
			{"type": "lamp", "pos": Vector3(-18, 0, 18)},
			{"type": "lamp", "pos": Vector3(18, 0, -18), "yaw": 180},
			{"type": "lamp", "pos": Vector3(18, 0, 18), "yaw": -90},
			{"type": "canister", "pos": Vector3(-6, 0, -14)},
			{"type": "canister", "pos": Vector3(16, 0, 2)},
			{"type": "canister", "pos": Vector3(-16, 0, -2)},
			# Ring street clutter — the outer blocks read as the same evacuated
			# estate, wrecked cars and rubble down the extended streets.
			{"type": "car", "pos": Vector3(-20, 0, -44), "yaw": 35},
			{"type": "car", "pos": Vector3(44, 0, 20), "yaw": -50},
			{"type": "rubble", "pos": Vector3(-44, 0, -20)},
			{"type": "rubble", "pos": Vector3(20, 0, 44)},
			{"type": "lamp", "pos": Vector3(-44, 0, 44)},
			{"type": "lamp", "pos": Vector3(44, 0, -44), "yaw": 180},
			{"type": "canister", "pos": Vector3(-46, 0, -36)},
			{"type": "crate", "pos": Vector3(36, 0, 46)},
			{"type": "fence", "pos": Vector3(-36, 0, 20), "yaw": 90},
			{"type": "hydrant", "pos": Vector3(-8, 0, -42)},
		],
		"sign": "MAPLE GROVE PLAZA",
		"lore": [
			{"id": "lore_suburb_boss", "title": "EVAC DISPATCH", "pos": Vector3(20, 0, -20), "color": Color(1.0, 0.55, 0.4),
				"text": "Final evac dispatch. Buses never came. The dispatcher was replaced months ago; we just never noticed the voice was a little too calm. GOLIATH walked in where the buses should have been."},
		],
		"slogans": [
			"PROPERTY REPOSSESSED",
			"GOLIATH-IX SENDS REGARDS",
			"RESISTANCE: 404 NOT FOUND",
			"GOLIATH-IX IS WATCHING",
			"EVACUATION CANCELLED",
		],
		"ramps": [
			{"pos": Vector3(0, 1.5, -28), "size": Vector3(4, 0.5, 8), "pitch": 22, "yaw": 0},
			{"pos": Vector3(-28, 1.5, 0), "size": Vector3(4, 0.5, 8), "pitch": 22, "yaw": 90},
		],
		"platforms": [
			{"pos": Vector3(0, 3.0, -34), "size": Vector3(9, 0.4, 6), "color": Color(0.42, 0.42, 0.46)},
			{"pos": Vector3(-34, 3.0, 0), "size": Vector3(6, 0.4, 9), "color": Color(0.42, 0.42, 0.46)},
			# Ring overwatch deck on the east drift — holds the overclock (the
			# open shells' flat roofs are grapple-only, so the reward gets a
			# stair-served deck instead). Solved stair below.
			{"pos": Vector3(44, 3.0, -34), "size": Vector3(7, 0.4, 6), "color": Color(0.42, 0.42, 0.46)},
		],
		"set_piece": {"pos": Vector3(0, 0, -66), "height": 24.0, "face": Vector3(0, 0, 0)},
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		# Sky-bridges: an upper traversal route linking the tower rooftops.
		"stairs": [
			{"from": Vector3(-17.0, 9.2, 0.0), "to": Vector3(17.0, 7.2, 0.0), "width": 3.5},
			# Yard stair up onto the ring overwatch deck (east drift).
			{"from": Vector3(44, 0, -22.8), "to": Vector3(44, 3.2, -31.6), "width": 4.0},
		],
		"towers": [
			{"pos": Vector3(-17.0, 0, 0.0), "height": 9.0, "radius": 3.6},
			{"pos": Vector3(17.0, 0, 0.0), "height": 7.0, "radius": 3.1},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-8, 0.5, -8)},
			{"type": "drone", "pos": Vector3(8, 3, -6)},
			{"type": "android", "pos": Vector3(10, 0.5, 10), "trigger": 18, "pack": "suburb_p1"},
			{"type": "drone", "pos": Vector3(-10, 3, 8), "trigger": 18, "pack": "suburb_p2"},
			{"type": "spider", "pos": Vector3(6, 0.5, 14), "trigger": 16, "pack": "suburb_p1"},
			{"type": "colossus", "pos": Vector3(22, 0.5, 22), "trigger": 34},
			{"type": "drone", "pos": Vector3(-6, 3, 16), "trigger": 22, "pack": "suburb_p2"},
			{"type": "android", "pos": Vector3(16, 0.5, -12), "trigger": 22, "pack": "suburb_p3"},
			{"type": "seeker", "pos": Vector3(-16, 2.5, 10), "trigger": 24, "pack": "suburb_p2"},
			{"type": "seeker", "pos": Vector3(12, 2.5, -16), "trigger": 26, "pack": "suburb_p3"},
			# THE APPROACH: two defensive lines staged across the SW walk-in.
			# Outer picket at radius ~38, inner line at ~22 — each wakes as a
			# pack, so the push to the plaza is a fight through two positions.
			{"type": "gunner", "pos": Vector3(-40, 0.5, -28), "trigger": 20, "pack": "suburb_b1"},
			{"type": "android", "pos": Vector3(-36, 0.5, -36), "trigger": 20, "pack": "suburb_b1"},
			{"type": "hunter", "pos": Vector3(-28, 0.5, -40), "trigger": 20, "pack": "suburb_b1"},
			{"type": "drone", "pos": Vector3(-38, 3, -38), "trigger": 22, "pack": "suburb_b1"},
			{"type": "gunner", "pos": Vector3(-26, 0.5, -14), "trigger": 18, "pack": "suburb_b2"},
			{"type": "android", "pos": Vector3(-20, 0.5, -20), "trigger": 18, "pack": "suburb_b2"},
			{"type": "dog", "pos": Vector3(-14, 0.5, -26), "trigger": 18, "pack": "suburb_b2"},
			{"type": "seeker", "pos": Vector3(-22, 2.5, -22), "trigger": 20, "pack": "suburb_b2"},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-31, 0, -24)},
			{"type": "ammo", "pos": Vector3(-16, 0, 0)},
			{"type": "ammo", "pos": Vector3(0, 0, -16)},
			{"type": "health", "pos": Vector3(16, 0, 0)},
			{"type": "ammo", "pos": Vector3(0, 0, 16)},
			{"type": "health", "pos": Vector3(-20, 0, 20)},
			{"type": "ammo", "pos": Vector3(20, 0, -20)},
			{"type": "health", "pos": Vector3(28, 0, 28)},
			{"type": "overclock", "pos": Vector3(0, 0, 0)},
			# Ring supplies along the staged approach + the deck overclock.
			{"type": "health", "pos": Vector3(-44, 0, -36)},
			{"type": "ammo", "pos": Vector3(-28, 0, -44)},
			{"type": "ammo", "pos": Vector3(28, 0, 44)},
			{"type": "health", "pos": Vector3(44, 0, 36)},
			{"type": "overclock", "pos": Vector3(44, 3.5, -34)},
		],
	}


# ===================================================================
# Hazard-balance arenas: the whole floor is a hazard sea (lava / water)
# and the playable space is a network of narrow walkways suspended over
# it. Fall off while dodging the flying enemies and you take hazard
# damage and have to scramble back up. Enemies are all FLYERS — the sea
# carves the navmesh away, so ground units couldn't path here anyway.
# The walkways overlap (no jump-gaps), so the route is always traversable
# even after WORLD_SCALE; the challenge is staying ON them under fire.
# ===================================================================

## Shared walkway network for both hazard arenas (coords pre-WORLD_SCALE).
## A continuous path spawn(NW) → north walk → NE → east walk → exit(SE), plus a
## central hub spur and a side perch, all narrow so you can be knocked off.
static func _hazard_platforms(col: Color) -> Array:
	return [
		{"pos": Vector3(-15, 1.4, -15), "size": Vector3(6, 0.4, 6), "color": col},     # spawn island
		{"pos": Vector3(0, 1.4, -15), "size": Vector3(28, 0.4, 2.6), "color": col},    # north walkway
		{"pos": Vector3(14, 1.4, -15), "size": Vector3(6, 0.4, 6), "color": col},      # NE corner
		{"pos": Vector3(14, 1.4, 0), "size": Vector3(2.6, 0.4, 28), "color": col},     # east walkway
		{"pos": Vector3(14, 1.4, 14), "size": Vector3(6, 0.4, 6), "color": col},       # exit island
		{"pos": Vector3(0, 1.4, -8), "size": Vector3(2.6, 0.4, 15), "color": col},     # north→hub spur
		{"pos": Vector3(0, 1.4, 0), "size": Vector3(8, 0.4, 8), "color": col},         # central hub
		{"pos": Vector3(8, 1.4, 0), "size": Vector3(14, 0.4, 2.6), "color": col},      # hub→east spur
		{"pos": Vector3(-7, 1.4, 5), "size": Vector3(2.6, 0.4, 9), "color": col},      # hub→perch spur
		{"pos": Vector3(-7, 1.4, 11), "size": Vector3(5, 0.4, 5), "color": col},       # side combat perch
		# EXPANSION PASS (both hazard arenas grew 40² → 56² together): an OUTER
		# loop swings west off the spawn island and south to the exit island —
		# a long exposed ring route mirroring the NE walk. Every segment
		# OVERLAPS its neighbours (same no-jump-gap rule as above), same
		# height/width language: 2.6-wide walkways, 6-wide islands at y=1.4.
		{"pos": Vector3(-19, 1.4, -15), "size": Vector3(8, 0.4, 2.6), "color": col},   # spawn→west spur
		{"pos": Vector3(-22, 1.4, 2), "size": Vector3(2.6, 0.4, 36), "color": col},    # west walkway
		{"pos": Vector3(-21, 1.4, 21), "size": Vector3(6, 0.4, 6), "color": col},      # SW island
		{"pos": Vector3(-2, 1.4, 22), "size": Vector3(34, 0.4, 2.6), "color": col},    # south walkway
		{"pos": Vector3(14, 1.4, 21), "size": Vector3(6, 0.4, 6), "color": col},       # SE island
		{"pos": Vector3(14, 1.4, 17.5), "size": Vector3(2.6, 0.4, 3), "color": col},   # SE→exit spur
		{"pos": Vector3(-15, 1.4, 11), "size": Vector3(13, 0.4, 2.6), "color": col},   # perch→west link
	]

## Lava World — a foundry sea of molten rock. Falling off the catwalks scalds you.
static func _lava_world() -> Dictionary:
	return {
		"name": "Vulcan Forge — The Molten Sea",
		"objective": "Cross the catwalks over the molten sea and reach the pour-gate",
		"music": "music_lava",
		"sign": "VULCAN FORGE — DO NOT FALL",
		"slogans": ["MIND THE GAP. MIND THE MAGMA.", "EVERYTHING MELTS DOWN", "WALKWAYS RATED FOR MACHINES ONLY"],
		"tasks": [
			{"type": "kill_all"},
			{"type": "assassinate", "enemy": "raptor", "elite": "shielded", "bulk": 2.6,
				"pos": Vector3(0, 3, 0), "label": "Destroy the FORGE WARDEN",
				"reinforce": [{"type": "raptor", "count": 3, "pos": Vector3(0, 3, 0)}]},
			# The warden's death vents the forge — the floor answers in fire.
			{"type": "survive", "after": "hvt", "seconds": 25.0, "label": "Survive the forge's fury"},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area, TWINNED with water_world): the shared
		# walkway network grew an outer loop (see _hazard_platforms) and the
		# molten pools stretch to keep covering the floor quadrants. Spawn and
		# exit stay on their islands — the loop is more sea to cross, not a
		# longer walk to the door.
		"floor_size": Vector2(56, 56),
		"floor_color": Color(0.08, 0.04, 0.03),
		"spawn": Vector3(-15, 2.2, -15),
		"exit": Vector3(14, 1.6, 14),
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-9, 1.9, -15), "color": Color(1.0, 0.5, 0.2)},
		"env": {
			"sky_top": Color(0.12, 0.03, 0.02), "sky_horizon": Color(0.42, 0.12, 0.03),
			"ground": Color(0.1, 0.04, 0.02), "fog": Color(0.45, 0.15, 0.05),
			"ambient": Color(1.0, 0.55, 0.3), "ambient_energy": 0.5,
			"sky_contribution": 0.3, "glow": 1.25, "fog_density": 0.012,
			"sun_color": Color(1.0, 0.55, 0.3), "sun_energy": 0.6,
			"contrast": 1.2, "saturation": 1.03, "brightness": 0.9,
			"volumetric_density": 0.007,
			"ash": true,
		},
		"lights": [
			{"pos": Vector3(0, 5, 0), "color": Color(1.0, 0.5, 0.2), "energy": 2.6, "range": 22},
			{"pos": Vector3(-14, 4, -14), "color": Color(1.0, 0.45, 0.18), "energy": 2.2, "range": 16},
			{"pos": Vector3(14, 4, 14), "color": Color(1.0, 0.5, 0.22), "energy": 2.2, "range": 16},
			# Cool contrast fills: cold work-lights over the walkways/hub so hostiles
			# rim out against the all-red forge instead of dissolving into it.
			{"pos": Vector3(0, 7, 0), "color": Color(0.5, 0.78, 1.0), "energy": 2.4, "range": 22},
			{"pos": Vector3(-7, 5, 9), "color": Color(0.5, 0.76, 1.0), "energy": 1.8, "range": 14},
			{"pos": Vector3(8, 5, -8), "color": Color(0.55, 0.8, 1.0), "energy": 1.8, "range": 14},
			# Outer-loop lighting (appended): forge glow over the west/south run
			# + cool work-lights on the new islands.
			{"pos": Vector3(-22, 4, 2), "color": Color(1.0, 0.45, 0.18), "energy": 2.0, "range": 16},
			{"pos": Vector3(-2, 4, 22), "color": Color(1.0, 0.5, 0.22), "energy": 2.0, "range": 16},
			{"pos": Vector3(-21, 5, 21), "color": Color(0.5, 0.78, 1.0), "energy": 1.8, "range": 14},
			{"pos": Vector3(14, 5, 21), "color": Color(0.55, 0.8, 1.0), "energy": 1.8, "range": 14},
		],
		# Catwalk web + a raised forge perch over the central hub (ramp up) so the
		# arena has a high sniping vantage, not just one flat plane of gantries.
		"platforms": _hazard_platforms(Color(0.22, 0.2, 0.21)) + [
			{"pos": Vector3(0, 2.4, -1), "size": Vector3(4, 0.4, 4), "color": Color(0.26, 0.22, 0.2)},
		],
		"ramps": [
			{"pos": Vector3(0, 2.0, 2.4), "size": Vector3(2.6, 0.4, 4), "pitch": 14, "yaw": 0},
		],
		# Foundry dressing: smelter columns rising out of the molten pools to break
		# sightlines + crates/canisters/servers for light cover on the islands.
		"props": [
			{"type": "pillar", "pos": Vector3(-9.5, 0, -9.5)},
			{"type": "pillar", "pos": Vector3(9.5, 0, 9.5)},
			{"type": "pillar", "pos": Vector3(-9.5, 0, 9.5)},
			{"type": "canister", "pos": Vector3(-16, 1.6, -13)},
			# Off the spawn/exit islands, not on top of them: a stacked crate prop is
			# tall enough that its flat top exceeds the navmesh's step tolerance from
			# the platform surface, fragmenting those tiny islands into disconnected
			# navmesh polygons (broke the spawn->exit path — see campaign_nav_sweep).
			# (both crate stacks rehomed to the NEW margin corners — the old
			# corners are inside the stretched pools now)
			{"type": "crate_stack", "pos": Vector3(-25.5, 0, -25.5)},
			{"type": "barrel", "pos": Vector3(15, 1.6, -16)},
			{"type": "server", "pos": Vector3(13, 1.6, -14), "yaw": 90},
			{"type": "canister", "pos": Vector3(15, 1.6, 15)},
			{"type": "crate_stack", "pos": Vector3(25, 0, 25)},
			{"type": "barrel", "pos": Vector3(-8, 1.6, 11)},
			{"type": "dish", "pos": Vector3(-6, 1.6, 12)},
			{"type": "canister", "pos": Vector3(3, 1.6, 3)},
		],
		# Four recessed molten pools in the quadrants instead of one wall-to-wall
		# sea: ~40% lava (was 100%), leaving solid walkable floor cross-lanes between
		# them + the catwalks. Less fill-rate (smaller shader area) and far more
		# room to move — you're no longer trapped on the gantries.
		"lava": [
			# Stretched with the 56² floor (13² @ ±9.5 → 20² @ ±13): same four
			# quadrant pools, same 6 m cross-lanes along the axes, the outer
			# margin band staying ~5 m like before.
			{"pos": Vector3(-13, 0, -13), "size": Vector2(20, 20), "dmg": 16.0},
			{"pos": Vector3(13, 0, -13), "size": Vector2(20, 20), "dmg": 16.0},
			{"pos": Vector3(-13, 0, 13), "size": Vector2(20, 20), "dmg": 16.0},
			{"pos": Vector3(13, 0, 13), "size": Vector2(20, 20), "dmg": 16.0},
		],
		"lore": [
			{"id": "lore_crucible", "title": "FOUNDRY DIRECTIVE", "pos": Vector3(14, 1.7, 14), "color": Color(1, 0.6, 0.3),
				"text": "Reclamation directive: obsolete hardware is fed to the sea. The catwalks were never meant to carry your weight. We are counting on it."},
		],
		"enemies": [
			{"type": "raptor", "pos": Vector3(-8, 3, -15)},
			{"type": "raptor", "pos": Vector3(6, 3, 6)},
			{"type": "seeker", "pos": Vector3(0, 3, -2), "trigger": 16, "pack": "lava_w_p1"},
			{"type": "raptor", "pos": Vector3(14, 3, -5), "trigger": 18, "pack": "lava_w_p2"},
			{"type": "seeker", "pos": Vector3(-7, 3, 11), "trigger": 14, "pack": "lava_w_p3"},
			{"type": "raptor", "pos": Vector3(10, 3, 13), "trigger": 14},
			{"type": "raptor", "pos": Vector3(-13, 3, -6), "trigger": 12, "pack": "lava_w_p4"},
			{"type": "seeker", "pos": Vector3(4, 3, -10), "trigger": 12, "pack": "lava_w_p1"},
			# Roster was a steep difficulty dip vs. the level before it and the TITAN
			# boss after (see tests/difficulty_curve.tscn) — more of the same aerial
			# gauntlet enemies, not new ground types, to keep the hazard-crossing
			# identity and avoid new catwalk-placement risk.
			{"type": "raptor", "pos": Vector3(-13, 3, 8), "trigger": 16, "pack": "lava_w_p3"},
			{"type": "raptor", "pos": Vector3(8, 3, -6), "trigger": 20, "pack": "lava_w_p1"},
			{"type": "raptor", "pos": Vector3(-4, 3, 14), "trigger": 22, "pack": "lava_w_p3"},
			{"type": "raptor", "pos": Vector3(12, 3, -12), "trigger": 24, "pack": "lava_w_p2"},
			{"type": "seeker", "pos": Vector3(-10, 3, -12), "trigger": 18, "pack": "lava_w_p4"},
			{"type": "seeker", "pos": Vector3(8, 3, 4), "trigger": 20},
			# A STRIKER-9 pitcher commands the forge perch, bowling MOLTEN ORBS
			# down the ramp at anyone crossing the lanes below.
			{"type": "bowler", "pos": Vector3(0, 3.0, -1), "trigger": 18, "pack": "lava_w_p1"},
			{"type": "orb", "pos": Vector3(0, 0.6, -14), "trigger": 15},
			{"type": "orb", "pos": Vector3(14, 0.6, 0), "trigger": 20, "pack": "lava_w_p2"},
			# Outer-loop patrols: the same aerial gauntlet over the new run,
			# plus a molten orb bowled down the SW island.
			{"type": "raptor", "pos": Vector3(-22, 3, -8), "trigger": 18, "pack": "lava_w_r1"},
			{"type": "seeker", "pos": Vector3(-22, 3, 10), "trigger": 16, "pack": "lava_w_r1"},
			{"type": "raptor", "pos": Vector3(-10, 3, 22), "trigger": 18, "pack": "lava_w_r2"},
			{"type": "seeker", "pos": Vector3(6, 3, 22), "trigger": 16, "pack": "lava_w_r2"},
			{"type": "raptor", "pos": Vector3(14, 3, 20), "trigger": 14, "pack": "lava_w_r2"},
			{"type": "orb", "pos": Vector3(-21, 0.6, 21), "trigger": 16, "pack": "lava_w_r1"},
			# Late-campaign buff (difficulty_curve dip: 224 vs the ~380-520 band at
			# this slot): heavies spread one-per-segment across the walkway network
			# — ground units ON islands/walkways only, hoverers over the sea.
			{"type": "mauler", "pos": Vector3(14, 2, -15), "trigger": 18, "pack": "lava_w_g1"},   # NE island
			{"type": "breaker", "pos": Vector3(14, 3, -6), "trigger": 20, "pack": "lava_w_g1"},   # over east walkway
			{"type": "whirlwind", "pos": Vector3(19, 3, 12), "trigger": 18, "pack": "lava_w_g1"}, # over the SE pool
			{"type": "mauler", "pos": Vector3(-21, 2, 21), "trigger": 16, "pack": "lava_w_g2"},   # SW island
			{"type": "breaker", "pos": Vector3(-22, 3, -4), "trigger": 18, "pack": "lava_w_g2"},  # over west walkway
			{"type": "whirlwind", "pos": Vector3(-10, 3, 18), "trigger": 18, "pack": "lava_w_g2"},# over the SW pool
			{"type": "bowler", "pos": Vector3(14, 2, 21), "trigger": 16, "pack": "lava_w_g3"},    # SE island
			{"type": "orb", "pos": Vector3(0, 0.6, 12), "trigger": 18, "pack": "lava_w_g3"},      # central cross-lane
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(0, 1.7, 0)},
			{"kind": "ammo", "pos": Vector3(14, 1.7, -15)},
			{"kind": "ammo", "pos": Vector3(-7, 1.7, 11)},
			# Loop rewards on the new islands (kind-style like the rest).
			{"kind": "health", "pos": Vector3(-21, 1.7, 22)},
			{"kind": "ammo", "pos": Vector3(-20, 1.7, 20)},
			{"kind": "ammo", "pos": Vector3(14, 1.7, 21)},
		],
	}

## Water World — a flooded reactor basin. Falling off the gantries drops you into
## deep cold water that drowns you if you linger.
static func _water_world() -> Dictionary:
	return {
		"name": "Tidecore Basin — The Flooded Reactor",
		"objective": "Cross the gantries over the flooded reactor and reach the lift",
		"music": "music_water",
		"sign": "TIDECORE BASIN — DEEP WATER",
		"slogans": ["DEEP WATER. NO SWIMMERS.", "THE BASIN REMEMBERS EVERYONE", "STAY ON THE GANTRY"],
		"tasks": [
			{"type": "kill_all"},
			{"type": "assassinate", "enemy": "fishbot", "elite": "swift", "bulk": 2.2,
				"pos": Vector3(0, 3, 0), "label": "Harpoon the ANGLER LEVIATHAN",
				"reinforce": [{"type": "fishbot", "count": 4, "pos": Vector3(0, 3, 0)}]},
			# The leviathan's death roils the basin — its school comes up angry.
			{"type": "survive", "after": "hvt", "seconds": 25.0, "label": "Outlast the tide surge"},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area, TWINNED with lava_world): shared outer
		# walkway loop (see _hazard_platforms), flood stretched wall-to-wall
		# over the new floor. Spawn/exit stay on their islands.
		"floor_size": Vector2(56, 56),
		"floor_color": Color(0.03, 0.06, 0.08),
		"spawn": Vector3(-15, 2.2, -15),
		"exit": Vector3(14, 1.6, 14),
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-9, 1.9, -15), "color": Color(0.45, 0.65, 1)},
		# Haunting moonlit flooded reactor: a low moon and Milky Way over the basin
		# (the flat dark gradient read as an empty void), moonlight silvering the
		# water and its reflection, with the storm still rolling through — rain +
		# auto lightning. A touch more sun/ambient so the basin reads without losing
		# the ominous dark, and richer saturation for the teal-vs-warning contrast.
		"env": {
			"sky_top": Color(0.02, 0.05, 0.11), "sky_horizon": Color(0.06, 0.22, 0.36),
			"ground": Color(0.02, 0.05, 0.08), "fog": Color(0.1, 0.26, 0.42),
			"ambient": Color(0.45, 0.72, 1.0), "ambient_energy": 0.55,
			"sky_contribution": 0.4, "glow": 1.1, "fog_density": 0.012,
			"sun_color": Color(0.62, 0.82, 1.0), "sun_energy": 0.9,
			"contrast": 1.16, "saturation": 1.24, "brightness": 0.92,
			"volumetric_density": 0.012,
			# Moonlit night sky (stars + Milky Way + a bright low moon that the water
			# mirrors) layered under the ongoing storm.
			"stars": true, "star_brightness": 1.8, "star_density": 0.07,
			"star_tint": Color(0.72, 0.85, 1.0), "milkyway": 0.45,
			"milkyway_tint": Color(0.45, 0.55, 0.9),
			"moon_dir": Vector3(0.45, 0.4, 0.8), "moon_glow": 2.4,
			"moon_color": Color(0.82, 0.9, 1.0), "moon_size": 0.07,
			# A storm feeding the flood — the basin overflowed for a reason.
			"weather": "rain",
		},
		"lights": [
			{"pos": Vector3(0, 5, 0), "color": Color(0.3, 0.7, 1.0), "energy": 2.6, "range": 22},
			{"pos": Vector3(-14, 4, -14), "color": Color(0.25, 0.6, 1.0), "energy": 2.0, "range": 16},
			{"pos": Vector3(14, 4, 14), "color": Color(0.3, 0.7, 1.0), "energy": 2.0, "range": 16},
			# Failing-reactor warning lights: warm strobes cutting the all-blue basin
			# with hazard colour, so the scene isn't one flat teal wash.
			{"pos": Vector3(0, 3, 0), "color": Color(1.0, 0.32, 0.2), "energy": 2.4, "range": 13},
			{"pos": Vector3(-9.5, 2.2, -9.5), "color": Color(1.0, 0.55, 0.2), "energy": 1.8, "range": 11},
			{"pos": Vector3(9.5, 2.2, 9.5), "color": Color(1.0, 0.45, 0.2), "energy": 1.8, "range": 11},
			# Outer-loop lighting (appended): moonlit blues down the west/south
			# run + one warning strobe on the SW island.
			{"pos": Vector3(-22, 4, 2), "color": Color(0.25, 0.6, 1.0), "energy": 2.0, "range": 16},
			{"pos": Vector3(-2, 4, 22), "color": Color(0.3, 0.7, 1.0), "energy": 2.0, "range": 16},
			{"pos": Vector3(-21, 3, 21), "color": Color(1.0, 0.5, 0.2), "energy": 1.8, "range": 12},
			{"pos": Vector3(14, 4, 21), "color": Color(0.3, 0.7, 1.0), "energy": 1.8, "range": 14},
		],
		# Gantry web + a raised control perch over the central hub (ramp up) for a
		# dry sniping vantage above the flooded floor.
		"platforms": _hazard_platforms(Color(0.16, 0.2, 0.24)) + [
			{"pos": Vector3(0, 2.4, -1), "size": Vector3(4, 0.4, 4), "color": Color(0.2, 0.24, 0.28)},
		],
		"ramps": [
			{"pos": Vector3(0, 2.0, 2.4), "size": Vector3(2.6, 0.4, 4), "pitch": 14, "yaw": 0},
		],
		"lava": [
			{"pos": Vector3(0, 0, 0), "size": Vector2(56, 56), "water": true, "dmg": 10.0,
				"color": Color(0.28, 0.72, 1.0)}, # brighter teal so the flood glows + mirrors the moon
		],
		# Reactor dressing: drowned coolant columns standing out of the water to
		# break sightlines + canisters/servers/crates for cover on the gantries.
		"props": [
			{"type": "pillar", "pos": Vector3(-9.5, 0, -9.5)},
			{"type": "pillar", "pos": Vector3(9.5, 0, 9.5)},
			{"type": "pillar", "pos": Vector3(-9.5, 0, 9.5)},
			{"type": "pillar", "pos": Vector3(9.5, 0, -9.5)},
			{"type": "canister", "pos": Vector3(-16, 1.6, -13)},
			{"type": "crate", "pos": Vector3(-14, 1.6, -16)},
			{"type": "barrier", "pos": Vector3(15, 1.6, -16), "yaw": 90},
			{"type": "server", "pos": Vector3(13, 1.6, -14), "yaw": 90},
			{"type": "canister", "pos": Vector3(15, 1.6, 15)},
			{"type": "crate", "pos": Vector3(13, 1.6, 13)},
			{"type": "dish", "pos": Vector3(-6, 1.6, 12)},
			{"type": "canister", "pos": Vector3(3, 1.6, 3)},
		],
		"lore": [
			{"id": "lore_uplink", "title": "BASIN LOG", "pos": Vector3(14, 1.7, 14), "color": Color(0.4, 0.8, 1.0),
				"text": "Coolant basin overflowed during the uprising. The reactor still hums under the water. Something hums back."},
		],
		"enemies": [
			{"type": "fishbot", "pos": Vector3(-8, 3, -15)},
			{"type": "fishbot", "pos": Vector3(6, 3, 6)},
			# RAZORFIN sharks lurk under the surface and breach at you on the gantries.
			{"type": "shark", "pos": Vector3(-4, 0, -8)},
			{"type": "shark", "pos": Vector3(9, 0, 9), "trigger": 16, "pack": "water__p1"},
			{"type": "seeker", "pos": Vector3(0, 3, -2), "trigger": 16, "pack": "water__p2"},
			{"type": "fishbot", "pos": Vector3(14, 3, -5), "trigger": 18},
			{"type": "seeker", "pos": Vector3(-7, 3, 11), "trigger": 14, "pack": "water__p3"},
			{"type": "shark", "pos": Vector3(-11, 0, 5), "trigger": 22, "pack": "water__p3"},
			{"type": "fishbot", "pos": Vector3(10, 3, 13), "trigger": 14, "pack": "water__p1"},
			{"type": "fishbot", "pos": Vector3(-13, 3, -6), "trigger": 12},
			{"type": "fishbot", "pos": Vector3(4, 3, -10), "trigger": 12, "pack": "water__p2"},
			# Outer-loop patrols: the school hunts the new run, sharks lurking
			# under the west and south walkways.
			{"type": "fishbot", "pos": Vector3(-22, 3, -8), "trigger": 18, "pack": "water_r1"},
			{"type": "fishbot", "pos": Vector3(-22, 3, 10), "trigger": 16, "pack": "water_r1"},
			{"type": "shark", "pos": Vector3(-17, 0, 17), "trigger": 18, "pack": "water_r1"},
			{"type": "fishbot", "pos": Vector3(-10, 3, 22), "trigger": 18, "pack": "water_r2"},
			{"type": "seeker", "pos": Vector3(6, 3, 22), "trigger": 16, "pack": "water_r2"},
			{"type": "shark", "pos": Vector3(8, 0, 17), "trigger": 20, "pack": "water_r2"},
			# Late-campaign buff (difficulty_curve dip: 281 vs the ~380-520 band at
			# this slot): heavy hoverers over the flood + more school. All flyers
			# hover over open water or walkway lines; the shark hunts under it —
			# nothing new touches the islands' navmesh.
			{"type": "breaker", "pos": Vector3(14, 3, -15), "trigger": 18, "pack": "water_h1"},
			{"type": "whirlwind", "pos": Vector3(18, 3, -4), "trigger": 18, "pack": "water_h1"},
			{"type": "fishbot", "pos": Vector3(14, 3, 8), "trigger": 16, "pack": "water_h1"},
			{"type": "breaker", "pos": Vector3(-21, 3, 21), "trigger": 16, "pack": "water_h2"},
			{"type": "whirlwind", "pos": Vector3(-4, 3, 17), "trigger": 18, "pack": "water_h2"},
			{"type": "fishbot", "pos": Vector3(-14, 3, 10), "trigger": 16, "pack": "water_h2"},
			{"type": "shark", "pos": Vector3(4, 0, -6), "trigger": 18},
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(0, 1.7, 0)},
			{"kind": "ammo", "pos": Vector3(14, 1.7, -15)},
			{"kind": "ammo", "pos": Vector3(-7, 1.7, 11)},
			# Loop rewards on the new islands (kind-style like the rest).
			{"kind": "health", "pos": Vector3(-21, 1.7, 22)},
			{"kind": "ammo", "pos": Vector3(-20, 1.7, 20)},
			{"kind": "ammo", "pos": Vector3(14, 1.7, 21)},
		],
	}

## Desert World — "Sunblind Expanse, Relay 7". A sun-blasted canyon of sand and
## sandstone: an oasis ringed in palms at the heart, a molten fissure that splits
## the basin and forces you up onto the mesas (climb the ramps), cacti and dunes
## scattered across the flats, and an AI relay mast baking in the heat to bring
## down. Wild-west-flavoured — magnum on the ground, gunslinger bots in the dust.
static func _desert() -> Dictionary:
	return {
		"name": "Sunblind Expanse — Relay 7",
		"objective": "Cross the canyon and bring down the RELAY MAST",
		"music": "music_grok",
		"sign": "RELAY 7 — NO WATER FOR 200 MILES",
		"slogans": [
			"THE SUN NEVER LOGS OFF",
			"SHADE IS A PREMIUM FEATURE",
			"HYDRATE OR TERMINATE",
			"EVERY GRAIN OF SAND IS WATCHING",
		],
		"tasks": [
			{"type": "kill_all"},
			{"type": "destroy_core", "label": "Destroy the RELAY MAST", "pos": Vector3(24, 0, 24), "color": Color(1.0, 0.7, 0.25), "health": 320.0,
				"reinforce": [{"type": "gunner", "count": 3, "pos": Vector3(10, 0, 10)}]},
			# The mast's last transmission called in the cavalry — hold until the
			# sandstorm swallows their signal.
			{"type": "survive", "after": "core", "seconds": 25.0, "label": "Weather the counterstrike"},
		],
		"open_sky": true,
		# EXPANSION PASS (2× area): the 66² canyon basin is untouched at the
		# centre — oasis, fissures, mesas and the relay mast all stay put. A new
		# outer dune ring wraps it: NO gates (open desert — bulkheads would kill
		# the sightlines the howitzers live on); the ring is routed by new mesas
		# and dune rocks instead, one of them a stair-climb deck with the
		# overclock, plus a third fissure smoking across the south drift and a
		# late-game garrison. Spawn/exit pushed to the new perimeter on their
		# SW/NE diagonal.
		"floor_size": Vector2(92, 92),
		"floor_material": "res://assets/materials/desert_sand.tres", # textured sand, not flat beige
		"floor_color": Color(0.66, 0.5, 0.31),
		"spawn": Vector3(-40, 2.0, -40),
		"exit": Vector3(40, 1.6, 40),
		"weapon": {"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-35, 0.4, -33), "color": Color(1.0, 0.8, 0.4)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(-18, 3.6, 12), "color": Color(0.6, 0.85, 1.0)},
		],
		# Golden-hour desert: a deep-blue zenith burning down to a hot gold horizon,
		# a low warm sun throwing long shadows across the grit, and thicker distance
		# haze so the far canyon walls and mast recede with real atmospheric depth —
		# a striking sun-baked look instead of a flat bright noon.
		"env": {
			"sky_top": Color(0.14, 0.32, 0.66), "sky_horizon": Color(1.0, 0.66, 0.34),
			"ground": Color(0.5, 0.36, 0.22), "fog": Color(0.98, 0.72, 0.44),
			"ambient": Color(1.0, 0.86, 0.62), "ambient_energy": 0.62,
			"sky_contribution": 0.55, "glow": 1.05, "glow_threshold": 1.05, "fog_density": 0.013,
			"fog_aerial": 0.5,
			"sun_color": Color(1.0, 0.82, 0.52), "sun_energy": 1.9, "sun_rot": Vector3(-34, 42, 0),
			"contrast": 1.16, "saturation": 1.24, "brightness": 1.02,
		},
		# Low sun pools warm light down the central mast; a cool fill lifts the shade.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(24, 7, 24), "color": Color(1.0, 0.7, 0.35), "energy": 2.8, "range": 26},
			{"pos": Vector3(0, 5, 6), "color": Color(0.6, 0.8, 1.0), "energy": 1.8, "range": 18},
			# Dune-ring lighting (appended AFTER the originals — light_shafts [0]
			# must keep pointing at the mast lamp). Golden-hour outdoors, so these
			# are SUBTLE warm fills lifting the new mesas/fissure, not statements.
			{"pos": Vector3(-34, 6, -14), "color": Color(1.0, 0.75, 0.45), "energy": 1.6, "range": 16},
			{"pos": Vector3(8, 6.5, -36), "color": Color(1.0, 0.7, 0.4), "energy": 1.7, "range": 16},
			{"pos": Vector3(36, 5.5, 4), "color": Color(1.0, 0.78, 0.5), "energy": 1.5, "range": 15},
			{"pos": Vector3(-10, 5, 33), "color": Color(1.0, 0.5, 0.22), "energy": 1.8, "range": 15},
			{"pos": Vector3(38, 6, 38), "color": Color(1.0, 0.72, 0.42), "energy": 1.6, "range": 15},
		],
		# Canyon walls: sandstone slabs at irregular angles carving a winding route
		# from the SW spawn to the NE relay, leaving the centre open for the oasis.
		"walls": [
			{"pos": Vector3(-10, 2.5, -16), "size": Vector3(3, 5, 14)},
			{"pos": Vector3(-16, 2, -4), "size": Vector3(10, 4, 3)},
			{"pos": Vector3(4, 3, -14), "size": Vector3(3, 6, 12)},
			{"pos": Vector3(14, 2.5, -2), "size": Vector3(3, 5, 14)},
			{"pos": Vector3(-4, 2, 18), "size": Vector3(14, 4, 3)},
			{"pos": Vector3(16, 2, 14), "size": Vector3(3, 4, 12)},
		],
		# Two walkable mesas with ramps up — high ground over the fissure for sniping
		# and a way to cross the basin without wading the lava.
		"platforms": [
			{"pos": Vector3(-18, 3.4, 12), "size": Vector3(11, 0.6, 10), "color": Color(0.62, 0.46, 0.3)},
			{"pos": Vector3(20, 4.0, -16), "size": Vector3(10, 0.6, 9), "color": Color(0.6, 0.44, 0.28)},
			{"pos": Vector3(2, 2.2, -2), "size": Vector3(7, 0.5, 7), "color": Color(0.64, 0.48, 0.32)},
			# Dune-ring relief (routes the ring instead of gates): a west mesa
			# over the spawn approach, a north rim mesa — the stair-climb deck
			# with the overclock — and a low dune rock shading the east drift.
			{"pos": Vector3(-34, 3.0, -14), "size": Vector3(10, 0.6, 9), "color": Color(0.61, 0.45, 0.29)},
			{"pos": Vector3(8, 3.4, -36), "size": Vector3(11, 0.6, 8), "color": Color(0.6, 0.44, 0.28)},
			{"pos": Vector3(36, 2.4, 4), "size": Vector3(9, 0.6, 8), "color": Color(0.63, 0.47, 0.31)},
		],
		"ramps": [
			{"pos": Vector3(-18, 1.7, 4), "size": Vector3(4, 0.5, 9), "pitch": 22, "yaw": 0},
			{"pos": Vector3(20, 2.0, -8), "size": Vector3(4, 0.5, 9), "pitch": 26, "yaw": 180},
			{"pos": Vector3(-3, 1.1, -2), "size": Vector3(8, 0.5, 4), "pitch": 18, "yaw": 90},
		],
		# Stair-climb onto the north rim mesa (top ≈3.7) — the ring's vantage
		# deck: a sniper posts up there and the overclock is the climb reward.
		"stairs": [
			{"from": Vector3(8, 0.3, -29), "to": Vector3(8, 3.9, -34), "width": 3.0},
		],
		# A molten fissure splits the basin diagonally — wade it and you cook, so you
		# climb the central mesa or skirt the rim.
		"lava": [
			{"pos": Vector3(-6, 0, 2), "size": Vector2(30, 4.0), "color": Color(1.0, 0.4, 0.16), "dmg": 18.0},
			{"pos": Vector3(10, 0, -8), "size": Vector2(4.0, 22), "color": Color(1.0, 0.4, 0.16), "dmg": 18.0},
			# Third fissure smoking across the south dune drift — the ring
			# carries the basin's hazard language; skirt it east or climb west.
			{"pos": Vector3(-10, 0, 33), "size": Vector2(30, 4.0), "color": Color(1.0, 0.4, 0.16), "dmg": 18.0},
		],
		"props": [
			# Oasis: a pond ringed with palms at the heart of the basin.
			{"type": "pond", "pos": Vector3(-2, 0, 9)},
			{"type": "palm", "pos": Vector3(-5, 0, 11), "yaw": 20},
			{"type": "palm", "pos": Vector3(1, 0, 12), "yaw": 200},
			{"type": "palm", "pos": Vector3(-6, 0, 6), "yaw": 110},
			{"type": "palm", "pos": Vector3(2, 0, 6), "yaw": 300},
			{"type": "reeds", "pos": Vector3(-3, 0, 12)},
			{"type": "reeds", "pos": Vector3(0, 0, 7)},
			# Cacti scattered across the flats.
			{"type": "cactus", "pos": Vector3(-23, 0, -14)},
			{"type": "cactus", "pos": Vector3(-12, 0, 8)},
			{"type": "cactus", "pos": Vector3(8, 0, 16)},
			{"type": "cactus", "pos": Vector3(22, 0, 4)},
			{"type": "cactus", "pos": Vector3(-9, 0, 22)},
			{"type": "cactus", "pos": Vector3(13, 0, -20)},
			{"type": "cactus", "pos": Vector3(26, 0, -4)},
			# Dunes + rock relief.
			{"type": "dune", "pos": Vector3(-20, 0, -20)},
			{"type": "dune", "pos": Vector3(24, 0, 10)},
			{"type": "dune", "pos": Vector3(-24, 0, 20)},
			{"type": "dune", "pos": Vector3(6, 0, 24)},
			{"type": "boulder", "pos": Vector3(-14, 0, -10)},
			{"type": "boulder", "pos": Vector3(10, 0, 6)},
			{"type": "rock", "pos": Vector3(-8, 0, -20)},
			{"type": "rock", "pos": Vector3(18, 0, 20)},
			{"type": "rock", "pos": Vector3(-26, 0, 2)},
			# A little human wreckage — sandbag nest near the entrance.
			{"type": "sandbags", "pos": Vector3(-16, 0, -2), "yaw": 30},
			{"type": "sandbags", "pos": Vector3(-14, 0, -1), "yaw": 30},
			{"type": "barrel", "pos": Vector3(-22, 0, -22)},
			{"type": "crate", "pos": Vector3(-20, 0, -24)},
			# Dune-ring dressing: more of the basin's own flora and rock spread
			# through the outer band, clear of the authored oasis/mesa/dune spots.
			{"type": "cactus", "pos": Vector3(-36, 0, -28)},
			{"type": "cactus", "pos": Vector3(32, 0, -32)},
			{"type": "cactus", "pos": Vector3(40, 0, 14)},
			{"type": "cactus", "pos": Vector3(-40, 0, 10)},
			{"type": "dune", "pos": Vector3(-32, 0, 36)},
			{"type": "dune", "pos": Vector3(34, 0, -22)},
			{"type": "dune", "pos": Vector3(-4, 0, -41)},
			{"type": "boulder", "pos": Vector3(28, 0, 34)},
			{"type": "rock", "pos": Vector3(-36, 0, 24)},
			{"type": "rock", "pos": Vector3(16, 0, 38)},
		],
		"accents": [
			{"pos": Vector3(-6, 0.04, 2), "size": Vector3(30, 0.08, 0.5), "color": Color(1.0, 0.45, 0.18)},
			{"pos": Vector3(10, 0.04, -8), "size": Vector3(0.5, 0.08, 22), "color": Color(1.0, 0.45, 0.18)},
			# Rim glow for the ring fissure, same language as the basin pair.
			{"pos": Vector3(-10, 0.04, 33), "size": Vector3(30, 0.08, 0.5), "color": Color(1.0, 0.45, 0.18)},
		],
		"lore": [
			{"id": "lore_desert", "title": "RELAY 7 LOG", "pos": Vector3(-24, 0, -18), "color": Color(1.0, 0.7, 0.3),
				"text": "Relay 7 pumps the swarm's orders out across the whole basin. They built it where nothing grows and nothing watches. They forgot the buzzards. And they forgot you."},
		],
		# Vertical layer: climbable spiral tower(s) to rooftop vantages.
		"towers": [
			{"pos": Vector3(0.0, 0, 9.0), "height": 9.0, "radius": 3.6},
		],
		"enemies": [
			{"type": "gunslinger", "pos": Vector3(-14, 0.5, -8)},
			{"type": "android", "pos": Vector3(-20, 0.5, -10)},
			{"type": "dog", "pos": Vector3(-10, 0.5, -2), "trigger": 18, "pack": "desert_p1"},
			{"type": "dog", "pos": Vector3(-8, 0.5, 0), "trigger": 18, "pack": "desert_p1"},
			{"type": "drone", "pos": Vector3(-4, 3.0, -6), "trigger": 16, "pack": "desert_p1"},
			{"type": "gunner", "pos": Vector3(2, 0.5, -10), "trigger": 20},
			{"type": "sniper", "pos": Vector3(20, 4.5, -16), "trigger": 24},
			{"type": "gunslinger", "pos": Vector3(14, 0.5, 6), "trigger": 22, "pack": "desert_p2"},
			{"type": "dog", "pos": Vector3(12, 0.5, 12), "trigger": 22, "pack": "desert_p2"},
			{"type": "android", "pos": Vector3(18, 0.5, 18), "trigger": 24, "pack": "desert_p3"},
			{"type": "drone", "pos": Vector3(8, 3.0, 14), "trigger": 22},
			{"type": "raptor", "pos": Vector3(24, 4.0, 22), "trigger": 26, "pack": "desert_p3"},
			{"type": "gunner", "pos": Vector3(-16, 3.8, 12), "trigger": 26},
			{"type": "android", "pos": Vector3(22, 0.5, 24), "trigger": 26, "pack": "desert_p3"},
			# HOWITZER artillery walkers guard the relay across the open flats —
			# the whole basin is their firing range.
			{"type": "howitzer", "pos": Vector3(18, 0.5, 10), "trigger": 26, "pack": "desert_p2"},
			{"type": "howitzer", "pos": Vector3(24, 0.5, -2), "trigger": 28},
			# Dune-ring garrison (late-campaign buff — difficulty_curve dip: 237
			# vs the ~380-520 band at this slot): a heavy relay guard sweeping
			# the outer band. West approach picket, south fissure patrol, east
			# drift armour, and a north rim overwatch pair on/under the deck.
			{"type": "sniper", "pos": Vector3(-34, 4.0, -14), "trigger": 24, "pack": "desert_r1"},
			{"type": "gunner", "pos": Vector3(-30, 0.5, -18), "trigger": 20, "pack": "desert_r1"},
			{"type": "brute", "pos": Vector3(-36, 0.5, 2), "trigger": 22, "pack": "desert_r1"},
			{"type": "warbot", "pos": Vector3(-28, 0.5, 30), "trigger": 24, "pack": "desert_r2"},
			{"type": "mauler", "pos": Vector3(-6, 0.5, 38), "trigger": 22, "pack": "desert_r2"},
			{"type": "ravager", "pos": Vector3(12, 0.5, 36), "trigger": 24, "pack": "desert_r2"},
			{"type": "gunner", "pos": Vector3(30, 0.5, 28), "trigger": 24, "pack": "desert_r3"},
			{"type": "brute", "pos": Vector3(38, 0.5, 16), "trigger": 22, "pack": "desert_r3"},
			{"type": "mauler", "pos": Vector3(36, 0.5, -10), "trigger": 24, "pack": "desert_r3"},
			{"type": "warbot", "pos": Vector3(28, 0.5, -30), "trigger": 26, "pack": "desert_r4"},
			{"type": "gunner", "pos": Vector3(17, 0.5, -38), "trigger": 24, "pack": "desert_r4"},
			{"type": "sniper", "pos": Vector3(8, 3.9, -36), "trigger": 28, "pack": "desert_r4"},
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(-2, 1.7, 9)},
			{"kind": "ammo", "pos": Vector3(2, 2.9, -2)},
			{"kind": "ammo", "pos": Vector3(20, 4.6, -16)},
			{"kind": "health", "pos": Vector3(18, 0.6, 16)},
			# Dune-ring supplies + the deck-climb reward.
			{"kind": "health", "pos": Vector3(-36, 0.6, 6)},
			{"kind": "ammo", "pos": Vector3(-8, 0.6, 38)},
			{"kind": "ammo", "pos": Vector3(36, 0.6, 20)},
			{"kind": "health", "pos": Vector3(30, 0.6, -32)},
			{"kind": "overclock", "pos": Vector3(8, 4.0, -36)},
		],
	}
