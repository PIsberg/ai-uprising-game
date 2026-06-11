class_name LevelDefs
## Compact data for every builder-driven level. Each entry is consumed by
## LevelBuilder. The rogue-AI factions are affectionate parodies of real
## assistants — GPT / Gemini / Claude / Grok — themed only by name, colour and
## layout (no logos or real assets).

static func get_def(id: String) -> Dictionary:
	return _defs().get(id, {})

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
		"props": [
			{"type": "crate", "pos": Vector3(-4, 0, -3)},
			{"type": "barrel", "pos": Vector3(8, 0, 3)},
			{"type": "crate", "pos": Vector3(-9, 0, 9)},
			{"type": "barrel", "pos": Vector3(12, 0, -9)},
			{"type": "crate", "pos": Vector3(3, 0, 12)},
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
		"props": [
			{"type": "crate", "pos": Vector3(-4, 0, -2)},
			{"type": "crate", "pos": Vector3(4, 0, 3)},
			{"type": "barrel", "pos": Vector3(9, 0, -6)},
			{"type": "barrel", "pos": Vector3(-9, 0, 9)},
			{"type": "crate", "pos": Vector3(12, 0, 8)},
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
		],
	}

# --- Gemini Nexus: open blue arena, drone swarm around a central platform ---
static func _gemini() -> Dictionary:
	return {
		"name": "Gemini Data Nexus",
		"objective": "Break the Gemini swarm and reach the beacon",
		"tasks": [
			{"type": "kill_all"},
			{"type": "collect_shards", "label": "Recover the Gemini data shards", "points": [Vector3(-16, 0, -16), Vector3(16, 0, -14), Vector3(-15, 0, 16), Vector3(16, 0, 16), Vector3(0, 0, 18)]},
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
		"props": [
			{"type": "crate", "pos": Vector3(-8, 0, -4)},
			{"type": "barrel", "pos": Vector3(8, 0, 4)},
			{"type": "barrel", "pos": Vector3(4, 0, -13)},
			{"type": "crate", "pos": Vector3(-13, 0, 8)},
			{"type": "crate", "pos": Vector3(15, 0, -6)},
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
		"props": [
			{"type": "crate", "pos": Vector3(0, 0, -8)},
			{"type": "barrel", "pos": Vector3(-3, 0, 2)},
			{"type": "crate", "pos": Vector3(8, 0, 8)},
			{"type": "barrel", "pos": Vector3(12, 0, -4)},
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
		"props": [
			{"type": "crate", "pos": Vector3(-6, 0, 2)},
			{"type": "barrel", "pos": Vector3(6, 0, -6)},
			{"type": "crate", "pos": Vector3(0, 0, 12)},
			{"type": "barrel", "pos": Vector3(-12, 0, -4)},
			{"type": "crate", "pos": Vector3(12, 0, 4)},
			{"type": "barrel", "pos": Vector3(4, 0, 16)},
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
		"weapon": {"scene": "res://scenes/weapons/tesla.tscn", "pos": Vector3(-31, 0, -31), "color": Color(0.45, 0.85, 1)},
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
		],
	}
