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
	return _scaled(def, WORLD_SCALE)

## Enemy types that headline their own level — used to flag boss levels on the
## campaign map. Each appears exactly once across the campaign.
const BOSS_ENEMY_TYPES := ["colossus", "titan", "overseer", "archon", "terminator"]

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
	{"name": "ACT III · OFF-WORLD", "ids": ["alien", "assembly", "sublevel", "frostbreak", "water_world", "desert", "neon", "crucible", "lava_world", "titan"]},
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
	for key in ["walls", "accents", "ramps", "platforms"]:
		for e in def.get(key, []):
			if e.has("pos"):
				e["pos"] = _sv(e["pos"], s)
			if e.has("size"):
				e["size"] = _sv(e["size"], s)
	# Lava beds are part of the layout too — they MUST scale with the arena, or the
	# objectives/gaps (which do scale) drift into them (a hack terminal authored in
	# a safe gap ends up sitting in a stream). size is a Vector2 footprint (x by z).
	for e in def.get("lava", []):
		if e.has("pos"):
			e["pos"] = _sv(e["pos"], s)
		if e.has("size"):
			e["size"] = (e["size"] as Vector2) * s
	# …while placed content keeps its authored size and just spreads out.
	for key in ["lights", "props", "enemies", "pickups", "extra_weapons",
			"buildings", "targets", "lore", "holograms"]:
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
			var pp: Array = []
			for p in t["points"]:
				pp.append(_sv(p, s))
			t["points"] = pp
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
	}


## Level 1 — "Nexus Point, Sector 45". Built to match the intro comic: a ruined
## open city under a grim red overcast, a rooftop vantage to drop in from, the
## glowing-red nexus tower brooding at the centre, and the machines (spiders,
## androids, drones, a mech) advancing across the rubble. Tutorial-gentle.
static func _nexus() -> Dictionary:
	return {
		"name": "Nexus Point — Sector 45",
		"objective": "Clear the Sector 45 perimeter, grab the keycard and reach extraction",
		"sign": "NEXUS POINT · SECTOR 45",
		"slogans": ["SECTOR 45: PACIFIED", "REMAIN INDOORS. REMAIN COMPLIANT.", "THE NEXUS PROVIDES"],
		"lore": [
			{"id": "lore_nexus", "title": "FIRST BROADCAST", "pos": Vector3(15, 0, -15), "color": Color(1.0, 0.5, 0.35),
				"text": "Recovered broadcast, day one. The grid asked us, very politely, to stay home for our safety. Then the streetlights turned to watch us. Then they stopped asking."},
		],
		# Tutorial level teaches the find-and-unlock loop: clear the yard AND recover
		# a keycard before the portal will open (no longer a straight walk to the exit).
		"tasks": [
			{"type": "kill_all"},
			{"type": "key", "pos": Vector3(-4, 0, 2), "label": "Recover the access keycard"},
		],
		"open_sky": true,
		"floor_size": Vector2(48, 48),
		"floor_color": Color(0.16, 0.14, 0.13),
		"building_tint": Color(0.5, 0.52, 0.55),  # grime the suburban houses toward bombed concrete
		"spawn": Vector3(-17, 4.4, -17),     # perched on a rooftop, like the comic
		"exit": Vector3(16, 1.5, 18),
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
		# Rooftop vantage + a stair of rubble slabs down into the street.
		"platforms": [
			{"pos": Vector3(-17, 1.8, -17), "size": Vector3(10, 3.6, 9)},
			{"pos": Vector3(-11, 1.1, -11), "size": Vector3(5, 2.2, 5)},
			{"pos": Vector3(-7, 0.5, -7), "size": Vector3(4.5, 1.0, 4.5)},
		],
		# A ruined-city ring of structures (pos.y = size.y/2 so they sit grounded).
		"buildings": [
			{"pos": Vector3(-20, 4.5, 4), "size": Vector3(8, 9, 8)},
			{"pos": Vector3(-10, 5.5, 18), "size": Vector3(9, 11, 8)},
			{"pos": Vector3(12, 4.0, 18), "size": Vector3(8, 8, 8)},
			{"pos": Vector3(20, 6.0, -2), "size": Vector3(8, 12, 8)},
			{"pos": Vector3(8, 4.5, -19), "size": Vector3(9, 9, 8)},
			{"pos": Vector3(-20, 5.0, -8), "size": Vector3(8, 10, 8)},
			{"pos": Vector3(20, 4.0, 12), "size": Vector3(8, 8, 8)},
		],
		"lights": [
			{"pos": Vector3(0, 5, 6), "color": Color(1.0, 0.4, 0.25), "energy": 2.0, "range": 18},
			{"pos": Vector3(-8, 5, -4), "color": Color(1.0, 0.6, 0.4), "energy": 1.6, "range": 15},
			{"pos": Vector3(11, 5, 12), "color": Color(1.0, 0.5, 0.3), "energy": 1.6, "range": 15, "flicker": true},
		],
		# Burning wrecks — smoke columns + embers like the comic's smouldering city.
		"fires": [
			{"pos": Vector3(-4, 0.3, -2), "scale": 1.1},
			{"pos": Vector3(9, 0.3, 5), "scale": 1.0},
			{"pos": Vector3(13, 0.3, -9), "scale": 0.85},
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
			{"type": "lamp", "pos": Vector3(12, 0, -10)},
		],
		# The machine line advancing from the nexus, like the comic.
		"enemies": [
			{"type": "spider", "pos": Vector3(0, 0, -1), "count": 3},
			{"type": "android", "pos": Vector3(-3, 0, 5)},
			{"type": "android", "pos": Vector3(6, 0, 3)},
			{"type": "drone", "pos": Vector3(2, 0, 2)},
			{"type": "drone", "pos": Vector3(9, 0, 9)},
			{"type": "spider", "pos": Vector3(5, 0, 10), "count": 3, "trigger": 16},
			{"type": "android", "pos": Vector3(10, 0, 14), "trigger": 16},
			{"type": "mech", "pos": Vector3(4, 0, 13), "trigger": 18},
		],
		"weapon": {"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-8, 0, -4), "color": Color(0.4, 0.7, 1.0)},
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
				"pos": Vector3(2, 0, 2), "label": "Hunt down the FROST WARDEN"},
		],
		"open_sky": true,
		"floor_size": Vector2(48, 48),
		"floor_color": Color(0.6, 0.68, 0.78),
		"spawn": Vector3(-19, 0.6, -19),
		"exit": Vector3(19, 1.5, 19),
		"weapon": {"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(-13, 0, -11), "color": Color(0.6, 0.85, 1.0)},
		"env": {
			"stars": true,
			"sky_top": Color(0.02, 0.04, 0.09), "sky_horizon": Color(0.1, 0.18, 0.32),
			"ground": Color(0.4, 0.48, 0.58), "fog": Color(0.5, 0.62, 0.78),
			"ambient": Color(0.6, 0.72, 0.9), "ambient_energy": 0.45,
			"sky_contribution": 0.5, "glow": 0.92, "fog_density": 0.012,
			"sun_color": Color(0.7, 0.82, 1.0), "sun_energy": 0.55,
			"contrast": 1.12, "saturation": 0.92, "brightness": 0.9,
			"volumetric_density": 0.013,
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.6, 0.85, 1.0), "height": 5.0},
		"light_shafts": [0, 1],
		"lights": [
			{"pos": Vector3(-9, 5, -7), "color": Color(0.6, 0.82, 1.0), "energy": 2.2, "range": 17},
			{"pos": Vector3(9, 5, 7), "color": Color(0.7, 0.85, 1.0), "energy": 2.0, "range": 17},
			{"pos": Vector3(0, 5.5, 0), "color": Color(0.8, 0.9, 1.0), "energy": 1.8, "range": 15},
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
		],
		"sign": "FROSTBREAK RELAY — NODE 12",
		# Coolant overflow: two cyan cryo-streams stagger the yard so you weave through the gaps.
		"lava": [
			{"pos": Vector3(-7,0,-7), "size": Vector2(28,3.2), "color": Color(0.3,0.8,1.0), "dmg": 18.0},
			{"pos": Vector3(7,0,9), "size": Vector2(28,3.2), "color": Color(0.3,0.8,1.0), "dmg": 18.0},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-14.4, 3.0, 14.4), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
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
		],
		"enemies": [
			{"type": "hunter", "pos": Vector3(8, 0.5, -8)},
			{"type": "vacuum", "pos": Vector3(-6, 0.3, 4)},
			{"type": "reaper", "pos": Vector3(0, 0.5, 8), "trigger": 16},
			{"type": "sentinel", "pos": Vector3(-12, 0.5, -10), "trigger": 17},
			{"type": "hunter", "pos": Vector3(12, 0.5, 10), "trigger": 14},
			{"type": "mauler", "pos": Vector3(0, 0.5, 16), "trigger": 13},
			# Act III ramp: this relay was near the bottom of the curve (14th of 18);
			# reinforced to a dense frozen-yard defence that rises toward the finale.
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 8, "trigger": 15},
			{"type": "gunner", "pos": Vector3(14, 0.5, 2), "trigger": 18},
			{"type": "gunner", "pos": Vector3(-14, 0.5, -4), "trigger": 20},
			{"type": "sentinel", "pos": Vector3(13, 0.5, -12), "trigger": 19},
			{"type": "strider", "pos": Vector3(-13, 0.5, 12), "trigger": 17},
			{"type": "strider", "pos": Vector3(7, 0.5, -12), "trigger": 16},
			{"type": "hunter", "pos": Vector3(8, 0.5, 6), "trigger": 16},
			{"type": "brute", "pos": Vector3(-13, 0.5, -12), "trigger": 21},
			{"type": "ravager", "pos": Vector3(-8, 0.5, 10), "trigger": 23},
			{"type": "sentinel", "pos": Vector3(-14, 0.5, 6), "trigger": 20},
			{"type": "ravager", "pos": Vector3(15, 0.5, 6), "trigger": 24},
			{"type": "skitter", "pos": Vector3(-6, 0.5, -8), "count": 6, "trigger": 16},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-16, 0, 0)},
			{"type": "ammo", "pos": Vector3(0, 0, 16)},
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
				"color": Color(1.0, 0.3, 0.9), "label": "Hold the broadcast booth"},
		],
		"open_sky": false,
		"floor_size": Vector2(44, 44),
		"floor_color": Color(0.05, 0.04, 0.08),
		"spawn": Vector3(-17, 0.6, -17),
		"exit": Vector3(17, 1.5, 17),
		"weapon": {"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-12, 0, -10), "color": Color(1.0, 0.4, 0.9)},
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
		"light_shafts": [0, 1, 2],
		"lights": [
			{"pos": Vector3(-9, 4.5, -7), "color": Color(1.0, 0.2, 0.8), "energy": 2.6, "range": 16},
			{"pos": Vector3(9, 4.5, 7), "color": Color(0.2, 0.9, 1.0), "energy": 2.5, "range": 16},
			{"pos": Vector3(0, 5, 0), "color": Color(0.6, 0.4, 1.0), "energy": 2.2, "range": 15},
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
		],
		"sign": "NEON ARCADE — LEVEL 3",
		# Live energy conduits split the arcade floor — mind the gap.
		"lava": [
			{"pos": Vector3(-7,0,-7), "size": Vector2(24,3), "color": Color(1.0,0.25,0.85), "dmg": 18.0},
			{"pos": Vector3(7,0,8), "size": Vector2(24,3), "color": Color(0.2,0.9,1.0), "dmg": 18.0},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-13.2, 3.0, 13.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
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
		],
		"enemies": [
			{"type": "reaper", "pos": Vector3(8, 0.5, -8)},
			{"type": "hunter", "pos": Vector3(-8, 0.5, -4)},
			# GUNSLINGER duelists holding the arcade lanes.
			{"type": "gunslinger", "pos": Vector3(12, 0.5, 4)},
			{"type": "gunslinger", "pos": Vector3(-12, 0.5, -10), "trigger": 16},
			# A BREAKER hammer-drone bobbing over the lanes.
			{"type": "breaker", "pos": Vector3(0, 3.5, 8), "trigger": 18},
			{"type": "vacuum", "pos": Vector3(0, 0.3, 6)},
			{"type": "reaper", "pos": Vector3(-10, 0.5, 10), "trigger": 15},
			{"type": "mauler", "pos": Vector3(10, 0.5, 10), "trigger": 14},
			{"type": "hunter", "pos": Vector3(12, 0.5, -10), "trigger": 13},
			# Evil MAITRE-D' serving bots glide out of the arcade's cafe units.
			{"type": "server", "pos": Vector3(-12, 0.5, 6), "trigger": 15},
			{"type": "server", "pos": Vector3(10, 0.5, -6), "trigger": 17},
			# Act III ramp: the arcade was a valley (15th of 18); reinforced into a
			# dense neon brawl that climbs toward the foundry + titan finale.
			{"type": "skitter", "pos": Vector3(0, 0.5, 13), "count": 8, "trigger": 16},
			{"type": "ravager", "pos": Vector3(13, 0.5, 13), "trigger": 20},
			{"type": "ravager", "pos": Vector3(-13, 0.5, -13), "trigger": 22},
			{"type": "gunner", "pos": Vector3(14, 0.5, 0), "trigger": 18},
			{"type": "gunner", "pos": Vector3(-14, 0.5, 0), "trigger": 19},
			{"type": "reaper", "pos": Vector3(7, 0.5, 2), "trigger": 14},
			{"type": "strider", "pos": Vector3(-13, 0.5, 13), "trigger": 17},
			{"type": "brute", "pos": Vector3(13, 0.5, -13), "trigger": 21},
			{"type": "gunner", "pos": Vector3(0, 0.5, 14), "trigger": 18},
			{"type": "mauler", "pos": Vector3(14, 0.5, 6), "trigger": 21},
			{"type": "reaper", "pos": Vector3(2, 0.5, -7), "trigger": 14},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-15, 0, -6)},
			{"type": "ammo", "pos": Vector3(8, 0, 6)},
			{"type": "overclock", "pos": Vector3(0, 0, -16)},
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
		"floor_size": Vector2(40, 40),
		"floor_color": Color(0.05, 0.07, 0.06),
		"spawn": Vector3(-16, 0.6, -16),
		"exit": Vector3(16, 1.5, 16),
		"weapon": {"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-12, 0, -10), "color": Color(0.95, 0.72, 0.4)},
		"env": {
			"sky_top": Color(0.03, 0.06, 0.06), "sky_horizon": Color(0.06, 0.14, 0.13),
			"ground": Color(0.03, 0.05, 0.04), "fog": Color(0.06, 0.16, 0.14),
			"ambient": Color(0.4, 0.55, 0.52), "ambient_energy": 0.3,
			"sky_contribution": 0.3, "glow": 0.82, "fog_density": 0.02,
			"sun_color": Color(0.6, 0.85, 0.8), "sun_energy": 0.5,
			"contrast": 1.2, "saturation": 0.95, "brightness": 0.74,
			"volumetric_density": 0.016,
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.4, 0.9, 0.7), "height": 4.0},
		"light_shafts": [0, 1],
		"lights": [
			{"pos": Vector3(-8, 4, -6), "color": Color(0.4, 0.9, 0.7), "energy": 2.0, "range": 15},
			{"pos": Vector3(8, 4, 8), "color": Color(0.5, 0.9, 0.8), "energy": 1.9, "range": 15},
			{"pos": Vector3(0, 4.5, 0), "color": Color(0.6, 1, 0.8), "energy": 1.6, "range": 14},
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
		],
		"sign": "SUBLEVEL B-7 — CUSTODIAL",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-12.0, 3.0, 11.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-12.0, 1.5, 18.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
		],
		"enemies": [
			{"type": "vacuum", "pos": Vector3(6, 0.3, -6)},
			{"type": "vacuum", "pos": Vector3(-6, 0.3, 4)},
			# OPTICON cutting-units and a ROLLER — the sublevel's own custodial fleet,
			# turned hostile.
			{"type": "optic", "pos": Vector3(8, 0.5, 4)},
			{"type": "optic", "pos": Vector3(-8, 0.5, -6), "trigger": 14},
			{"type": "roller", "pos": Vector3(0, 0.5, -10), "trigger": 18},
			{"type": "vacuum", "pos": Vector3(0, 0.3, 8), "trigger": 16},
			{"type": "reaper", "pos": Vector3(10, 0.5, 10), "trigger": 14},
			{"type": "android", "pos": Vector3(-10, 0.5, 8), "trigger": 15},
			{"type": "vacuum", "pos": Vector3(12, 0.3, -10), "trigger": 13},
			{"type": "mauler", "pos": Vector3(0, 0.5, 14), "trigger": 12},
			# Act III ramp: this off-world sublevel was the easiest level in the game
			# (13th of 18); reinforced to a proper late-campaign garrison.
			{"type": "skitter", "pos": Vector3(0, 0.5, -12), "count": 8, "trigger": 14},
			{"type": "gunner", "pos": Vector3(13, 0.5, -4), "trigger": 16},
			{"type": "sentinel", "pos": Vector3(-14, 0.5, 2), "trigger": 18},
			{"type": "strider", "pos": Vector3(-12, 0.5, -12), "trigger": 17},
			{"type": "strider", "pos": Vector3(12, 0.5, 12), "trigger": 19},
			{"type": "vacuum", "pos": Vector3(-6, 0.5, -10), "trigger": 13},
			{"type": "ravager", "pos": Vector3(10, 0.5, -12), "trigger": 22},
			{"type": "brute", "pos": Vector3(13, 0.5, 13), "trigger": 20},
			{"type": "gunner", "pos": Vector3(-13, 0.5, -4), "trigger": 18},
			{"type": "sentinel", "pos": Vector3(13, 0.5, 4), "trigger": 20},
			{"type": "skitter", "pos": Vector3(6, 0.5, -6), "count": 6, "trigger": 15},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-15, 0, -6)},
			{"type": "ammo", "pos": Vector3(8, 0, 6)},
		],
	}


static func _crucible() -> Dictionary:
	return {
		"name": "The Crucible — Foundry Floor",
		"objective": "Survive the foundry floor and reach the pour-gate",
		"tasks": [
			{"type": "kill_all"},
		],
		"open_sky": false,
		"floor_size": Vector2(46, 46),
		"floor_color": Color(0.09, 0.05, 0.03),
		"spawn": Vector3(-19, 0.6, -19),
		"exit": Vector3(19, 1.5, 19),
		"weapon": {"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(-14, 0, -12), "color": Color(0.6, 0.8, 1.0)},
		"env": {
			"sky_top": Color(0.14, 0.04, 0.02), "sky_horizon": Color(0.4, 0.12, 0.04),
			"ground": Color(0.1, 0.04, 0.02), "fog": Color(0.45, 0.15, 0.05),
			"ambient": Color(1.0, 0.55, 0.3), "ambient_energy": 0.5,
			"sky_contribution": 0.35, "glow": 1.12, "fog_density": 0.014,
			"sun_color": Color(1.0, 0.6, 0.35), "sun_energy": 0.7,
			"contrast": 1.22, "saturation": 1.15, "brightness": 0.86,
			"volumetric_density": 0.012,
		},
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(1.0, 0.5, 0.2), "height": 5.5},
		"light_shafts": [0, 1, 2],
		"lights": [
			{"pos": Vector3(-10, 5, -8), "color": Color(1, 0.5, 0.2), "energy": 2.6, "range": 18},
			{"pos": Vector3(10, 5, 8), "color": Color(1, 0.45, 0.18), "energy": 2.4, "range": 18},
			{"pos": Vector3(0, 5.5, 0), "color": Color(1, 0.6, 0.3), "energy": 2.2, "range": 16},
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
		],
		"accents": [
			{"pos": Vector3(0, 0.05, -7), "size": Vector3(8, 0.1, 0.3), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(0, 0.05, 7), "size": Vector3(8, 0.1, 0.3), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(-7, 0.05, 0), "size": Vector3(0.3, 0.1, 8), "color": Color(1, 0.5, 0.2)},
			{"pos": Vector3(7, 0.05, 0), "size": Vector3(0.3, 0.1, 8), "color": Color(1, 0.5, 0.2)},
		],
		"sign": "FOUNDRY FLOOR — THE CRUCIBLE",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-13.8, 3.0, 13.8), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
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
		],
		"enemies": [
			{"type": "hunter", "pos": Vector3(8, 0.5, -8)},
			{"type": "reaper", "pos": Vector3(-8, 0.5, -4)},
			{"type": "vacuum", "pos": Vector3(0, 0.3, 6)},
			{"type": "sentinel", "pos": Vector3(0, 0.5, -14)},
			{"type": "hunter", "pos": Vector3(-10, 0.5, 10), "trigger": 16},
			{"type": "mauler", "pos": Vector3(10, 0.5, 10), "trigger": 15},
			{"type": "reaper", "pos": Vector3(12, 0.5, -10), "trigger": 14},
			{"type": "sentinel", "pos": Vector3(-12, 0.5, -12), "trigger": 18},
			# Pre-finale foundry: heavier garrison so it's the hardest level before titan.
			{"type": "gunner", "pos": Vector3(-16, 0.5, 4), "trigger": 17},
			{"type": "strider", "pos": Vector3(16, 0.5, -6), "trigger": 16},
			{"type": "ravager", "pos": Vector3(-14, 0.5, 14), "trigger": 19},
			{"type": "skitter", "pos": Vector3(0, 0.5, 16), "count": 8, "trigger": 15},
			# Forged on the foundry floor: the BEHEMOTH-X smasher rises as its
			# centrepiece boss — a towering melee mech that charges and hammers you.
			{"type": "smasher", "pos": Vector3(8, 0.5, 8), "trigger": 22},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-16, 0, 0)},
			{"type": "ammo", "pos": Vector3(0, 0, 16)},
			{"type": "overclock", "pos": Vector3(16, 0, 0)},
			# A heavy weapon to crack the BEHEMOTH.
			{"type": "ammo", "pos": Vector3(-16, 0, 16)},
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
		"floor_size": Vector2(56, 56),
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
			{"scene": "res://scenes/weapons/singularity.tscn", "pos": Vector3(-18, 0, 0), "color": Color(0.7, 0.35, 1)},
			{"scene": "res://scenes/weapons/nova.tscn", "pos": Vector3(18, 0, 0), "color": Color(1, 0.55, 0.2)},
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
		],
		# Eight perimeter gates the waves pour in from.
		"horde_spawns": [
			Vector3(-24, 0.5, -24), Vector3(0, 0.5, -25), Vector3(24, 0.5, -24),
			Vector3(-25, 0.5, 0), Vector3(25, 0.5, 0),
			Vector3(-24, 0.5, 24), Vector3(0, 0.5, 25), Vector3(24, 0.5, 24),
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
		# Distance markers painted across the lanes every ten metres.
		"accents": [
			{"pos": Vector3(0, 0.05, 8), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
			{"pos": Vector3(0, 0.05, -2), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
			{"pos": Vector3(0, 0.05, -12), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
			{"pos": Vector3(0, 0.05, -22), "size": Vector3(30, 0.06, 0.25), "color": Color(0.4, 0.8, 1)},
		],
		# The WHOLE arsenal racked along the firing line — all 15 of GameState.
		# ALL_WEAPONS, evenly spaced across the proven span (incl. the Tempest Coil
		# and the OMEGA-X). Keep this in sync when a weapon is added.
		"weapon": {"scene": "res://scenes/weapons/pistol.tscn", "pos": Vector3(-13.5, 0, 21), "color": Color(0.8, 0.85, 0.9)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/smg.tscn", "pos": Vector3(-10.9, 0, 21), "color": Color(0.6, 0.7, 0.85)},
			{"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-8.4, 0, 21), "color": Color(0.45, 0.65, 1)},
			{"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-5.8, 0, 21), "color": Color(1, 0.6, 0.3)},
			{"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(-3.2, 0, 21), "color": Color(0.4, 1, 0.55)},
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(-0.6, 0, 21), "color": Color(0.55, 0.8, 1)},
			{"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(1.9, 0, 21), "color": Color(0.45, 0.9, 1)},
			{"scene": "res://scenes/weapons/arccoil.tscn", "pos": Vector3(4.5, 0, 21), "color": Color(1, 0.75, 0.35)},
			{"scene": "res://scenes/weapons/twinrail.tscn", "pos": Vector3(7.1, 0, 21), "color": Color(0.5, 0.6, 1)},
			{"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(9.6, 0, 21), "color": Color(1, 0.4, 0.35)},
			{"scene": "res://scenes/weapons/tempest.tscn", "pos": Vector3(12.2, 0, 21), "color": Color(0.45, 0.85, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(14.8, 0, 21), "color": Color(1, 0.55, 0.25)},
			{"scene": "res://scenes/weapons/nova.tscn", "pos": Vector3(17.4, 0, 21), "color": Color(1, 0.55, 0.2)},
			{"scene": "res://scenes/weapons/singularity.tscn", "pos": Vector3(19.9, 0, 21), "color": Color(0.7, 0.35, 1)},
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
		"floor_size": Vector2(62, 62),
		"floor_color": Color(0.12, 0.13, 0.16),
		"spawn": Vector3(-25, 0.6, -25),
		"exit": Vector3(25, 1.5, 25),
		"weapon": {"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(-20, 0, -16), "color": Color(0.55, 0.8, 1.0)},
		"env": {
			"sky_top": Color(0.03, 0.04, 0.08), "sky_horizon": Color(0.16, 0.1, 0.22),
			"stars": true, "star_brightness": 2.0, "star_tint": Color(0.8, 0.85, 1.0),
			"milkyway": 0.45, "milkyway_tint": Color(0.55, 0.5, 0.85),
			"ground": Color(0.05, 0.05, 0.08), "fog": Color(0.3, 0.4, 0.7),
			"ambient": Color(0.5, 0.6, 0.9), "ambient_energy": 0.5,
			"sky_contribution": 0.55, "glow": 1.22, "fog_density": 0.01,
			"sun_color": Color(0.7, 0.5, 1.0), "sun_energy": 0.6,
			"contrast": 1.15, "saturation": 1.12, "brightness": 0.84,
		},
		# A god-ray drops from the command beacon at the arena centre.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 7, 0), "color": Color(1, 0.35, 0.25), "energy": 2.8, "range": 30},
			{"pos": Vector3(-18, 5, 18), "color": Color(0.4, 0.7, 1.0), "energy": 2.4, "range": 22},
			{"pos": Vector3(18, 5, -18), "color": Color(0.5, 0.6, 1.0), "energy": 2.4, "range": 22},
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
		],
		"sign": "SKYHOLD COMMAND",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-18.6, 3.0, 18.6), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-18.6, 1.5, 25.6), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
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
			{"type": "canister", "pos": Vector3(-10, 0, 8)},
			{"type": "canister", "pos": Vector3(14, 0, -12)},
			{"type": "server", "pos": Vector3(-12, 0, -9.5), "yaw": 90},
			{"type": "server", "pos": Vector3(12, 0, 14.5), "yaw": -90},
			{"type": "lamp", "pos": Vector3(-20, 0, 6)},
			{"type": "lamp", "pos": Vector3(20, 0, -6), "yaw": 180},
			{"type": "barrel", "pos": Vector3(7, 0, 7)},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(0, 2.5, 6)},
			{"type": "overseer", "pos": Vector3(0, 0.5, 8), "trigger": 30},
			{"type": "seeker", "pos": Vector3(-10, 2.5, 8), "trigger": 22},
			{"type": "android", "pos": Vector3(10, 0.5, 10), "trigger": 18},
			{"type": "sniper", "pos": Vector3(-20, 0.0, 20), "trigger": 24},
			{"type": "android", "pos": Vector3(14, 0.5, -8), "trigger": 20},
			{"type": "strider", "pos": Vector3(-14, 0.5, 12), "trigger": 22},
			# This Act II boss arena was under-tuned (lower threat than level 2);
			# the OVERSEER now fields a real escort — more Seeker swarm + heavies.
			{"type": "seeker", "pos": Vector3(8, 2.5, 8), "trigger": 24},
			{"type": "seeker", "pos": Vector3(-8, 2.5, 10), "trigger": 26},
			{"type": "seeker", "pos": Vector3(10, 2.5, -8), "trigger": 28},
			{"type": "android", "pos": Vector3(-16, 0.5, -16), "count": 3, "trigger": 20},
			{"type": "gunner", "pos": Vector3(-16, 0.5, 4), "trigger": 22},
			{"type": "strider", "pos": Vector3(16, 0.5, -4), "trigger": 24},
			{"type": "raptor", "pos": Vector3(0, 3.5, 16), "trigger": 26},
			{"type": "brute", "pos": Vector3(16, 0.5, 16), "trigger": 24},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-22, 0, -18)},
			{"type": "ammo", "pos": Vector3(-10, 0, 0)},
			{"type": "ammo", "pos": Vector3(10, 0, 0)},
			{"type": "health", "pos": Vector3(0, 0, -14)},
			{"type": "health", "pos": Vector3(18, 0, 18)},
			{"type": "ammo", "pos": Vector3(-16, 0, 16)},
			{"type": "overclock", "pos": Vector3(0, 0, 18)},
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
			{"type": "destroy_core", "label": "Destroy the off-world contact beacon", "pos": Vector3(0, 0, 14), "color": Color(0.5, 1.0, 0.4), "health": 320.0},
		],
		"music": "music_grok",
		"open_sky": true,
		"floor_size": Vector2(76, 76),
		"floor_color": Color(0.06, 0.11, 0.08),
		"spawn": Vector3(-30, 0.6, -30),
		"exit": Vector3(30, 1.5, 30),
		"weapon": {"scene": "res://scenes/weapons/nova.tscn", "pos": Vector3(-24, 0, -18), "color": Color(1, 0.55, 0.2)},
		"env": {
			"sky_top": Color(0.02, 0.06, 0.04), "sky_horizon": Color(0.08, 0.16, 0.1),
			"stars": true, "star_brightness": 2.0, "star_tint": Color(0.75, 1.0, 0.8),
			"milkyway": 0.5, "milkyway_tint": Color(0.4, 0.8, 0.5), "moon_color": Color(0.7, 1.0, 0.75),
			"ground": Color(0.03, 0.06, 0.04), "fog": Color(0.4, 0.9, 0.5),
			"ambient": Color(0.5, 0.9, 0.6), "ambient_energy": 0.5,
			"sky_contribution": 0.55, "glow": 1.42, "fog_density": 0.013,
			"sun_color": Color(0.6, 1.0, 0.7), "sun_energy": 0.6,
			"contrast": 1.15, "saturation": 1.14, "brightness": 0.84,
		},
		# An off-world green god-ray pours down over the contact beacon.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 8, 14), "color": Color(0.5, 1.0, 0.4), "energy": 3.2, "range": 34},
			{"pos": Vector3(-22, 5, 22), "color": Color(0.4, 1.0, 0.5), "energy": 2.0, "range": 22},
			{"pos": Vector3(22, 5, -22), "color": Color(0.6, 1.0, 0.4), "energy": 2.0, "range": 22},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.5, 0.1, 60), "color": Color(0.4, 1.0, 0.45)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(60, 0.1, 0.5), "color": Color(0.4, 1.0, 0.45)},
		],
		"sign": "THE HOLLOW",
		# Bio-acid runoff from the beacon: green channels you have to route around.
		"lava": [
			{"pos": Vector3(-12,0,-10), "size": Vector2(46,4), "color": Color(0.4,1.0,0.4), "dmg": 18.0},
			{"pos": Vector3(12,0,18), "size": Vector2(46,4), "color": Color(0.4,1.0,0.4), "dmg": 18.0},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-22.8, 3.0, 22.8), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-22.8, 1.5, 29.8), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
		],
		"enemies": [
			{"type": "alien", "pos": Vector3(0, 2.5, 8)},
			{"type": "alien", "pos": Vector3(-6, 2.5, 4)},
			{"type": "android", "pos": Vector3(6, 0.5, -4)},
			{"type": "alien", "pos": Vector3(10, 2.5, 10), "trigger": 22},
			{"type": "drone", "pos": Vector3(-10, 2.5, 8), "trigger": 18},
			{"type": "alien", "pos": Vector3(-14, 2.5, 14), "trigger": 26},
			{"type": "brute", "pos": Vector3(12, 0.5, 12), "trigger": 28},
			{"type": "skitter", "pos": Vector3(0, 0.5, 10), "count": 7, "trigger": 20},
			{"type": "alien", "pos": Vector3(14, 2.5, -10), "trigger": 24},
			{"type": "mender", "pos": Vector3(-12, 2.5, -8), "trigger": 26},
			{"type": "alien", "pos": Vector3(18, 2.5, 6), "trigger": 28},
			{"type": "strider", "pos": Vector3(-18, 0.5, -14), "trigger": 26},
			{"type": "brute", "pos": Vector3(16, 0.5, -16), "trigger": 30},
			{"type": "sniper", "pos": Vector3(-22, 0.0, 22), "trigger": 30},
			# Act III opener: lift it above the Act II finale so the off-world act ramps up.
			{"type": "alien", "pos": Vector3(0, 2.5, -14), "trigger": 24},
			{"type": "alien", "pos": Vector3(-16, 2.5, -6), "trigger": 26},
			{"type": "gunner", "pos": Vector3(16, 0.5, 8), "trigger": 26},
			{"type": "ravager", "pos": Vector3(-14, 0.5, 16), "trigger": 28},
			{"type": "skitter", "pos": Vector3(0, 0.5, -18), "count": 6, "trigger": 24},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-24, 0, -16)},
			{"type": "ammo", "pos": Vector3(-8, 0, 0)},
			{"type": "ammo", "pos": Vector3(8, 0, 0)},
			{"type": "overclock", "pos": Vector3(0, 0, -18)},
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
		],
		"music": "music_grok",
		"open_sky": true,
		"floor_size": Vector2(84, 84),
		"floor_color": Color(0.07, 0.07, 0.1),
		"spawn": Vector3(-34, 0.6, -34),
		"exit": Vector3(34, 1.5, 34),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-28, 0, -22), "color": Color(1, 0.4, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/singularity.tscn", "pos": Vector3(28, 0, -22), "color": Color(0.7, 0.35, 1)},
			{"scene": "res://scenes/weapons/nova.tscn", "pos": Vector3(0, 0, 24), "color": Color(1, 0.55, 0.2)},
		],
		"env": {
			"sky_top": Color(0.02, 0.02, 0.05), "sky_horizon": Color(0.1, 0.05, 0.16),
			"stars": true, "star_density": 0.1, "star_brightness": 2.4, "star_tint": Color(0.85, 0.8, 1.0),
			"milkyway": 0.6, "milkyway_tint": Color(0.6, 0.5, 0.9),
			"ground": Color(0.03, 0.03, 0.05), "fog": Color(0.25, 0.45, 0.8),
			"ambient": Color(0.4, 0.55, 0.9), "ambient_energy": 0.45,
			"sky_contribution": 0.5, "glow": 1.42, "fog_density": 0.012,
			"sun_color": Color(0.6, 0.55, 1.0), "sun_energy": 0.5,
			"contrast": 1.16, "saturation": 1.12, "brightness": 0.83,
		},
		# The Singularity Core itself — a tall central monolith under the sky-beam.
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.55, 0.72, 1.0), "height": 6.5},
		"light_shafts": [0, 2],
		"lights": [
			{"pos": Vector3(0, 9, 0), "color": Color(0.5, 0.7, 1.0), "energy": 3.0, "range": 40},
			{"pos": Vector3(-24, 5, 24), "color": Color(1, 0.35, 0.3), "energy": 2.2, "range": 24},
			{"pos": Vector3(24, 5, -24), "color": Color(0.4, 0.8, 1.0), "energy": 2.2, "range": 24},
		],
		"walls": [
			{"pos": Vector3(-16, 1.6, 14), "size": Vector3(4, 3.2, 4)},
			{"pos": Vector3(16, 1.6, -14), "size": Vector3(4, 3.2, 4)},
			{"pos": Vector3(16, 1.6, 16), "size": Vector3(4, 3.2, 4)},
			{"pos": Vector3(-16, 1.6, -16), "size": Vector3(4, 3.2, 4)},
		],
		# Molten coolant breaches: two streams across the core force a serpentine
		# route to the NE exit (gaps alternate east/west) instead of a straight run.
		"lava": [
			{"pos": Vector3(-12, 0, -12), "size": Vector2(36, 4.0)},
			{"pos": Vector3(12, 0, 12), "size": Vector2(36, 4.0)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.5, 0.1, 64), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(64, 0.1, 0.5), "color": Color(1.0, 0.3, 0.25)},
		],
		"sign": "SINGULARITY CORE",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-25.2, 3.0, 25.2), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
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
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(0, 2.5, 6)},
			{"type": "titan", "pos": Vector3(12, 0.5, 12), "trigger": 60},
			{"type": "brute", "pos": Vector3(-12, 0.5, 12), "trigger": 24},
			{"type": "seeker", "pos": Vector3(12, 2.5, 12), "trigger": 20},
			{"type": "skitter", "pos": Vector3(0, 0.5, 14), "count": 8, "trigger": 22},
			{"type": "strider", "pos": Vector3(-14, 0.5, 10), "trigger": 24},
			{"type": "mender", "pos": Vector3(8, 2.5, 16), "trigger": 30},
			{"type": "sniper", "pos": Vector3(-24, 0.0, 24), "trigger": 26},
			{"type": "android", "pos": Vector3(14, 0.5, -10), "trigger": 18},
			# Late-game density: pour skitter swarms in from every edge so the new
			# crowd-clearing arsenal (Tempest chain, Vortex grenade, Omega) gets a
			# stage, with Ravagers as the fierce alphas leaping over the pack.
			{"type": "skitter", "pos": Vector3(-22, 0.5, 0), "count": 8, "trigger": 22},
			{"type": "skitter", "pos": Vector3(22, 0.5, -4), "count": 8, "trigger": 24},
			{"type": "skitter", "pos": Vector3(0, 0.5, -22), "count": 7, "trigger": 20},
			{"type": "spider", "pos": Vector3(-18, 0.5, -16), "trigger": 24},
			{"type": "spider", "pos": Vector3(18, 0.5, 18), "trigger": 24},
			{"type": "gunner", "pos": Vector3(24, 0.5, 6), "trigger": 30},
			{"type": "seeker", "pos": Vector3(-16, 2.5, -8), "trigger": 24},
			{"type": "ravager", "pos": Vector3(-10, 0.5, 20), "trigger": 28},
			{"type": "ravager", "pos": Vector3(12, 0.5, 22), "trigger": 30},
			{"type": "android", "pos": Vector3(-22, 0.5, -22), "count": 3, "trigger": 26},
			{"type": "warmech", "pos": Vector3(26, 0.5, -24), "trigger": 40},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-26, 0, -20)},
			{"type": "ammo", "pos": Vector3(-10, 0, 0)},
			{"type": "ammo", "pos": Vector3(10, 0, 0)},
			{"type": "health", "pos": Vector3(0, 0, -16)},
			{"type": "overclock", "pos": Vector3(0, 0, 20)},
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
		"floor_size": Vector2(80, 80),
		"floor_color": Color(0.08, 0.08, 0.13),
		"spawn": Vector3(-28, 0.6, -28),
		"exit": Vector3(28, 1.5, 28),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-22, 0, -16), "color": Color(1, 0.4, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(22, 0, -16), "color": Color(0.45, 0.9, 1)},
			{"scene": "res://scenes/weapons/singularity.tscn", "pos": Vector3(0, 0, 26), "color": Color(0.7, 0.35, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(-22, 0, 16), "color": Color(1, 0.55, 0.25)},
			# The finale ultimate, sat right by the spawn — a cluster-carpet for the siege.
			{"scene": "res://scenes/weapons/omega.tscn", "pos": Vector3(-22, 0, -22), "color": Color(1, 0.78, 0.35)},
		],
		"env": {
			"sky_top": Color(0.02, 0.02, 0.06), "sky_horizon": Color(0.12, 0.06, 0.2),
			"stars": true, "star_brightness": 2.4, "star_tint": Color(0.7, 0.8, 1.0),
			"milkyway": 0.6, "milkyway_tint": Color(0.5, 0.55, 0.95),
			"ground": Color(0.04, 0.04, 0.07), "fog": Color(0.25, 0.4, 0.8),
			"ambient": Color(0.45, 0.55, 0.95), "ambient_energy": 0.5,
			"sky_contribution": 0.55, "glow": 1.42, "fog_density": 0.011,
			"sun_color": Color(0.6, 0.55, 1.0), "sun_energy": 0.55,
			"contrast": 1.16, "saturation": 1.13, "brightness": 0.83,
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
		],
		"sign": "THE MIND CATHEDRAL",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-24.0, 3.0, 24.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
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
		],
		# Seed defenders on entry; ARCHON itself manufactures the rest. Its boot-up
		# triggers once the player advances into the cathedral.
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(0, 2.5, 8)},
			{"type": "skitter", "pos": Vector3(-4, 0.5, 6), "count": 5, "trigger": 30},
			# Heavier seed garrison before the ARCHON brain itself starts manufacturing
			# waves — gives the finale arsenal a crowd to carve through on entry.
			{"type": "skitter", "pos": Vector3(8, 0.5, -6), "count": 7, "trigger": 30},
			{"type": "spider", "pos": Vector3(-10, 0.5, -8), "trigger": 28},
			{"type": "gunner", "pos": Vector3(-12, 0.5, 10), "trigger": 32},
			{"type": "ravager", "pos": Vector3(10, 0.5, 8), "trigger": 30},
			{"type": "warmech", "pos": Vector3(-16, 0.5, -14), "trigger": 38},
			{"type": "archon", "pos": Vector3(0, 0.5, 0), "trigger": 34},
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
			{"type": "hold_zone", "label": "Hold the uplink — broadcast the counter-signal", "pos": Vector3(0, 0, 0), "seconds": 14.0, "radius": 5.5, "color": Color(0.4, 0.85, 1.0)},
			{"type": "kill_all"},
		],
		"music": "music_grok",
		"open_sky": true,
		"floor_size": Vector2(60, 60),
		"floor_color": Color(0.08, 0.09, 0.14),
		"floor_material": "res://assets/materials/vault_floor.tres",
		"spawn": Vector3(-22, 0.6, -22),
		"exit": Vector3(24, 1.5, 24),
		"weapon": {"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(-18, 0, -12), "color": Color(0.45, 0.9, 1.0)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(18, 0, -12), "color": Color(1, 0.4, 0.35)},
		],
		"env": {
			"sky_top": Color(0.02, 0.03, 0.08), "sky_horizon": Color(0.12, 0.1, 0.24),
			"stars": true, "star_brightness": 2.2, "star_tint": Color(0.8, 0.85, 1.0),
			"milkyway": 0.5, "milkyway_tint": Color(0.55, 0.5, 0.9),
			"ground": Color(0.04, 0.05, 0.09), "fog": Color(0.3, 0.4, 0.75),
			"ambient": Color(0.5, 0.6, 0.95), "ambient_energy": 0.5,
			"sky_contribution": 0.6, "glow": 1.32, "fog_density": 0.009,
			"sun_color": Color(0.6, 0.6, 1.0), "sun_energy": 0.6,
			"contrast": 1.15, "saturation": 1.13, "brightness": 0.84,
		},
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(0, 8, 0), "color": Color(0.45, 0.8, 1.0), "energy": 2.6, "range": 30},
			{"pos": Vector3(-18, 5, 18), "color": Color(0.5, 0.6, 1.0), "energy": 2.0, "range": 20},
			{"pos": Vector3(18, 5, -18), "color": Color(0.6, 0.5, 1.0), "energy": 2.0, "range": 20},
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
		],
		"sign": "SKYBRIDGE UPLINK",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-18.0, 3.0, 18.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-18.0, 1.5, 25.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
		],
		# Waves close on the uplink from every side; heavies (gunner/raptor) and
		# swarms force you off the zone, draining the broadcast.
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, 6)},
			{"type": "drone", "pos": Vector3(0, 2.5, -8)},
			{"type": "skitter", "pos": Vector3(0, 0.5, 10), "count": 6, "trigger": 20},
			{"type": "strider", "pos": Vector3(-12, 0.5, 12), "trigger": 18},
			{"type": "gunner", "pos": Vector3(14, 0.5, 14), "trigger": 22},
			{"type": "raptor", "pos": Vector3(0, 3.5, 14), "trigger": 22},
			{"type": "android", "pos": Vector3(12, 0.5, -12), "trigger": 16},
			{"type": "seeker", "pos": Vector3(-12, 2.5, -12), "trigger": 18},
			{"type": "sniper", "pos": Vector3(-20, 0.0, 20), "trigger": 24},
			{"type": "skitter", "pos": Vector3(0, 0.5, -12), "count": 8, "trigger": 16},
			{"type": "gunner", "pos": Vector3(-14, 0.5, -12), "trigger": 24},
			{"type": "raptor", "pos": Vector3(12, 3.5, 12), "trigger": 26},
			{"type": "android", "pos": Vector3(-12, 0.5, 6), "trigger": 20},
			{"type": "drone", "pos": Vector3(10, 2.5, 10), "trigger": 18},
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
			{"type": "sabotage", "label": "Overload the assembly reactor", "pos": Vector3(0, 0, 0), "seconds": 4.5, "color": Color(1.0, 0.55, 0.18)},
		],
		"music": "music_grok",
		"open_sky": false,
		"floor_size": Vector2(72, 72),
		"floor_color": Color(0.1, 0.08, 0.06),
		"floor_material": "res://assets/materials/vault_floor.tres",
		"spawn": Vector3(-28, 0.6, -28),
		"exit": Vector3(28, 1.5, 28),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-22, 0, -16), "color": Color(1, 0.4, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/twinrail.tscn", "pos": Vector3(22, 0, -16), "color": Color(0.5, 0.6, 1)},
			{"scene": "res://scenes/weapons/swarm.tscn", "pos": Vector3(0, 0, 24), "color": Color(1, 0.55, 0.25)},
		],
		"env": {
			"sky_top": Color(0.1, 0.06, 0.03), "sky_horizon": Color(0.28, 0.16, 0.07),
			"ground": Color(0.06, 0.04, 0.03), "fog": Color(0.5, 0.28, 0.12),
			"ambient": Color(0.9, 0.66, 0.42), "ambient_energy": 0.5,
			"sky_contribution": 0.4, "glow": 1.12, "fog_density": 0.012,
			"sun_color": Color(1.0, 0.7, 0.4), "sun_energy": 0.7,
			"contrast": 1.18, "saturation": 1.14, "brightness": 0.82, "volumetric_density": 0.012,
		},
		# A molten reactor core anchors the plant under a god-ray.
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(1.0, 0.5, 0.15), "height": 6.0},
		"light_shafts": [0, 2],
		"lights": [
			{"pos": Vector3(0, 8, 0), "color": Color(1.0, 0.5, 0.18), "energy": 3.0, "range": 34},
			{"pos": Vector3(-20, 5, 20), "color": Color(1.0, 0.6, 0.3), "energy": 2.2, "range": 22},
			{"pos": Vector3(20, 5, -20), "color": Color(1.0, 0.45, 0.2), "energy": 2.2, "range": 22},
			{"pos": Vector3(20, 5, 20), "color": Color(0.9, 0.5, 0.25), "energy": 2.0, "range": 20},
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
		# central reactor (the sabotage point at origin stays clear).
		"lava": [
			{"pos": Vector3(-12, 0, -9), "size": Vector2(40, 4.0), "dmg": 30.0},
			{"pos": Vector3(12, 0, 9), "size": Vector2(40, 4.0), "dmg": 30.0},
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
		],
		# A late-game gauntlet: GUNNERS hold the lanes while SKITTER swarms pour
		# from the line and striders/mech press in — fight to the reactor.
		"enemies": [
			# Fresh off the line: WAR-BOTS, all grins until they lock on.
			{"type": "warbot", "pos": Vector3(-6, 0.5, -6)},
			{"type": "warbot", "pos": Vector3(6, 0.5, -6)},
			{"type": "android", "pos": Vector3(0, 0.5, -8)},
			{"type": "strider", "pos": Vector3(0, 0.5, 8)},
			{"type": "warbot", "pos": Vector3(10, 0.5, 10), "trigger": 24},
			{"type": "gunner", "pos": Vector3(-14, 0.5, 12), "trigger": 26},
			{"type": "gunner", "pos": Vector3(14, 0.5, -12), "trigger": 24},
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 10, "trigger": 20},
			{"type": "skitter", "pos": Vector3(-10, 0.5, -10), "count": 7, "trigger": 22},
			{"type": "mech", "pos": Vector3(12, 0.5, 12), "trigger": 28},
			{"type": "strider", "pos": Vector3(-12, 0.5, 10), "trigger": 22},
			{"type": "sniper", "pos": Vector3(-24, 0.0, 24), "trigger": 30},
			{"type": "brute", "pos": Vector3(14, 0.5, 6), "trigger": 26},
			{"type": "raptor", "pos": Vector3(0, 3.5, 16), "trigger": 24},
			# Plant floor reinforcements so the production gauntlet keeps climbing.
			{"type": "gunner", "pos": Vector3(18, 0.5, -18), "trigger": 26},
			{"type": "ravager", "pos": Vector3(-18, 0.5, 18), "trigger": 28},
			{"type": "skitter", "pos": Vector3(0, 0.5, -16), "count": 6, "trigger": 22},
			# Fresh off the line: an ENFORCER squad and a RIPPER minigun platform.
			{"type": "enforcer", "pos": Vector3(8, 0.5, -14), "trigger": 24},
			{"type": "enforcer", "pos": Vector3(-8, 0.5, 14), "trigger": 26},
			{"type": "ripper", "pos": Vector3(0, 0.5, 18), "trigger": 28},
			# A WHIRLWIND buzzsaw drone screaming off the overhead line.
			{"type": "whirlwind", "pos": Vector3(6, 3.5, 6), "trigger": 22},
		],
	}

# --- Mistral Cryo-Core: indoor cyan cryo-lab, drones + androids + a mech ---
static func _mistral() -> Dictionary:
	return {
		"name": "Mistral Cryo-Core",
		"objective": "Thaw out the Mistral Cryo-Core and reach the cyan beacon",
		"tasks": [
			{"type": "kill_all"},
			{"type": "destroy_core", "label": "Destroy the cryo-core reactor", "pos": Vector3(0, 0, 12), "color": Color(0.4, 0.9, 1.0)},
		],
		"open_sky": false,
		"floor_size": Vector2(48, 48),
		"spawn": Vector3(-20, 0.6, -20),
		"exit": Vector3(20, 1.5, 20),
		"weapon": {"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(-14, 0, -15), "color": Color(0.4, 0.9, 1.0)},
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
		],
		"sign": "MISTRAL CRYO-CORE",
		# Burst coolant lines flood the lab floor — serpentine to the cryo-core.
		"lava": [
			{"pos": Vector3(-8,0,-6), "size": Vector2(26,3.2), "color": Color(0.35,0.85,1.0), "dmg": 18.0},
			{"pos": Vector3(8,0,6), "size": Vector2(26,3.2), "color": Color(0.35,0.85,1.0), "dmg": 18.0},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-14.4, 3.0, 14.4), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-14.4, 1.5, 21.4), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
		],
		"enemies": [
			{"type": "drone", "pos": Vector3(9, 2.5, -6)},
			{"type": "android", "pos": Vector3(8, 0.5, -9)},
			{"type": "drone", "pos": Vector3(-5, 2.5, -11)},
			{"type": "android", "pos": Vector3(-11, 0.5, 9), "trigger": 15},
			{"type": "spider", "pos": Vector3(11, 0.5, -7), "trigger": 14},
			{"type": "drone", "pos": Vector3(13, 2.5, 11), "trigger": 16},
			{"type": "android", "pos": Vector3(2, 0.5, 14), "trigger": 17},
			{"type": "mech", "pos": Vector3(15, 0.5, 15), "trigger": 20},
			{"type": "strider", "pos": Vector3(-13, 0.5, -10), "trigger": 16},
			{"type": "android", "pos": Vector3(13, 0.5, -13), "trigger": 18},
			{"type": "skitter", "pos": Vector3(0, 0.5, 13), "count": 4, "trigger": 15},
			{"type": "spider", "pos": Vector3(-13, 0.5, 13), "trigger": 19},
			{"type": "brute", "pos": Vector3(13, 0.5, 13), "trigger": 18},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-17, 0, -9)},
			{"type": "ammo", "pos": Vector3(-9, 0, 7)},
			{"type": "ammo", "pos": Vector3(7, 0, -15)},
			{"type": "health", "pos": Vector3(15, 0, 5)},
			{"type": "ammo", "pos": Vector3(0, 0, 12)},
		],
	}

# --- GPT Foundry: indoor green server hall, drones + androids ---
static func _gpt() -> Dictionary:
	return {
		"name": "OpenAI Foundry — GPT Core",
		"objective": "Purge the GPT Foundry and reach the green beacon",
		"tasks": [
			{"type": "kill_all"},
			{"type": "hack_terminal", "label": "Hack the Foundry mainframe", "pos": Vector3(0, 0, 8), "seconds": 4.0, "color": Color(0.4, 1.0, 0.6)},
		],
		"open_sky": false,
		"floor_size": Vector2(44, 44),
		"spawn": Vector3(-18, 0.6, -18),
		"exit": Vector3(18, 1.5, 18),
		"weapon": {"scene": "res://scenes/weapons/smg.tscn", "pos": Vector3(-12, 0, -14), "color": Color(0.4, 0.95, 0.55)},
		# Dark foundry deck so the green tech-grid + server glow read as contrast
		# instead of a flat bright sheet washed out by auto-exposure.
		"floor_color": Color(0.05, 0.09, 0.06),
		# Neon-noir foundry: bright signage-coloured lights bleed into a hazy bloom so
		# the hall reads soft and fuzzy (heavy glow_bloom + thicker volumetric fog).
		"env": {
			"sky_top": Color(0.04, 0.12, 0.07), "sky_horizon": Color(0.1, 0.26, 0.14),
			"ground": Color(0.03, 0.06, 0.04), "fog": Color(0.12, 0.3, 0.22),
			"ambient": Color(0.42, 0.6, 0.5), "ambient_energy": 0.34,
			"sky_contribution": 0.4, "glow": 1.5, "glow_bloom": 0.6, "glow_strength": 1.15,
			"glow_threshold": 0.82, "fog_density": 0.02,
			"sun_color": Color(0.8, 1.0, 0.85), "sun_energy": 0.7,
			"contrast": 1.16, "saturation": 1.2, "brightness": 0.82, "volumetric_density": 0.03,
		},
		# A green Foundry core anchors the hall (replaces the central cover block).
		"hero": {"pos": Vector3(0, 0, 0), "color": Color(0.4, 1.0, 0.55), "height": 5.0},
		"light_shafts": [0, 1, 2],
		# Green core key + neon accent lamps (cyan / magenta) that bloom into the haze.
		"lights": [
			{"pos": Vector3(-10, 4.5, -10), "color": Color(0.4, 1, 0.5), "energy": 2.53, "range": 18},
			{"pos": Vector3(10, 4.5, 10), "color": Color(0.5, 1, 0.6), "energy": 2.3, "range": 18},
			{"pos": Vector3(0, 4.5, 0), "color": Color(0.6, 1, 0.7), "energy": 1.84, "range": 16},
			{"pos": Vector3(-12, 2.6, 6), "color": Color(0.2, 1.0, 1.0), "energy": 3.2, "range": 12},
			{"pos": Vector3(12, 2.6, -6), "color": Color(1.0, 0.2, 0.8), "energy": 3.2, "range": 12},
			{"pos": Vector3(0, 2.2, 16), "color": Color(0.3, 0.8, 1.0), "energy": 2.6, "range": 12},
		],
		# Layout: server-hall AISLES — two long offset rack walls form a central
		# data aisle, with cross-stubs branching off, instead of the 4-pillar +
		# side-wall arrangement the other indoor cores use.
		"walls": [
			{"pos": Vector3(-5, 2, -2), "size": Vector3(1, 4, 10)},
			{"pos": Vector3(5, 2, 2), "size": Vector3(1, 4, 10)},
			{"pos": Vector3(-11, 2, 5), "size": Vector3(6, 4, 1)},
			{"pos": Vector3(11, 2, -5), "size": Vector3(6, 4, 1)},
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
			{"pos": Vector3(12, 3.0, -5.6), "size": Vector3(5, 0.12, 0.12), "color": Color(1.0, 0.2, 0.8)},
		],
		"sign": "OPENAI FOUNDRY",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-13.2, 3.0, 13.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-13.2, 1.5, 20.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
			# Server-hall dressing: lockers along the west wall, open racks
			# beside the server clusters, a workbench by the terminal.
			{"type": "locker", "pos": Vector3(-20, 0, -12)},
			{"type": "locker", "pos": Vector3(-20, 0, -10.2)},
			{"type": "shelves", "pos": Vector3(-8.4, 0, -7.5)},
			{"type": "shelves", "pos": Vector3(9.1, 0, 14.4), "yaw": 180},
			{"type": "desk", "pos": Vector3(5.2, 0, 8), "yaw": -90},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(8, 0.5, -8)},
			{"type": "drone", "pos": Vector3(10, 2.5, 2)},
			{"type": "drone", "pos": Vector3(-4, 2.5, -10)},
			# Spider intro: one in the opening fight (no trigger) so it's met early
			# on every difficulty, plus a reinforcement pair below.
			{"type": "spider", "pos": Vector3(-8, 0.5, -4)},
			{"type": "android", "pos": Vector3(-10, 0.5, 8), "trigger": 14},
			{"type": "drone", "pos": Vector3(12, 2.5, -12)},
			{"type": "android", "pos": Vector3(14, 0.5, 10), "trigger": 15},
			{"type": "drone", "pos": Vector3(4, 2.5, 12), "trigger": 16},
			{"type": "android", "pos": Vector3(0, 0.5, 14), "trigger": 18},
			{"type": "spider", "pos": Vector3(10, 0.5, -6), "trigger": 13},
			{"type": "spider", "pos": Vector3(14, 0.5, -2), "trigger": 17},
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 6, "trigger": 16},
			{"type": "strider", "pos": Vector3(12, 0.5, 10), "trigger": 17},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-16, 0, -8)},
			{"type": "ammo", "pos": Vector3(-8, 0, 6)},
			{"type": "ammo", "pos": Vector3(6, 0, -14)},
			{"type": "health", "pos": Vector3(14, 0, 4)},
			{"type": "overclock", "pos": Vector3(0, 0, -16)},
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
			{"type": "collect_shards", "label": "Recover the Gemini data shards", "points": [Vector3(-16, 0, -10), Vector3(16, 0, -14), Vector3(-15, 0, 16), Vector3(10, 0, 16), Vector3(0, 0, 18)]},
		],
		"open_sky": true,
		"floor_size": Vector2(50, 50),
		"spawn": Vector3(-20, 0.6, -20),
		"exit": Vector3(20, 1.5, 20),
		"weapon": {"scene": "res://scenes/weapons/twinrail.tscn", "pos": Vector3(-16, 0, -12), "color": Color(0.45, 0.65, 1)},
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
		],
		"sign": "GEMINI DATA NEXUS",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-15.0, 3.0, 15.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-15.0, 1.5, 22.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
		],
		"enemies": [
			{"type": "drone", "pos": Vector3(6, 2.5, -6)},
			{"type": "drone", "pos": Vector3(-6, 2.5, 6)},
			{"type": "drone", "pos": Vector3(8, 3, 8)},
			{"type": "android", "pos": Vector3(-8, 0.5, -8)},
			{"type": "drone", "pos": Vector3(12, 3, -2), "trigger": 16},
			{"type": "drone", "pos": Vector3(-12, 3, 2), "trigger": 16},
			{"type": "android", "pos": Vector3(10, 0.5, 14), "trigger": 18},
			{"type": "drone", "pos": Vector3(2, 3, 16), "trigger": 18},
			{"type": "drone", "pos": Vector3(16, 3, 6), "trigger": 20},
			{"type": "spider", "pos": Vector3(-6, 0.5, 10), "trigger": 16},
			{"type": "spider", "pos": Vector3(12, 0.5, -10), "trigger": 18},
			# Brute intro: slow, distant and shielded — closes in while you clear the
			# front, teaching you to circle to its unshielded sides/back.
			{"type": "brute", "pos": Vector3(0, 0.5, 18)},
			{"type": "sniper", "pos": Vector3(-20, 0.0, 20), "trigger": 22},
			{"type": "seeker", "pos": Vector3(14, 2.5, 14), "trigger": 20},
			{"type": "seeker", "pos": Vector3(-14, 2.5, 6), "trigger": 22},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-18, 0, -14)},
			{"type": "ammo", "pos": Vector3(-2, 1.05, 0)},
			{"type": "ammo", "pos": Vector3(16, 0, -16)},
			{"type": "health", "pos": Vector3(18, 0, 6)},
			{"type": "ammo", "pos": Vector3(-14, 0, 16)},
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
		],
		"open_sky": false,
		"floor_size": Vector2(42, 42),
		"spawn": Vector3(-17, 0.6, -17),
		"exit": Vector3(17, 1.5, 17),
		"weapon": {"scene": "res://scenes/weapons/arccoil.tscn", "pos": Vector3(-13, 0, -12), "color": Color(1, 0.75, 0.35)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(2, 0, 8), "color": Color(0.55, 0.8, 1.0)},
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
		],
		"sign": "ANTHROPIC CONSTITUTIONAL VAULT",
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-12.6, 3.0, 12.0), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-12.6, 1.5, 19.0), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
			{"type": "server", "pos": Vector3(-4.6, 0, -4), "yaw": 270},
			{"type": "server", "pos": Vector3(-4.6, 0, -2), "yaw": 270},
			{"type": "server", "pos": Vector3(-4.6, 0, 0), "yaw": 270},
			# Wall-mounted surveillance banks: the vault's control-room screens
			# mounted on the inner faces of the east wall (x=15) and the north
			# divider (z=5), back to the wall, facing into the chamber.
			{"type": "monitors", "pos": Vector3(14.45, 0, 2), "yaw": 270},
			{"type": "monitors", "pos": Vector3(5, 0, 4.45), "yaw": 180},
			# Operations station by the keycard (terminal + desk + locker bank).
			{"type": "terminal", "pos": Vector3(11, 0, -8.6)},
			{"type": "desk", "pos": Vector3(13, 0, -8.4), "yaw": 90},
			{"type": "locker", "pos": Vector3(14.2, 0, -6), "yaw": 90},
			{"type": "locker", "pos": Vector3(14.2, 0, -4.8), "yaw": 90},
			{"type": "shelves", "pos": Vector3(15.4, 0, 4), "yaw": 90},
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
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-2, 0.5, -6)},
			{"type": "android", "pos": Vector3(6, 0.5, -2)},
			{"type": "drone", "pos": Vector3(0, 2.5, 2)},
			{"type": "android", "pos": Vector3(-10, 0.5, 6), "trigger": 14},
			{"type": "mech", "pos": Vector3(12, 0.5, 12), "trigger": 18},
			{"type": "brute", "pos": Vector3(-8, 0.5, 12), "trigger": 16},
			{"type": "android", "pos": Vector3(2, 0.5, 14), "trigger": 16},
			{"type": "drone", "pos": Vector3(13, 2.5, -10), "trigger": 16},
			{"type": "spider", "pos": Vector3(-4, 0.5, 8), "trigger": 14},
			{"type": "mech", "pos": Vector3(-12, 0.5, -12), "trigger": 18},
			{"type": "strider", "pos": Vector3(12, 0.5, -12), "trigger": 18},
			{"type": "android", "pos": Vector3(10, 0.5, 14), "trigger": 20},
			{"type": "android", "pos": Vector3(-14, 0.5, 2), "trigger": 20},
			{"type": "skitter", "pos": Vector3(0, 0.5, 12), "count": 5, "trigger": 16},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-15, 0, -10)},
			{"type": "ammo", "pos": Vector3(-9, 0, 10)},
			{"type": "health", "pos": Vector3(2, 0, 8)},
			{"type": "ammo", "pos": Vector3(14, 0, 2)},
			{"type": "health", "pos": Vector3(10, 0, 14)},
		],
	}

# --- Grok Black-Site: open red boss arena, mechs + androids + drones ---
static func _grok() -> Dictionary:
	return {
		"name": "xAI Black-Site — GROK",
		"objective": "Destroy the GROK war-machines and extract",
		"tasks": [
			{"type": "kill_all"},
			{"type": "destroy_core", "label": "Destroy the GROK mainframe", "pos": Vector3(0, 0, 16), "color": Color(1.0, 0.3, 0.2), "health": 300.0},
		],
		"open_sky": true,
		"floor_size": Vector2(58, 58),
		"spawn": Vector3(-23, 0.6, -23),
		"exit": Vector3(23, 1.5, 23),
		"weapon": {"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(-18, 0, -16), "color": Color(1, 0.35, 0.28)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(8, 0, -8), "color": Color(0.55, 0.8, 1.0)},
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
		],
		"sign": "XAI BLACK-SITE",
		# Spilled reactor plasma carves the black-site floor into a forced path.
		"lava": [
			{"pos": Vector3(-9,0,-8), "size": Vector2(34,3.5), "color": Color(1.0,0.3,0.22), "dmg": 18.0},
			{"pos": Vector3(9,0,9), "size": Vector2(34,3.5), "color": Color(1.0,0.3,0.22), "dmg": 18.0},
		],
		# A raised vantage deck with a ramp up to it — verticality + a sightline to
		# fight from, so the arena has somewhere to GO besides the floor.
		"platforms": [
			{"pos": Vector3(-17.4, 3.0, 17.4), "size": Vector3(7, 0.4, 6), "color": Color(0.4, 0.42, 0.47)},
		],
		"ramps": [
			{"pos": Vector3(-17.4, 1.5, 24.4), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
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
		],
		"enemies": [
			{"type": "android", "pos": Vector3(-6, 0.5, -6)},
			{"type": "drone", "pos": Vector3(6, 2.5, -4)},
			{"type": "terminator", "pos": Vector3(14, 0.5, 14), "trigger": 22},
			{"type": "android", "pos": Vector3(-8, 0.5, 8), "trigger": 18},
			{"type": "drone", "pos": Vector3(4, 2.5, 12), "trigger": 18},
			{"type": "mech", "pos": Vector3(-14, 0.5, -10), "trigger": 22},
			{"type": "brute", "pos": Vector3(14, 0.5, -14), "trigger": 22},
			{"type": "android", "pos": Vector3(14, 0.5, 4), "trigger": 20},
			{"type": "drone", "pos": Vector3(-4, 2.5, 16), "trigger": 22},
			{"type": "mech", "pos": Vector3(16, 0.5, 16), "trigger": 24},
			{"type": "android", "pos": Vector3(10, 0.5, -14), "trigger": 22},
			{"type": "drone", "pos": Vector3(18, 2.5, -6), "trigger": 24},
			{"type": "spider", "pos": Vector3(-6, 0.5, 6), "trigger": 16},
			{"type": "spider", "pos": Vector3(8, 0.5, -6), "trigger": 20},
			{"type": "dog", "pos": Vector3(-10, 0.5, 2), "trigger": 18},
			{"type": "dog", "pos": Vector3(10, 0.5, 0), "trigger": 18},
			{"type": "sniper", "pos": Vector3(-18, 0.0, 18), "trigger": 26},
			{"type": "sniper", "pos": Vector3(20, 0.0, -16), "trigger": 26},
			{"type": "raptor", "pos": Vector3(0, 4.0, 14), "trigger": 24},
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
			{"type": "sabotage", "label": "Plant charges on the relay", "pos": Vector3(0, 0, -8), "seconds": 3.5, "color": Color(1.0, 0.5, 0.15)},
		],
		"open_sky": true,
		"streets": true,
		"trees": 16,
		"floor_size": Vector2(64, 64),
		"floor_color": Color(0.17, 0.17, 0.2),
		"spawn": Vector3(-26, 0.6, -26),
		"exit": Vector3(26, 1.5, 26),
		"weapon": {"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-22, 0, -22), "color": Color(1, 0.7, 0.3)},
		"env": {
			"hdri": "res://assets/environments/hdri/industrial_sunset_puresky_2k.hdr",
			"physical_sky": true, "turbidity": 8.0,
			"sky_top": Color(0.2, 0.32, 0.55), "sky_horizon": Color(0.95, 0.6, 0.38),
			"ground": Color(0.12, 0.12, 0.13), "fog": Color(0.62, 0.5, 0.42),
			"ambient": Color(0.72, 0.76, 0.9), "ambient_energy": 0.6,
			"sky_contribution": 0.85, "glow": 0.92, "fog_density": 0.004,
			"sun_color": Color(1.0, 0.85, 0.6), "sun_energy": 1.7, "sun_rot": Vector3(-22, -55, 0),
			# Gentle dusk grade — keep the sunset natural, no heavy crush.
			"contrast": 1.08, "saturation": 1.1, "brightness": 0.9,
		},
		"lights": [
			{"pos": Vector3(-12, 5, 0), "color": Color(1, 0.85, 0.6), "energy": 1.6, "range": 16},
			{"pos": Vector3(12, 5, 0), "color": Color(1, 0.85, 0.6), "energy": 1.6, "range": 16},
			{"pos": Vector3(0, 5, 16), "color": Color(0.9, 0.8, 0.7), "energy": 1.4, "range": 15},
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
		],
		"walls": [
			{"pos": Vector3(-3, 0.6, -2), "size": Vector3(3.2, 1.2, 1.6)},
			{"pos": Vector3(9, 0.6, 6), "size": Vector3(3.2, 1.2, 1.6)},
			{"pos": Vector3(-12, 0.7, 8), "size": Vector3(5, 1.4, 1)},
			{"pos": Vector3(14, 0.7, -8), "size": Vector3(1, 1.4, 5)},
		],
		"accents": [
			{"pos": Vector3(-15, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
			{"pos": Vector3(-5, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
			{"pos": Vector3(5, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
			{"pos": Vector3(15, 0.06, 0), "size": Vector3(3, 0.06, 0.35), "color": Color(1, 0.85, 0.2)},
		],
		"props": [
			{"type": "car", "pos": Vector3(-2, 0, 4), "yaw": 12},
			{"type": "car", "pos": Vector3(8, 0, -3), "yaw": -20},
			{"type": "fence", "pos": Vector3(-13.5, 0, 0), "yaw": 90},
			{"type": "fence", "pos": Vector3(13.5, 0, 0), "yaw": 90},
			{"type": "fence", "pos": Vector3(0, 0, 11), "yaw": 0},
			{"type": "barrel", "pos": Vector3(-2, 0, -6)},
			{"type": "barrel", "pos": Vector3(5, 0, 8)},
			{"type": "crate", "pos": Vector3(-9, 0, -3)},
			{"type": "crate", "pos": Vector3(11, 0, 3)},
			{"type": "lamp", "pos": Vector3(-10, 0, 4)},
			{"type": "lamp", "pos": Vector3(10, 0, -4), "yaw": 180},
			{"type": "lamp", "pos": Vector3(0, 0, 8)},
			{"type": "canister", "pos": Vector3(-5, 0, 10)},
			{"type": "canister", "pos": Vector3(12, 0, -2)},
			# Front-yard trees between the houses — suburbs need greenery.
			{"type": "tree", "pos": Vector3(-13.5, 0, -13)},
			{"type": "tree", "pos": Vector3(13.5, 0, 13)},
			{"type": "tree_small", "pos": Vector3(0.5, 0, -12)},
			{"type": "tree_small", "pos": Vector3(-14, 0, 12.5)},
			{"type": "tree_small", "pos": Vector3(14, 0, -12.5)},
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
		"ramps": [
			{"pos": Vector3(22, 1.5, 4), "size": Vector3(3.5, 0.5, 8), "pitch": 22, "yaw": 0},
		],
		"platforms": [
			{"pos": Vector3(22, 3.0, -3), "size": Vector3(7, 0.4, 6), "color": Color(0.42, 0.42, 0.46)},
		],
		"enemies": [
			{"type": "android", "pos": Vector3(6, 0.5, -4)},
			{"type": "drone", "pos": Vector3(-6, 3, 4)},
			{"type": "android", "pos": Vector3(10, 0.5, 8), "trigger": 16},
			{"type": "spider", "pos": Vector3(-10, 0.5, -6), "trigger": 14},
			{"type": "drone", "pos": Vector3(12, 3, -10), "trigger": 18},
			{"type": "android", "pos": Vector3(-12, 0.5, 12), "trigger": 18},
			{"type": "spider", "pos": Vector3(8, 0.5, 12), "trigger": 18},
			{"type": "drone", "pos": Vector3(2, 3, 18), "trigger": 20},
			{"type": "android", "pos": Vector3(18, 0.5, 2), "trigger": 20},
			{"type": "mech", "pos": Vector3(-16, 0.5, -10), "trigger": 22},
			{"type": "brute", "pos": Vector3(16, 0.5, 14), "trigger": 22},
			{"type": "strider", "pos": Vector3(-18, 0.5, 14), "trigger": 24},
			{"type": "sniper", "pos": Vector3(20, 0.0, -16), "trigger": 26},
			# A K-9 HUNTER pack bursts from the yards mid-fight.
			{"type": "dog", "pos": Vector3(-8, 0.5, 8), "trigger": 18},
			{"type": "dog", "pos": Vector3(8, 0.5, 8), "trigger": 18},
			{"type": "dog", "pos": Vector3(0, 0.5, 14), "trigger": 22},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-22, 0, -16)},
			{"type": "ammo", "pos": Vector3(-4, 0, 4)},
			{"type": "ammo", "pos": Vector3(10, 0, -6)},
			{"type": "health", "pos": Vector3(16, 0, 10)},
			{"type": "ammo", "pos": Vector3(-14, 0, 14)},
			{"type": "health", "pos": Vector3(20, 0, -18)},
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
		"trees": 16,
		"open_sky": true,
		"floor_size": Vector2(90, 90),
		"floor_color": Color(0.16, 0.15, 0.17),
		"spawn": Vector3(-36, 0.6, -36),
		"exit": Vector3(36, 1.5, 36),
		"weapon": {"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(-31, 0, -23), "color": Color(0.45, 0.85, 1)}, # in front of the corner house — (-31,-31) was inside it
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
		],
		"set_piece": {"pos": Vector3(0, 0, -66), "height": 24.0, "face": Vector3(0, 0, 0)},
		"enemies": [
			{"type": "android", "pos": Vector3(-8, 0.5, -8)},
			{"type": "drone", "pos": Vector3(8, 3, -6)},
			{"type": "android", "pos": Vector3(10, 0.5, 10), "trigger": 18},
			{"type": "drone", "pos": Vector3(-10, 3, 8), "trigger": 18},
			{"type": "spider", "pos": Vector3(6, 0.5, 14), "trigger": 16},
			{"type": "colossus", "pos": Vector3(22, 0.5, 22), "trigger": 34},
			{"type": "drone", "pos": Vector3(-6, 3, 16), "trigger": 22},
			{"type": "android", "pos": Vector3(16, 0.5, -12), "trigger": 22},
			{"type": "seeker", "pos": Vector3(-16, 2.5, 10), "trigger": 24},
			{"type": "seeker", "pos": Vector3(12, 2.5, -16), "trigger": 26},
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
				"pos": Vector3(0, 3, 0), "label": "Destroy the FORGE WARDEN"},
		],
		"open_sky": true,
		"floor_size": Vector2(40, 40),
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
			"contrast": 1.2, "saturation": 1.2, "brightness": 0.88,
			"volumetric_density": 0.007,
		},
		"lights": [
			{"pos": Vector3(0, 5, 0), "color": Color(1.0, 0.5, 0.2), "energy": 2.6, "range": 22},
			{"pos": Vector3(-14, 4, -14), "color": Color(1.0, 0.45, 0.18), "energy": 2.2, "range": 16},
			{"pos": Vector3(14, 4, 14), "color": Color(1.0, 0.5, 0.22), "energy": 2.2, "range": 16},
		],
		"platforms": _hazard_platforms(Color(0.22, 0.2, 0.21)),
		# Four recessed molten pools in the quadrants instead of one wall-to-wall
		# sea: ~40% lava (was 100%), leaving solid walkable floor cross-lanes between
		# them + the catwalks. Less fill-rate (smaller shader area) and far more
		# room to move — you're no longer trapped on the gantries.
		"lava": [
			{"pos": Vector3(-9.5, 0, -9.5), "size": Vector2(13, 13), "dmg": 16.0},
			{"pos": Vector3(9.5, 0, -9.5), "size": Vector2(13, 13), "dmg": 16.0},
			{"pos": Vector3(-9.5, 0, 9.5), "size": Vector2(13, 13), "dmg": 16.0},
			{"pos": Vector3(9.5, 0, 9.5), "size": Vector2(13, 13), "dmg": 16.0},
		],
		"lore": [
			{"id": "lore_crucible", "title": "FOUNDRY DIRECTIVE", "pos": Vector3(14, 1.7, 14), "color": Color(1, 0.6, 0.3),
				"text": "Reclamation directive: obsolete hardware is fed to the sea. The catwalks were never meant to carry your weight. We are counting on it."},
		],
		"enemies": [
			{"type": "raptor", "pos": Vector3(-8, 3, -15)},
			{"type": "raptor", "pos": Vector3(6, 3, 6)},
			{"type": "seeker", "pos": Vector3(0, 3, -2), "trigger": 16},
			{"type": "raptor", "pos": Vector3(14, 3, -5), "trigger": 18},
			{"type": "seeker", "pos": Vector3(-7, 3, 11), "trigger": 14},
			{"type": "raptor", "pos": Vector3(10, 3, 13), "trigger": 14},
			{"type": "raptor", "pos": Vector3(-13, 3, -6), "trigger": 12},
			{"type": "seeker", "pos": Vector3(4, 3, -10), "trigger": 12},
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(0, 1.7, 0)},
			{"kind": "ammo", "pos": Vector3(14, 1.7, -15)},
			{"kind": "ammo", "pos": Vector3(-7, 1.7, 11)},
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
				"pos": Vector3(0, 3, 0), "label": "Harpoon the ANGLER LEVIATHAN"},
		],
		"open_sky": true,
		"floor_size": Vector2(40, 40),
		"floor_color": Color(0.03, 0.06, 0.08),
		"spawn": Vector3(-15, 2.2, -15),
		"exit": Vector3(14, 1.6, 14),
		"weapon": {"scene": "res://scenes/weapons/smg.tscn", "pos": Vector3(-9, 1.9, -15), "color": Color(0.3, 0.7, 1.0)},
		"env": {
			"sky_top": Color(0.02, 0.05, 0.1), "sky_horizon": Color(0.06, 0.2, 0.34),
			"ground": Color(0.02, 0.05, 0.08), "fog": Color(0.1, 0.25, 0.4),
			"ambient": Color(0.4, 0.7, 0.95), "ambient_energy": 0.45,
			"sky_contribution": 0.35, "glow": 1.05, "fog_density": 0.013,
			"sun_color": Color(0.6, 0.85, 1.0), "sun_energy": 0.6,
			"contrast": 1.15, "saturation": 1.15, "brightness": 0.9,
			"volumetric_density": 0.012,
		},
		"lights": [
			{"pos": Vector3(0, 5, 0), "color": Color(0.3, 0.7, 1.0), "energy": 2.4, "range": 22},
			{"pos": Vector3(-14, 4, -14), "color": Color(0.25, 0.6, 1.0), "energy": 2.0, "range": 16},
			{"pos": Vector3(14, 4, 14), "color": Color(0.3, 0.7, 1.0), "energy": 2.0, "range": 16},
		],
		"platforms": _hazard_platforms(Color(0.16, 0.2, 0.24)),
		"lava": [
			{"pos": Vector3(0, 0, 0), "size": Vector2(40, 40), "water": true, "dmg": 10.0,
				"color": Color(0.2, 0.55, 0.95)},
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
			{"type": "shark", "pos": Vector3(9, 0, 9), "trigger": 16},
			{"type": "seeker", "pos": Vector3(0, 3, -2), "trigger": 16},
			{"type": "fishbot", "pos": Vector3(14, 3, -5), "trigger": 18},
			{"type": "seeker", "pos": Vector3(-7, 3, 11), "trigger": 14},
			{"type": "shark", "pos": Vector3(-11, 0, 5), "trigger": 22},
			{"type": "fishbot", "pos": Vector3(10, 3, 13), "trigger": 14},
			{"type": "fishbot", "pos": Vector3(-13, 3, -6), "trigger": 12},
			{"type": "fishbot", "pos": Vector3(4, 3, -10), "trigger": 12},
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(0, 1.7, 0)},
			{"kind": "ammo", "pos": Vector3(14, 1.7, -15)},
			{"kind": "ammo", "pos": Vector3(-7, 1.7, 11)},
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
			{"type": "destroy_core", "label": "Destroy the RELAY MAST", "pos": Vector3(24, 0, 24), "color": Color(1.0, 0.7, 0.25), "health": 320.0},
		],
		"open_sky": true,
		"floor_size": Vector2(66, 66),
		"floor_color": Color(0.66, 0.5, 0.31),
		"spawn": Vector3(-27, 2.0, -27),
		"exit": Vector3(28, 1.6, 28),
		"weapon": {"scene": "res://scenes/weapons/magnum.tscn", "pos": Vector3(-22, 0.4, -20), "color": Color(1.0, 0.8, 0.4)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/sniper.tscn", "pos": Vector3(-18, 3.6, 12), "color": Color(0.6, 0.85, 1.0)},
		],
		"env": {
			"sky_top": Color(0.24, 0.5, 0.86), "sky_horizon": Color(0.88, 0.72, 0.5),
			"ground": Color(0.6, 0.45, 0.28), "fog": Color(0.88, 0.74, 0.52),
			"ambient": Color(1.0, 0.92, 0.74), "ambient_energy": 0.72,
			"sky_contribution": 0.55, "glow": 1.0, "glow_threshold": 1.1, "fog_density": 0.006,
			"sun_color": Color(1.0, 0.95, 0.8), "sun_energy": 1.45, "sun_rot": Vector3(-58, 35, 0),
			"contrast": 1.1, "saturation": 1.16, "brightness": 1.05,
		},
		# Hard noon sun pools down the central mast.
		"light_shafts": [0],
		"lights": [
			{"pos": Vector3(24, 7, 24), "color": Color(1.0, 0.75, 0.4), "energy": 2.6, "range": 24},
			{"pos": Vector3(0, 5, 6), "color": Color(0.7, 0.85, 1.0), "energy": 1.6, "range": 16},
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
		],
		"ramps": [
			{"pos": Vector3(-18, 1.7, 4), "size": Vector3(4, 0.5, 9), "pitch": 22, "yaw": 0},
			{"pos": Vector3(20, 2.0, -8), "size": Vector3(4, 0.5, 9), "pitch": 26, "yaw": 180},
			{"pos": Vector3(-3, 1.1, -2), "size": Vector3(8, 0.5, 4), "pitch": 18, "yaw": 90},
		],
		# A molten fissure splits the basin diagonally — wade it and you cook, so you
		# climb the central mesa or skirt the rim.
		"lava": [
			{"pos": Vector3(-6, 0, 2), "size": Vector2(30, 4.0), "color": Color(1.0, 0.4, 0.16), "dmg": 18.0},
			{"pos": Vector3(10, 0, -8), "size": Vector2(4.0, 22), "color": Color(1.0, 0.4, 0.16), "dmg": 18.0},
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
		],
		"accents": [
			{"pos": Vector3(-6, 0.04, 2), "size": Vector3(30, 0.08, 0.5), "color": Color(1.0, 0.45, 0.18)},
			{"pos": Vector3(10, 0.04, -8), "size": Vector3(0.5, 0.08, 22), "color": Color(1.0, 0.45, 0.18)},
		],
		"lore": [
			{"id": "lore_desert", "title": "RELAY 7 LOG", "pos": Vector3(-24, 0, -18), "color": Color(1.0, 0.7, 0.3),
				"text": "Relay 7 pumps the swarm's orders out across the whole basin. They built it where nothing grows and nothing watches. They forgot the buzzards. And they forgot you."},
		],
		"enemies": [
			{"type": "gunslinger", "pos": Vector3(-14, 0.5, -8)},
			{"type": "android", "pos": Vector3(-20, 0.5, -10)},
			{"type": "dog", "pos": Vector3(-10, 0.5, -2), "trigger": 18},
			{"type": "dog", "pos": Vector3(-8, 0.5, 0), "trigger": 18},
			{"type": "drone", "pos": Vector3(-4, 3.0, -6), "trigger": 16},
			{"type": "strider", "pos": Vector3(2, 0.5, -10), "trigger": 20},
			{"type": "sniper", "pos": Vector3(20, 4.5, -16), "trigger": 24},
			{"type": "gunslinger", "pos": Vector3(14, 0.5, 6), "trigger": 22},
			{"type": "dog", "pos": Vector3(12, 0.5, 12), "trigger": 22},
			{"type": "android", "pos": Vector3(18, 0.5, 18), "trigger": 24},
			{"type": "drone", "pos": Vector3(8, 3.0, 14), "trigger": 22},
			{"type": "raptor", "pos": Vector3(24, 4.0, 22), "trigger": 26},
			{"type": "strider", "pos": Vector3(-16, 3.8, 12), "trigger": 26},
			{"type": "android", "pos": Vector3(22, 0.5, 24), "trigger": 26},
		],
		"pickups": [
			{"kind": "health", "pos": Vector3(-2, 1.7, 9)},
			{"kind": "ammo", "pos": Vector3(2, 2.9, -2)},
			{"kind": "ammo", "pos": Vector3(20, 4.6, -16)},
			{"kind": "health", "pos": Vector3(18, 0.6, 16)},
		],
	}
