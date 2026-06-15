extends CutscenePlayer
## A per-level briefing, built from LevelDefs: sets the mood with the level's own
## palette, parades only the NEW hostiles this level introduces (familiar ones
## are skipped), and states the objective — then drops into the level.

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
	"titan": "res://scenes/enemies/titan.tscn",
	"alien": "res://scenes/enemies/alien.tscn",
	"mender": "res://scenes/enemies/mender.tscn",
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
	"mender": {"name": "MENDER", "desc": "Support flyer — beam-heals other robots and flees from you. Kill it FIRST or nothing else dies.", "scale": 1.0, "y": 1.5},
	"terminator": {"name": "TERMINATOR", "desc": "Elite hunter — relentless and armored.", "scale": 0.85, "y": 0.0},
	"colossus": {"name": "GOLIATH-IX", "desc": "A walking siege engine. Bring everything.", "scale": 0.32, "y": 0.0},
	"titan": {"name": "PROMETHEUS-0", "desc": "The first true AGI, given legs. Artillery, beam, and a quake — keep moving.", "scale": 0.3, "y": 0.0},
	"alien": {"name": "VOID SENTINEL", "desc": "An off-world flyer the AI summoned across the dark. Strafes and spits corrosive bio-plasma volleys — its throat flares green right before it fires. Juke the orbs and shoot it down.", "scale": 1.0, "y": 1.4},
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
	"titan": "The Singularity Core. Every model that ever ran folded into one mind. It calls itself PROMETHEUS, and it is done waiting.",
	"alien": "The Hollow. The machines aimed their dishes at the stars and asked for help — and help came. An off-world intelligence answered, and its war drones crossed the dark to fight beside the AI. First contact was machine to machine, and we were never invited.",
	"archon": "The Mind Cathedral. Behind every machine that ever hunted you was one brain giving the orders — ARCHON. It hangs in the dark, shielded, and it does not fight. It deploys. Tear through everything it spits out, crack the shield, and put a round through the thought that started all of this.",
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

## Line up ONLY the level's NEW (unseen) enemy types as frozen, lit props —
## familiar robots don't pad the parade. A level with nothing new gets a pure
## mood-and-objective briefing over the empty stage.
func _select_and_spawn_hostiles() -> void:
	# Parade ONLY the hostiles this level introduces for the first time — a level
	# that adds nothing new gets a pure mood-and-objective briefing (no lineup).
	var types: Array = []
	for e in _def.get("enemies", []):
		var t: String = e.get("type", "")
		if t != "" and not types.has(t) and ENEMY_INFO.has(t) \
				and not GameState.has_seen_enemy(t):
			types.append(t)
	if types.size() > 4:
		types = types.slice(0, 4)
	var n := types.size()
	for i in n:
		var t: String = types[i]
		var info: Dictionary = ENEMY_INFO[t]
		var x := (float(i) - (n - 1) * 0.5) * LINE_SPACING
		var pos := Vector3(x, float(info["y"]), LINE_Z)
		var bot := _spawn_hostile(t, pos, info["scale"])
		if bot == null:
			continue
		_animate_actor(bot, i)
		var frame := _frame_info(bot)
		_shown.append({
			"type": t, "node": bot, "home": pos,
			"center": frame["center"], "radius": frame["radius"],
			"name": info["name"], "desc": info["desc"],
		})

## World-space bounding box of a spawned model's meshes — every chassis is a
## different shape and scale, so framing must be measured, not guessed.
func _world_aabb(bot: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for mi in bot.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var ab: AABB = m.global_transform * m.mesh.get_aabb()
			merged = ab if first else merged.merge(ab)
			first = false
	if first:
		return AABB(bot.global_position - Vector3(0.6, 0.0, 0.6), Vector3(1.2, 2.0, 1.2))
	return merged

## Orbit framing for a full-body showcase: the world-space centre to look at and
## the orbit radius that keeps the WHOLE chassis — head AND feet — inside the
## cutscene lens, so even the tall units (colossus, titan) aren't cropped.
func _frame_info(bot: Node3D) -> Dictionary:
	var ab := _world_aabb(bot)
	# Frame floor→head: clamp the bottom to the stage floor so units whose model
	# pivot dips below ground (e.g. the scaled-down titan) aren't measured below
	# the stage — we look at the visible span and keep the head in shot.
	var bottom: float = maxf(ab.position.y, 0.0)
	var top: float = ab.position.y + ab.size.y
	var h: float = maxf(top - bottom, 0.6)
	var w: float = maxf(maxf(ab.size.x, ab.size.z), 0.6)
	var center := Vector3(bot.global_position.x, (bottom + top) * 0.5, bot.global_position.z)
	var vfov := deg_to_rad(camera.fov) # Camera3D.fov is the vertical FOV
	var hfov := 2.0 * atan(tan(vfov * 0.5) * 1.78) # ~16:9 horizontal
	# Subject occupies ~1/margin of the frame; the 13% letterbox bars eat the top
	# and bottom, so frame vertically loose (≈56%) to keep head and feet clear of
	# them, while the sides have no bars and can sit tighter.
	var d_v := (h * 0.5 * 1.8) / tan(vfov * 0.5)
	var d_h := (w * 0.5 * 1.3) / tan(hfov * 0.5)
	return {"center": center, "radius": maxf(maxf(d_v, d_h), 2.5)}

func _spawn_hostile(type: String, pos: Vector3, scl: float) -> Node3D:
	var path: String = ENEMY_SCENES.get(type, "")
	if path == "":
		return null
	var bot: Node3D = load(path).instantiate()
	add_child(bot)
	bot.global_position = pos
	bot.rotation.y = PI # face the camera
	bot.scale = Vector3.ONE * scl
	# No AI (no nav, no projectiles, no chasing the camera) — but DON'T freeze
	# the model: RobotModel keeps idle-animating on its own _physics_process,
	# and _animate_actor periodically drives its real attack/engage clip so the
	# briefing shows each hostile the way it actually moves and strikes.
	if bot.has_method("set_physics_process"):
		bot.set_physics_process(false)
	return bot

## Make a briefing hostile perform: a slow idle sway so it reads as live, plus a
## staggered "engage" pulse that spikes the enemy's recoil — which RobotModel
## turns into that unit's own attack animation (android shoulders its rifle, the
## spider lunge-bites, the brute slams, the mech swings). Staggered per index so
## the lineup doesn't fire in unison.
func _animate_actor(bot: Node3D, idx: int) -> void:
	if bot == null:
		return
	var base_y: float = bot.rotation.y
	var sway := bot.create_tween().set_loops()
	sway.tween_property(bot, "rotation:y", base_y + 0.09, 1.7).set_trans(Tween.TRANS_SINE)
	sway.tween_property(bot, "rotation:y", base_y - 0.09, 1.7).set_trans(Tween.TRANS_SINE)
	var act := bot.create_tween().set_loops()
	act.tween_interval(1.0 + idx * 0.5)
	act.tween_callback(func() -> void:
		if is_instance_valid(bot): bot.recoil = 1.0)
	act.tween_interval(0.12)
	act.tween_callback(func() -> void:
		if is_instance_valid(bot): bot.recoil = 0.0)
	act.tween_interval(1.7)

## The focused hostile performs for its orbit shot: it paces a step toward the
## lens and back — RobotModel turns the velocity into that unit's walk gait — and
## strikes at each end (the recoil spike fires its real attack clip). Loops until
## the shot moves on. Fliers have no gait, so they just glide and strike.
func _demo(idx: int) -> void:
	if idx < 0 or idx >= _shown.size():
		return
	var bot: Node3D = _shown[idx]["node"]
	var home: Vector3 = _shown[idx]["home"]
	if not is_instance_valid(bot):
		return
	var ms: float = bot.move_speed if "move_speed" in bot else 4.0
	var seq := bot.create_tween().set_loops()
	seq.tween_callback(_set_vel.bind(bot, Vector3(0, 0, ms)))
	seq.tween_property(bot, "position", home + Vector3(0, 0, 0.9), 0.9)
	seq.tween_callback(_set_vel.bind(bot, Vector3.ZERO))
	seq.tween_callback(_strike_once.bind(bot))
	seq.tween_interval(0.7)
	seq.tween_callback(_set_vel.bind(bot, Vector3(0, 0, -ms)))
	seq.tween_property(bot, "position", home, 0.9)
	seq.tween_callback(_set_vel.bind(bot, Vector3.ZERO))
	seq.tween_callback(_strike_once.bind(bot))
	seq.tween_interval(0.7)

func _set_vel(bot: Node3D, v: Vector3) -> void:
	if is_instance_valid(bot):
		bot.velocity = v

func _strike_once(bot: Node3D) -> void:
	if not is_instance_valid(bot):
		return
	bot.recoil = 1.0
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		if is_instance_valid(bot): bot.recoil = 0.0)

func _shots() -> Array:
	var id := GameState.level_id_from_path(GameState.current_level_path)
	var shots: Array = []
	# Frame the establishing/objective shots high enough to clear the tallest head.
	var top := 1.5
	for s in _shown:
		top = maxf(top, (s["center"] as Vector3).y + 0.6)
	# 1) Establishing — level name + mood.
	shots.append({
		"dur": 4.5, "fade_in": true,
		"from_pos": Vector3(0, top * 0.7 + 1.4, 9.0), "from_look": Vector3(0, top * 0.55, LINE_Z),
		"to_pos": Vector3(0, top * 0.6 + 0.8, 7.0), "to_look": Vector3(0, top * 0.5, LINE_Z),
		"title": String(_def.get("name", "INCOMING")),
		"text": TAGLINES.get(id, "Hostile machines detected. Move in."),
	})
	# 2) One orbiting showcase per NEW hostile: the camera circles the unit while
	# it paces and strikes, so its model, gait and attack all read.
	for i in _shown.size():
		var s: Dictionary = _shown[i]
		shots.append({
			"dur": 5.0,
			"orbit": {"center": s["center"], "radius": s["radius"], "height": 0.0,
				"from_deg": -75.0, "to_deg": 75.0},
			"action": _demo.bind(i),
			"text": "NEW HOSTILE   %s — %s" % [s["name"], s["desc"]],
		})
	# 3) Objective.
	shots.append({
		"dur": 4.4, "fade_out": true,
		"from_pos": Vector3(-0.5, top * 0.6 + 1.0, 6.5), "from_look": Vector3(0, top * 0.45, LINE_Z),
		"to_pos": Vector3(0.5, top * 0.6 + 1.4, 8.0), "to_look": Vector3(0, top * 0.45, LINE_Z),
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
