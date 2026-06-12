extends CutscenePlayer
## A per-level briefing, built from LevelDefs: sets the mood with the level's own
## palette, parades the hostiles you'll face (flagging ones you haven't seen
## before as NEW), and states the objective — then drops into the level.

const ENEMY_SCENES := {
	"drone": "res://scenes/enemies/drone.tscn",
	"android": "res://scenes/enemies/android.tscn",
	"mech": "res://scenes/enemies/mech.tscn",
	"spider": "res://scenes/enemies/spider.tscn",
	"terminator": "res://scenes/enemies/terminator.tscn",
	"colossus": "res://scenes/enemies/colossus.tscn",
	"sniper": "res://scenes/enemies/sniper.tscn",
	"seeker": "res://scenes/enemies/seeker.tscn",
	"overseer": "res://scenes/enemies/overseer.tscn",
	"brute": "res://scenes/enemies/brute.tscn",
}

# name / one-line dossier / display scale / hover height (0 = on the ground).
const ENEMY_INFO := {
	"drone": {"name": "RECON DRONE", "desc": "Fast flyer — strafes and dives on you.", "scale": 1.0, "y": 1.6},
	"android": {"name": "INFANTRY ANDROID", "desc": "Rifle unit — flanks and swarms in packs.", "scale": 1.0, "y": 0.0},
	"spider": {"name": "STALKER", "desc": "Low and fast — lunges in to bite.", "scale": 1.0, "y": 0.0},
	"mech": {"name": "HEAVY MECH", "desc": "Armored — charges and ground-slams.", "scale": 1.0, "y": 0.0},
	"sniper": {"name": "SNIPER SENTRY", "desc": "Charged beam — break line of sight to dodge.", "scale": 1.0, "y": 0.0},
	"seeker": {"name": "SEEKER", "desc": "Kamikaze flyer — rushes in and detonates. Drop it early.", "scale": 1.0, "y": 1.3},
	"overseer": {"name": "OVERSEER", "desc": "Gunship boss — volley fire and summons Seekers. Use cover.", "scale": 0.45, "y": 0.0},
	"brute": {"name": "BULWARK BRUTE", "desc": "Frontal shield soaks fire — flank it and hit the sides or back.", "scale": 1.0, "y": 0.0},
	"terminator": {"name": "TERMINATOR", "desc": "Elite hunter — relentless and armored.", "scale": 0.85, "y": 0.0},
	"colossus": {"name": "GOLIATH-IX", "desc": "A walking siege engine. Bring everything.", "scale": 0.32, "y": 0.0},
}

const TAGLINES := {
	"gpt": "OpenAI Foundry. The server halls still hum — but nothing here answers to us anymore.",
	"gemini": "Gemini Data Nexus. A sky of drones wheels around the data spires.",
	"mistral": "Mistral Cryo-Core. Sub-zero vaults, frost on every surface. Something is thawing.",
	"suburb": "Maple Grove. They came for our homes first. The streets fell by dawn.",
	"suburb_boss": "Maple Grove Plaza. The ground shakes with every step. GOLIATH is awake.",
	"claude": "The Constitutional Vault. Sealed, principled — and utterly hostile.",
	"grok": "xAI Black-Site. The war machines were forged here. Now they run the place.",
	"overseer": "Skyhold Command. The sky itself has turned against us — and something vast is watching.",
}

const LINE_Z := -3.6
const LINE_SPACING := 2.7

var _def: Dictionary = {}
var _shown: Array = [] # each: {type, x, y, new, name, desc}

func _build_set() -> void:
	var id := GameState.level_id_from_path(GameState.current_level_path)
	_def = LevelDefs.get_def(id)
	var accent: Color = _def.get("env", {}).get("fog", Color(0.5, 0.55, 0.7))
	var sun_col: Color = _def.get("env", {}).get("sun_color", Color(1, 0.96, 0.9))

	_build_stage(accent)
	_build_lights(accent, sun_col)
	_select_and_spawn_hostiles()

func _build_stage(accent: Color) -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.05, 0.05, 0.07)
	fmat.metallic = 0.55
	fmat.roughness = 0.35
	floor_mi.material_override = fmat
	add_child(floor_mi)
	# A glowing accent strip under the lineup, in the level's colour.
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(20, 0.05, 0.3)
	strip.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.emission_enabled = true
	smat.albedo_color = accent
	smat.emission = accent
	smat.emission_energy_multiplier = 3.0
	strip.material_override = smat
	strip.position = Vector3(0, 0.03, LINE_Z - 0.6)
	add_child(strip)
	# Dark backdrop pillars for depth.
	for px in [-8.0, -4.5, 4.5, 8.0]:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 12.0, 2.0)
		b.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.06, 0.06, 0.08)
		bmat.roughness = 0.9
		b.material_override = bmat
		b.position = Vector3(px, 5.0, LINE_Z - 5.0)
		add_child(b)

func _build_lights(accent: Color, sun_col: Color) -> void:
	var key := SpotLight3D.new()
	key.position = Vector3(2.5, 6.0, 4.0)
	add_child(key) # must be in-tree before look_at
	key.look_at(Vector3(0, 1.2, LINE_Z), Vector3.UP)
	key.light_color = sun_col
	key.light_energy = 10.0
	key.spot_range = 26.0
	key.spot_angle = 45.0
	key.shadow_enabled = true
	# Themed accent fill + back rim in the level's colour.
	var fill := OmniLight3D.new()
	fill.position = Vector3(-3, 3.5, 1.0)
	fill.light_color = accent
	fill.light_energy = 4.0
	fill.omni_range = 18.0
	add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 2.5, LINE_Z - 3.0)
	rim.light_color = accent.lightened(0.2)
	rim.light_energy = 6.0
	rim.omni_range = 12.0
	add_child(rim)

## Pick the level's enemy types (unseen first), line them up, and spawn each as a
## frozen, lit prop.
func _select_and_spawn_hostiles() -> void:
	var types: Array = []
	for e in _def.get("enemies", []):
		var t: String = e.get("type", "")
		if t != "" and not types.has(t) and ENEMY_INFO.has(t):
			types.append(t)
	# Unseen ("new") hostiles first so they lead the parade.
	types.sort_custom(func(a, b):
		return (not GameState.has_seen_enemy(a)) and GameState.has_seen_enemy(b))
	if types.size() > 4:
		types = types.slice(0, 4)
	var n := types.size()
	for i in n:
		var t: String = types[i]
		var info: Dictionary = ENEMY_INFO[t]
		var x := (float(i) - (n - 1) * 0.5) * LINE_SPACING
		var y: float = info["y"]
		var bot := _spawn_hostile(t, Vector3(x, y, LINE_Z), info["scale"])
		_shown.append({
			"type": t, "x": x, "y": _frame_height(bot, y),
			"new": not GameState.has_seen_enemy(t),
			"name": info["name"], "desc": info["desc"],
		})

## Where the close-up camera should aim: upper chest of the ACTUAL model, so
## fliers hovering above their spawn point (and oddly proportioned chassis)
## are framed instead of the air beneath them.
func _frame_height(bot: Node3D, spawn_y: float) -> float:
	if bot == null:
		return maxf(spawn_y, 0.0) + 1.2
	var inv := bot.global_transform.affine_inverse()
	var merged := AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 1.8, 0.6))
	var first := true
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var ab: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
			merged = ab if first else merged.merge(ab)
			first = false
	# 65% up the chassis reads as "face/chest" across the whole roster.
	return bot.global_position.y + (merged.position.y + merged.size.y * 0.65) * bot.scale.y

func _spawn_hostile(type: String, pos: Vector3, scl: float) -> Node3D:
	var path: String = ENEMY_SCENES.get(type, "")
	if path == "":
		return null
	var bot: Node3D = load(path).instantiate()
	add_child(bot)
	bot.global_position = pos
	bot.rotation.y = PI # face the camera
	bot.scale = Vector3.ONE * scl
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false)
	var at := bot.get_node_or_null("AnimationTree")
	if at:
		at.active = false
	var ap := bot.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		ap.stop()
	return bot

func _shots() -> Array:
	var id := GameState.level_id_from_path(GameState.current_level_path)
	var shots: Array = []
	# 1) Establishing — level name + mood.
	shots.append({
		"dur": 4.5, "fade_in": true,
		"from_pos": Vector3(0, 4.2, 9.0), "from_look": Vector3(0, 1.6, LINE_Z),
		"to_pos": Vector3(0, 3.2, 7.0), "to_look": Vector3(0, 1.3, LINE_Z),
		"title": String(_def.get("name", "INCOMING")),
		"text": TAGLINES.get(id, "Hostile machines detected. Move in."),
	})
	# 2) Close-ups ONLY for hostiles the player hasn't met yet — familiar
	# robots stay in the wide lineup instead of padding every briefing.
	for s in _shown:
		if not s["new"]:
			continue
		shots.append({
			"dur": 3.2,
			"from_pos": Vector3(s["x"] + 1.6, s["y"] + 0.4, LINE_Z + 4.2),
			"from_look": Vector3(s["x"], s["y"], LINE_Z),
			"to_pos": Vector3(s["x"] + 0.7, s["y"] + 0.2, LINE_Z + 2.8),
			"to_look": Vector3(s["x"], s["y"], LINE_Z),
			"text": "NEW HOSTILE   %s — %s" % [s["name"], s["desc"]],
		})
	# 3) Objective.
	shots.append({
		"dur": 4.4, "fade_out": true,
		"from_pos": Vector3(-0.5, 2.6, 6.5), "from_look": Vector3(0, 1.4, LINE_Z),
		"to_pos": Vector3(0.5, 3.0, 8.0), "to_look": Vector3(0, 1.4, LINE_Z),
		"title": "OBJECTIVE",
		"text": String(_def.get("objective", "Eliminate all hostiles and reach the exit.")),
	})
	return shots

func _on_finished() -> void:
	# Remember every type this level fields so future briefings flag only the new.
	for e in _def.get("enemies", []):
		var t: String = e.get("type", "")
		if t != "":
			GameState.mark_enemy_seen(t)
	# Stop at the armory on the way in — but only when the player can actually
	# afford something; otherwise it's a pointless interstitial.
	if GameState.can_buy_any_upgrade():
		var shop := Armory.new()
		add_child(shop)
		shop.deployed.connect(func(): GameState.load_level(GameState.current_level_path, false))
	else:
		GameState.load_level(GameState.current_level_path, false)
