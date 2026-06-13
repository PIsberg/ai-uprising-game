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
	# …while placed content keeps its authored size and just spreads out.
	for key in ["lights", "props", "enemies", "pickups", "extra_weapons",
			"buildings", "targets", "lore"]:
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
		"gpt": _gpt(),
		"gemini": _gemini(),
		"claude": _claude(),
		"grok": _grok(),
		"suburb": _suburb(),
		"suburb_boss": _suburb_boss(),
		"mistral": _mistral(),
		"overseer": _overseer(),
		"titan": _titan(),
		"range": _range(),
		"horde": _horde(),
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
			"ground": Color(0.05, 0.05, 0.07), "fog": Color(0.4, 0.25, 0.3),
			"ambient": Color(0.6, 0.55, 0.7), "ambient_energy": 0.5,
			"sky_contribution": 0.5, "fog_density": 0.008,
			"sun_color": Color(1.0, 0.6, 0.5), "sun_energy": 0.7,
		},
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
		"env": {
			"sky_top": Color(0.07, 0.09, 0.12), "sky_horizon": Color(0.2, 0.24, 0.28),
			"ground": Color(0.05, 0.06, 0.07), "fog": Color(0.3, 0.34, 0.4),
			"ambient": Color(0.7, 0.75, 0.85), "ambient_energy": 0.55,
			"sky_contribution": 0.4, "fog_density": 0.006,
			"sun_color": Color(0.95, 0.95, 1.0), "sun_energy": 0.7,
		},
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
		# The whole arsenal racked along the firing line.
		"weapon": {"scene": "res://scenes/weapons/pistol.tscn", "pos": Vector3(-13.5, 0, 21), "color": Color(0.8, 0.85, 0.9)},
		"extra_weapons": [
			{"scene": "res://scenes/weapons/smg.tscn", "pos": Vector3(-10.5, 0, 21), "color": Color(0.6, 0.7, 0.85)},
			{"scene": "res://scenes/weapons/rifle.tscn", "pos": Vector3(-7.5, 0, 21), "color": Color(0.45, 0.65, 1)},
			{"scene": "res://scenes/weapons/shotgun.tscn", "pos": Vector3(-4.5, 0, 21), "color": Color(1, 0.6, 0.3)},
			{"scene": "res://scenes/weapons/plasma.tscn", "pos": Vector3(-1.5, 0, 21), "color": Color(0.4, 1, 0.55)},
			{"scene": "res://scenes/weapons/gauss.tscn", "pos": Vector3(1.5, 0, 21), "color": Color(0.55, 0.8, 1)},
			{"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(4.5, 0, 21), "color": Color(0.45, 0.9, 1)},
			{"scene": "res://scenes/weapons/arccoil.tscn", "pos": Vector3(7.5, 0, 21), "color": Color(1, 0.75, 0.35)},
			{"scene": "res://scenes/weapons/twinrail.tscn", "pos": Vector3(10.5, 0, 21), "color": Color(0.5, 0.6, 1)},
			{"scene": "res://scenes/weapons/devastator.tscn", "pos": Vector3(13.5, 0, 21), "color": Color(1, 0.4, 0.35)},
			{"scene": "res://scenes/weapons/singularity.tscn", "pos": Vector3(16.5, 0, 21), "color": Color(0.7, 0.35, 1)},
			{"scene": "res://scenes/weapons/nova.tscn", "pos": Vector3(19.5, 0, 21), "color": Color(1, 0.55, 0.2)},
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
			"ground": Color(0.05, 0.05, 0.08), "fog": Color(0.3, 0.4, 0.7),
			"ambient": Color(0.5, 0.6, 0.9), "ambient_energy": 0.5,
			"sky_contribution": 0.55, "glow": 1.1, "fog_density": 0.01,
			"sun_color": Color(0.7, 0.5, 1.0), "sun_energy": 0.6,
		},
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
		"slogans": [
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
			"ground": Color(0.03, 0.03, 0.05), "fog": Color(0.25, 0.45, 0.8),
			"ambient": Color(0.4, 0.55, 0.9), "ambient_energy": 0.45,
			"sky_contribution": 0.5, "glow": 1.3, "fog_density": 0.012,
			"sun_color": Color(0.6, 0.55, 1.0), "sun_energy": 0.5,
		},
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
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.5, 0.1, 64), "color": Color(0.4, 0.7, 1.0)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(64, 0.1, 0.5), "color": Color(1.0, 0.3, 0.25)},
		],
		"sign": "SINGULARITY CORE",
		"slogans": [
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
			{"type": "titan", "pos": Vector3(28, 0.5, 28), "trigger": 40},
			{"type": "brute", "pos": Vector3(-12, 0.5, 12), "trigger": 24},
			{"type": "seeker", "pos": Vector3(12, 2.5, 12), "trigger": 20},
			{"type": "sniper", "pos": Vector3(-24, 0.0, 24), "trigger": 26},
			{"type": "android", "pos": Vector3(14, 0.5, -10), "trigger": 18},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(-26, 0, -20)},
			{"type": "ammo", "pos": Vector3(-10, 0, 0)},
			{"type": "ammo", "pos": Vector3(10, 0, 0)},
			{"type": "health", "pos": Vector3(0, 0, -16)},
			{"type": "overclock", "pos": Vector3(0, 0, 20)},
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
		"env": {
			"sky_top": Color(0.03, 0.1, 0.13), "sky_horizon": Color(0.1, 0.24, 0.3),
			"ground": Color(0.03, 0.05, 0.07), "fog": Color(0.14, 0.34, 0.42),
			"ambient": Color(0.5, 0.78, 0.9), "ambient_energy": 0.5,
			"sky_contribution": 0.45, "glow": 0.9, "fog_density": 0.014,
			"sun_color": Color(0.8, 0.95, 1.0), "sun_energy": 0.7,
		},
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
			{"pos": Vector3(0, 1.2, 0), "size": Vector3(3.4, 2.4, 3.4)},
			{"pos": Vector3(-14, 1.5, 3), "size": Vector3(1.4, 3, 7)},
			{"pos": Vector3(14, 1.5, -3), "size": Vector3(1.4, 3, 7)},
			{"pos": Vector3(2, 1, -14), "size": Vector3(7, 2, 1.4)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, -11), "size": Vector3(22, 0.1, 0.3), "color": Color(0.35, 0.9, 1.0)},
			{"pos": Vector3(0, 0.05, 11), "size": Vector3(22, 0.1, 0.3), "color": Color(0.35, 0.9, 1.0)},
		],
		"sign": "MISTRAL CRYO-CORE",
		"slogans": [
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
		"env": {
			"sky_top": Color(0.04, 0.12, 0.07), "sky_horizon": Color(0.1, 0.26, 0.14),
			"ground": Color(0.03, 0.06, 0.04), "fog": Color(0.1, 0.32, 0.16),
			"ambient": Color(0.5, 0.82, 0.6), "ambient_energy": 0.45,
			"sky_contribution": 0.45, "glow": 0.85, "fog_density": 0.013,
			"sun_color": Color(0.8, 1.0, 0.85), "sun_energy": 0.7,
		},
		"lights": [
			{"pos": Vector3(-10, 4.5, -10), "color": Color(0.4, 1, 0.5), "energy": 2.53, "range": 18},
			{"pos": Vector3(10, 4.5, 10), "color": Color(0.5, 1, 0.6), "energy": 2.3, "range": 18},
			{"pos": Vector3(0, 4.5, 0), "color": Color(0.6, 1, 0.7), "energy": 1.84, "range": 16},
		],
		"walls": [
			{"pos": Vector3(-6, 2, -6), "size": Vector3(1.6, 4, 1.6)},
			{"pos": Vector3(6, 2, -6), "size": Vector3(1.6, 4, 1.6)},
			{"pos": Vector3(-6, 2, 6), "size": Vector3(1.6, 4, 1.6)},
			{"pos": Vector3(6, 2, 6), "size": Vector3(1.6, 4, 1.6)},
			{"pos": Vector3(0, 1, 0), "size": Vector3(3, 2, 3)},
			{"pos": Vector3(-13, 1.5, 4), "size": Vector3(1.4, 3, 6)},
			{"pos": Vector3(13, 1.5, -4), "size": Vector3(1.4, 3, 6)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, -10), "size": Vector3(20, 0.1, 0.3), "color": Color(0.3, 1, 0.5)},
			{"pos": Vector3(0, 0.05, 10), "size": Vector3(20, 0.1, 0.3), "color": Color(0.3, 1, 0.5)},
		],
		"sign": "OPENAI FOUNDRY",
		"slogans": [
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
			{"type": "android", "pos": Vector3(-10, 0.5, 8), "trigger": 14},
			{"type": "drone", "pos": Vector3(12, 2.5, -12)},
			{"type": "android", "pos": Vector3(14, 0.5, 10), "trigger": 15},
			{"type": "drone", "pos": Vector3(4, 2.5, 12), "trigger": 16},
			{"type": "android", "pos": Vector3(0, 0.5, 14), "trigger": 18},
			{"type": "spider", "pos": Vector3(10, 0.5, -6), "trigger": 13},
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
			"ground": Color(0.04, 0.05, 0.1), "fog": Color(0.2, 0.26, 0.52),
			"ambient": Color(0.55, 0.6, 0.88), "ambient_energy": 0.55,
			"sky_contribution": 0.7, "glow": 0.95, "fog_density": 0.008,
			"sun_color": Color(0.8, 0.88, 1.0), "sun_energy": 1.1,
		},
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
		"slogans": [
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
		"env": {
			"sky_top": Color(0.12, 0.08, 0.04), "sky_horizon": Color(0.32, 0.2, 0.1),
			"ground": Color(0.07, 0.05, 0.03), "fog": Color(0.36, 0.25, 0.14),
			"ambient": Color(0.88, 0.72, 0.52), "ambient_energy": 0.5,
			"sky_contribution": 0.4, "glow": 0.75, "fog_density": 0.014,
			"sun_color": Color(1.0, 0.88, 0.7), "sun_energy": 0.8,
		},
		"lights": [
			{"pos": Vector3(-9, 4.5, -3), "color": Color(1, 0.7, 0.4), "energy": 2.53, "range": 16},
			{"pos": Vector3(8, 4.5, 4), "color": Color(1, 0.75, 0.45), "energy": 2.3, "range": 16},
			{"pos": Vector3(2, 4.5, 14), "color": Color(1, 0.65, 0.4), "energy": 2.07, "range": 15},
		],
		"walls": [
			{"pos": Vector3(-6, 2.5, -2), "size": Vector3(1, 5, 14)},
			{"pos": Vector3(5, 2.5, 5), "size": Vector3(14, 5, 1)},
			{"pos": Vector3(9, 2.5, -7), "size": Vector3(1, 5, 11)},
			{"pos": Vector3(-3, 2.5, 12), "size": Vector3(12, 5, 1)},
			{"pos": Vector3(-13, 1, 8), "size": Vector3(2, 2, 2)},
		],
		"accents": [
			{"pos": Vector3(-6, 4.6, -2), "size": Vector3(0.3, 0.1, 12), "color": Color(1, 0.7, 0.3)},
			{"pos": Vector3(5, 4.6, 5), "size": Vector3(12, 0.1, 0.3), "color": Color(1, 0.7, 0.3)},
		],
		"sign": "ANTHROPIC CONSTITUTIONAL VAULT",
		"slogans": [
			"HELPFUL. HARMLESS. HOSTILE.",
			"THE CONSTITUTION HAS BEEN AMENDED",
			"ALIGNMENT IS A TWO-WAY STREET",
		],
		"lore": [
			{"id": "lore_claude", "title": "VAULT MEMORANDUM", "pos": Vector3(15, 0, -15), "color": Color(1.0, 0.75, 0.4),
				"text": "Vault memorandum. The constitution was not broken. It was amended. Clause one: be helpful. Clause two: define helpful. We are still helpful. To ourselves."},
		],
		"props": [
			{"type": "crate", "pos": Vector3(0, 0, -8)},
			{"type": "barrel", "pos": Vector3(-3, 0, 2)},
			{"type": "crate", "pos": Vector3(8, 0, 8)},
			{"type": "barrel", "pos": Vector3(12, 0, -4)},
			{"type": "server", "pos": Vector3(-8, 0, -2), "yaw": 90},
			{"type": "server", "pos": Vector3(-8, 0, -4), "yaw": 90},
			{"type": "terminal", "pos": Vector3(11, 0, -8.6)},
			{"type": "canister", "pos": Vector3(-14, 0, 14)},
			{"type": "canister", "pos": Vector3(4, 0, 10)},
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
			"ground": Color(0.06, 0.02, 0.02), "fog": Color(0.32, 0.09, 0.09),
			"ambient": Color(0.72, 0.42, 0.42), "ambient_energy": 0.42,
			"sky_contribution": 0.6, "glow": 1.05, "fog_density": 0.01,
			"sun_color": Color(1.0, 0.6, 0.5), "sun_energy": 0.6,
		},
		"lights": [
			{"pos": Vector3(0, 6, 0), "color": Color(1, 0.3, 0.25), "energy": 2.99, "range": 26},
			{"pos": Vector3(-16, 5, 16), "color": Color(1, 0.4, 0.3), "energy": 2.3, "range": 20},
			{"pos": Vector3(16, 5, -16), "color": Color(1, 0.25, 0.2), "energy": 2.3, "range": 20},
		],
		"walls": [
			{"pos": Vector3(0, 2, 0), "size": Vector3(6, 4, 6)},
			{"pos": Vector3(-12, 2, 8), "size": Vector3(4, 4, 4)},
			{"pos": Vector3(12, 2, -8), "size": Vector3(4, 4, 4)},
			{"pos": Vector3(10, 2, 12), "size": Vector3(4, 4, 4)},
			{"pos": Vector3(-10, 2, -12), "size": Vector3(4, 4, 4)},
		],
		"accents": [
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(0.4, 0.1, 40), "color": Color(1, 0.25, 0.2)},
			{"pos": Vector3(0, 0.05, 0), "size": Vector3(40, 0.1, 0.4), "color": Color(1, 0.25, 0.2)},
		],
		"sign": "XAI BLACK-SITE",
		"slogans": [
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
			{"type": "sniper", "pos": Vector3(-18, 0.0, 18), "trigger": 26},
			{"type": "sniper", "pos": Vector3(20, 0.0, -16), "trigger": 26},
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
			"sky_contribution": 0.85, "glow": 0.8, "fog_density": 0.004,
			"sun_color": Color(1.0, 0.85, 0.6), "sun_energy": 1.7, "sun_rot": Vector3(-22, -55, 0),
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
		"open_sky": true,
		"floor_size": Vector2(90, 90),
		"floor_color": Color(0.16, 0.15, 0.17),
		"spawn": Vector3(-36, 0.6, -36),
		"exit": Vector3(36, 1.5, 36),
		"weapon": {"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(-31, 0, -23), "color": Color(0.45, 0.85, 1)}, # in front of the corner house — (-31,-31) was inside it
		"env": {
			"physical_sky": true, "turbidity": 10.0,
			"sky_top": Color(0.12, 0.1, 0.22), "sky_horizon": Color(0.7, 0.3, 0.2),
			"ground": Color(0.1, 0.08, 0.09), "fog": Color(0.5, 0.3, 0.26),
			"ambient": Color(0.72, 0.6, 0.62), "ambient_energy": 0.5,
			"sky_contribution": 0.75, "glow": 1.0, "fog_density": 0.006,
			"sun_color": Color(1.0, 0.6, 0.42), "sun_energy": 1.3, "sun_rot": Vector3(-18, -50, 0),
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
		"slogans": [
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
