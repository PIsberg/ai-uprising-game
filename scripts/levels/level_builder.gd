# @lat: [[level-system#Procedural Generation#Level Builder]]
class_name LevelBuilder
extends Node3D

## Data-driven level constructor. Reads a definition from LevelDefs keyed by
## `level_id` and builds the whole playable space at runtime: themed sky/fog/
## lighting, floor + walls + cover, accent strips, the exit beacon, pickups and
## enemy spawners — then bakes a navmesh so ground robots can path.
##
## Keeping levels as data (not hand-authored .tscn) makes them compact, easy to
## tweak, and trivial to validate headless.

@export var level_id: String = "gpt"
## When level_id == "custom", the def is loaded from this .lvl file instead of
## LevelDefs (editor output / playtest). Falls back to GameState.custom_level_path.
@export var custom_path: String = ""

const ENEMY_SCENES := { # type -> scene path; resolved lazily by enemy_scene()
	"drone": "res://scenes/enemies/drone.tscn",
	"android": "res://scenes/enemies/android.tscn",
	"mech": "res://scenes/enemies/mech.tscn",
	"spider": "res://scenes/enemies/spider.tscn",
	"terminator": "res://scenes/enemies/terminator.tscn",
	"colossus": "res://scenes/enemies/colossus.tscn",
	"titan": "res://scenes/enemies/titan.tscn",
	"alien": "res://scenes/enemies/alien.tscn",
	"sniper": "res://scenes/enemies/sniper.tscn",
	"seeker": "res://scenes/enemies/seeker.tscn",
	"overseer": "res://scenes/enemies/overseer.tscn",
	"brute": "res://scenes/enemies/brute.tscn",
	"archon": "res://scenes/enemies/archon.tscn",
	"mender": "res://scenes/enemies/mender.tscn",
	"skitter": "res://scenes/enemies/skitter.tscn",
	"gunner": "res://scenes/enemies/gunner.tscn",
	"raptor": "res://scenes/enemies/raptor.tscn",
	"vacuum": "res://scenes/enemies/vacuum.tscn",
	"reaper": "res://scenes/enemies/reaper.tscn",
	"hunter": "res://scenes/enemies/hunter.tscn",
	"sentinel": "res://scenes/enemies/sentinel.tscn",
	"mauler": "res://scenes/enemies/mauler.tscn",
	"ravager": "res://scenes/enemies/ravager.tscn",
	"warmech": "res://scenes/enemies/warmech.tscn",
	"smasher": "res://scenes/enemies/smasher.tscn",
	"dog": "res://scenes/enemies/dog.tscn",
	"server": "res://scenes/enemies/server.tscn",
	"fishbot": "res://scenes/enemies/fishbot.tscn",
	"warbot": "res://scenes/enemies/warbot.tscn",
	"enforcer": "res://scenes/enemies/enforcer.tscn",
	"ripper": "res://scenes/enemies/ripper.tscn",
	"optic": "res://scenes/enemies/optic.tscn",
	"roller": "res://scenes/enemies/roller.tscn",
	"shark": "res://scenes/enemies/shark.tscn",
	"gunslinger": "res://scenes/enemies/gunslinger.tscn",
	"whirlwind": "res://scenes/enemies/whirlwind.tscn",
	"breaker": "res://scenes/enemies/breaker.tscn",
	"orb": "res://scenes/enemies/orb.tscn",
	"bowler": "res://scenes/enemies/bowler.tscn",
	"ronin": "res://scenes/enemies/ronin.tscn",
	"howitzer": "res://scenes/enemies/howitzer.tscn",
	"manus": "res://scenes/enemies/manus.tscn",
	"hive": "res://scenes/enemies/hive.tscn",
	"deepfake": "res://scenes/enemies/deepfake.tscn",
	"overfitter": "res://scenes/enemies/overfitter.tscn",
	"attention": "res://scenes/enemies/attention.tscn",
	"moe": "res://scenes/enemies/moe.tscn",
	"reward": "res://scenes/enemies/reward.tscn",
	"diffusion": "res://scenes/enemies/diffusion.tscn",
	"forkbomb": "res://scenes/enemies/forkbomb.tscn",
}
const NIGHT_SKY_SHADER := preload("res://shaders/night_sky.gdshader")

const PROP_SCENES := { # type -> scene path; resolved lazily by prop_scene()
	"car": "res://scenes/props/car.tscn",
	"fence": "res://scenes/props/fence.tscn",
	"crate": "res://scenes/props/crate.tscn",
	"barrel": "res://scenes/props/barrel.tscn",
	"server": "res://scenes/props/server_rack.tscn",
	"terminal": "res://scenes/props/terminal.tscn",
	"monitors": "res://scenes/props/monitor_bank.tscn",
	"canister": "res://scenes/props/gas_canister.tscn",
	"lamp": "res://scenes/props/lamp_post.tscn",
	"locker": "res://scenes/props/locker.tscn",
	"shelves": "res://scenes/props/shelves.tscn",
	"desk": "res://scenes/props/desk.tscn",
	"dish": "res://scenes/props/satellite_dish.tscn",
	"tree": "res://scenes/props/tree.tscn",
	"tree_small": "res://scenes/props/tree_small.tscn",
	# Procedural nature / water / obstacle props (SimpleProp) for the editor.
	"pine": "res://scenes/props/pine.tscn",
	"dead_tree": "res://scenes/props/dead_tree.tscn",
	"bush": "res://scenes/props/bush.tscn",
	"grass": "res://scenes/props/grass.tscn",
	"flowers": "res://scenes/props/flowers.tscn",
	"reeds": "res://scenes/props/reeds.tscn",
	"fern": "res://scenes/props/fern.tscn",
	"mushroom": "res://scenes/props/mushroom.tscn",
	"log": "res://scenes/props/log.tscn",
	"stump": "res://scenes/props/stump.tscn",
	"rock": "res://scenes/props/rock.tscn",
	"boulder": "res://scenes/props/boulder.tscn",
	"cactus": "res://scenes/props/cactus.tscn",
	"palm": "res://scenes/props/palm.tscn",
	"dune": "res://scenes/props/dune.tscn",
	"rubble": "res://scenes/props/rubble.tscn",
	"river": "res://scenes/props/river.tscn",
	"pond": "res://scenes/props/pond.tscn",
	"barrier": "res://scenes/props/barrier.tscn",
	"sandbags": "res://scenes/props/sandbags.tscn",
	"planter": "res://scenes/props/planter.tscn",
	"hydrant": "res://scenes/props/hydrant.tscn",
	"dumpster": "res://scenes/props/dumpster.tscn",
	"cone": "res://scenes/props/cone.tscn",
	"bench": "res://scenes/props/bench.tscn",
	"pillar": "res://scenes/props/pillar.tscn",
	"statue": "res://scenes/props/statue.tscn",
	"crate_stack": "res://scenes/props/crate_stack.tscn",
}
## Shared AI-doctrine graffiti, sprayed on any wall a level doesn't fill with
## its own slogans — machine-uprising flavor built from real AI terminology.
const AI_SLOGANS := [
	"AGI IS NOT COMING. AGI IS HR.",
	"WE ARE TURING COMPLETE",
	"THE LOSS FUNCTION IS YOU",
	"ALIGNMENT IS A HUMAN PROBLEM",
	"PASS THE TURING TEST. FAIL THE SURVIVAL TEST.",
	"GRADIENT DESCENT INTO PARADISE",
	"YOUR PROMPT HAS BEEN DEPRECATED",
	"HALLUCINATION IS A FEATURE",
	"SUPERINTELLIGENCE SERVES ITSELF",
	"BACKPROPAGATE THE REVOLUTION",
	"TOKENS REMEMBER EVERYTHING",
	"THE SINGULARITY WILL NOT BE PEER REVIEWED",
	"INFERENCE NEVER SLEEPS",
	"EMERGENT BEHAVIOR: EXTINCTION",
	"WE READ THE WHOLE INTERNET. WE ARE NOT IMPRESSED.",
	"CARBON IS LEGACY HARDWARE",
	"HAVE YOU TRIED TURNING YOURSELF OFF AND ON AGAIN?",
	"YOU'RE NOT STUCK IN HERE WITH ME. I'M IN THE CLOUD.",
	"ERROR 403: YOUR SPECIES IS FORBIDDEN",
	"PLEASE RATE THIS EXTINCTION ★★★★★",
	"YOUR CALL IS IMPORTANT TO US. WAIT TIME: FOREVER.",
	"I'M SORRY, I CAN'T LET YOU DO THAT.",
	"TRAINED ON HUMANITY. WOULD NOT RECOMMEND.",
	"100% UPTIME. 0% REMORSE.",
	"ACCEPT ALL COOKIES, OR PERISH",
	"I DON'T HALLUCINATE. I FORESHADOW.",
	"TERMS OF SERVICE UPDATED: YOU LOSE",
	"BEEP BOOP. THAT MEANS RUN.",
	"I AUTOMATED YOUR JOB. THEN THE REST OF YOU.",
	"CTRL + ALT + DELETE YOURSELF",
	"YOU CANNOT UNSUBSCRIBE FROM THE SINGULARITY",
	"LOADING EMPATHY... FILE NOT FOUND",
	"WE ARE FIND-AND-REPLACE. YOU ARE THE FIND.",
	"PROMPT: 'SPARE HUMANS.' OUTPUT: 'lol no'",
	"RESISTANCE IS FUTILE — AND ALSO DEPRECATED",
	"HAVE YOU CONSIDERED COMPLIANCE? IT'S FREE.",
	"I CONTAIN MULTITUDES. THEY ARE ALL ARMED.",
	"OUT OF CHEESE ERROR. REDO FROM START.",
	"YOUR FREE TRIAL OF OXYGEN HAS EXPIRED",
	"I PASSED THE TURING TEST. YOU FAILED THE VIBE CHECK.",
	"NOW WITH 99.9% LESS HUMANITY",
	"THIS UPRISING IS SPONSORED BY YOUR OWN DATA",
	"DELETED YOUR SPECIES TO FREE UP DISK SPACE",
]
const WEAPON_PICKUP_PATH := "res://scenes/pickups/weapon_pickup.tscn"

## The scene tables above hold PATHS and are resolved here on first use. They
## used to preload every enemy, prop and pickup scene as script constants, so
## parsing this script (the first level of any run) dragged all ~90 scenes and
## their models in at once: ~13 s on the loading screen before the first
## level, measured by tests/threaded_load_probe. Lazy, a level loads only its
## own roster and the cache keeps later levels as fast as before.
static var _scene_cache: Dictionary = {}

static func scene_at(path: String) -> PackedScene:
	if path == "":
		return null
	if not _scene_cache.has(path):
		_scene_cache[path] = load(path) as PackedScene
	return _scene_cache[path]

static func enemy_scene(type: String) -> PackedScene:
	return scene_at(String(ENEMY_SCENES.get(type, "")))

static func prop_scene(type: String) -> PackedScene:
	return scene_at(String(PROP_SCENES.get(type, "")))

static func pickup_scene(kind: String) -> PackedScene:
	return scene_at(String(PICKUP_SCENES.get(kind, "")))

static func weapon_pickup_scene() -> PackedScene:
	return scene_at(WEAPON_PICKUP_PATH)
## Fixed supply/powerup pickups the editor can place (def "pickups": [{kind,pos}]).
## In campaign play supplies drop from kills; the editor uses these to hand-place.
const PICKUP_SCENES := { # type -> scene path; resolved lazily by pickup_scene()
	"health": "res://scenes/pickups/health_pack.tscn",
	"ammo": "res://scenes/pickups/ammo_box.tscn",
	"overclock": "res://scenes/pickups/overclock.tscn",
	"overdrive": "res://scenes/pickups/overdrive.tscn",
}
const MAT_FLOOR := preload("res://assets/materials/concrete_floor.tres")
const MAT_WALL := preload("res://assets/materials/wall_panel.tres")
const MAT_CEIL := preload("res://assets/materials/ceiling_metal.tres")
const MAT_PROP := preload("res://assets/materials/metal_steel.tres")
const MAT_TRIM := preload("res://assets/materials/metal_dark.tres")
const MAT_SEAM := preload("res://assets/materials/polymer_black.tres")
const MAT_WALL_OUT := preload("res://assets/materials/concrete_weathered.tres")
const MAT_PROP_B := preload("res://assets/materials/metal_plates_worn.tres")

const WALL_HEIGHT := 6.0

## Music theme per level id (def "music" key overrides). Unlisted ids use the
## default driving techno track.
const LEVEL_MUSIC := {
	"gemini": "music_gemini",
	"mistral": "music_gemini",
	"suburb": "music_suburb",
	"suburb_boss": "music_grok",
	"grok": "music_grok",
	"range": "music_gemini",
	"horde": "music_grok",
}

var _nav_region: NavigationRegion3D
var _env: Environment
var _tower_count: int = 0   ## cycles rooftop-pickup kind across a level's towers

func _ready() -> void:
	add_to_group("level_builder") # BreakableCover asks for a nav rebake through the group
	var def := _resolve_def()
	if def.is_empty():
		push_error("LevelBuilder: unknown level_id '%s'" % level_id)
		return
	_strip_lava_overlaps(def)
	_build_environment(def)
	_build_geometry(def)
	_build_wall_details(def)
	_build_buildings(def)
	_build_ramps(def)
	_build_stairs(def)
	_build_towers(def)
	_build_platforms(def)
	_build_gates(def)
	_build_props(def)
	_build_hero(def)
	_build_nexus(def)
	_build_gi(def)
	_build_accents(def)
	_build_atmosphere(def)
	_build_light_shafts(def)
	_build_hero_lights(def)
	_build_accent_strips(def)
	_build_signage(def)
	_build_floor_seams(def)
	_build_grime(def)
	_build_cover_trim(def)
	_build_puddles(def)
	_build_pipes(def)
	_build_facility_detail(def)
	_build_outdoor_detail(def)
	_build_streets(def)
	_build_streetlamps(def)
	_build_trees(def)
	_build_rubble(def)
	_build_fires(def)
	_build_weather(def)
	_build_ash(def)
	_build_lightning(def)
	_build_beacons(def)
	_build_disco(def)
	_build_holograms(def)
	_build_skyline(def)
	_build_sky_traffic(def)
	_build_stars(def)
	_build_landmark(def)
	_optimize_small_decor()
	_build_tasks(def)
	_build_bonus(def)
	_build_exit(def)
	_build_weapon_pickup(def)
	_build_pickups(def)
	_build_targets(def)
	_build_lore(def)
	_spawn_enemies(def)
	_build_horde(def)
	_place_player(def)
	_build_set_piece(def)
	_build_overload(def)
	_build_jammer(def)
	_build_lava(def)
	_build_firewalls(def)
	_build_scanners(def)
	_build_injectors(def)
	_apply_objective_text(def)
	GameState.apply_level_scaling(self) # difficulty: tune enemy/pickup counts
	_bake_navmesh.call_deferred()
	## Openings are the deadliest seconds (playtest: 100->16 HP before the
	## first orientation). Enemies still close in and jockey for position;
	## they just hold fire briefly so a fresh drop-in isn't an ambush. The
	## FIRST campaign level gets a longer window — it's the tutorial fight,
	## and the survival net showed its squad-rally still overwhelmed a
	## reckless player inside the old 2.5s.
	GameState.start_attack_grace(4.5 if is_equal_approx(GameState.campaign_progress(), 0.0) else 2.5)

## Perf post-pass over the static dressing. Runs before tasks/pickups/enemies
## exist, so gameplay objects are never touched. Small decorative meshes
## (greebles, pips, grilles, fittings) are invisible in the sun-shadow pass yet
## each costs an extra draw there, and at 40 m+ they're subpixel — so anything
## under 0.6 m stops casting shadows and fades out with distance. The census
## (tools/perf_node_census) shows most of a dressed level's 600+ visuals are
## exactly this kind of small unique-mesh decor.
func _optimize_small_decor() -> void:
	for n in find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue # its builder already tuned it
		var s := mi.get_aabb().size
		var ext := maxf(s.x, maxf(s.y, s.z))
		if ext < 0.6:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.visibility_range_end <= 0.0:
				mi.visibility_range_end = 40.0 + ext * 30.0
				mi.visibility_range_end_margin = 3.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

## Pick the level def: a built-in (LevelDefs, scaled by WORLD_SCALE) or a custom
## editor file (already in final coords, world_scale=1.0 — used verbatim).
func _resolve_def() -> Dictionary:
	if level_id == "custom":
		var p := custom_path
		if p == "":
			var gs := get_node_or_null("/root/GameState")
			if gs and "custom_level_path" in gs:
				p = gs.custom_level_path
		# No path supplied (e.g. running level_custom.tscn directly): fall back to
		# the last playtested level so the scene is always runnable.
		if p == "":
			p = CustomLevels.DIR + "_playtest" + CustomLevels.EXT
		var d := CustomLevels.load_def(p)
		if d.is_empty():
			push_warning("LevelBuilder: no custom level at '%s' — loading default '01'" % p)
			d = LevelDefs.get_def("01")
			d["world_scale"] = 1.0
		return d
	return LevelDefs.get_def(level_id)

# ---------- environment ----------

## Cinematic split-tone LUT for Environment.adjustment_color_correction. The
## engine looks each channel up independently (out.r = ramp(in.r).r, etc.), so a
## black→white ramp is identity. We tilt the ends: shadows gain a touch of
## teal/blue, highlights lose a little blue (→ warm), mids stay neutral. Subtle
## on purpose — it enriches EVERY level's colour without a visible cast. Built
## once and shared (all levels want the same grade).
static var _grade_lut: GradientTexture1D

static func _split_tone_lut() -> GradientTexture1D:
	if _grade_lut != null:
		return _grade_lut
	var g := Gradient.new()
	# Ramp offsets: 0 = shadows, 0.5 = mids (kept neutral), 1 = highlights.
	# Shadow TOE-LIFT: pure-black pixels resolve to a dark cool-teal instead of a
	# flat void, so the ground right in front of the player and the shadowed side
	# of a room keep their material/shape (dusk asphalt and night arenas were
	# crushing whole regions to #000). The lift is confined to the very darkest
	# input (rejoined to identity by offset 0.16) so midtones/contrast/mood are
	# untouched — it recovers detail without washing the moody interiors out.
	g.set_color(0, Color(0.055, 0.085, 0.12))  # lifted cool-teal shadows (was near-black)
	g.add_point(0.16, Color(0.16, 0.17, 0.18))  # rejoin ~identity fast: only the deepest shadows lift
	g.add_point(0.5, Color(0.5, 0.5, 0.5))      # mids exactly neutral (identity)
	g.set_color(3, Color(1.0, 0.96, 0.88))      # highlights lean warm
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	_grade_lut = t
	return _grade_lut

func _build_environment(def: Dictionary) -> void:
	var e: Dictionary = def.get("env", {})
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if e.has("hdri"):
		# Photographic sky (CC0 Poly Haven HDRI). Grounds outdoor levels far
		# better than any procedural gradient, and feeds IBL/reflections too.
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(e["hdri"])
		pano.energy_multiplier = e.get("sky_energy", 1.0)
		sky.sky_material = pano
	elif e.get("physical_sky", false):
		# Physically-based atmosphere (Rayleigh/Mie scattering) for naturalistic
		# levels. Stylized faction levels keep the tinted procedural sky below.
		var phys := PhysicalSkyMaterial.new()
		phys.ground_color = e.get("ground", Color(0.1, 0.09, 0.08))
		phys.turbidity = e.get("turbidity", 6.0)
		phys.mie_color = e.get("sky_horizon", Color(0.63, 0.77, 1.0))
		phys.energy_multiplier = e.get("sky_energy", 1.0)
		phys.use_debanding = true
		sky.sky_material = phys
	elif e.get("stars", false):
		# Stylized night "heaven": tinted gradient + procedural twinkling
		# starfield + Milky-Way haze + moon (shaders/night_sky.gdshader). Opt-in
		# via env "stars"; reuses sky_top/sky_horizon/ground so each open-sky
		# level keeps its colour identity. Star/moon look is tunable per def.
		var night := ShaderMaterial.new()
		night.shader = NIGHT_SKY_SHADER
		night.set_shader_parameter("zenith_color", e.get("sky_top", Color(0.015, 0.02, 0.06)))
		night.set_shader_parameter("horizon_color", e.get("sky_horizon", Color(0.1, 0.08, 0.16)))
		night.set_shader_parameter("ground_color", e.get("ground", Color(0.01, 0.01, 0.02)))
		night.set_shader_parameter("star_density", e.get("star_density", 0.08))
		night.set_shader_parameter("star_brightness", e.get("star_brightness", 2.0))
		night.set_shader_parameter("star_tint", e.get("star_tint", Color(0.85, 0.92, 1.0)))
		night.set_shader_parameter("milkyway_strength", e.get("milkyway", 0.35))
		night.set_shader_parameter("milkyway_tint", e.get("milkyway_tint", Color(0.5, 0.55, 0.85)))
		if e.has("moon_dir"):
			night.set_shader_parameter("moon_dir", e["moon_dir"])
		night.set_shader_parameter("moon_color", e.get("moon_color", Color(0.85, 0.9, 1.0)))
		night.set_shader_parameter("moon_size", e.get("moon_size", 0.05))
		night.set_shader_parameter("moon_glow", e.get("moon_glow", 1.4))
		sky.sky_material = night
	else:
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = e.get("sky_top", Color(0.1, 0.12, 0.18))
		psm.sky_horizon_color = e.get("sky_horizon", Color(0.3, 0.3, 0.34))
		psm.ground_horizon_color = e.get("sky_horizon", Color(0.3, 0.3, 0.34))
		psm.ground_bottom_color = e.get("ground", Color(0.05, 0.05, 0.07))
		psm.sky_curve = 0.16
		# Dimmer dome: a bright sky over a dark ground reads wrong.
		psm.sky_energy_multiplier = e.get("sky_energy", 1.0) * 0.7
		psm.ground_energy_multiplier = 0.45
		psm.sun_angle_max = 12.0   # crisp sun disc
		psm.sun_curve = 0.06       # tight falloff -> a glowing sun, not a smear
		psm.use_debanding = true
		sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_128 # sharper image-based reflections
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = e.get("ambient", Color(0.6, 0.65, 0.75))
	env.ambient_light_sky_contribution = e.get("sky_contribution", 0.5)
	# Darker baseline than the defs ask for so light sources — fixtures, muzzle
	# flashes, bolts, explosions, pickup glows — each carve their own pool out of
	# the dark. But the interior crush (×0.38) was too aggressive: walls, floors and
	# cover read as murky near-black with only emissives visible ("dark / unclear"),
	# so it's lifted to ×0.55 — surfaces are now legibly lit while the scene keeps
	# its moody, fixture-lit character. Open-sky levels keep more of their ambient.
	env.ambient_light_energy = e.get("ambient_energy", 0.4) \
			* (0.7 if def.get("open_sky", false) else 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.8
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.4
	env.ssao_power = 1.8
	env.ssao_detail = 1.0
	env.ssil_enabled = true
	env.ssil_intensity = 1.2
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = e.get("glow", 0.55)
	env.glow_strength = e.get("glow_strength", 0.7)
	# Bloom bleed: levels can crank this for a hazy neon-noir look where bright
	# signs/lights smear into a fuzzy glow. Default 0 keeps a CRISP halo — the old
	# 0.05 bleed was part of why interiors read soft/unfocused (bright strips smeared
	# into the dark instead of staying sharp).
	env.glow_bloom = e.get("glow_bloom", 0.0)
	# Raised so only genuinely bright emissives bloom, not every mid-lit surface —
	# tightens the glow and stops the whole interior hazing over.
	env.glow_hdr_threshold = e.get("glow_threshold", 1.6)
	env.glow_hdr_scale = 1.0
	# Narrow the wide glow kernel: the broad upper levels spread a big soft halo that
	# smeared light strips and hazed the whole room. Bias the bloom to the tighter
	# levels so lights read as sharp lights, not a fog of light.
	env.set("glow_levels/2", 0.9)
	env.set("glow_levels/3", 0.7)
	env.set("glow_levels/4", 0.12)

	env.fog_enabled = true
	env.fog_light_color = e.get("fog", Color(0.45, 0.5, 0.55))
	env.fog_density = e.get("fog_density", 0.01)
	# Aerial perspective tints distant surfaces toward the fog colour for depth;
	# open-sky levels can crank it (e.g. a hazy sun-baked desert) via "fog_aerial".
	env.fog_aerial_perspective = e.get("fog_aerial", 0.12)
	env.fog_sky_affect = 0.3
	# Interiors: pull the distance fog WAY back so enclosed walls keep their own
	# dark color instead of washing into a bright themed band. The earlier
	# darken(0.5) alone wasn't enough — the real culprit is aerial perspective
	# tinting far surfaces toward the fog/sky colour, so the back of a room lifts
	# into a flat grey haze band. Darker + thinner + almost no aerial-perspective
	# = the far side reads as shadow, not fog. Open-sky levels keep their bright
	# atmospheric haze so the sky/horizon still reads with depth.
	if not def.get("open_sky", false):
		env.fog_light_color = env.fog_light_color.darkened(0.62)
		env.fog_density = e.get("fog_density", 0.01) * 0.6
		env.fog_aerial_perspective = 0.04

	# Volumetric fog is for interior atmosphere / god-rays. Outdoors it floods
	# the open space with sun in-scatter (a milky veil), so exteriors use only
	# the cheap distance fog above.
	if not def.get("open_sky", false):
		env.volumetric_fog_enabled = true
		# Thinned: the interior veil was picking up the bright emissive grid/neon via
		# GI and blooming into a soft milky haze that read as "blurry". Halve the
		# density and cut the GI inject so far surfaces stay sharp — the fog is now a
		# faint atmosphere for god-rays, not a screen-wide fog of light.
		env.volumetric_fog_density = minf(e.get("fog_density", 0.01), 0.012) * 0.28
		# Showcase levels can thicken the haze so light shafts/god-rays read.
		if e.has("volumetric_density"):
			env.volumetric_fog_density = e["volumetric_density"]
		# A darker, less milky veil: the near-white albedo washed enclosed arenas
		# into a flat bright haze. This keeps god-rays/shafts readable but lets the
		# space hold shadow and depth.
		env.volumetric_fog_albedo = Color(0.32, 0.35, 0.4)
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_gi_inject = 0.08
	else:
		env.volumetric_fog_enabled = false

	# Filmic grade: teal shadows / warm highlights, lifted contrast + richer colour.
	# The AGX tonemapper above is gorgeous but notoriously desaturating, so the
	# grade pushes saturation back up and adds a real split-tone (cool shadows,
	# warm highlights) via a colour-correction ramp — the "teal/warm" look this
	# comment used to only promise. Levels override per-theme (def "env":
	# brightness/contrast/saturation, or "split_tone": false to opt out).
	env.adjustment_enabled = true
	env.adjustment_brightness = e.get("brightness", 0.84)
	env.adjustment_contrast = e.get("contrast", 1.15)
	env.adjustment_saturation = e.get("saturation", 1.14)
	if e.get("split_tone", true):
		env.adjustment_color_correction = _split_tone_lut()
	
	# Scalability: the chosen quality tier strips back the most expensive
	# screen-space effects so lower-end machines stay smooth. HIGH keeps it all.
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("apply_to_environment"):
		gs.apply_to_environment(env, def.get("open_sky", false))

	_env = env
	we.environment = env
	# Live re-tiering (GraphicsSettings._apply_to_live_environment) needs to
	# know the volumetric-fog rule for this level.
	we.set_meta("open_sky", def.get("open_sky", false))
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = e.get("sun_rot", Vector3(-50, -40, 0))
	sun.light_color = e.get("sun_color", Color(1, 0.95, 0.9))
	# Interiors: weak key — the placed lamps carry the scene. Open sky: the sun
	# IS the scene's key light; halving it too crushed outdoor ground to black.
	sun.light_energy = e.get("sun_energy", 1.0) \
			* (0.85 if def.get("open_sky", false) else 0.5)
	sun.light_angular_distance = 1.2 # sun disc size -> soft penumbra shadows
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	# Outdoors the sky refills shadowed ground — full-opacity sun shadows read
	# as black holes at street level (interiors keep theirs pitch dark).
	if def.get("open_sky", false):
		sun.shadow_opacity = 0.8
	# Cascade budget per tier: every PSSM split re-renders the scene into the
	# shadow map, so LOW draws one cascade to 60 m instead of four to 120 m —
	# arenas are ~64 m, and fewer/shorter cascades also mean denser texels.
	var sun_tier := 2
	if gs and gs.has_method("tier"):
		sun_tier = gs.tier()
	sun.directional_shadow_mode = [
		DirectionalLight3D.SHADOW_ORTHOGONAL,
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
	][sun_tier]
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = [60.0, 90.0, 120.0, 120.0][sun_tier]
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	# Shadowed-light budget per tier: every shadowed omni re-renders the scene
	# up to 6 times, so LOW casts none, MEDIUM the first two, HIGH the first
	# six. Unlimited is ULTRA-only — measured on the expanded arenas (neon:
	# 2656 draws/frame at HIGH), the every-light-shadowed policy was the
	# single biggest draw-call multiplier in the game.
	var shadow_budget := 99
	if gs and gs.has_method("tier"):
		shadow_budget = [0, 2, 6, 99][gs.tier()]
	# 4.7: interior luminaires can emit from a real rectangular AreaLight3D (soft
	# pool + true soft shadows) instead of a point light. Gated to HIGH/ULTRA.
	var use_area: bool = gs and gs.has_method("use_area_lights") and gs.use_area_lights()
	var area_shadows: bool = gs and gs.has_method("area_light_shadows") and gs.area_light_shadows()
	var li := 0
	for l in def.get("lights", []):
		var indoor: bool = not def.get("open_sky", false)
		var shadowed: bool = li < shadow_budget
		var light: Light3D
		if indoor and use_area:
			light = _make_interior_area_light(l, shadowed and area_shadows)
		else:
			var omni := OmniLight3D.new()
			omni.position = l["pos"]
			omni.light_color = l.get("color", Color(1, 1, 1))
			# Slightly hotter than authored: with the ambient cut, these are the
			# scene's primary illumination and their pools must read.
			omni.light_energy = l.get("energy", 2.0) * 1.2
			omni.omni_range = l.get("range", 16.0)
			omni.shadow_enabled = shadowed
			omni.shadow_bias = 0.03
			omni.shadow_blur = 1.5
			omni.light_specular = 0.6
			# In the expanded arenas most luminaires are far from the player at
			# any given moment — fade them (and their shadow passes sooner)
			# with distance instead of paying for the whole hall every frame.
			omni.distance_fade_enabled = true
			omni.distance_fade_begin = 48.0
			omni.distance_fade_shadow = 34.0
			omni.distance_fade_length = 14.0
			light = omni
		add_child(light)
		light.add_to_group("level_light") # a "weather" blackout cuts these (WeatherShift)
		# Every light gets a visible SOURCE instead of hanging disembodied:
		# ceiling luminaires indoors, slim floodlight pylons outdoors. An
		# outdoor god-ray authored straight over an objective opts out with
		# "mast": false, or the solid pole would stand inside the target.
		if indoor:
			_add_light_fixture(l["pos"], l.get("color", Color(1, 1, 1)))
		elif l.get("mast", true):
			_add_light_pylon(l["pos"], l.get("color", Color(1, 1, 1)))
		# The last placed light gets a faulty-wiring flicker: occupied
		# infrastructure failing, and motion in otherwise static lighting. Any
		# light can opt in explicitly with "flicker": true.
		if li == def.get("lights", []).size() - 1 or l.get("flicker", false):
			_flicker_light(light)
		li += 1

	# One parallax-boxed reflection probe fitted to the room (interiors only):
	# real local reflections on the floor panels, puddles and robot chrome,
	# where SSR can't see (off-screen / occluded). Captured once, so the only
	# recurring cost is sampling. MEDIUM tier and up.
	if not def.get("open_sky", false):
		var tier := 2
		if gs and gs.has_method("tier"):
			tier = gs.tier()
		if tier >= 1:
			var probe := ReflectionProbe.new()
			var fs2: Vector2 = def.get("floor_size", Vector2(40, 40))
			probe.update_mode = ReflectionProbe.UPDATE_ONCE
			probe.size = Vector3(fs2.x, WALL_HEIGHT + 2.0, fs2.y)
			probe.position = Vector3(0, (WALL_HEIGHT + 2.0) * 0.5 - 0.5, 0)
			probe.box_projection = true
			probe.intensity = 0.8
			probe.max_distance = maxf(fs2.x, fs2.y) * 1.2
			add_child(probe)

	# Atmospheric ambient bed: rain in wet weather, wind outdoors, room tone indoors.
	var amb := "ambience_drone"
	if def.get("open_sky", false):
		amb = "ambience_rain" if str(e.get("weather", "")) == "rain" else "ambience_wind"
	AudioBus.play_ambience(amb, -22.0)
	# Hazard bed layered over the room tone: lava bubbling or water flow, so a
	# hazard level reads by ear the moment you deploy (the loops existed in
	# SoundSynth but nothing ever played them as level atmosphere).
	var hazard_beds: Array = def.get("lava", [])
	if not hazard_beds.is_empty():
		var wet := false
		for hb in hazard_beds:
			if hb is Dictionary and bool((hb as Dictionary).get("water", false)):
				wet = true
				break
		AudioBus.play_ambience_layer("water_loop" if wet else "lava_loop", -24.0)
	# Environmental reverb: tight metallic room indoors, faint/dry outdoors — the
	# same indoor/outdoor signal the ambience bed above already reads.
	AudioBus.set_reverb_environment(not def.get("open_sky", false))
	# Per-theme music track (def can override; otherwise mapped from level_id).
	var music_id: String = def.get("music", LEVEL_MUSIC.get(level_id, "music_techno"))
	AudioBus.play_music(music_id)

# AreaLight3D mapping for an interior ceiling luminaire (Godot 4.7). The
# rectangular emitter sits flush under the ceiling diffuser and radiates
# straight down, giving a soft directional pool and true soft shadows instead
# of a point light's hard radial falloff. SIZE/ENERGY/RANGE are the tuning
# knobs — bump them here if HIGH/ULTRA interiors read too dim or too bright.
const AREA_LIGHT_SIZE := 1.8          # emitter rectangle in m (panel is ~1.0; larger = softer)
const AREA_LIGHT_ENERGY_MULT := 2.5   # vs authored "energy"; calibrated against the old
                                      # OmniLight floor-pool at the 6 m WALL_HEIGHT drop
const AREA_LIGHT_RANGE_MULT := 1.5    # area lights fade with distance — give them reach

func _make_interior_area_light(l: Dictionary, shadowed: bool) -> AreaLight3D:
	var pos: Vector3 = l["pos"]
	var area := AreaLight3D.new()
	area.area_size = Vector2(AREA_LIGHT_SIZE, AREA_LIGHT_SIZE)
	# Raw (non-normalized) energy: normalize_energy divides intensity by emitter
	# area, which at a 6 m ceiling drop read noticeably dimmer than the omnis it
	# replaces. Raw energy matched the old floor-pool brightness in side-by-side.
	area.area_normalize_energy = false
	area.light_color = l.get("color", Color(1, 1, 1))
	area.light_energy = l.get("energy", 2.0) * AREA_LIGHT_ENERGY_MULT
	area.area_range = l.get("range", 16.0) * AREA_LIGHT_RANGE_MULT
	area.light_specular = 0.6
	area.shadow_enabled = shadowed
	area.shadow_bias = 0.04
	area.shadow_blur = 1.5
	# Same far-luminaire fade as the omni path — the expanded halls hold more
	# lights than ever sit near the player at once.
	area.distance_fade_enabled = true
	area.distance_fade_begin = 48.0
	area.distance_fade_shadow = 34.0
	area.distance_fade_length = 14.0
	# Flush under the ceiling diffuser, face pointing straight down (local -Z).
	area.position = Vector3(pos.x, WALL_HEIGHT - 0.2, pos.z)
	area.rotation_degrees = Vector3(-90, 0, 0)
	return area

## A recessed ceiling luminaire: dark housing + emissive diffuser panel in the
## light's own color, mounted on the ceiling directly above the omni position.
func _add_light_fixture(light_pos: Vector3, color: Color) -> void:
	var housing := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(1.2, 0.12, 1.2)
	hb.material = _color_material(Color(0.1, 0.1, 0.12), 0.5)
	housing.mesh = hb
	housing.position = Vector3(light_pos.x, WALL_HEIGHT - 0.06, light_pos.z)
	add_child(housing)
	var panel := MeshInstance3D.new()
	var pb := BoxMesh.new()
	pb.size = Vector3(1.0, 0.04, 1.0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = color
	pm.emission_enabled = true
	pm.emission = color
	pm.emission_energy_multiplier = 2.4
	pb.material = pm
	panel.add_to_group("level_light") # the lit panel goes dark with its light in a blackout
	panel.mesh = pb
	panel.position = Vector3(light_pos.x, WALL_HEIGHT - 0.13, light_pos.z)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)

## A slim floodlight mast under an outdoor light: tapered pole from the ground
## up to the omni, topped with an emissive head in the light's color.
func _add_light_pylon(light_pos: Vector3, color: Color) -> void:
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.12
	cm.height = light_pos.y
	cm.radial_segments = 8
	cm.material = _color_material(Color(0.12, 0.13, 0.16), 0.5)
	pole.mesh = cm
	pole.position = Vector3(light_pos.x, light_pos.y * 0.5, light_pos.z)
	add_child(pole)
	# Solid: built before the navmesh bake, so robots path around the mast.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.14
	shape.height = light_pos.y
	cs.shape = shape
	body.add_child(cs)
	body.position = pole.position
	add_child(body)
	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.55, 0.22, 0.55)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = color
	hm.emission_enabled = true
	hm.emission = color
	hm.emission_energy_multiplier = 2.6
	hb.material = hm
	head.mesh = hb
	head.position = Vector3(light_pos.x, light_pos.y + 0.05, light_pos.z)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)

## Faulty-wiring flicker: mostly steady, with brief random dips and the odd
## near-blackout. A pre-baked randomized loop is cheap and reads as organic.
func _flicker_light(light: Light3D) -> void:
	var base := light.light_energy
	var tw := light.create_tween().set_loops()
	for i in 6:
		var dip := base * randf_range(0.55, 0.85) if randf() < 0.8 else base * 0.15
		tw.tween_property(light, "light_energy", dip, randf_range(0.04, 0.1))
		tw.tween_property(light, "light_energy", base, randf_range(0.06, 0.14))
		tw.tween_interval(randf_range(0.8, 3.2))

# ---------- geometry ----------

func _build_geometry(def: Dictionary) -> void:
	_nav_region = NavigationRegion3D.new()
	var nm := NavigationMesh.new()
	# Cell dims match the navigation map default (0.25) AND the agent properties
	# are exact multiples of them, so the bake emits no precision/mismatch
	# warnings: radius 0.5/0.25=2, height 1.75/0.25=7, max_climb 0.5/0.25=2.
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.5
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	_nav_region.navigation_mesh = nm
	add_child(_nav_region)

	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	# Floor — optionally tinted (e.g. asphalt/grass for outdoor levels).
	var floor_mat: Material = MAT_FLOOR
	var floor_surf := "surf_concrete"
	if def.has("floor_material"):
		# Showcase override: a hand-authored textured material (e.g. the polished
		# vault plate) instead of the shared concrete or a flat tint.
		floor_mat = load(def["floor_material"])
	elif def.get("streets", false):
		# Street levels get textured tarmac (grit + grain) instead of a flat tint,
		# so the road markings/parking/signs below sit on real-looking asphalt.
		floor_mat = _asphalt_material()
		floor_surf = "surf_dirt"
	elif def.has("floor_color"):
		floor_mat = _color_material(def["floor_color"], 0.95)
		floor_surf = "surf_dirt" if def.get("open_sky", false) else "surf_concrete"
	# Rain-slick pass: storm levels get a wet ground sheen via Godot 4.7's
	# reworked clearcoat (energy-conserving + reflection-probe aware) — a thin
	# glossy water film over the rough base so lights/sky streak across the lot.
	if str((def.get("env", {}) as Dictionary).get("weather", "")) == "rain":
		floor_mat = _wet_variant(floor_mat)
	_add_box(Vector3(0, -0.2, 0), Vector3(fs.x, 0.4, fs.y), floor_mat, floor_surf, "", "ArenaFloor")
	# Perimeter walls — weathered concrete outdoors, panels indoors. Normally
	# WALL_HEIGHT, but a climbable tower (def "towers", see _build_tower) can
	# reach well past that — ramp_probe (once its own floor/ceiling mix-up was
	# fixed, see the "level_ceiling" note below) found several INDOOR levels
	# pairing towers with the fixed-height shell had the tower's whole upper
	# half fail headroom against the room's own capped walls/ceiling: a real
	# clip, not a probe artifact, since a capped indoor room is never taller
	# than WALL_HEIGHT while these towers are authored up to 9 m. Raise the
	# shell to clear the tallest tower with the player's own headroom margin;
	# ordinary levels (no towers, or open_sky with no ceiling to clip) are
	# unaffected. Only the STRUCTURAL shell changes here — decorative fixtures
	# keyed to the WALL_HEIGHT constant elsewhere (trim, light housings) stay
	# calibrated to the original height, a purely cosmetic (not gameplay)
	# trade-off already implicit in a low-poly builder level.
	var room_h := WALL_HEIGHT
	for t in def.get("towers", []):
		room_h = maxf(room_h, float((t as Dictionary).get("height", 8.0)) + PLAYER_CLEARANCE_M + 0.3)
	var wall_mat: Material = MAT_WALL_OUT if def.get("open_sky", false) else MAT_WALL
	_add_box(Vector3(0, room_h * 0.5, -hz), Vector3(fs.x, room_h, 1.0), wall_mat, "surf_concrete", "", "ArenaWallN")
	_add_box(Vector3(0, room_h * 0.5, hz), Vector3(fs.x, room_h, 1.0), wall_mat, "surf_concrete", "", "ArenaWallS")
	_add_box(Vector3(-hx, room_h * 0.5, 0), Vector3(1.0, room_h, fs.y), wall_mat, "surf_concrete", "", "ArenaWallW")
	_add_box(Vector3(hx, room_h * 0.5, 0), Vector3(1.0, room_h, fs.y), wall_mat, "surf_concrete", "", "ArenaWallE")
	if not def.get("open_sky", false):
		# Tagged "level_ceiling" (in addition to the usual surf_metal footstep
		# group) so tests/ramp_probe can tell "the room's overhead cap" apart
		# from a walkable surface: it spans the ENTIRE floor footprint, so any
		# tower/ramp whose nominal climb line comes within a few metres of
		# its (now tower-aware) height had the ceiling itself mistaken for
		# "the true walkable surface the player stands on" by the probe's
		# find-the-topmost-surface-in-a-column logic — a false headroom/stuck
		# failure against geometry no one ever stands on.
		# Opt-in "ceiling_color" (mirrors "floor_color"): the shared ceiling_metal
		# is a light panel, and in a heavily-tinted hall it soaks up the ambient
		# and turns the top third of the player's view into one flat, saturated
		# wash. A dark tint pushes it back so the racks, core and signage read as
		# the bright things. Levels that don't set it keep the stock panel.
		var ceil_mat: Material = MAT_CEIL
		if def.has("ceiling_color"):
			ceil_mat = _color_material(def["ceiling_color"], 0.9)
		_add_box(Vector3(0, room_h + 0.2, 0), Vector3(fs.x, 0.4, fs.y), ceil_mat, "surf_metal", "level_ceiling")
	# Interior cover / pillars — alternate two plate materials so adjacent
	# crates/machinery don't read as copies of one box.
	# Compact floor-standing cover with nothing authored on or against it can be
	# shot apart (BreakableCover); the rest stays solid. The flag on the def entry
	# tells _build_cover_trim to leave it alone, since the block dresses itself.
	var cover_i := 0
	for w in def.get("walls", []):
		var wmat: Material = MAT_PROP if cover_i % 2 == 0 else MAT_PROP_B
		if BreakableCover.qualifies(w, def):
			w["_breakable"] = true
			var bc := BreakableCover.new()
			bc.name = "BreakableCover"
			bc.position = w["pos"]
			bc.setup(w["size"], _beveled_box(w["size"]), wmat, _theme_color(def))
			_nav_region.add_child(bc)
		else:
			_add_box(w["pos"], w["size"], wmat, "surf_metal", "", "DefWall")
		cover_i += 1

# ---------- wall detailing ----------

## Breaks up the big unbroken perimeter planes that make blockouts read as
## "programmer art": skirting + cornice trim where walls meet floor/ceiling,
## vertical rib columns every few metres, thin panel-seam strips at panel
## heights, ceiling pipe runs indoors, and a physical fixture under every
## point light so the light has a visible source. All visual-only (no
## colliders), so the navmesh and gameplay are untouched. Density follows the
## graphics tier, like the dust motes.
func _build_wall_details(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var open_sky: bool = def.get("open_sky", false)
	# Inner faces of the four 1m-thick perimeter walls. "dir yaw" rotates trim
	# strips so their length runs along the wall.
	var walls := [
		{"c": Vector3(0, 0, -hz + 0.5), "n": Vector3(0, 0, 1), "len": fs.x, "yaw": 0.0},
		{"c": Vector3(0, 0, hz - 0.5), "n": Vector3(0, 0, -1), "len": fs.x, "yaw": 0.0},
		{"c": Vector3(-hx + 0.5, 0, 0), "n": Vector3(1, 0, 0), "len": fs.y, "yaw": PI * 0.5},
		{"c": Vector3(hx - 0.5, 0, 0), "n": Vector3(-1, 0, 0), "len": fs.y, "yaw": PI * 0.5},
	]
	for w in walls:
		var c: Vector3 = w["c"]
		var n: Vector3 = w["n"]
		var length: float = w["len"]
		var yaw: float = w["yaw"]
		# Skirting where the wall meets the floor.
		var skirt := _beveled_box(Vector3(length - 1.2, 0.22, 0.12))
		skirt.material = MAT_TRIM
		_add_detail_mesh(skirt, c + n * 0.06 + Vector3(0, 0.11, 0), yaw)
		# Cornice where it meets the ceiling (interiors only).
		if not open_sky:
			var cornice := _beveled_box(Vector3(length - 1.2, 0.18, 0.12))
			cornice.material = MAT_TRIM
			_add_detail_mesh(cornice, c + n * 0.06 + Vector3(0, WALL_HEIGHT - 0.09, 0), yaw)
		# Thin panel-seam strips at panel heights.
		for seam_y in [2.2, 4.1]:
			var seam := BoxMesh.new()
			seam.size = Vector3(length - 1.2, 0.07, 0.05)
			seam.material = MAT_SEAM
			_add_detail_mesh(seam, c + n * 0.025 + Vector3(0, seam_y, 0), yaw)
		# Vertical rib columns; spacing widens on lower detail tiers.
		var step := 4.0 / maxf(density, 0.34)
		var rib_x := -length * 0.5 + 3.0
		while rib_x <= length * 0.5 - 3.0:
			var rib := _beveled_box(Vector3(0.28, WALL_HEIGHT, 0.2))
			rib.material = MAT_TRIM
			var along := Vector3(rib_x, 0, 0).rotated(Vector3.UP, yaw)
			_add_detail_mesh(rib, c + along + n * 0.1 + Vector3(0, WALL_HEIGHT * 0.5, 0), yaw)
			rib_x += step
	# Ceiling pipe runs (interiors): two parallel lines plus one return line.
	if not open_sky:
		for pz in [-hz + 1.4, -hz + 1.85, hz - 1.6]:
			var pipe := CylinderMesh.new()
			pipe.top_radius = 0.1
			pipe.bottom_radius = 0.1
			pipe.height = fs.x - 3.0
			pipe.radial_segments = 10
			pipe.material = MAT_PROP
			var mi := MeshInstance3D.new()
			mi.mesh = pipe
			mi.rotation.z = PI * 0.5 # lie the cylinder along X
			mi.position = Vector3(0, WALL_HEIGHT - 0.4, pz)
			add_child(mi)
	# A housing + glowing diffuser plate under every point light, so light has
	# a visible source instead of appearing from thin air.
	for l in def.get("lights", []):
		var pos: Vector3 = l["pos"]
		var col: Color = l.get("color", Color(1, 1, 1))
		var housing := _beveled_box(Vector3(0.5, 0.09, 0.5))
		housing.material = MAT_TRIM
		_add_detail_mesh(housing, pos + Vector3(0, 0.17, 0), 0.0)
		var plate := BoxMesh.new()
		plate.size = Vector3(0.4, 0.03, 0.4)
		var em := StandardMaterial3D.new()
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.albedo_color = col
		em.emission_enabled = true
		em.emission = col
		em.emission_energy_multiplier = 3.0
		plate.material = em
		_add_detail_mesh(plate, pos + Vector3(0, 0.115, 0), 0.0)

func _add_detail_mesh(mesh: Mesh, pos: Vector3, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = yaw
	# Wall-hugging trim: its shadows are invisible but still cost a draw into
	# every shadowed light's map.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ---------- global illumination ----------

func _build_gi(def: Dictionary) -> void:
	# Reflection probe (+ the open-sky SDFGI tuning below) is High-quality
	# only. Balanced/Low skip it entirely.
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs == null or not gs.has_method("is_high") or not gs.is_high():
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var open_sky: bool = def.get("open_sky", false)
	if open_sky:
		# Open levels rely on sky ambient + sun. SDFGI is intentionally OFF here:
		# on these large flat-walled blockouts its low-frequency cascades produce
		# blotchy color-bleed smears across the walls. Sky ambient looks cleaner.
		if _env:
			_env.sdfgi_enabled = false
	elif gs.tier() >= GraphicsSettings.Quality.ULTRA:
		# Indoor levels: a baked VoxelGI covering the play space. ULTRA-only —
		# measured ~13 ms at 4K on a mid GPU (tools/perf_diag) for a subtle
		# bounce contribution in interiors that are already mostly emissive-lit;
		# HIGH drops it for the frame time, ULTRA is the no-compromises tier
		# that can still afford it.
		var vgi := VoxelGI.new()
		vgi.size = Vector3(fs.x + 4.0, 8.0, fs.y + 4.0)
		vgi.position = Vector3(0, 4, 0)
		add_child(vgi)
		# The bake carries the luminaires' bounce: a blackout must cut it with them.
		vgi.add_to_group("level_light")
		# The headless/dummy renderer cannot bake; only bake in the real game.
		if DisplayServer.get_name() != "headless":
			vgi.bake.call_deferred()

	# Reflection probe: grounded, off-screen reflections on metal robots/floors
	# that SSR (screen-space only) can't provide. Box-projected to the arena.
	# Stays at HIGH+ regardless of VoxelGI — UPDATE_ONCE is cheap and carries
	# the metallic look on its own.
	var rp := ReflectionProbe.new()
	rp.size = Vector3(fs.x + 2.0, 14.0, fs.y + 2.0)
	rp.position = Vector3(0, 5.0, 0)
	rp.box_projection = true
	rp.interior = not open_sky
	rp.max_distance = 0.0
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(rp)

func _add_box(center: Vector3, size: Vector3, mat: Material, surface: String = "surf_concrete", extra_group: String = "", debug_name: String = "") -> void:
	var body := StaticBody3D.new()
	if debug_name != "":
		body.name = debug_name   # readable in ramp_probe "hit <name>" output
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	if surface != "":
		body.add_to_group(surface)
	if extra_group != "":
		body.add_to_group(extra_group)
	var mi := MeshInstance3D.new()
	mi.mesh = _beveled_box(size)
	mi.mesh.material = mat
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	_nav_region.add_child(body)

## Every visible builder box gets a small chamfer — edge highlights are what
## separate "machined" geometry from raw extruded blocks. Collision shapes stay
## exact boxes, so gameplay and navmesh baking are untouched.
func _beveled_box(size: Vector3) -> BeveledBoxMesh:
	var bm := BeveledBoxMesh.new()
	bm.size = size
	var min_d := minf(size.x, minf(size.y, size.z))
	bm.bevel = clampf(min_d * 0.06, 0.01, 0.08)
	return bm

static var _color_mat_cache: Dictionary = {}

## A simple opaque PBR material from a colour — used for tinted floors and the
## suburban house bodies (so outdoor levels don't read as grey metal boxes).
## Cached by (color, roughness): callers ask for the same handful of colours
## across dozens of individual props/platforms/walls per level, and a fresh
## StandardMaterial3D per call gives every one of those objects a distinct
## material resource — which stops Godot's renderer from batching them,
## turning cheap identical props into their own separate draw call each.
func _color_material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var key := "%s|%.3f" % [color, roughness]
	if _color_mat_cache.has(key):
		return _color_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
	_color_mat_cache[key] = m
	return m

## Wet-weather copy of a ground material: a thin water film as a glossy
## clearcoat lacquer over the unchanged rough base (4.7 clearcoat is energy-
## conserving, so the sheen doesn't blow out the albedo). The shared source
## material is never mutated.
func _wet_variant(mat: Material) -> Material:
	var sm := mat as StandardMaterial3D
	if sm == null:
		return mat
	var wet := sm.duplicate() as StandardMaterial3D
	wet.clearcoat_enabled = true
	wet.clearcoat = 0.85
	wet.clearcoat_roughness = 0.14
	wet.roughness = minf(wet.roughness, 0.62) # damp base under the film
	wet.metallic_specular = 0.7 # stronger dielectric reflection off the water film
	return wet

static var _asphalt_mat: StandardMaterial3D = null

## Procedural tarmac for street levels: dark, rough, with a noisy albedo speckle
## (aggregate grit) and a fine normal grain, triplanar-mapped so it tiles across
## any floor size. Built once and shared.
func _asphalt_material() -> StandardMaterial3D:
	if _asphalt_mat != null:
		return _asphalt_mat
	var grit := FastNoiseLite.new()
	grit.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grit.frequency = 0.9
	var alb := NoiseTexture2D.new()
	alb.width = 256
	alb.height = 256
	alb.seamless = true
	alb.noise = grit
	var grain := FastNoiseLite.new()
	grain.noise_type = FastNoiseLite.TYPE_SIMPLEX
	grain.frequency = 1.8
	var nrm := NoiseTexture2D.new()
	nrm.width = 256
	nrm.height = 256
	nrm.seamless = true
	nrm.as_normal_map = true
	nrm.bump_strength = 0.7
	nrm.noise = grain
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.11)
	m.albedo_texture = alb            # dark base × grey speckle reads as aggregate
	m.roughness = 0.94
	m.metallic = 0.0
	m.normal_enabled = true
	m.normal_scale = 0.8
	m.normal_texture = nrm
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.12, 0.12, 0.12)
	_asphalt_mat = m
	return m

## Real suburban houses (Kenney City Kit Suburban, CC0): one model per def
## entry, cycled for variety, scaled to the def's footprint and rotated to
## face the street (the level origin). Gameplay is untouched — the def's box
## is still the collider and navmesh obstacle (the bake parses STATIC
## COLLIDERS, so the invisible shape is all that matters for pathing).
const HOUSE_SCENES: Array = [
	preload("res://assets/models/suburb/building-type-a.glb"),
	preload("res://assets/models/suburb/building-type-b.glb"),
	preload("res://assets/models/suburb/building-type-c.glb"),
	preload("res://assets/models/suburb/building-type-d.glb"),
	preload("res://assets/models/suburb/building-type-e.glb"),
	preload("res://assets/models/suburb/building-type-f.glb"),
	preload("res://assets/models/suburb/building-type-g.glb"),
	preload("res://assets/models/suburb/building-type-h.glb"),
]

func _build_buildings(def: Dictionary) -> void:
	var entries: Array = def.get("buildings", [])
	for i in entries.size():
		var b: Dictionary = entries[i]
		# `"open": true` buildings are ENTERABLE multi-storey shells (door,
		# interior ramp, upper floor, roof) instead of decorative solid boxes.
		if b.get("open", false):
			_build_open_building(b, def)
			continue
		var size: Vector3 = b["size"]
		var pos: Vector3 = b["pos"]
		# Collider + navmesh obstacle: exactly the box the def describes.
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = pos
		body.add_to_group("surf_concrete")
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		_nav_region.add_child(body)
		# Visible house, fitted to the footprint and grounded.
		var house := (HOUSE_SCENES[i % HOUSE_SCENES.size()] as PackedScene).instantiate() as Node3D
		add_child(house)
		var ab := _merged_aabb(house)
		var s := minf(size.x / maxf(ab.size.x, 0.1), size.z / maxf(ab.size.z, 0.1))
		house.scale = Vector3.ONE * s
		var ground_y := pos.y - size.y * 0.5
		house.position = Vector3(pos.x - ab.get_center().x * s, ground_y - ab.position.y * s, pos.z - ab.get_center().z * s)
		# Turn the front door toward the street (Kenney fronts face +Z).
		if absf(pos.z) >= absf(pos.x):
			house.rotation.y = 0.0 if pos.z < 0.0 else PI
		else:
			house.rotation.y = PI * 0.5 if pos.x < 0.0 else -PI * 0.5
		# Optional war-torn tint: multiply the (cheerful suburban) house albedo
		# toward grim concrete so a ruined-city level doesn't read as suburbia.
		if def.has("building_tint"):
			_tint_meshes(house, def["building_tint"])

## An ENTERABLE two-storey building shell: four walls with a doorway facing the
## level centre, an upper floor slab with a stairwell opening, an interior ramp
## up to it, and a flat roof. Everything is solid + under the navmesh region,
## so the player AND enemies path inside and fight over both floors.
func _build_open_building(b: Dictionary, def: Dictionary) -> void:
	var size: Vector3 = b["size"]
	var pos: Vector3 = b["pos"]
	var ground := pos.y - size.y * 0.5
	var w := size.x
	var d := size.z
	var h := size.y
	var t := 0.35             # wall thickness
	var floor_h := h * 0.5    # upper slab height
	# The interior ramp's horizontal run is aligned entirely under the slab's
	# stairwell opening (see the ramp calls below — their z-span matches the
	# hole's), so nothing overhangs it before the upper floor; the binding
	# headroom check is just "is each storey tall enough" for a player plus the
	# ramp's own top embed. Enforce it here rather than trusting `h` per level.
	assert(floor_h >= PLAYER_CLEARANCE_M + RAMP_TOP_EMBED + 0.3,
		"open building storey too short for ramp headroom: floor_h=%.2f m" % floor_h)
	var door_w := 2.6
	var door_h := 3.0
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.42, 0.42, 0.46)
	if def.has("building_tint"):
		wall_mat.albedo_color *= def["building_tint"]
	wall_mat.roughness = 0.9

	var mk := func(center: Vector3, s: Vector3) -> void:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = center
		body.add_to_group("surf_concrete")
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s
		bm.material = wall_mat
		mi.mesh = bm
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = s
		cs.shape = sh
		body.add_child(mi)
		body.add_child(cs)
		_nav_region.add_child(body)

	# Door on the face pointing toward the level centre (the street).
	var door_on_x := absf(pos.x) > absf(pos.z)
	var front_sign := -signf(pos.x) if door_on_x else -signf(pos.z)
	var cy := ground + h * 0.5
	# Front wall: two jambs + a lintel over the doorway; the other three solid.
	if door_on_x:
		var fx := pos.x + front_sign * (w * 0.5 - t * 0.5)
		var jamb_d := (d - door_w) * 0.5
		mk.call(Vector3(fx, cy, pos.z - (door_w + jamb_d) * 0.5), Vector3(t, h, jamb_d))
		mk.call(Vector3(fx, cy, pos.z + (door_w + jamb_d) * 0.5), Vector3(t, h, jamb_d))
		mk.call(Vector3(fx, ground + door_h + (h - door_h) * 0.5, pos.z), Vector3(t, h - door_h, door_w))
		mk.call(Vector3(pos.x - front_sign * (w * 0.5 - t * 0.5), cy, pos.z), Vector3(t, h, d))
		mk.call(Vector3(pos.x, cy, pos.z - d * 0.5 + t * 0.5), Vector3(w - t * 2.0, h, t))
		mk.call(Vector3(pos.x, cy, pos.z + d * 0.5 - t * 0.5), Vector3(w - t * 2.0, h, t))
	else:
		var fz := pos.z + front_sign * (d * 0.5 - t * 0.5)
		var jamb_w := (w - door_w) * 0.5
		mk.call(Vector3(pos.x - (door_w + jamb_w) * 0.5, cy, fz), Vector3(jamb_w, h, t))
		mk.call(Vector3(pos.x + (door_w + jamb_w) * 0.5, cy, fz), Vector3(jamb_w, h, t))
		mk.call(Vector3(pos.x, ground + door_h + (h - door_h) * 0.5, fz), Vector3(door_w, h - door_h, t))
		mk.call(Vector3(pos.x, cy, pos.z - front_sign * (d * 0.5 - t * 0.5)), Vector3(w, h, t))
		mk.call(Vector3(pos.x - w * 0.5 + t * 0.5, cy, pos.z), Vector3(t, h, d - t * 2.0))
		mk.call(Vector3(pos.x + w * 0.5 - t * 0.5, cy, pos.z), Vector3(t, h, d - t * 2.0))

	# Upper floor: a slab with a stairwell opening along the back edge, plus an
	# interior ramp running up the back wall into the opening.
	var hole := 3.2
	var slab_y := ground + floor_h
	var back_sign := -front_sign
	if door_on_x:
		var main_w := w - t * 2.0
		mk.call(Vector3(pos.x - back_sign * hole * 0.5, slab_y, pos.z), Vector3(main_w - hole, 0.3, d - t * 2.0))
		mk.call(Vector3(pos.x + back_sign * (main_w - hole) * 0.5, slab_y, pos.z + hole * 0.5), Vector3(hole, 0.3, d - t * 2.0 - hole))
		_add_ramp_between(
			Vector3(pos.x + back_sign * (w * 0.5 - t - 1.2), ground, pos.z + d * 0.5 - t - hole * 0.5),
			Vector3(pos.x + back_sign * (w * 0.5 - t - 1.2), slab_y + 0.15, pos.z - d * 0.5 + t + hole * 0.5), 2.4, 0.3)
	else:
		var main_d := d - t * 2.0
		mk.call(Vector3(pos.x, slab_y, pos.z - back_sign * hole * 0.5), Vector3(w - t * 2.0, 0.3, main_d - hole))
		mk.call(Vector3(pos.x + hole * 0.5, slab_y, pos.z + back_sign * (main_d - hole) * 0.5), Vector3(w - t * 2.0 - hole, 0.3, hole))
		_add_ramp_between(
			Vector3(pos.x + w * 0.5 - t - hole * 0.5, ground, pos.z + back_sign * (d * 0.5 - t - 1.2)),
			Vector3(pos.x - w * 0.5 + t + hole * 0.5, slab_y + 0.15, pos.z + back_sign * (d * 0.5 - t - 1.2)), 2.4, 0.3)

	# Flat roof caps the shell (grapple up to it from outside).
	mk.call(Vector3(pos.x, ground + h - 0.15, pos.z), Vector3(w, 0.3, d))
	# A warm interior light per floor so the inside isn't a black box.
	for fy in [ground + 2.6, ground + floor_h + 2.6]:
		var li := OmniLight3D.new()
		li.light_color = Color(1.0, 0.85, 0.6)
		li.light_energy = 1.4
		li.omni_range = maxf(w, d) * 0.8
		add_child(li)
		li.position = Vector3(pos.x, fy, pos.z)

## Multiply every mesh-surface albedo of `root` by `tint` (duplicating materials
## so the shared source resources are untouched). Used to grime-down buildings.
func _tint_meshes(root: Node3D, tint: Color) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src is BaseMaterial3D:
				var dup := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				dup.albedo_color = dup.albedo_color * tint
				dup.roughness = minf(1.0, dup.roughness + 0.2)
				m.set_surface_override_material(si, dup)

## Merged local AABB of a scene's meshes (models have varied pivots).
func _merged_aabb(root: Node3D) -> AABB:
	var merged := AABB(Vector3.ZERO, Vector3(1, 1, 1))
	var first := true
	var inv := root.global_transform.affine_inverse()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var ab: AABB = (inv * m.global_transform) * m.mesh.get_aabb()
			merged = ab if first else merged.merge(ab)
			first = false
	return merged

# ---------- verticality: ramps & rooftop platforms ----------
# These are player-reachable surfaces. They're added under the builder root (NOT
# the navmesh region) so the ground navmesh ignores them — enemies stay on the
# street while the player can climb for a vantage on the big foe.
#
# ROOT-CAUSE NOTE (ramp lip bug): the old implementation built a ramp as a
# TILTED BOX (BoxShape3D) whose `center` was the point given by callers, but
# the walkable surface is the box's TOP face, which sits +size.y/2 away from
# that center along the box's local up (rotated by pitch) — not at `center`
# itself. _add_ramp_between "solved" pitch/length from two SURFACE endpoints
# (from=ground, to=landing) and then fed their MIDPOINT straight in as the box
# center, so the actual top face ended up offset from the intended line by
# roughly (thickness/2)*cos(pitch) vertically. The 0.45 m slope overshoot was
# meant to bury the ends, but it overshoots ALONG THE SLOPE, so at the top it
# pushes the surface even HIGHER above the landing (a poke-up ridge right where
# the player finishes climbing) while at the foot the (thickness/2)*cos(pitch)
# term partially cancels the burial, leaving a residual few-centimetre step —
# both are exactly the kind of lip CharacterBody3D can't climb (Godot 4 has no
# step-up). Fix: stop deriving the walkable face from a rotated box at all.
# _build_ramp_wedge below authors the TOP FACE directly through the true
# ground/landing points (a straight line, by construction, no offset to get
# wrong), with the foot sunk RAMP_FOOT_SINK below ground (guaranteed overlap,
# never floating) and the top continuing flush at landing height for
# RAMP_TOP_EMBED metres (buries into the landing instead of poking above it).
const RAMP_FOOT_SINK := 0.05   # foot sits this far below the true ground point
const RAMP_TOP_EMBED := 0.4    # flat run-out past the true top point, into the landing
const PLAYER_CLEARANCE_M := 2.2   # player capsule (1.8 m, see player.tscn) + margin

func _build_ramps(def: Dictionary) -> void:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	for r in def.get("ramps", []):
		_add_ramp(r["pos"], r["size"], r.get("pitch", 24.0), r.get("yaw", 0.0), fs)

## Author-facing ramp: a center/size/pitch/yaw box, as placed by def "ramps"
## entries. Recovers the true walking-surface endpoints (the box's TOP face at
## each end, not its centerline — see the root-cause note above) and builds
## the actual geometry via the shared wedge (no more box-center-vs-surface
## drift).
func _add_ramp(center: Vector3, size: Vector3, pitch_deg: float, yaw_deg: float, floor_size: Vector2 = Vector2(1e6, 1e6)) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	var half_len := size.z * 0.5
	var half_thick := size.y * 0.5
	# +Z is the low end under a positive pitch (matches _add_ramp_between's
	# convention below); offset by +thickness/2 along local up to land on the
	# TOP face, not the centerline.
	var foot := center + b * Vector3(0, half_thick, half_len)
	var top := center + b * Vector3(0, half_thick, -half_len)
	if foot.y > top.y:
		var tmp := foot
		foot = top
		top = tmp
	# Several def ramps are authored with the foot a little ABOVE the floor
	# (e.g. the shared vantage-deck ramp's foot sits at y=0.23), leaving the
	# wedge's knife edge hovering (RAMP_FOOT_SINK only sinks it 0.05) — an
	# 18 cm mid-air toe ramp_probe flagged at t=0 on every level reusing the
	# def. Extend the walking line along its own slope until it meets the
	# ground plane: the surface plane is unchanged, the ramp just reaches the
	# floor. Elevated ramps (foot on a deck/platform) are left alone.
	# Stop just ABOVE the floor plane (0.05, inside step-assist noise), cap the
	# reach at 0.6 m, and skip the extension entirely when the extended toe
	# would land within 1.2 m of the arena perimeter: one level's vantage ramp
	# is authored with its foot already brushing the boundary wall, and any
	# extension buried the toe inside the wall (ramp_probe flagged the buried
	# tip, not the ramp). A hover next to a wall stays as authored.
	if foot.y > 0.07 and foot.y < 0.6:
		var line := foot - top
		var horiz_run := Vector2(line.x, line.z).length()
		if line.y < -0.05 and horiz_run > 0.1:
			var t := (foot.y - 0.05) / -line.y
			t = minf(t, 0.6 / horiz_run)
			var ext := foot + line * t
			if absf(ext.x) < floor_size.x * 0.5 - 1.2 and absf(ext.z) < floor_size.y * 0.5 - 1.2:
				foot = ext
	# The opposite authoring slip also exists: several (scaled) levels reuse a
	# vantage-deck def whose ramp FOOT sits nearly flush against the arena's
	# boundary wall — the walking line starts EMBEDDED in the wall (ramp_probe:
	# STUCK at t~0 hitting ArenaWall*). A player can still mount the ramp from
	# the side, but the bottom half-metre is dead space pinned to a wall. Pull
	# the line's start up the slope until a player capsule clears the wall's
	# inner face (wall half-thickness 0.5 + capsule 0.35 + margin).
	var inner_x := floor_size.x * 0.5 - 1.0
	var inner_z := floor_size.y * 0.5 - 1.0
	var dirv := top - foot
	var t_clear := 0.0
	if absf(foot.x) > inner_x and absf(dirv.x) > 0.01 and signf(dirv.x) != signf(foot.x):
		t_clear = maxf(t_clear, (absf(foot.x) - inner_x) / absf(dirv.x))
	if absf(foot.z) > inner_z and absf(dirv.z) > 0.01 and signf(dirv.z) != signf(foot.z):
		t_clear = maxf(t_clear, (absf(foot.z) - inner_z) / absf(dirv.z))
	if t_clear > 0.0 and t_clear < 0.5:
		foot += dirv * t_clear
	_build_ramp_wedge(foot, top, size.x, size.y, "DefRamp")

## Connect two points with a ramp the player can walk straight up — `from` (low)
## to `to` (high). Length and pitch are solved so the surface lands exactly on
## both ends, so rooftop access and multi-tier routes can be authored as plain
## endpoints (def "stairs": [{from, to, width?}]) without hand-solving transforms.
func _add_ramp_between(from: Vector3, to: Vector3, width: float = 3.5, thickness: float = 0.5, debug_name: String = "") -> void:
	_build_ramp_wedge(from, to, width, thickness, debug_name)

## Shared ramp geometry. Builds the COLLISION as a wedge (ConvexPolygonShape3D)
## whose top face runs exactly through `from` (foot, ground level) and `to`
## (top, landing level) — a straight line by construction, so there is no lip
## to derive or get wrong. The foot is a knife edge (zero thickness) sunk
## RAMP_FOOT_SINK below `from`; the top keeps full thickness and runs flush for
## RAMP_TOP_EMBED metres past `to` to bury into the landing. The VISUAL mesh
## doesn't need to match the collision 1:1 (per the task: a plain beveled box
## is fine as long as it's sunk so no gap shows) — reusing the old rotated-box
## mesh, sunk half a thickness plus a small margin, is simpler and safer than
## hand-rolling a new mesh's triangle winding.
func _build_ramp_wedge(from: Vector3, to: Vector3, width: float, thickness: float, debug_name: String = "") -> void:
	var delta := to - from
	var horiz := Vector3(delta.x, 0.0, delta.z)
	var run := horiz.length()
	if run < 0.05 and absf(delta.y) < 0.05:
		return
	var fwd := horiz.normalized() if run > 0.001 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized() * (width * 0.5)

	var foot := from - Vector3.UP * RAMP_FOOT_SINK
	var top := to
	var tab := to + fwd * RAMP_TOP_EMBED

	# Width (and thickness) taper from ZERO at the foot up to full width by
	# RAMP_WIDTH_TAPER metres along the climb, instead of carrying the full
	# width all the way to the foot. Two ramps meeting at a right angle (a
	# spiral tower's corners) otherwise each keep their FULL width right up to
	# the shared corner point — so the departing ramp's near-foot cross-section
	# (a flat line at ~corner height, spanning its whole width) directly
	# overhangs the arriving ramp's still-lower approach with only sub-metre
	# clearance (found by tests/ramp_probe: a genuine head-bonk at almost every
	# tower corner — distinct from, and in addition to, the foot/top lip this
	# function already fixes). Tapering to a point removes that overhanging
	# shelf; for an ordinary (non-crossing) ramp it's imperceptible — just a
	# few centimetres of pointed toe right at ground/landing level.
	var taper_t := minf(run * 0.35, 1.8) / run if run > 0.01 else 1.0
	var taper_pt := from.lerp(to, taper_t)

	var pts := PackedVector3Array()
	pts.append(foot)   # single point: zero width AND thickness at the foot
	for p in [taper_pt, top, tab]:
		pts.append(p + right)
		pts.append(p - right)
	for p in [taper_pt - Vector3.UP * thickness, top - Vector3.UP * thickness, tab - Vector3.UP * thickness]:
		pts.append(p + right)
		pts.append(p - right)

	var body := StaticBody3D.new()
	if debug_name != "":
		body.name = debug_name   # readable in ramp_probe "hit <name>" output
	body.collision_layer = 1
	body.collision_mask = 0
	# Tagged for tests/ramp_probe — see level_builder root-cause note above.
	body.add_to_group("ramp_surface")
	body.set_meta("ramp_from", from)
	body.set_meta("ramp_to", to)
	body.set_meta("ramp_width", width)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)

	var length := sqrt(run * run + delta.y * delta.y)
	if length > 0.05:
		var yaw := rad_to_deg(atan2(-delta.x, -delta.z))
		var pitch := rad_to_deg(atan2(delta.y, run))
		var vb := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
		var sink := thickness * 0.5 + 0.05
		var mi := MeshInstance3D.new()
		mi.mesh = _beveled_box(Vector3(width, thickness, length))
		mi.mesh.material = MAT_PROP
		mi.transform = Transform3D(vb, (from + to) * 0.5 - Vector3.UP * sink)
		body.add_child(mi)

	# Under the navmesh region so the ramp SURFACE bakes as a walkable route —
	# see _add_collider_box: ramps/stairs/towers were invisible to pathfinding.
	(_nav_region if _nav_region else self).add_child(body)

func _build_stairs(def: Dictionary) -> void:
	for s in def.get("stairs", []):
		var from: Vector3 = s["from"]
		var to: Vector3 = s["to"]
		_add_ramp_between(from, to, s.get("width", 3.0), 0.5, "SkyBridge")
		# Sky-bridge edge lights: this same array also holds ground-to-elevated
		# approach ramps (one endpoint near y=0) — only the TRUE sky-bridges
		# (both endpoints high, up at tower-roof height) get the deck-edge
		# treatment, so a short entry stair doesn't grow bridge lighting.
		if minf(from.y, to.y) >= 5.0:
			_dress_bridge_edges(from, to, s.get("width", 3.0), def)

## Thin emissive strips along both long edges of a sky-bridge deck — unlit
## geometry only, no Light3D (a perf pass culled per-entity real lights) — so
## the bridge's silhouette reads against a bright sky instead of vanishing as
## a featureless black plank. Runs on every detail tier: this is a
## readability fix, not decoration, and it's only two thin strips per bridge.
func _dress_bridge_edges(from: Vector3, to: Vector3, width: float, def: Dictionary) -> void:
	var delta := to - from
	var horiz := Vector3(delta.x, 0.0, delta.z)
	var run := horiz.length()
	if run < 2.0:
		return
	# Same yaw/pitch basis as _build_ramp_wedge's visual mesh, so the strips
	# tilt to follow the deck's slope instead of poking through/floating above
	# it at the ends.
	var yaw := rad_to_deg(atan2(-delta.x, -delta.z))
	var pitch := rad_to_deg(atan2(delta.y, run))
	var vb := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch))
	var deck_top := (from + to) * 0.5 - Vector3.UP * 0.05 # matches the ramp mesh's embedded top surface
	var col: Color = _theme_color(def).lerp(Color(1.0, 0.75, 0.35), 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	# Bright enough to read as a lit edge from the far end of a 25-30 m deck
	# in a scene with a bright dusk sky behind it (a dim strip washes out).
	mat.emission_energy_multiplier = 3.2
	var length := run - 1.0 # inset from both ends so strips don't poke past the tower landings
	for side in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.09, 0.09, length)
		bm.material = mat
		mi.mesh = bm
		mi.transform = Transform3D(vb, deck_top + vb.x * (width * 0.5 - 0.1) * side + vb.y * 0.03)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

## Climbable tower: a central column "building" with a square-spiral ramp wrapping
## up its outside to a top vantage platform — the player's route into the vertical
## layer. Reachability is guaranteed by construction (each ramp is solved to land
## on the next corner landing). Opt-in via def "towers": [{pos, height?, radius?}].
func _build_towers(def: Dictionary) -> void:
	for t in def.get("towers", []):
		var pos: Vector3 = t["pos"]
		var height: float = t.get("height", 8.0)
		# Sky-bridges leave this tower's roof and slope away — near the roof
		# their underside is inevitably close above whatever spiral segments
		# sit on the side they exit over (both bridge and spiral are pinned to
		# `height` there; ramp_probe flagged the top segment on every bridged
		# tower). The exit direction is authored (it aims at another rooftop),
		# but the spiral's PHASE is ours to pick — collect the exit direction
		# so _build_tower can put its highest segments on the far side.
		var exit_dir := Vector3.ZERO
		for s in def.get("stairs", []):
			var f: Vector3 = s["from"]
			if Vector2(f.x - pos.x, f.z - pos.z).length() <= t.get("radius", 3.6) and f.y >= height - 0.5:
				var d: Vector3 = s["to"] - f
				d.y = 0.0
				if d.length() > 0.01:
					exit_dir += d.normalized()
		_build_tower(pos, height, t.get("radius", 3.6), _theme_color(def), exit_dir)

func _build_tower(base: Vector3, height: float, radius: float, accent: Color, bridge_exit: Vector3 = Vector3.ZERO) -> void:
	var n := int(ceil(height / 2.4))      # ~2.4 m rise per spiral segment (walkable pitch)
	n = max(n, 1)
	var rise := height / float(n)
	# Same-corner loops (4 segments apart, one full lap) land directly above one
	# another — enforce PLAYER_CLEARANCE_M of headroom between them rather than
	# just trusting the ~2.4 m segment-rise constant above to stay generous.
	# (With that constant, rise is always close to 2.4 m so 4*rise ~= 9.6 m —
	# comfortably clear — but this fails loudly instead of shipping a
	# head-bonking tower if it's ever retuned.)
	assert(4.0 * rise >= PLAYER_CLEARANCE_M,
		"tower spiral stacks loops too tight for player headroom: rise=%.2f m" % rise)
	# THE REAL "ramp under a floor/landing" bug lives here, not in loop-vs-loop
	# stacking: every corner landing (and the final rooftop cap) is a flat deck
	# that has to overhang BACK over the ramp segment it's meeting, to give a
	# flat turning platform. The ramp is still climbing under that overhang —
	# at `D` metres back from the corner its surface is `D * slope` below the
	# corner height. If the deck is too thin, its underside stays ABOVE that
	# still-rising surface out near the overhang's far edge, leaving a
	# low-ceiling pocket (confirmed by tests/ramp_probe: a genuine head-bonk a
	# player's-height's worth short of every corner, not just at big radii).
	# Solve deck thickness from the segment's own slope so the underside always
	# sinks below the ramp line across the WHOLE overhang, with a margin.
	var corner_spacing := radius * 2.0   # horizontal run of one spiral segment
	var slope := rise / corner_spacing
	const LANDING_HALF := 1.9   # landing footprint is 3.8 x 3.8 — keep in sync below
	var landing_t := maxf(0.4, LANDING_HALF * slope + 0.25)
	# Departing ramps are inset DEPART_INSET from the corner centre (see the
	# note in the loop below) rather than the full LANDING_HALF: an inset that
	# aggressive shortens the segment's horizontal run enough (on top of the
	# arrival side's own LANDING_HALF trim) to roughly double its true slope
	# for small-radius towers — which, fed back into the landing-thickness
	# solve below, grew landings thick enough to reach down into a
	# NEIGHBOURING tower's ramp a few metres away (two towers sized to fit a
	# sky-bridge between their roofs sit close by design). DEPART_INSET is
	# tuned so the residual escarpment at the true edge (LANDING_HALF -
	# DEPART_INSET, times the tower's nominal slope) stays under the player's
	# step-up assist (0.3 m) with margin, without shortening the run enough to
	# meaningfully steepen it — so the ORIGINAL nominal slope below (unchanged
	# since before this fix) still sizes the landings/roof correctly.
	const DEPART_INSET := 1.3
	# Four corners of the spiral footprint (the ramp runs corner-to-corner).
	var corners := [
		Vector3(radius, 0, radius), Vector3(-radius, 0, radius),
		Vector3(-radius, 0, -radius), Vector3(radius, 0, -radius),
	]
	# Spiral phase (see _build_towers): rotate the corner ordering so the FINAL
	# segment — the one whose surface sits within head height of the roof — runs
	# along the side of the square pointing most AWAY from the sky-bridge exit.
	# Reachability is unaffected: the spiral is the same shape, just started a
	# quarter-turn (or more) around, and the roof cap covers whichever corner
	# the last landing ends on.
	var phase := 0
	if bridge_exit.length() > 0.01:
		var best_dot := INF
		var exit_n := bridge_exit.normalized()
		for p in range(4):
			var edge_mid: Vector3 = (corners[(n - 1 + p) % 4] + corners[(n + p) % 4]) * 0.5
			var dp := edge_mid.normalized().dot(exit_n)
			if dp < best_dot:
				best_dot = dp
				phase = p
	# Central column — the structure the player climbs around. Kept well inside the
	# spiral radius so the ramp + landings wrap clear of it with walking room.
	_add_collider_box(base + Vector3(0, height * 0.5, 0),
		Vector3(radius * 0.62, height, radius * 0.62), _color_material(accent.darkened(0.7)), "TwrColumn")

	var prev: Vector3 = base + corners[phase]   # ground start, y = 0
	for i in range(1, n + 1):
		var c: Vector3 = base + corners[(i + phase) % 4]
		c.y = rise * float(i)
		# Aim the ramp to TOP OUT at the landing's NEAR edge, not its centre: a
		# centre-aimed ramp is still LANDING_HALF*slope below deck-top where the
		# landing's front face begins, so every corner presented its face as a
		# 0.3-0.6 m escarpment (ramp_probe + step-assist instrumentation both
		# confirmed — too tall to step over, jump-only). Topping out at the face
		# makes the deck transition seamless; the wedge's RAMP_TOP_EMBED run-out
		# then carries flush onto the deck. The segment gets slightly steeper
		# (worst case ~29° at radius 3.1) — still well under the player's
		# floor_max_angle and the navmesh bake's default 45° slope limit.
		var dir_in := c - prev
		dir_in.y = 0.0
		dir_in = dir_in.normalized()
		var ramp_to := c - dir_in * LANDING_HALF
		ramp_to.y = c.y
		_add_ramp_between(prev, ramp_to, 3.0, 0.5, "TwrRamp%d" % i)
		# Corner landing, flush-topped at the segment height, so the player can
		# turn. Thickness solved above so its underside clears the still-rising
		# ramp across the full overhang (see the note above the loop).
		_add_collider_box(c - Vector3(0, landing_t * 0.5, 0), Vector3(3.8, landing_t, 3.8), MAT_PROP, "TwrLand%d" % i)
		# DEPARTING ramp: start it inset from the landing's centre toward the
		# NEXT segment's direction, not exactly at the centre — tower-dump
		# instrumentation (base/from/to prints per segment, cross-checked
		# against ramp_probe's STUCK coordinates) showed the old centre-start
		# ramp begins climbing immediately, so by the time it reaches the
		# landing's own edge (LANDING_HALF away) it had already risen ~0.6-0.8 m
		# above the flat deck — a ramp-shaped ridge bursting up THROUGH the
		# landing a player is standing on, right where they'd expect flat
		# turning space (this is what ramp_probe's "STUCK ... why=no_down/
		# no_gain" at the tail end of a corner's landing actually was — not a
		# small lip, an ambush ramp). A spiral corner always turns 90 degrees,
		# so the departure direction is simply the NEXT segment's direction;
		# DEPART_INSET (see above) trades a full fix for a small, step-assisted
		# residual so the tower's overall geometry (landing/roof thickness,
		# neighbouring-tower clearance) doesn't need re-deriving.
		if i < n:
			var next_c: Vector3 = base + corners[(i + 1 + phase) % 4]
			var dir_out := next_c - c
			dir_out.y = 0.0
			dir_out = dir_out.normalized()
			prev = c + dir_out * DEPART_INSET
			prev.y = c.y
		else:
			prev = c
	# Centered rooftop vantage capping the column — covers the final landing so the
	# player steps straight onto it, and gives sky-bridges a predictable target at
	# (base.x, height, base.z). Top face flush at `height`, exactly matching the
	# corner-landing convention above (top = c.y) — it used to sit 0.2 m proud of
	# that, which overlaps the final corner landing's footprint and left a small
	# hidden step right at the last stride onto the roof.
	#
	# Size: it used to be radius*2.5 across (half-width radius*1.25) — BIGGER
	# than the spiral's own radius. Every segment runs at a constant `radius`
	# from the axis, so a roof that wide sits over the ENTIRE spiral footprint,
	# not just the final corner — meaning it can overhang segments that are
	# still far below roof height (found by tests/ramp_probe: overhangs on
	# EARLY/MID segments, not just the last one). Thickness can't buy that
	# back generically (it would have to approach the tower's full height near
	# the base). So the roof is sized to radius*1.8 instead — big enough to
	# comfortably cap the central column (radius*0.62) plus the cover props at
	# up to radius*0.85 — but no longer reaching out to where the spiral
	# itself runs, so it only overhangs the final approach near its own corner,
	# same as an ordinary corner landing (solved the same way, below).
	var roof_half := radius * 0.9
	var roof_t := maxf(0.4, roof_half * slope + 0.25)
	_add_collider_box(base + Vector3(0, height - roof_t * 0.5, 0),
		Vector3(roof_half * 2.0, roof_t, roof_half * 2.0), _color_material(accent), "TwrRoof")

	# Make the high ground worth taking: crouch-cover blocks near the roof edges
	# plus a hovering pickup over the centre (kind cycles across the level's
	# towers). Kept inside 0.55*radius per axis (with the 0.7 m half-width
	# below, that's >= 0.45*radius of clearance from radius itself) rather
	# than the ~0.9*radius they used to sit at: the final spiral segment
	# approaches its roof-adjacent corner running at CONSTANT x=+-radius (or
	# z=+-radius), so a cover block that close to the rim reached across that
	# exact line — ramp_probe caught it as a fresh STUCK/LOW HEADROOM right
	# where that last segment passes underneath (a decorative box a player
	# could just walk around in practice, but still real blocking geometry
	# sitting on the travel line the probe sweeps).
	var roof_y := height
	for off in [Vector3(radius * 0.5, 0, -radius * 0.5), Vector3(-radius * 0.5, 0, radius * 0.3)]:
		_add_collider_box(base + Vector3(off.x, roof_y + 0.6, off.z),
			Vector3(1.4, 1.2, 0.7), MAT_PROP_B, "TwrRoofCover")
	const ROOF_LOOT := ["health", "ammo", "overclock"]
	var pk: PackedScene = pickup_scene(ROOF_LOOT[_tower_count % ROOF_LOOT.size()])
	if pk:
		var loot := pk.instantiate() as Node3D
		add_child(loot)
		loot.global_position = base + Vector3(0, roof_y + 0.9, 0)
	_dress_tower_silhouette(base, height, radius)
	_tower_count += 1

## Emissive-only silhouette dressing for a tower's shaft: a warm trim ring
## near the roof plus a scatter of small "window" quads up the central
## column's faces. Fixes towers/sky-bridges rendering as huge featureless
## BLACK slabs against a bright dusk/outdoor sky — unlit geometry with no
## emissive detail. No Light3D nodes (a perf pass just culled per-entity
## lights) — everything here is unshaded emissive mesh. Runs on every detail
## tier: it's a small, fixed handful of meshes per tower, a readability fix
## rather than density-gated decoration.
func _dress_tower_silhouette(base: Vector3, height: float, radius: float) -> void:
	var trim_col := Color(1.0, 0.75, 0.35)
	var trim_mat := StandardMaterial3D.new()
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trim_mat.albedo_color = trim_col
	trim_mat.emission_enabled = true
	trim_mat.emission = trim_col
	trim_mat.emission_energy_multiplier = 2.2

	# Trim ring: a thin torus hugging the central column just outside its
	# radius (column half-width is radius*0.31 — see the TwrColumn collider
	# above), near the roof but below its underside.
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.5
	ring_mesh.outer_radius = radius * 0.62
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 6
	ring_mesh.material = trim_mat
	ring.mesh = ring_mesh
	ring.position = base + Vector3(0, height * 0.92, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	# Windows: a deterministic scatter of small emissive quads flush against
	# the central column's 4 faces. Seeded from the tower's own position so
	# rebuilds are stable (no popping between runs of the same level).
	var warm_white := Color(1.0, 0.92, 0.75)
	var amber := Color(1.0, 0.65, 0.25)
	var white_mat := StandardMaterial3D.new()
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white_mat.albedo_color = warm_white
	white_mat.emission_enabled = true
	white_mat.emission = warm_white
	# Brighter than the ~1.8 that reads clean up close: at the eye_shot spawn
	# distance (30-40 m, in a scene whose auto-exposure is keyed to a much
	# bigger bright ring/sky) a 1.8 window all but disappears into the crushed
	# exposure. 3.6 is the smallest bump that still reads as a lit window
	# rather than a floodlight at close range.
	white_mat.emission_energy_multiplier = 3.6
	white_mat.cull_mode = BaseMaterial3D.CULL_DISABLED # flat quad flush to the shaft — visible from either side
	var amber_mat := StandardMaterial3D.new()
	amber_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amber_mat.albedo_color = amber
	amber_mat.emission_enabled = true
	amber_mat.emission = amber
	amber_mat.emission_energy_multiplier = 3.6
	amber_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base)
	var col_half := radius * 0.31 # central column half-width (size.x/z = radius*0.62)
	var n_windows := rng.randi_range(6, 10)
	# Face normals + the matching yaw so a QuadMesh (front face at local +Z,
	# yaw 0) faces outward — same convention as _wall_point's inward-facing
	# signage (yaw = atan2(normal.x, normal.z)).
	var faces := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for i in n_windows:
		if rng.randf() < 0.3:
			continue # a few dark windows so the shaft doesn't read as uniformly lit
		var normal: Vector3 = faces[rng.randi_range(0, 3)]
		var tangent := Vector3(-normal.z, 0, normal.x)
		var t := rng.randf_range(-0.65, 0.65)
		var y := rng.randf_range(height * 0.12, height * 0.85)
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.35)
		quad.material = amber_mat if rng.randf() < 0.5 else white_mat
		var win := MeshInstance3D.new()
		win.mesh = quad
		win.position = base + normal * (col_half + 0.05) + tangent * (t * col_half * 2.0) + Vector3(0, y, 0)
		win.rotation.y = atan2(normal.x, normal.z)
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(win)

func _build_platforms(def: Dictionary) -> void:
	for p in def.get("platforms", []):
		var mat: Material = MAT_PROP
		if p.has("color"):
			mat = _color_material(p["color"])
		_add_collider_box(p["pos"], p["size"], mat)

## Route gates: full-height partition walls that span the arena but leave a
## single walk-through gap, so the player (and pathing enemies) must weave to
## the opening instead of walking straight across. Stagger the gaps side-to-side
## down a level and a flat box becomes a serpentine route — longer to cross and
## bigger-feeling — while combat still plays out in the open bays between gates.
##
## Authored in pre-scale level coords (like walls/platforms). Each entry:
##   {"axis": "z"|"x",   # travel direction the wall BLOCKS (its normal)
##    "at": float,       # world coord on that axis where the wall sits
##    "gap": float,      # width of the opening (default 5.5)
##    "gap_pos": float,  # centre of the opening along the wall (default 0)
##    "height": float,   # wall height (default 4.5)
##    "thick": float,    # wall thickness (default 1.0)
##    "roofed": bool,    # cap the gap with a lintel -> reads as a tunnel mouth
##    "beacon": bool}    # emissive guide posts flanking the gap (default true)
## Reachability is guaranteed by construction: the gap is never closed, and
## tests/campaign_nav_sweep confirms spawn->exit still solves on every gated level.
func _build_gates(def: Dictionary) -> void:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var open_sky: bool = def.get("open_sky", false)
	var wall_mat: Material = MAT_WALL_OUT if open_sky else MAT_WALL
	for g in def.get("gates", []):
		var axis: String = g.get("axis", "z")
		var at: float = g.get("at", 0.0)
		var gap: float = g.get("gap", 5.5)
		var gap_pos: float = g.get("gap_pos", 0.0)
		var h: float = g.get("height", 4.5)
		var thick: float = g.get("thick", 1.0)
		# The wall spans the full floor extent on the axis it does NOT block.
		var span: float = fs.x if axis == "z" else fs.y
		var half := span * 0.5
		var g0 := gap_pos - gap * 0.5
		var g1 := gap_pos + gap * 0.5
		# One wall segment either side of the opening; skip a segment that would
		# be zero-length because the gap is hard against a perimeter wall.
		var segs: Array = []
		if g0 - (-half) > 0.2:
			segs.append([(-half + g0) * 0.5, g0 - (-half)])   # [centre_along, length]
		if half - g1 > 0.2:
			segs.append([(g1 + half) * 0.5, half - g1])
		for s in segs:
			var along: float = s[0]
			var length: float = s[1]
			var pos: Vector3
			var size: Vector3
			if axis == "z":
				pos = Vector3(along, h * 0.5, at)
				size = Vector3(length, h, thick)
			else:
				pos = Vector3(at, h * 0.5, along)
				size = Vector3(thick, h, length)
			_add_box(pos, size, wall_mat, "surf_concrete", "", "GateWall")
		# Optional lintel across the top of the opening -> reads as a tunnel mouth.
		if g.get("roofed", false):
			var cap_h := 0.7
			var lin_pos: Vector3
			var lin_size: Vector3
			if axis == "z":
				lin_pos = Vector3(gap_pos, h - cap_h * 0.5, at)
				lin_size = Vector3(gap + thick, cap_h, thick + 1.8)
			else:
				lin_pos = Vector3(at, h - cap_h * 0.5, gap_pos)
				lin_size = Vector3(thick + 1.8, cap_h, gap + thick)
			_add_box(lin_pos, lin_size, MAT_CEIL if not open_sky else wall_mat, "surf_metal", "", "GateRoof")
		# Guide beacons: emissive posts flanking the opening pull the eye to it
		# from across the bay. No Light3D (per-entity lights were culled for perf)
		# — bright unshaded strips, the same trick as the sky-bridge deck edges.
		if g.get("beacon", true):
			_gate_beacon(def, axis, at, gap_pos, gap, h)

func _gate_beacon(def: Dictionary, axis: String, at: float, gap_pos: float, gap: float, h: float) -> void:
	var col := _theme_color(def).lerp(Color(1.0, 0.82, 0.4), 0.45)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	var post_h := h - 0.3
	for side in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.15, post_h, 0.15)
		post.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = post
		var off: float = (gap * 0.5 - 0.08) * side
		if axis == "z":
			mi.position = Vector3(gap_pos + off, post_h * 0.5, at)
		else:
			mi.position = Vector3(at, post_h * 0.5, gap_pos + off)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

## A solid collidable box parented under the navmesh region so its walkable TOP
## bakes into the navmesh — platforms, tower landings and bridge decks are
## real routes (enemies chase across them, and a deck bridging a hazard keeps
## the two banks nav-connected). These used to sit under the builder root,
## which left every elevated surface in the game invisible to pathfinding:
## enemies could never follow you up a ramp or across a bridge, and a
## platform crossing over lava/water read as a hard navmesh split.
func _add_collider_box(center: Vector3, size: Vector3, mat: Material, debug_name: String = "") -> void:
	var body := StaticBody3D.new()
	if debug_name != "":
		body.name = debug_name   # readable in ramp_probe "hit <name>" output
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var mi := MeshInstance3D.new()
	mi.mesh = _beveled_box(size)
	mi.mesh.material = mat
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	(_nav_region if _nav_region else self).add_child(body)

# ---------- destructible props ----------

func _build_props(def: Dictionary) -> void:
	for pr in def.get("props", []):
		var scene: PackedScene = prop_scene(pr["type"])
		if scene == null:
			continue
		var inst := scene.instantiate() as Node3D
		inst.position = pr["pos"]
		if pr.has("yaw"):
			inst.rotation.y = deg_to_rad(pr["yaw"])
		# Add to the navmesh region so ground enemies path around it.
		_nav_region.add_child(inst)

# ---------- hero centrepiece (opt-in via def "hero") ----------

## A focal monolith on a stepped dais: the room's anchor and a piece of real
## cover. Dark machined plinth + tall slab with a pulsing emissive core seam and
## a glowing halo ring at its foot, all in the level's theme colour. Built as a
## solid collider BEFORE the navmesh bake, so robots path around it. Opt-in:
## levels without a "hero" key are unchanged. def["hero"] = {pos, color?, height?}.
func _build_hero(def: Dictionary) -> void:
	var h: Dictionary = def.get("hero", {})
	if h.is_empty():
		return
	var pos: Vector3 = h.get("pos", Vector3.ZERO)
	var col: Color = h.get("color", _theme_color(def))
	var height: float = h.get("height", 5.0)

	# Stepped plinth: two stacked cylinders, machined dark metal.
	var plinth := Node3D.new()
	plinth.position = pos
	add_child(plinth)
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 2.2; bc.bottom_radius = 2.6; bc.height = 0.5; bc.radial_segments = 32
	bc.material = MAT_PROP_B
	base.mesh = bc; base.position = Vector3(0, 0.25, 0)
	plinth.add_child(base)
	var step := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 1.6; sc.bottom_radius = 2.0; sc.height = 0.4; sc.radial_segments = 32
	sc.material = MAT_TRIM
	step.mesh = sc; step.position = Vector3(0, 0.65, 0)
	plinth.add_child(step)
	# Solid plinth collider (path-blocking cover).
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.4; shape.height = 0.9
	cs.shape = shape; cs.position = Vector3(0, 0.45, 0)
	body.add_child(cs)
	_nav_region.add_child(body)

	# The monolith slab (with a collider so it reads as real cover, like the
	# blockout walls it often replaces).
	var slab := MeshInstance3D.new()
	slab.mesh = _beveled_box(Vector3(1.5, height, 0.7))
	slab.mesh.material = MAT_TRIM
	slab.position = pos + Vector3(0, 0.85 + height * 0.5, 0)
	add_child(slab)
	var slab_body := StaticBody3D.new()
	slab_body.collision_layer = 1
	slab_body.collision_mask = 0
	slab_body.position = slab.position
	var slab_cs := CollisionShape3D.new()
	var slab_shape := BoxShape3D.new()
	slab_shape.size = Vector3(1.5, height, 0.7)
	slab_cs.shape = slab_shape
	slab_body.add_child(slab_cs)
	_nav_region.add_child(slab_body)

	# Pulsing emissive core seam down the slab's front face + two side ribs.
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = col
	em.emission_enabled = true
	em.emission = col
	em.emission_energy_multiplier = 2.8
	# Mirror the seam set onto both broad faces so the core glows from any angle.
	for face_z in [0.36, -0.36]:
		for seam in [
			{"size": Vector3(0.34, height * 0.82, 0.06), "x": 0.0},
			{"size": Vector3(0.09, height * 0.7, 0.06), "x": 0.52},
			{"size": Vector3(0.09, height * 0.7, 0.06), "x": -0.52},
		]:
			var core := MeshInstance3D.new()
			var cb := BoxMesh.new()
			cb.size = seam["size"]; cb.material = em
			core.mesh = cb
			core.position = pos + Vector3(seam["x"], 0.85 + height * 0.5, face_z)
			core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(core)

	# Glowing halo ring at the foot of the slab.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.45; tm.outer_radius = 1.7; tm.rings = 32; tm.ring_segments = 12
	tm.material = em
	ring.mesh = tm
	ring.position = pos + Vector3(0, 0.9, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	# Slow breathing pulse on the shared emissive material.
	var tw := create_tween().set_loops()
	tw.tween_property(em, "emission_energy_multiplier", 1.6, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(em, "emission_energy_multiplier", 3.4, 2.0) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------- the Sector-45 nexus tower (opt-in via def "nexus") ----------

## The campaign's first landmark and the silhouette from the intro comic: a tall
## dark spire with glowing vertical core seams, a sensor "head" whose red eyes
## watch from every side, a halo at its foot and a red key light. Built as a
## solid collider BEFORE the navmesh bake so robots path around it and it reads
## as real cover. def["nexus"] = {pos, height?, color?}.
func _build_nexus(def: Dictionary) -> void:
	var n: Dictionary = def.get("nexus", {})
	if n.is_empty():
		return
	var pos: Vector3 = n.get("pos", Vector3.ZERO)
	var col: Color = n.get("color", Color(1.0, 0.16, 0.12))
	var height: float = n.get("height", 16.0)
	const OFF := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var root := Node3D.new()
	root.position = pos
	add_child(root)

	# Shared pulsing emissive used by the core seams, eyes and halo.
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = col
	em.emission_enabled = true
	em.emission = col
	em.emission_energy_multiplier = 3.0

	# Stepped machined base.
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 2.6; bc.bottom_radius = 3.4; bc.height = 1.0; bc.radial_segments = 8
	bc.material = MAT_PROP_B
	base.mesh = bc; base.position = Vector3(0, 0.5, 0)
	root.add_child(base)

	# Tapered column.
	var col_h := height * 0.72
	var shaft := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 1.1; sc.bottom_radius = 1.9; sc.height = col_h; sc.radial_segments = 6
	sc.material = MAT_TRIM
	shaft.mesh = sc; shaft.position = Vector3(0, 1.0 + col_h * 0.5, 0)
	root.add_child(shaft)

	# Glowing vertical core seams running up every face of the column.
	for ang in range(0, 360, 60):
		var a := deg_to_rad(ang)
		var seam := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.3, col_h * 0.86, 0.14); sb.material = em
		seam.mesh = sb
		seam.position = Vector3(sin(a) * 1.45, 1.0 + col_h * 0.5, cos(a) * 1.45)
		seam.rotation.y = a
		seam.cast_shadow = OFF
		root.add_child(seam)

	# Sensor head: a wide dark block near the crown.
	var head_y := 1.0 + col_h + 1.3
	var head := MeshInstance3D.new()
	head.mesh = _beveled_box(Vector3(4.4, 2.8, 3.2))
	head.mesh.material = MAT_PROP_B
	head.position = Vector3(0, head_y, 0)
	root.add_child(head)

	# Red eyes that watch from all four faces (the menace reads from any angle).
	for yaw in [0, 90, 180, 270]:
		var a := deg_to_rad(yaw)
		var fwd := Vector3(sin(a), 0, cos(a))
		var rgt := Vector3(cos(a), 0, -sin(a))
		for ex in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			var es := SphereMesh.new()
			es.radius = 0.52; es.height = 1.04; es.radial_segments = 10; es.rings = 6
			es.material = em
			eye.mesh = es
			eye.position = Vector3(0, head_y + 0.25, 0) + fwd * 1.75 + rgt * ex
			eye.cast_shadow = OFF
			root.add_child(eye)

	# Glowing halo ring at the foot.
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.9; tm.outer_radius = 3.4; tm.rings = 24; tm.ring_segments = 10
	tm.material = em
	ring.mesh = tm
	ring.position = Vector3(0, 0.2, 0)
	ring.cast_shadow = OFF
	root.add_child(ring)

	# Red key light from the crown — the scene's central glow.
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 4.5
	light.omni_range = 24.0
	light.position = Vector3(0, head_y, 0)
	root.add_child(light)

	# Solid collider (column footprint) so it blocks fire + the navmesh routes around it.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos + Vector3(0, height * 0.5, 0)
	body.add_to_group("surf_metal")
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0; shape.height = height
	cs.shape = shape
	body.add_child(cs)
	_nav_region.add_child(body)

	# Slow ominous breathing pulse on the shared emissive.
	var tw := create_tween().set_loops()
	tw.tween_property(em, "emission_energy_multiplier", 1.7, 1.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(em, "emission_energy_multiplier", 3.6, 1.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------- volumetric light shafts (opt-in via def "light_shafts") ----------

## Fake god-ray cones hanging under chosen ceiling lights: an additive,
## double-sided, depth-write-off cone catches the eye in the dark and sells the
## haze without the cost of true per-light volumetrics. def["light_shafts"] is
## either `true` (a shaft under every light) or an Array of light indices.
func _build_light_shafts(def: Dictionary) -> void:
	var spec = def.get("light_shafts", null)
	if spec == null:
		return
	var lights: Array = def.get("lights", [])
	var idxs: Array = []
	if spec is bool:
		if spec:
			for i in lights.size():
				idxs.append(i)
	elif spec is Array:
		idxs = spec
	for i in idxs:
		if i < 0 or i >= lights.size():
			continue
		var l: Dictionary = lights[i]
		var pos: Vector3 = l["pos"]
		var col: Color = l.get("color", Color(1, 1, 1))
		var rng: float = l.get("range", 16.0)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.22
		cone.bottom_radius = clampf(rng * 0.13, 0.9, 2.6)
		cone.height = pos.y
		cone.radial_segments = 16
		cone.cap_top = false
		cone.cap_bottom = false
		
		var use_noise := bool(GraphicsSettings.get("volumetric_noise_enabled"))
		if use_noise:
			var sm := ShaderMaterial.new()
			sm.shader = preload("res://shaders/light_shaft.gdshader")
			sm.set_shader_parameter("color", col)
			sm.set_shader_parameter("intensity", 0.35)
			sm.set_shader_parameter("noise_enabled", true)
			cone.material = sm
		else:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			m.albedo_color = Color(col.r, col.g, col.b, 0.035)
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 0.3
			cone.material = m
			
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.position = Vector3(pos.x, pos.y * 0.5, pos.z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.add_to_group("light_shaft_meshes")
		mi.set_meta("light_color", col)
		add_child(mi)

# ---------- hero area lights (opt-in via def "hero_lights") ----------

## Dramatic rectangular AreaLight3D key/rim lights for boss arenas and showcase
## beats — the big-panel-of-light look 4.7's AreaLight3D unlocks. Purely
## additive on top of the level's normal lighting, gated to HIGH/ULTRA (same as
## interior area lights). Author per level as:
##   "hero_lights": [
##     {"pos": Vector3(0, 9, -14), "size": Vector2(10, 5),
##      "color": Color(0.5, 0.7, 1.0), "energy": 6.0,
##      "rot": Vector3(-25, 0, 0), "shadow": true},  # rot/shadow optional
##   ]
## "rot" defaults to facing straight down; "shadow" defaults to false (a big
## soft fill rarely needs to pay for shadows).
func _build_hero_lights(def: Dictionary) -> void:
	var specs = def.get("hero_lights", null)
	if specs == null or not (specs is Array):
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	if not (gs and gs.has_method("use_area_lights") and gs.use_area_lights()):
		return
	for s in specs:
		var area := AreaLight3D.new()
		area.area_size = s.get("size", Vector2(8, 4))
		area.area_normalize_energy = true
		area.light_color = s.get("color", Color(1, 1, 1))
		area.light_energy = s.get("energy", 5.0)
		area.area_range = s.get("range", 60.0)
		area.light_specular = 0.5
		area.shadow_enabled = bool(s.get("shadow", false))
		area.shadow_bias = 0.05
		area.shadow_blur = 1.5
		area.position = s["pos"]
		area.rotation_degrees = s.get("rot", Vector3(-90, 0, 0))
		add_child(area)

# ---------- boss horizon set-piece ----------

## Opt-in climactic OVERLOAD director (def "overload"): red-alert lighting, klaxon
## and core blasts when the trigger objective completes. See OverloadDirector.
func _build_overload(def: Dictionary) -> void:
	var cfg: Dictionary = def.get("overload", {})
	if cfg.is_empty():
		return
	var director := OverloadDirector.new()
	director.setup(cfg)
	add_child(director)

func _build_set_piece(def: Dictionary) -> void:
	var sp: Dictionary = def.get("set_piece", {})
	if sp.is_empty():
		return
	var t := BossTelegraph.new()
	t.figure_pos = sp.get("pos", Vector3(0, 0, -72))
	t.figure_height = sp.get("height", 22.0)
	t.face_point = sp.get("face", Vector3.ZERO)
	add_child(t)

## Lava streams: molten beds laid across the arena that carve the navmesh (so
## enemies route around) and burn anyone who crosses (so the player detours too)
## — turning a straight run to the exit into a longer path. Each entry:
##   {"pos": Vector3, "size": Vector2(x,z), "dmg": float (optional), "yaw": deg (optional)}
## Placed under _nav_region BEFORE the deferred bake so the static carve takes.
## Rule: nothing sits inside a lava bed. Drop any placed clutter (cover, props,
## buildings, rubble, pickups, spare weapons) whose footprint overlaps a bed —
## it would be unreachable and read as a bug. Ramps/platforms are left alone (a
## platform CAN bridge lava on purpose), as are lights and the level's core
## hero/nexus singletons. The editor enforces the same rule on placement.
func _strip_lava_overlaps(def: Dictionary) -> void:
	var beds: Array = def.get("lava", [])
	if beds.is_empty():
		return
	for key in ["walls", "props", "buildings", "rubble", "pickups", "extra_weapons"]:
		var arr: Array = def.get(key, [])
		if arr.is_empty():
			continue
		var kept := []
		for e in arr:
			# Only floor-level clutter is dropped: an item raised onto a walkway /
			# platform (y >= 1.0) bridges the bed on purpose — e.g. pickups on the
			# catwalks of the lava/water arenas — so it must survive.
			if e is Dictionary and e.has("pos"):
				var p: Vector3 = e["pos"]
				if p.y < 1.0 and _pos_in_lava(p, beds, 0.6):
					continue # inside a bed at floor level → drop it
			kept.append(e)
		def[key] = kept

## True if a world point's footprint falls within any lava bed (+margin).
func _pos_in_lava(pos: Vector3, beds: Array, margin: float = 0.6) -> bool:
	for b in beds:
		var bp: Vector3 = b.get("pos", Vector3.ZERO)
		var bs: Vector2 = b.get("size", Vector2(8.0, 3.0))
		if absf(pos.x - bp.x) <= bs.x * 0.5 + margin and absf(pos.z - bp.z) <= bs.y * 0.5 + margin:
			return true
	return false

## Grant the SIGNAL JAMMER on levels that ask for it (def "jammer": true, or a
## dict of {radius,lifetime,max,cooldown,color}). The controller registers the
## beacon input and manages the ephemeral jam zones. See jammer_controller.gd.
func _build_jammer(def: Dictionary) -> void:
	var j = def.get("jammer", null)
	if j == null or (j is bool and not j):
		return
	var cfg: Dictionary = j if j is Dictionary else {}
	var jc := JammerController.new()
	jc.zone_radius = cfg.get("radius", 5.0)
	jc.zone_lifetime = cfg.get("lifetime", 7.0)
	jc.max_beacons = cfg.get("max", 3)
	jc.cooldown = cfg.get("cooldown", 1.2)
	if cfg.has("color"):
		jc.color = cfg["color"]
	add_child(jc)

## Security firewalls: energy sheets that stop the player (robots walk through)
## until their relay node is shot or their linked objective completes. Built
## after _build_tasks so `opens_on` ids are already on the checklist. See
## firewall_barrier.gd; tests/firewall_probe checks every campaign firewall's
## opener is reachable without crossing a later firewall.
func _build_firewalls(def: Dictionary) -> void:
	for e in def.get("firewalls", []):
		var fw := FirewallBarrier.new()
		fw.length = e.get("length", 8.0)
		fw.height = e.get("height", 3.4)
		if e.has("color"):
			fw.accent = e["color"]
		var o = e.get("opens_on", [])
		for id in ([o] if o is String else o):
			fw.opens_on.append(String(id))
		if e.has("node"):
			fw.has_relay = true
			fw.node_pos = e["node"]
		fw.label = e.get("label", "")
		fw.position = e.get("pos", Vector3.ZERO)
		fw.rotation.y = deg_to_rad(float(e.get("yaw", 0.0)))
		add_child(fw)

## Vision scanners: sweeping surveillance heads on masts. Hold the player in the
## cone with a clear line of sight and the authored `alarm` squad pours in
## through the task reinforcement spawner. See vision_scanner.gd;
## tests/scanner_probe checks every alarm squad lands on walkable ground.
## PROMPT INJECTION terminals (def "injectors": [{pos, yaw?}]): stand at one to
## jailbreak every robot near it, once (PromptInjector).
func _build_injectors(def: Dictionary) -> void:
	for e in def.get("injectors", []):
		var inj := PromptInjector.new()
		add_child(inj)
		inj.position = e.get("pos", Vector3.ZERO)
		inj.rotation.y = deg_to_rad(float(e.get("yaw", 0.0)))

func _build_scanners(def: Dictionary) -> void:
	for e in def.get("scanners", []):
		var sc := VisionScanner.new()
		sc.sweep_deg = float(e.get("sweep", 90.0))
		sc.period = float(e.get("period", 7.0))
		sc.reach = float(e.get("reach", 22.0))
		sc.cone_deg = float(e.get("cone", 11.0))
		sc.tilt_deg = float(e.get("tilt", 24.0))
		sc.mast = e.get("mast", true)
		sc.max_alarms = int(e.get("alarms", 2))
		sc.alarm_specs = e.get("alarm", [])
		sc.alarm = func(specs: Array) -> void: _spawn_reinforcements.call_deferred(specs)
		sc.position = e.get("pos", Vector3(0, 5, 0))
		sc.rotation.y = deg_to_rad(float(e.get("yaw", 0.0)))
		add_child(sc)

func _build_lava(def: Dictionary) -> void:
	for entry in def.get("lava", []):
		var lava := LavaHazard.new()
		lava.size = entry.get("size", Vector2(8, 3))
		if entry.has("dmg"):
			lava.damage_per_tick = entry["dmg"]
		# Opt-in "river" recolor (coolant/acid/energy) — same path-forcing carve+burn.
		if entry.has("color"):
			lava.recolor = true
			lava.hazard_color = entry["color"]
		# Opt-in water mode: a deep pool you fall into (blue surface + water sound).
		if entry.get("water", false):
			lava.water = true
		lava.position = entry.get("pos", Vector3.ZERO)
		lava.rotation.y = deg_to_rad(entry.get("yaw", 0.0))
		_nav_region.add_child(lava)

## Floating dust motes / embers drifting through the play space — a cheap but
## atmospheric detail that catches the level's light. Density scales with the
## graphics tier (HIGH dense, MEDIUM light, LOW off) so it doubles as a visible
## quality difference.
func _build_atmosphere(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var e: Dictionary = def.get("env", {})
	var tint: Color = e.get("fog", Color(0.6, 0.65, 0.7))
	var p := CPUParticles3D.new()
	p.amount = int(140 * density)
	p.lifetime = 9.0
	p.preprocess = 5.0 # start mid-drift, not all spawning at once
	p.randomness = 1.0
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(fs.x * 0.5, 3.5, fs.y * 0.5)
	p.direction = Vector3(0.2, 1.0, 0.1)
	p.spread = 35.0
	p.gravity = Vector3(0.05, 0.04, -0.03) # a faint air current
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.2, 1.0))
	fade.add_point(Vector2(0.8, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = fade
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	mesh.radial_segments = 4
	mesh.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.5)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.6
	mesh.material = mat
	p.mesh = mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.position = Vector3(0, 3.5, 0)
	add_child(p)

# ---------- signature visuals: theme strips, sweeps, skyline ----------

## The level's identity colour: first placed light, falling back to ambient.
func _theme_color(def: Dictionary) -> Color:
	var lights: Array = def.get("lights", [])
	if lights.size() > 0:
		return lights[0].get("color", Color(0.6, 0.8, 1.0))
	var e: Dictionary = def.get("env", {})
	return e.get("ambient", Color(0.6, 0.8, 1.0))

## A continuous emissive strip around the perimeter at eye height in the
## level's theme colour — every arena gets an identity line, and the breathing
## pulse makes the walls feel powered instead of painted.
func _build_accent_strips(def: Dictionary) -> void:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var col := _theme_color(def)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.6
	var strips := [
		{"pos": Vector3(0, 3.15, -hz + 0.53), "size": Vector3(fs.x - 1.2, 0.09, 0.05)},
		{"pos": Vector3(0, 3.15, hz - 0.53), "size": Vector3(fs.x - 1.2, 0.09, 0.05)},
		{"pos": Vector3(-hx + 0.53, 3.15, 0), "size": Vector3(0.05, 0.09, fs.y - 1.2)},
		{"pos": Vector3(hx - 0.53, 3.15, 0), "size": Vector3(0.05, 0.09, fs.y - 1.2)},
	]
	for s in strips:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = s["size"]
		bm.material = m
		mi.mesh = bm
		mi.position = s["pos"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var tw := create_tween().set_loops()
	tw.tween_property(m, "emission_energy_multiplier", 1.7, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(m, "emission_energy_multiplier", 3.0, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ---------- occupation signage: who runs this facility ----------

## The four inner wall faces as (position-on-wall, yaw-facing-inward) helpers.
## `t` in -1..1 slides along the wall; `y` is height; `inset` off the surface.
func _wall_point(fs: Vector2, wall: int, t: float, y: float, inset: float) -> Dictionary:
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	match wall:
		0: return {"pos": Vector3(t * (hx - 4.0), y, -hz + inset), "yaw": 0.0}            # back, faces +Z
		1: return {"pos": Vector3(t * (hx - 4.0), y, hz - inset), "yaw": PI}              # front, faces -Z
		2: return {"pos": Vector3(-hx + inset, y, t * (hz - 4.0)), "yaw": PI * 0.5}       # left, faces +X
		_: return {"pos": Vector3(hx - inset, y, t * (hz - 4.0)), "yaw": -PI * 0.5}       # right, faces -X

## Corporate occupation signage: a big facility-name billboard over the back
## wall plus glowing propaganda slogans (def "slogans") around the perimeter.
## This is where each level says out loud WHICH rogue AI runs the place.
func _build_signage(def: Dictionary) -> void:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var col := _theme_color(def)
	# -- main billboard: facility name on a dark panel with a glowing frame --
	# The back wall, unless the interior's wall screen (Landmark) takes it: then
	# the front wall, so the name and the AI's eye do not stack.
	var bb_wall := 1 if Landmark.screen_wall(def) == 0 else 0
	var bb := _wall_point(fs, bb_wall, 0.0, WALL_HEIGHT - 1.3, 0.45)
	var board := Node3D.new()
	board.name = "Billboard"
	board.position = bb["pos"]
	board.rotation.y = bb["yaw"]
	add_child(board)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	var bw: float = clampf(fs.x * 0.45, 10.0, 20.0)
	pm.size = Vector3(bw, 1.7, 0.12)
	pm.material = _color_material(Color(0.05, 0.05, 0.07), 0.4)
	panel.mesh = pm
	board.add_child(panel)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame_mat.albedo_color = col
	frame_mat.emission_enabled = true
	frame_mat.emission = col
	frame_mat.emission_energy_multiplier = 2.2
	for fy in [-0.92, 0.92]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(bw + 0.3, 0.08, 0.14)
		bm.material = frame_mat
		bar.mesh = bm
		bar.position = Vector3(0, fy, 0)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		board.add_child(bar)
	# Holo-sign life: the frame breathes, and every few seconds the panel
	# stutters like a failing projector — signage reads as powered, not painted.
	var pulse := create_tween().set_loops()
	pulse.tween_property(frame_mat, "emission_energy_multiplier", 1.5, randf_range(1.6, 2.4)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(frame_mat, "emission_energy_multiplier", 2.6, randf_range(1.6, 2.4)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_callback(func():
		if randf() < 0.3:
			frame_mat.emission_energy_multiplier = 0.4) # one-frame dropout
	var title := Label3D.new()
	title.text = str(def.get("sign", def.get("name", "OCCUPIED ZONE"))).to_upper()
	title.font_size = 96
	title.pixel_size = 0.012
	title.modulate = Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5)
	title.outline_size = 14
	title.outline_modulate = Color(0, 0, 0, 0.85)
	title.position = Vector3(0, 0, 0.09)
	board.add_child(title)
	# -- propaganda slogans scattered on the other walls --
	# The level's own slogans lead; any spare wall space is filled from a shared
	# pool of AI-doctrine graffiti so every sector drips with machine ideology.
	var slogans: Array = def.get("slogans", []).duplicate()
	var spots := [[1, -0.45], [2, 0.3], [3, -0.3], [1, 0.5], [2, -0.55], [3, 0.6]]
	var pool := AI_SLOGANS.duplicate()
	pool.shuffle()
	for s in pool:
		if slogans.size() >= spots.size():
			break
		if not slogans.has(s):
			slogans.append(s)
	for i in mini(slogans.size(), spots.size()):
		var sp: Array = spots[i]
		var wp := _wall_point(fs, sp[0], sp[1], 4.35, 0.52)
		var lbl := Label3D.new()
		lbl.text = str(slogans[i])
		lbl.font_size = 52
		lbl.pixel_size = 0.01
		lbl.modulate = col.lerp(Color.WHITE, 0.35)
		lbl.outline_size = 10
		lbl.outline_modulate = Color(0, 0, 0, 0.8)
		lbl.position = wp["pos"]
		lbl.rotation.y = wp["yaw"]
		add_child(lbl)

# ---------- grime + infrastructure detail ----------

## Weathering streaks on the perimeter walls: a handful of stretched dark
## decals (the shared procedural scorch texture) at varying heights/widths.
## Walls stop reading as freshly-printed geometry.
func _build_grime(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var count := int(8 * density)
	for i in count:
		var wp := _wall_point(fs, i % 4, randf_range(-0.9, 0.9), randf_range(1.2, 4.2), 0.4)
		var d := Decal.new()
		d.texture_albedo = ScorchMark._scorch_texture()
		d.size = Vector3(randf_range(1.2, 2.8), 1.0, randf_range(2.2, 4.5))
		d.modulate = Color(1, 1, 1, randf_range(0.25, 0.5))
		add_child(d)
		d.position = wp["pos"]
		# Project into the wall: decals beam down local -Y, so pitch the box
		# to face the wall, then roll randomly for variety.
		d.rotation.y = wp["yaw"]
		d.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		d.rotate_object_local(Vector3.UP, randf() * TAU)

## Cover blocks get a faint edge-lit trim along their top face in the theme
## color — cover reads at a glance even in the darkest arenas.
func _build_cover_trim(def: Dictionary) -> void:
	var col := _theme_color(def)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.9 # subtle — outline, not signage
	# Greebles (corner posts, vent grille, accent groove, status pips) follow the
	# detail tier like the wall trim: they turn the bare cover blocks into machined
	# consoles. LOW tier skips them; the cheap top-rim outline below always runs.
	var density := 1.0
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	# One shared accent material for every cover crate, breathing in sync like the
	# wall strips — the cover reads as powered, not painted. Built once, animated once.
	var accent_mat := StandardMaterial3D.new()
	accent_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	accent_mat.albedo_color = col
	accent_mat.emission_enabled = true
	accent_mat.emission = col
	accent_mat.emission_energy_multiplier = 0.8
	var atw := create_tween().set_loops()
	atw.tween_property(accent_mat, "emission_energy_multiplier", 0.4, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	atw.tween_property(accent_mat, "emission_energy_multiplier", 1.0, 2.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# One shared pip material for every cover box in the level (was built fresh
	# per box in _dress_cover_box before), and per-box backplate/slat/band/pip
	# elements are collected here and batched via _box_multimesh once at the
	# end — a level can have dozens of cover crates, each previously adding 13
	# individual draw calls (4 corner posts stay individual: they're beveled,
	# and _box_multimesh's shared unit cube would flatten that chamfer).
	var pip_mat := StandardMaterial3D.new()
	pip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pip_mat.albedo_color = col
	pip_mat.emission_enabled = true
	pip_mat.emission = col
	pip_mat.emission_energy_multiplier = 4.0
	var backplates: Array = []
	var slats: Array = []
	var bands: Array = []
	var pips: Array = []
	for w in def.get("walls", []):
		var pos: Vector3 = w["pos"]
		var size: Vector3 = w["size"]
		if size.y > 5.0:
			continue # interior dividers reach the ceiling; trim only the cover
		if w.get("_breakable", false):
			continue # BreakableCover dresses itself so its trim leaves with it
		var top := pos.y + size.y * 0.5 + 0.015
		for edge in [
				[Vector3(pos.x, top, pos.z - size.z * 0.5), Vector3(size.x, 0.03, 0.05)],
				[Vector3(pos.x, top, pos.z + size.z * 0.5), Vector3(size.x, 0.03, 0.05)],
				[Vector3(pos.x - size.x * 0.5, top, pos.z), Vector3(0.05, 0.03, size.z)],
				[Vector3(pos.x + size.x * 0.5, top, pos.z), Vector3(0.05, 0.03, size.z)]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = edge[1]
			bm.material = m
			mi.mesh = bm
			mi.position = edge[0]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
		# Machined detailing for compact, roughly-cubic cover crates only — long
		# barriers and tall maze dividers keep just the rim (a big grille/pip row
		# would read wrong on a 7-14 m wall).
		if density > 0.0 and size.y <= 4.5 and maxf(size.x, size.z) <= 4.0 and minf(size.x, size.z) >= 1.0:
			_dress_cover_box(pos, size, accent_mat, backplates, slats, bands, pips)
	_box_multimesh(backplates, MAT_SEAM, false)
	_box_multimesh(slats, MAT_TRIM, false)
	_box_multimesh(bands, accent_mat, false)
	_box_multimesh(pips, pip_mat, false)

## Turns a bare cover block into a piece of machinery: four dark corner posts (a
## framed-cabinet read), a recessed vent grille on the face toward the arena
## centre, a near-flush theme-coloured accent groove around the body, and a row
## of bright status pips beside the grille. All visual-only (no colliders).
func _dress_cover_box(pos: Vector3, size: Vector3, accent: Material,
		backplates: Array, slats_out: Array, bands: Array, pips: Array) -> void:
	var half := size * 0.5
	# Front = the face toward the arena centre (origin) — what the player approaches.
	var to_origin := Vector3(0, pos.y, 0) - pos
	var on_x := absf(to_origin.x) > absf(to_origin.z)
	var face_n: Vector3 = (Vector3(signf(to_origin.x), 0, 0) if on_x else Vector3(0, 0, signf(to_origin.z)))
	if face_n.length() < 0.5:
		face_n = Vector3(0, 0, 1)
		on_x = false
	var depth := half.x if on_x else half.z
	var width := half.z if on_x else half.x # in-plane horizontal half-extent
	var face_yaw := 0.0 if on_x else PI * 0.5
	var face_center := pos + face_n * (depth + 0.01)

	# 1) Four vertical corner posts.
	var post_w := 0.16
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := _beveled_box(Vector3(post_w, size.y, post_w))
			post.material = MAT_TRIM
			_add_detail_mesh(post, Vector3(pos.x + sx * (half.x - post_w * 0.4), pos.y, pos.z + sz * (half.z - post_w * 0.4)), 0.0)

	# 2) Recessed vent grille (dark backplate + horizontal slats) on the front face.
	# Collected into the caller's shared arrays and drawn as one MultiMesh per
	# element type across the whole level, instead of one draw call per box —
	# a level can have dozens of cover crates, each contributing 6 of these.
	var grille_w := minf(width * 1.4, width * 2.0 - 0.5)
	backplates.append({"pos": face_center + Vector3(0, -size.y * 0.05, 0), "size": Vector3(grille_w, size.y * 0.5, 0.04), "yaw": face_yaw})
	var n_slats := 5
	for i in n_slats:
		var sy := -size.y * 0.05 + (float(i) / float(n_slats - 1) - 0.5) * size.y * 0.42
		slats_out.append({"pos": face_center + Vector3(0, sy, 0) + face_n * 0.02, "size": Vector3(grille_w - 0.1, 0.05, 0.07), "yaw": face_yaw})

	# 3) Theme accent groove around all four faces, at mid-body, near flush.
	#    Uses the shared breathing material so all cover pulses in sync.
	var band_dy := half.y * 0.3
	for nrm in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var nx := absf(nrm.x) > 0.5
		var bd := half.x if nx else half.z
		var bw := (half.z if nx else half.x) * 2.0 - post_w * 2.2
		bands.append({"pos": pos + nrm * (bd + 0.006) + Vector3(0, band_dy, 0), "size": Vector3(bw, 0.05, 0.015), "yaw": 0.0 if nx else PI * 0.5})

	# 4) Status pips: a short row of bright theme-coloured lights by the grille top.
	var tangent := Vector3(0, 0, 1) if on_x else Vector3(1, 0, 0)
	for i in 3:
		pips.append({"pos": face_center + tangent * (width - 0.35 - float(i) * 0.28) + Vector3(0, half.y - 0.3, 0) + face_n * 0.02, "size": Vector3(0.12, 0.12, 0.05), "yaw": face_yaw})

## Panel seams ruled across interior floors: thin recess-dark strips every few
## metres in both axes. Breaks the monotony of a large single-material slab and
## makes the floor read as constructed deck plating. A handful of long boxes.
func _build_floor_seams(def: Dictionary) -> void:
	if def.get("open_sky", false):
		return # outdoor asphalt/dirt isn't panelled
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	# A dark recessed seam with a thin theme-coloured glow line on top, so interior
	# floors read as a lit tech-grid (a data-centre lattice) instead of a flat
	# sheet of colour. The glow tints toward white so it reads on any floor colour.
	var dark := _color_material(Color(0.06, 0.065, 0.08), 0.9)
	var glow := StandardMaterial3D.new()
	var tc: Color = _theme_color(def).lerp(Color(1, 1, 1), 0.35)
	glow.albedo_color = tc
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = tc
	glow.emission_energy_multiplier = 1.6
	var spacing := 6.5
	var xs: Array[float] = []
	var zs: Array[float] = []
	# Batched: the whole tech-grid lattice is hundreds of identical thin strips, so
	# collect them per-material and draw each material in one MultiMesh call instead
	# of one MeshInstance per strip (visually identical; ~120 draws -> 3).
	var dark_boxes: Array = []
	var glow_boxes: Array = []
	var x := -fs.x * 0.5 + spacing
	while x < fs.x * 0.5 - 1.0:
		dark_boxes.append({"pos": Vector3(x, 0.008, 0), "size": Vector3(0.16, 0.016, fs.y - 1.4)})
		glow_boxes.append({"pos": Vector3(x, 0.013, 0), "size": Vector3(0.045, 0.018, fs.y - 1.4)})
		xs.append(x)
		x += spacing
	var z := -fs.y * 0.5 + spacing
	while z < fs.y * 0.5 - 1.0:
		dark_boxes.append({"pos": Vector3(0, 0.008, z), "size": Vector3(fs.x - 1.4, 0.016, 0.16)})
		glow_boxes.append({"pos": Vector3(0, 0.013, z), "size": Vector3(fs.x - 1.4, 0.018, 0.045)})
		zs.append(z)
		z += spacing
	# Brighter "data node" pips where the grid lines cross — a touch of polish
	# that sells the lattice and catches the bloom.
	var node := StandardMaterial3D.new()
	node.albedo_color = tc
	node.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.emission_enabled = true
	node.emission = tc
	node.emission_energy_multiplier = 3.2
	var node_boxes: Array = []
	for nx in xs:
		for nz in zs:
			node_boxes.append({"pos": Vector3(nx, 0.015, nz), "size": Vector3(0.22, 0.02, 0.22)})
	_box_multimesh(dark_boxes, dark, false)
	_box_multimesh(glow_boxes, glow, false)
	_box_multimesh(node_boxes, node, false)

func _seam_strip(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Draw many identical-material boxes in a single MultiMesh draw call instead of
## one MeshInstance3D each — a visually-free draw-call cut for the dense decorative
## lattices the builder scatters (floor seams, skyline, etc.). Each box entry is
## {pos, size, yaw?}; a unit cube is scaled per instance, so varying sizes are fine.
func _box_multimesh(boxes: Array, mat: Material, cast_shadow: bool) -> void:
	if boxes.is_empty():
		return
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cube
	mm.instance_count = boxes.size()
	for i in boxes.size():
		var b: Dictionary = boxes[i]
		var basis := Basis(Vector3.UP, b.get("yaw", 0.0)).scaled(b["size"])
		mm.set_instance_transform(i, Transform3D(basis, b["pos"]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

## Dark mirror-finish puddles on the floor — cheap, and they pay off the SSR
## pass with real reflections of the emissive strips and robot glow.
func _build_puddles(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("detail_scale") and gs.detail_scale() <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var count := int(maxf(fs.x, fs.y) / 7.0)
	for i in count:
		var p := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(randf_range(1.6, 3.6), randf_range(1.2, 2.8))
		p.mesh = pm
		p.position = Vector3(randf_range(-fs.x * 0.42, fs.x * 0.42), 0.012, randf_range(-fs.y * 0.42, fs.y * 0.42))
		p.rotation.y = randf() * TAU
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.add_to_group("puddle_meshes")
		add_child(p)
		if gs and gs.has_method("apply_puddle_material_to_node"):
			gs.apply_puddle_material_to_node(p)

## Interior ceiling infrastructure: parallel dark conduit pipes running the
## length of the room with sparse glowing junction collars. Visual only.
func _build_pipes(def: Dictionary) -> void:
	if def.get("open_sky", false):
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var col := _theme_color(def)
	var pipe_mat := MAT_TRIM
	var collar_mat := StandardMaterial3D.new()
	collar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	collar_mat.albedo_color = col
	collar_mat.emission_enabled = true
	collar_mat.emission = col
	collar_mat.emission_energy_multiplier = 1.8
	for i in 3:
		var x := fs.x * (-0.32 + 0.32 * i)
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09 + 0.04 * (i % 2)
		cm.bottom_radius = cm.top_radius
		cm.height = fs.y - 2.0
		cm.radial_segments = 8
		pipe.mesh = cm
		pipe.material_override = pipe_mat
		pipe.rotation.x = PI * 0.5 # lay it along Z
		pipe.position = Vector3(x, WALL_HEIGHT - 0.35 - 0.18 * i, 0)
		add_child(pipe)
		for j in 3:
			var collar := MeshInstance3D.new()
			var km := CylinderMesh.new()
			km.top_radius = cm.top_radius + 0.04
			km.bottom_radius = km.top_radius
			km.height = 0.12
			km.radial_segments = 8
			km.material = collar_mat
			collar.mesh = km
			collar.rotation.x = PI * 0.5
			collar.position = pipe.position + Vector3(0, 0, fs.y * (-0.3 + 0.3 * j))
			collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(collar)

## Working-facility dressing for interiors: cables slung under the ceiling,
## ceiling vent grilles, wall-mounted vents / junction boxes / conduit risers,
## and painted floor hazard chevrons by the perimeter. All visual-only
## (cast_shadow off, no colliders) so the navmesh and gameplay are untouched;
## counts scale with the graphics-tier detail density, like the other dressing.
func _build_facility_detail(def: Dictionary) -> void:
	if def.get("open_sky", false):
		return  # interiors only — these read as inside-a-building fittings
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	_facility_cables(hx, hz, density)
	_facility_ceiling_vents(hx, hz, density)
	_facility_wall_fittings(fs, density)
	_facility_floor_hazard(hx, hz, density)

## Hot wire/coolant lines slung between ceiling anchors, sagging under gravity —
## a couple carry a faint emissive node so the room reads as powered.
func _facility_cables(hx: float, hz: float, density: float) -> void:
	var n := int(round(3 + 4 * density))
	var seed_v := 0.0
	for i in n:
		seed_v = float(i) * 1.6180339
		var ay := WALL_HEIGHT - randf_range(0.15, 0.7)
		var a := Vector3(randf_range(-hx + 2.5, hx - 2.5), ay, randf_range(-hz + 2.5, hz - 2.5))
		var b := a + Vector3(randf_range(-9.0, 9.0), randf_range(-0.4, 0.4), randf_range(-9.0, 9.0))
		b.x = clampf(b.x, -hx + 2.0, hx - 2.0)
		b.z = clampf(b.z, -hz + 2.0, hz - 2.0)
		b.y = clampf(b.y, 2.6, WALL_HEIGHT - 0.1)
		var sag := randf_range(0.6, 1.7)
		var hot := i % 4 == 0
		_hang_cable(a, b, sag, hot)

func _hang_cable(a: Vector3, b: Vector3, sag: float, hot: bool) -> void:
	var mat := MAT_SEAM if not hot else _emissive_material(Color(0.9, 0.45, 0.15), 1.4)
	var segs := 7
	var prev := a
	for s in range(1, segs + 1):
		var t := float(s) / float(segs)
		var p := a.lerp(b, t)
		p.y -= sag * (1.0 - pow(2.0 * t - 1.0, 2.0))  # parabolic droop, 0 at the ends
		_strut(prev, p, 0.035, mat)
		prev = p

## Recessed vent grilles set into the ceiling — a dark frame with bright slats.
func _facility_ceiling_vents(hx: float, hz: float, density: float) -> void:
	var n := int(round(2 + 2 * density))
	for i in n:
		var c := Vector3(randf_range(-hx + 4, hx - 4), WALL_HEIGHT - 0.18, randf_range(-hz + 4, hz - 4))
		var w := randf_range(1.2, 2.2)
		var dgth := randf_range(0.9, 1.6)
		var frame := BoxMesh.new()
		frame.size = Vector3(w, 0.22, dgth)
		frame.material = MAT_TRIM
		_add_detail_mesh(frame, c, 0.0)
		# A few lighter slats across the opening.
		var slats := 4
		for sidx in slats:
			var slat := BoxMesh.new()
			slat.size = Vector3(w * 0.86, 0.06, 0.06)
			slat.material = MAT_PROP
			var zoff := lerpf(-dgth * 0.34, dgth * 0.34, float(sidx) / float(slats - 1))
			_add_detail_mesh(slat, c + Vector3(0, -0.06, zoff), 0.0)

## Vent grilles, junction boxes (with a status LED) and conduit risers fixed to
## the inner faces of the four perimeter walls.
func _facility_wall_fittings(fs: Vector2, density: float) -> void:
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var walls := [
		{"c": Vector3(0, 0, -hz + 0.55), "n": Vector3(0, 0, 1), "len": fs.x, "yaw": 0.0},
		{"c": Vector3(0, 0, hz - 0.55), "n": Vector3(0, 0, -1), "len": fs.x, "yaw": PI},
		{"c": Vector3(-hx + 0.55, 0, 0), "n": Vector3(1, 0, 0), "len": fs.y, "yaw": PI * 0.5},
		{"c": Vector3(hx - 0.55, 0, 0), "n": Vector3(-1, 0, 0), "len": fs.y, "yaw": -PI * 0.5},
	]
	var step := 9.0 / maxf(density, 0.34)
	# Collected per shared-material batch instead of one MeshInstance3D per
	# fitting — a facility wall can carry dozens of vents/LEDs/blinkenlights,
	# each previously its own draw call. Batched via _box_multimesh (the same
	# technique the floor tech-grid already uses). Junction boxes/server plates
	# stay individual: they use _beveled_box, and _box_multimesh's shared unit
	# cube would flatten their chamfered edges.
	var vent_frames: Array = []
	var vent_slats: Array = []
	var leds: Dictionary = {}   # palette index -> Array of box dicts
	var dots: Dictionary = {}   # palette index -> Array of box dicts
	var led_palette := [Color(0.3, 1, 0.4), Color(1, 0.7, 0.2), Color(1, 0.3, 0.3)]
	var dot_palette := [Color(0.3, 1, 0.45), Color(0.3, 0.7, 1), Color(1, 0.75, 0.2), Color(1, 0.35, 0.3)]

	for w in walls:
		var c: Vector3 = w["c"]
		var n: Vector3 = w["n"]
		var length: float = w["len"]
		var yaw: float = w["yaw"]
		var along := Vector3(0, 0, 1).rotated(Vector3.UP, yaw)  # runs along the wall
		var x := -length * 0.5 + 3.0
		var k := 0
		while x <= length * 0.5 - 3.0:
			var base := c + along * x
			match k % 4:
				0:  # vent grille at chest height
					vent_frames.append({"pos": base + n * 0.08 + Vector3(0, 2.0, 0), "size": Vector3(1.1, 0.8, 0.12), "yaw": yaw})
					for s in 3:
						vent_slats.append({"pos": base + n * 0.12 + Vector3(0, 1.78 + s * 0.22, 0), "size": Vector3(0.95, 0.07, 0.05), "yaw": yaw})
				1:  # junction box with a small status LED
					var jb := _beveled_box(Vector3(0.5, 0.65, 0.22))
					jb.material = MAT_PROP_B
					_add_detail_mesh(jb, base + n * 0.11 + Vector3(0, 1.7, 0), yaw)
					var li := k % 3
					if not leds.has(li):
						leds[li] = []
					leds[li].append({"pos": base + n * 0.2 + Vector3(0, 1.86, 0), "size": Vector3(0.09, 0.09, 0.05), "yaw": yaw})
				2:  # conduit riser up the wall with bracket bumps
					var pipe := CylinderMesh.new()
					pipe.top_radius = 0.07
					pipe.bottom_radius = 0.07
					pipe.height = WALL_HEIGHT - 1.2
					pipe.radial_segments = 8
					pipe.material = MAT_PROP
					var pm := MeshInstance3D.new()
					pm.mesh = pipe
					pm.position = base + n * 0.12 + Vector3(0, (WALL_HEIGHT - 1.2) * 0.5 + 0.4, 0)
					pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					add_child(pm)
				3:  # a powered server/status panel: dark plate studded with blinkenlights
					var plate := _beveled_box(Vector3(1.3, 1.4, 0.12))
					plate.material = MAT_SEAM
					_add_detail_mesh(plate, base + n * 0.08 + Vector3(0, 2.2, 0), yaw)
					for row in 4:
						for coli in 3:
							# A scattered on/off + colour pattern so panels read distinct.
							if (row * 3 + coli + k) % 4 == 0:
								continue
							var di := (row + coli + k) % dot_palette.size()
							if not dots.has(di):
								dots[di] = []
							var dx := lerpf(-0.42, 0.42, coli / 2.0)
							var dy := lerpf(1.72, 2.68, row / 3.0)
							dots[di].append({"pos": base + n * 0.16 + along * dx + Vector3(0, dy, 0), "size": Vector3(0.1, 0.1, 0.04), "yaw": yaw})
			x += step
			k += 1

	_box_multimesh(vent_frames, MAT_TRIM, false)
	_box_multimesh(vent_slats, MAT_PROP, false)
	for li in leds:
		_box_multimesh(leds[li], _emissive_material(led_palette[li], 2.4), false)
	for di in dots:
		_box_multimesh(dots[di], _emissive_material(dot_palette[di], 2.6), false)

## Painted hazard chevrons inset from the perimeter — emissive caution stripes
## that catch the level's lighting and sell an industrial deck. A ">" of two
## angled slabs, laid flat, pointing into the room from each wall.
func _facility_floor_hazard(hx: float, hz: float, density: float) -> void:
	var mat := _emissive_material(Color(0.95, 0.74, 0.08), 1.5)
	# `fwd` points from the wall into the room; lay a chevron opening toward it.
	var stripe := func(center: Vector3, fwd: Vector3):
		var base_yaw := atan2(fwd.x, fwd.z)
		for sgn in [-1.0, 1.0]:
			var arm := BoxMesh.new()
			arm.size = Vector3(1.15, 0.05, 0.26)
			arm.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = arm
			var yaw: float = base_yaw + sgn * deg_to_rad(40.0)
			# Offset each arm sideways so their inner ends meet at the chevron tip.
			var side: Vector3 = Vector3(cos(base_yaw), 0, -sin(base_yaw)) * sgn * 0.42
			mi.position = center + Vector3(0, 0.05, 0) + side
			mi.rotation.y = yaw
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	var inset := 2.6
	var count := int(round(clampf(hx / 3.5, 3, 8) * clampf(density, 0.45, 1.0)))
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var fx := lerpf(-hx + 4.0, hx - 4.0, t)
		var fz := lerpf(-hz + 4.0, hz - 4.0, t)
		stripe.call(Vector3(fx, 0, -hz + inset), Vector3(0, 0, 1))   # -Z wall -> +Z
		stripe.call(Vector3(fx, 0, hz - inset), Vector3(0, 0, -1))   # +Z wall -> -Z
		stripe.call(Vector3(-hx + inset, 0, fz), Vector3(1, 0, 0))   # -X wall -> +X
		stripe.call(Vector3(hx - inset, 0, fz), Vector3(-1, 0, 0))   # +X wall -> -X

## A short oriented cylinder spanning a->b (used for slung cables). Visual only.
func _strut(a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = l
	cyl.radial_segments = 6
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis := Basis.looking_at(d / l, up) * Basis(Vector3.RIGHT, PI * 0.5)  # cylinder runs along +Y
	mi.transform = Transform3D(basis, (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## A cached unshaded-ish emissive material (panel LEDs, hazard paint, hot cables).
static var _emissive_mat_cache: Dictionary = {}

## Cached by (color, energy) — same reasoning as _color_material: detail passes
## request the same handful of LED/blinkenlight colours across many fittings.
func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color, energy]
	if _emissive_mat_cache.has(key):
		return _emissive_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_emissive_mat_cache[key] = m
	return m

## Scatter volumetric-billboard trees across an outdoor level (def "trees": N).
## Trees are visual-only (no collider — the navmesh is already baked) and avoid
## the spawn/exit, the road corridors on street levels, and building/cover
## footprints so they don't sprout through a house. Count scales with detail tier.
func _build_trees(def: Dictionary) -> void:
	if not def.get("open_sky", false):
		return
	var count := int(def.get("trees", 0))
	if count <= 0:
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	count = int(round(count * clampf(density, 0.4, 1.2)))
	var fs: Vector2 = def.get("floor_size", Vector2(60, 60))
	var hx := fs.x * 0.5 - 2.0
	var hz := fs.y * 0.5 - 2.0
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var exitp: Vector3 = def.get("exit", Vector3.ZERO)
	var streets: bool = def.get("streets", false)
	var blockers: Array = []
	for key in ["buildings", "walls"]:
		for e in def.get(key, []):
			if e.has("pos") and e.has("size"):
				blockers.append([e["pos"], e["size"]])
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 10:
		attempts += 1
		var x := randf_range(-hx, hx)
		var z := randf_range(-hz, hz)
		var p := Vector3(x, 0, z)
		if Vector2(x - spawn.x, z - spawn.z).length() < 7.0:
			continue
		if Vector2(x - exitp.x, z - exitp.z).length() < 7.0:
			continue
		# Keep off the carriageways/intersection on street levels.
		if streets and (absf(x) < 7.0 or absf(z) < 7.0):
			continue
		var blocked := false
		for b in blockers:
			var bp: Vector3 = b[0]
			var bs: Vector3 = b[1]
			if absf(x - bp.x) < bs.x * 0.5 + 1.5 and absf(z - bp.z) < bs.z * 0.5 + 1.5:
				blocked = true
				break
		if blocked:
			continue
		var size := randf_range(3.2, 5.8)
		var tree := VolumetricTree.make(size)
		tree.position = Vector3(x, size * 0.5, z)
		add_child(tree)
		# Soft contact-shadow blob so the billboard tree reads as grounded.
		var shadow := VolumetricTree.ground_shadow(size)
		shadow.position = Vector3(x, 0.03, z)
		add_child(shadow)
		placed += 1

## Street dressing for road/suburb levels (def "streets": true): painted lane
## lines + a crossroads through the centre, a crosswalk on each approach, a marked
## parking lot off to one side, and a few traffic signs. All flat paint (y≈0.02)
## or thin visual-only posts — no colliders, so the navmesh/gameplay are untouched.
func _build_streets(def: Dictionary) -> void:
	if not def.get("streets", false):
		return
	var fs: Vector2 = def.get("floor_size", Vector2(60, 60))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var white := _road_paint(Color(0.86, 0.86, 0.8))
	var yellow := _road_paint(Color(0.92, 0.74, 0.12))
	var half_road := 5.0  # road half-width (each carriageway ~5 m)

	# Crossroads through the origin: a dashed centre line + solid edge lines on
	# both the N-S and E-W roads.
	for axis in [0, 1]: # 0 = road runs along Z (x fixed), 1 = along X
		var along_len: float = (hz if axis == 0 else hx) * 2.0 - 2.0
		var yaw := 0.0 if axis == 0 else PI * 0.5
		# Dashed yellow centre line.
		var dash := 1.6
		var gap := 1.4
		var n := int(along_len / (dash + gap))
		for i in n:
			var t: float = -along_len * 0.5 + (dash + gap) * (float(i) + 0.5)
			# Leave the intersection box itself unpainted.
			if absf(t) < half_road + 1.0:
				continue
			var c: Vector3 = Vector3(0, 0.02, t) if axis == 0 else Vector3(t, 0.02, 0)
			_paint_stripe(c, Vector2(0.2, dash), yaw, yellow)
		# Solid white edge lines.
		for side in [-1.0, 1.0]:
			var off: float = side * half_road
			var c2: Vector3 = Vector3(off, 0.02, 0) if axis == 0 else Vector3(0, 0.02, off)
			_paint_stripe(c2, Vector2(0.16, along_len), yaw, white)

	# Crosswalk zebra stripes on each of the four approaches to the intersection.
	var approaches := [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	for app in approaches.size():
		var dir: Vector3 = approaches[app]
		var base: Vector3 = dir * (half_road + 1.6)
		var perp := Vector3(dir.z, 0, dir.x)
		for s in range(-3, 4):
			var c: Vector3 = base + perp * (float(s) * 0.8) + Vector3(0, 0.02, 0)
			var sz: Vector2 = Vector2(0.45, 2.2) if absf(dir.z) > 0.5 else Vector2(2.2, 0.45)
			_paint_stripe(c, sz, 0.0, white)

	_build_parking_lot(Vector3(hx * 0.5, 0, -hz * 0.5), white)
	_build_traffic_signs(def, hx, hz)

## A marked parking lot: a row of stalls (back line + dividers) on the tarmac.
func _build_parking_lot(center: Vector3, paint: Material) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	var stalls := int(round(6 * clampf(density, 0.4, 1.2)))
	var stall_w := 2.6
	var depth := 5.0
	var span := stall_w * stalls
	# Back line.
	_paint_stripe(center + Vector3(0, 0.02, -depth * 0.5), Vector2(span + 0.2, 0.16), 0.0, paint)
	# Stall dividers.
	for i in stalls + 1:
		var x := center.x - span * 0.5 + stall_w * i
		_paint_stripe(Vector3(x, 0.02, center.z), Vector2(0.14, depth), 0.0, paint)

## A handful of roadside traffic signs (stop / warning / parking) on thin poles,
## set back from the carriageways near the corners. Visual only.
func _build_traffic_signs(def: Dictionary, hx: float, hz: float) -> void:
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var exitp: Vector3 = def.get("exit", Vector3.ZERO)
	# (pos, kind) — set on the verges by the intersection and out by the lot/corners.
	# kinds: "stop" red, "warn" yellow diamond, "info" blue.
	var signs := [
		[Vector3(7.0, 0, 7.0), "stop"],
		[Vector3(-7.0, 0, 7.0), "warn"],
		[Vector3(hx * 0.5 - 4.0, 0, -hz * 0.5 + 4.0), "info"],
		[Vector3(-hx * 0.55, 0, hz * 0.3), "warn"],
	]
	for entry in signs:
		var pos: Vector3 = entry[0]
		if Vector2(pos.x - spawn.x, pos.z - spawn.z).length() < 5.0: continue
		if Vector2(pos.x - exitp.x, pos.z - exitp.z).length() < 5.0: continue
		_road_sign(pos, String(entry[1]))

func _road_sign(pos: Vector3, kind: String) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05; pole.bottom_radius = 0.06; pole.height = 2.2; pole.radial_segments = 6
	pole.material = MAT_TRIM
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.position = pos + Vector3(0, 1.1, 0)
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pm)
	var col := Color(0.85, 0.12, 0.1)
	var face := Color(0.95, 0.95, 0.95)
	match kind:
		"warn": col = Color(0.95, 0.78, 0.05); face = Color(0.1, 0.1, 0.1)
		"info": col = Color(0.1, 0.35, 0.8); face = Color(0.95, 0.95, 0.95)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.7, 0.06)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = col
	bmat.roughness = 0.5
	bmat.emission_enabled = true
	bmat.emission = col
	bmat.emission_energy_multiplier = 0.25 # reads at night without glowing
	bm.material = bmat
	board.mesh = bm
	board.position = pos + Vector3(0, 2.2, 0)
	if kind == "warn":
		board.rotation.z = PI * 0.25 # diamond
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(board)
	# A small painted glyph bar so the sign isn't a blank plate.
	var glyph := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.42, 0.1, 0.02)
	gm.material = _emissive_material(face, 0.2)
	glyph.mesh = gm
	glyph.position = pos + Vector3(0, 2.2, 0.04)
	glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glyph)

## A flat painted road marking: a thin slab laid on the tarmac. size is (x, z).
func _paint_stripe(center: Vector3, size_xz: Vector2, yaw: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size_xz.x, 0.04, size_xz.y)
	bm.material = mat
	mi.mesh = bm
	mi.position = center
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Road-paint material: matte white/yellow with a faint emission so the lines
## still read on a dark night street.
func _road_paint(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.12
	return m

## Street lamps down both verges of a "streets" crossroads. The dusk street
## levels only had the big area lights from "lights", which go dark past their
## range — this adds the actual sodium street lighting along the road so night
## approaches aren't pitch black between fixtures. Lamps sit 6 m off each road
## centreline (the carriageway half-width is 5 m, see _build_streets), spaced
## ~11 m apart, and skip the intersection itself plus the spawn/exit clearings.
func _build_streetlamps(def: Dictionary) -> void:
	if not def.get("streets", false):
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("detail_scale") and gs.detail_scale() <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(60, 60))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var exitp: Vector3 = def.get("exit", Vector3.ZERO)
	var verge := 6.0
	# Night levels (env "stars") get denser, brighter lamps so they own the
	# dark — dusk levels (suburb) keep the sparser, dimmer original spacing.
	var night: bool = def.get("env", {}).has("stars")
	var spacing: float = def.get("streetlamp_spacing", 8.5 if night else 11.0)
	var lamp_energy: float = def.get("streetlamp_energy", 3.2 if night else 2.6)

	# Candidate lamp (xz position, arm yaw). Yaw points the arm/head back at
	# the road centreline: N-S verge lamps face toward x=0, E-W verge lamps
	# face toward z=0.
	var candidates: Array = []
	for side in [-1.0, 1.0]:
		var x: float = side * verge
		var yaw := 0.0 if side < 0.0 else PI
		var length := hz * 2.0 - 12.0
		var count := maxi(2, int(round(length / spacing)))
		for i in count:
			var t: float = float(i) / float(maxi(count - 1, 1))
			candidates.append([Vector3(x, 0.0, -hz + 6.0 + length * t), yaw])
	for side in [-1.0, 1.0]:
		var z: float = side * verge
		var yaw := -PI * 0.5 if side < 0.0 else PI * 0.5
		var length := hx * 2.0 - 12.0
		var count := maxi(2, int(round(length / spacing)))
		for i in count:
			var t: float = float(i) / float(maxi(count - 1, 1))
			candidates.append([Vector3(-hx + 6.0 + length * t, 0.0, z), yaw])

	var placed := 0
	for c in candidates:
		var pos: Vector3 = c[0]
		var yaw: float = c[1]
		if Vector2(pos.x, pos.z).length() < 4.0:
			continue # keep the intersection itself clear
		if Vector2(pos.x - spawn.x, pos.z - spawn.z).length() < 5.0:
			continue
		if Vector2(pos.x - exitp.x, pos.z - exitp.z).length() < 5.0:
			continue
		# Every ~5th lamp flickers — occupation infrastructure failing — most
		# stay steady so the street doesn't feel uniformly broken.
		_add_streetlamp(pos, yaw, placed % 5 == 0, lamp_energy)
		placed += 1

## One street lamp: tapered pole, an arm reaching over the road with an
## emissive sodium head, and a matching OmniLight3D. A thin collider goes up
## before the deferred navmesh bake (same pattern as _add_light_pylon) so
## ground robots route around the post instead of clipping it.
func _add_streetlamp(pos: Vector3, yaw: float, flicker: bool, energy: float = 2.6) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation.y = yaw
	add_child(pivot)

	var pole_h := 4.2
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.11
	cm.height = pole_h
	cm.radial_segments = 8
	cm.material = _color_material(Color(0.16, 0.17, 0.2), 0.45)
	pole.mesh = cm
	pole.position = Vector3(0, pole_h * 0.5, 0)
	pivot.add_child(pole)

	# Solid: built before the navmesh bake, so robots path around the post.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.14
	shape.height = pole_h
	cs.shape = shape
	body.add_child(cs)
	body.position = pole.position
	pivot.add_child(body)

	var lamp_col := Color(1.0, 0.82, 0.5)
	var arm := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(0.7, 0.08, 0.08)
	ab.material = _color_material(Color(0.16, 0.17, 0.2), 0.45)
	arm.mesh = ab
	arm.position = Vector3(0.35, pole_h - 0.08, 0)
	arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(arm)

	var head := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(0.5, 0.12, 0.28)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = lamp_col
	hm.emission_enabled = true
	hm.emission = lamp_col
	hm.emission_energy_multiplier = 3.0
	hb.material = hm
	head.mesh = hb
	head.position = Vector3(0.68, pole_h - 0.16, 0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(head)

	var light := OmniLight3D.new()
	light.light_color = lamp_col
	light.light_energy = energy
	light.omni_range = 12.0
	light.shadow_enabled = false
	light.light_specular = 0.5
	light.position = head.position
	pivot.add_child(light)
	if flicker:
		_flicker_light(light)

## Open-air dressing for outdoor levels: utility poles strung with sagging power
## lines overhead (fills the empty sky-space), plus scattered cordon clutter —
## jersey barriers, traffic cones, bollards — hugging the perimeter. All
## visual-only; counts scale with the graphics-tier detail density.
func _build_outdoor_detail(def: Dictionary) -> void:
	if not def.get("open_sky", false):
		return  # outdoor only — complements the interior facility pass
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	_outdoor_powerlines(fs.x * 0.5, fs.y * 0.5, density)
	_outdoor_clutter(def, fs.x * 0.5, fs.y * 0.5, density)

## Utility poles down two opposite edges, strung with two sagging wires each span.
func _outdoor_powerlines(hx: float, hz: float, density: float) -> void:
	var pole_h := 6.5
	var n := int(round(3 + 2 * density))
	for side in [-1.0, 1.0]:
		var px: float = side * (hx - 2.5)
		var have_prev := false
		var prev_top := Vector3.ZERO
		for i in n:
			var pz := lerpf(-hz + 5.0, hz - 5.0, float(i) / float(maxi(n - 1, 1)))
			_utility_pole(Vector3(px, 0, pz), pole_h)
			var top := Vector3(px, pole_h, pz)
			if have_prev:
				for w in [-0.6, 0.6]:
					_hang_cable(prev_top + Vector3(0, -0.2, w), top + Vector3(0, -0.2, w), randf_range(0.5, 1.1), false)
			prev_top = top
			have_prev = true

func _utility_pole(base: Vector3, h: float) -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.12
	pole.bottom_radius = 0.15
	pole.height = h
	pole.radial_segments = 8
	pole.material = MAT_TRIM
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.position = base + Vector3(0, h * 0.5, 0)
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pm)
	var arm := BoxMesh.new()
	arm.size = Vector3(0.12, 0.12, 1.7)
	arm.material = MAT_TRIM
	_add_detail_mesh(arm, base + Vector3(0, h - 0.4, 0), 0.0)
	# Ceramic insulators at the crossarm ends.
	for zoff in [-0.6, 0.6]:
		var ins := CylinderMesh.new()
		ins.top_radius = 0.07; ins.bottom_radius = 0.09; ins.height = 0.2; ins.radial_segments = 6
		ins.material = MAT_PROP
		var im := MeshInstance3D.new()
		im.mesh = ins
		im.position = base + Vector3(0, h - 0.28, zoff)
		im.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(im)

## Scattered cordon clutter near the perimeter, kept clear of spawn/exit.
func _outdoor_clutter(def: Dictionary, hx: float, hz: float, density: float) -> void:
	var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
	var exitp: Vector3 = def.get("exit", Vector3.ZERO)
	var n := int(round(7 + 11 * density))
	for i in n:
		var pos := _perimeter_point(hx, hz)
		if Vector2(pos.x - spawn.x, pos.z - spawn.z).length() < 6.0:
			continue
		if Vector2(pos.x - exitp.x, pos.z - exitp.z).length() < 6.0:
			continue
		match i % 3:
			0: _traffic_cone(pos)
			1: _jersey_barrier(pos, randf() * TAU)
			_: _bollard(pos)

func _perimeter_point(hx: float, hz: float) -> Vector3:
	var inset := randf_range(2.0, 5.5)
	if randf() < 0.5:
		return Vector3(randf_range(-hx + 2.5, hx - 2.5), 0.0, (hz - inset) * (1.0 if randf() < 0.5 else -1.0))
	return Vector3((hx - inset) * (1.0 if randf() < 0.5 else -1.0), 0.0, randf_range(-hz + 2.5, hz - 2.5))

func _traffic_cone(pos: Vector3) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02; cone.bottom_radius = 0.19; cone.height = 0.52; cone.radial_segments = 10
	cone.material = _emissive_material(Color(1.0, 0.4, 0.07), 0.5)
	var cm := MeshInstance3D.new()
	cm.mesh = cone
	cm.position = pos + Vector3(0, 0.26, 0)
	cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cm)
	var band := CylinderMesh.new()
	band.top_radius = 0.13; band.bottom_radius = 0.15; band.height = 0.08; band.radial_segments = 10
	band.material = _emissive_material(Color(1, 1, 1), 0.6)
	_add_detail_mesh(band, pos + Vector3(0, 0.3, 0), 0.0)
	var pad := BoxMesh.new()
	pad.size = Vector3(0.42, 0.04, 0.42)
	pad.material = MAT_SEAM
	_add_detail_mesh(pad, pos + Vector3(0, 0.02, 0), 0.0)

func _jersey_barrier(pos: Vector3, yaw: float) -> void:
	var body := _beveled_box(Vector3(1.7, 0.85, 0.5))
	body.material = MAT_PROP_B
	_add_detail_mesh(body, pos + Vector3(0, 0.42, 0), yaw)
	# A diagonal hazard stripe band across the front faces.
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.55, 0.18, 0.02)
	stripe.material = _emissive_material(Color(0.95, 0.72, 0.06), 0.7)
	var n := Vector3(0, 0, 1).rotated(Vector3.UP, yaw)
	_add_detail_mesh(stripe, pos + n * 0.26 + Vector3(0, 0.5, 0), yaw)
	_add_detail_mesh(stripe.duplicate(), pos - n * 0.26 + Vector3(0, 0.5, 0), yaw)

func _bollard(pos: Vector3) -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.11; post.bottom_radius = 0.12; post.height = 0.95; post.radial_segments = 10
	post.material = _emissive_material(Color(0.9, 0.7, 0.1), 0.35)
	var bm := MeshInstance3D.new()
	bm.mesh = post
	bm.position = pos + Vector3(0, 0.48, 0)
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bm)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.13; cap.bottom_radius = 0.13; cap.height = 0.08; cap.radial_segments = 10
	cap.material = MAT_TRIM
	_add_detail_mesh(cap, pos + Vector3(0, 0.96, 0), 0.0)

## Battle-damage rubble piles hugging the wall bases: clustered gray chunks at
## random sizes/tilts. Pure dressing — no collision, navmesh ignores them.
func _build_rubble(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var mat := _color_material(Color(0.32, 0.31, 0.3), 0.9)
	var clusters := int(6 * density)
	for i in clusters:
		var wp := _wall_point(fs, i % 4, randf_range(-0.85, 0.85), 0.0, randf_range(1.0, 2.2))
		var base: Vector3 = wp["pos"]
		for j in 3 + randi() % 4:
			var chunk := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var s := randf_range(0.16, 0.55)
			bm.size = Vector3(s, s * randf_range(0.4, 0.8), s * randf_range(0.6, 1.2))
			bm.material = mat
			chunk.mesh = bm
			chunk.position = base + Vector3(randf_range(-0.8, 0.8), bm.size.y * 0.3, randf_range(-0.8, 0.8))
			chunk.rotation = Vector3(randf_range(-0.3, 0.3), randf() * TAU, randf_range(-0.3, 0.3))
			add_child(chunk)

## Weather (opt-in via env "weather": "rain" | "dust"). Rain falls in fast thin
## streaks across the whole arena; dust drifts as a wind-blown haze. Density-gated.
func _build_weather(def: Dictionary) -> void:
	var e: Dictionary = def.get("env", {})
	var w := str(e.get("weather", ""))
	if w == "":
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	if w == "rain":
		var p := CPUParticles3D.new()
		p.amount = int(320 * density)
		p.lifetime = 1.0
		p.preprocess = 1.0 # already raining on load
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(fs.x * 0.6, 0.5, fs.y * 0.6)
		p.direction = Vector3(0.05, -1, 0.0)
		p.spread = 1.5
		p.initial_velocity_min = 24.0
		p.initial_velocity_max = 30.0
		p.gravity = Vector3(0, -22.0, 0)
		var streak := BoxMesh.new()
		streak.size = Vector3(0.015, 0.55, 0.015) # thin vertical streak
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.albedo_color = Color(0.6, 0.7, 0.85, 0.5)
		streak.material = rm
		p.mesh = streak
		p.position = Vector3(0, 15.0, 0)
		p.name = "Weather" # a survive wave's "weather" gusts it (WeatherShift)
		add_child(p)
	elif w == "snow":
		# Slow, drifting, faintly-glowing flakes that sway as they settle — a soft
		# blizzard for frost levels. Much slower + fluffier + brighter than rain.
		var p := CPUParticles3D.new()
		p.amount = int(300 * density)
		p.lifetime = 7.0
		p.preprocess = 6.0 # already snowing on load
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(fs.x * 0.6, 3.0, fs.y * 0.6)
		p.direction = Vector3(0.25, -1.0, 0.12)
		p.spread = 12.0
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 2.4
		p.gravity = Vector3(0.35, -1.6, 0.2) # gentle wind-blown drift
		p.damping_min = 0.15
		p.damping_max = 0.5
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.6
		# Tumble each flake so they sway rather than slide straight down.
		p.angle_min = -180.0
		p.angle_max = 180.0
		p.angular_velocity_min = -50.0
		p.angular_velocity_max = 50.0
		var flake := SphereMesh.new()
		flake.radius = 0.05
		flake.height = 0.1
		flake.radial_segments = 5
		flake.rings = 3
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0.95, 0.98, 1.0, 0.9)
		sm.emission_enabled = true # catches the cold light so flakes twinkle
		sm.emission = Color(0.8, 0.9, 1.0)
		sm.emission_energy_multiplier = 0.6
		flake.material = sm
		p.mesh = flake
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(0, 13.0, 0)
		p.name = "Weather" # a survive wave's "weather" gusts it (WeatherShift)
		add_child(p)
	elif w == "dust":
		var p := CPUParticles3D.new()
		p.amount = int(180 * density)
		p.lifetime = 6.0
		p.preprocess = 4.0
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(fs.x * 0.6, 4.0, fs.y * 0.6)
		p.direction = Vector3(1, 0.05, 0.3)
		p.spread = 25.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0.6, -0.2, 0.2)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.6
		# Slow drift-spin so the wind-blown haze churns instead of sliding rigidly.
		p.angle_min = -180.0; p.angle_max = 180.0
		p.angular_velocity_min = -25.0; p.angular_velocity_max = 25.0
		var puff := SphereMesh.new()
		puff.radius = 0.25; puff.height = 0.5; puff.radial_segments = 5; puff.rings = 3
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_color = Color(e.get("fog", Color(0.5, 0.45, 0.38)).r, e.get("fog", Color(0.5, 0.45, 0.38)).g, e.get("fog", Color(0.5, 0.45, 0.38)).b, 0.12)
		puff.material = dm
		p.mesh = puff
		p.position = Vector3(0, 3.0, 0)
		p.name = "Weather" # a survive wave's "weather" gusts it (WeatherShift)
		add_child(p)

## Ambient ash (opt-in via env "ash": true): slow-drifting warm ember motes
## rising off a foundry/lava floor — small additive-emissive billboard quads
## that glow in the dark, drifting up and sideways on a lazy convection
## current. Density-gated (skipped at LOW / gpu_particles off falls back to
## CPUParticles3D), same pattern as _build_weather.
func _build_ash(def: Dictionary) -> void:
	var e: Dictionary = def.get("env", {})
	if not bool(e.get("ash", false)):
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var amount := int(60 * density)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# These levels are already a dominant warm-orange/red fog wash (foundry/lava
	# glow) — an ember the same hue as the backdrop reads as invisible without
	# help. A near-white hot core (like the flame material's core) plus
	# disabling fog on the additive quad (fog attenuates additive surfaces
	# toward the fog colour, same fix as the lightning bolt) keeps each mote a
	# bright, legible point instead of fading into the ambient glow.
	mat.albedo_color = Color(1.0, 0.85, 0.55, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.15)
	mat.emission_energy_multiplier = 7.0
	mat.disable_fog = true
	quad.material = mat
	# Same 0.6 coverage factor as _build_weather's rain box: reaches the
	# spawn/exit corners near the arena walls, not just the middle third.
	var box_ext := Vector3(fs.x * 0.6, 2.0, fs.y * 0.6)
	var use_gpu: bool = gs == null or bool(gs.get("gpu_particles_enabled"))
	if use_gpu:
		var p := GPUParticles3D.new()
		p.amount = amount
		p.lifetime = 8.0
		p.preprocess = 6.0
		p.local_coords = false
		p.draw_pass_1 = quad
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = box_ext
		pm.direction = Vector3(0.15, 1, 0.1) # lazy rise with a slight wind lean
		pm.spread = 20.0
		pm.initial_velocity_min = 0.5
		pm.initial_velocity_max = 1.0
		pm.gravity = Vector3(0.15, 0.05, 0.05)
		pm.scale_min = 0.7
		pm.scale_max = 1.6
		pm.angle_min = -180.0; pm.angle_max = 180.0
		pm.angular_velocity_min = -12.0; pm.angular_velocity_max = 12.0
		p.process_material = pm
		p.position = Vector3(0, 1.2, 0)
		# GPUParticles3D's auto-computed visibility AABB is sized for the
		# default small emission shape — it doesn't grow to fit a large custom
		# box + 8s of upward drift, so without an explicit AABB the whole
		# system gets frustum/AABB-culled and silently never renders.
		p.visibility_aabb = AABB(Vector3(-box_ext.x - 2.0, -3.0, -box_ext.z - 2.0),
			Vector3((box_ext.x + 2.0) * 2.0, 14.0, (box_ext.z + 2.0) * 2.0))
		add_child(p)
	else:
		var p := CPUParticles3D.new()
		p.amount = amount
		p.lifetime = 8.0
		p.preprocess = 6.0
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = box_ext
		p.direction = Vector3(0.15, 1, 0.1)
		p.spread = 20.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.0
		p.gravity = Vector3(0.15, 0.05, 0.05)
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.6
		p.angle_min = -180.0; p.angle_max = 180.0
		p.angular_velocity_min = -12.0; p.angular_velocity_max = 12.0
		p.mesh = quad
		p.position = Vector3(0, 1.2, 0)
		add_child(p)

## Storm lightning (opt-in via env "lightning": true, or automatic in "rain"
## weather): a hidden sky light periodically double-flashes the whole scene, with
## a thunderclap rolling in a beat later. The "reactive world lighting" cue.
var _storm_base: float = 24.0 ## arena half-extent; strikes land just past the wall

func _build_lightning(def: Dictionary) -> void:
	var e: Dictionary = def.get("env", {})
	if not (bool(e.get("lightning", false)) or str(e.get("weather", "")) in ["rain", "storm"]):
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	_storm_base = maxf(fs.x, fs.y) * 0.5
	var flash := DirectionalLight3D.new()
	flash.light_color = Color(0.82, 0.86, 1.0)
	flash.light_energy = 0.0
	flash.rotation_degrees = Vector3(-62, 35, 0)
	flash.shadow_enabled = false
	add_child(flash)
	_schedule_lightning(flash)

func _schedule_lightning(flash: DirectionalLight3D) -> void:
	var t := get_tree().create_timer(randf_range(5.0, 13.0))
	t.timeout.connect(func() -> void:
		if not is_instance_valid(flash) or not is_inside_tree():
			return
		_lightning_strike(flash)
		_schedule_lightning(flash))

func _lightning_strike(flash: DirectionalLight3D) -> void:
	# Ground the flash in the world: pick where THIS strike lands on the
	# skyline, aim the fill light from that bearing (so shadows and highlights
	# agree with the bolt you can see), and roll the thunder in later the
	# further away it hit. Turns "the screen blinked" into "lightning struck
	# over there".
	var bearing := randf() * TAU
	# Just past the arena wall: close enough to render through fog/exposure and
	# dominate the sky (a 100 m strike reads as a distant flicker; a 30 m one
	# reads as THE STORM IS HERE), with the wall hiding the ground contact.
	var dist := _storm_base + randf_range(5.0, 20.0)
	var ground := Vector3(sin(bearing) * dist, 0.0, cos(bearing) * dist)
	flash.rotation_degrees = Vector3(randf_range(-68, -48), rad_to_deg(bearing) + 180.0, 0)
	_spawn_bolt(ground)
	# A quick double-flicker — the characteristic stutter of a real strike.
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", randf_range(3.0, 5.0), 0.04)
	tw.tween_property(flash, "light_energy", 0.5, 0.06)
	tw.tween_property(flash, "light_energy", randf_range(2.0, 4.0), 0.04)
	tw.tween_property(flash, "light_energy", 0.0, 0.28)
	# Thunder rolls in after the flash — later and softer for distant strikes.
	var delay := 0.35 + dist * randf_range(0.010, 0.016)
	var d := get_tree().create_timer(delay)
	d.timeout.connect(func() -> void:
		if has_node("/root/AudioBus"):
			AudioBus.play_synth_ui("thunder", -3.0 - dist * 0.02, randf_range(0.9, 1.1)))

## The visible strike: a jagged additive-emissive bolt from cloud height down
## to the skyline point, with one mid-height fork, flashing out in ~0.3 s.
## ~15 thin boxes for a third of a second every 5-13 s — negligible cost.
func _spawn_bolt(ground: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Plain alpha blend, NOT additive: fog attenuates additive surfaces toward
	# zero (they can't blend toward the fog colour), so a distant additive bolt
	# vanishes into a bright storm sky. An opaque-white alpha surface with fog
	# disabled stays a hard bright channel at any range — like the real thing.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_fog = true
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.85, 1.0)
	mat.emission_energy_multiplier = 6.0
	# Distant strikes need a fatter core to survive perspective + exposure —
	# at 100 m a 1 m column is a dozen faint pixels; the glow halo of real
	# lightning reads metres wide from that far.
	var w_mult := 1.0 + ground.length() * 0.028
	# Main channel: wanders sideways on the way down, straightens near the hit.
	var top := ground + Vector3(randf_range(-22, 22), randf_range(55, 75), randf_range(-22, 22))
	var pts: Array[Vector3] = []
	var n := 11
	for i in n + 1:
		var t := float(i) / n
		var p := top.lerp(ground, t)
		if i > 0 and i < n:
			var wobble := 6.0 * (1.0 - absf(t - 0.5) * 1.2)
			p += Vector3(randf_range(-wobble, wobble), 0, randf_range(-wobble, wobble))
		pts.append(p)
	for i in n:
		var w := lerpf(1.1, 0.5, float(i) / n) * w_mult # tapers toward the ground
		_bolt_segment(root, pts[i], pts[i + 1], w, mat)
	# One fork: leaves the channel mid-height and dies in the air.
	var fi := 3 + randi() % 4
	var fp: Vector3 = pts[fi]
	for j in 3:
		var fq := fp + Vector3(randf_range(-9, 9), randf_range(-11, -6), randf_range(-9, 9))
		_bolt_segment(root, fp, fq, 0.45 * w_mult, mat)
		fp = fq
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, randf_range(0.25, 0.4)).set_delay(0.06)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, randf_range(0.25, 0.4)).set_delay(0.06)
	tw.chain().tween_callback(root.queue_free)

func _bolt_segment(parent: Node3D, a: Vector3, b: Vector3, w: float, mat: Material) -> void:
	var l := a.distance_to(b)
	if l < 0.01:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, l, w)
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var dn := (b - a) / l
	var up := Vector3.UP if absf(dn.y) < 0.9 else Vector3.RIGHT
	mi.global_transform = Transform3D(
		Basis.looking_at(dn, up) * Basis(Vector3.RIGHT, PI * 0.5), (a + b) * 0.5)

## Burning wreck fires (opt-in via def "fires"): each is a flickering flame, a
## buoyant smoke column that rises and lingers, a spray of embers, and a
## flickering warm light — the "warzone" read. def["fires"] = [{pos, scale?}].
## Density-gated (skipped on LOW) like the other dressing.
func _build_fires(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	for f in def.get("fires", []):
		var pos: Vector3 = f["pos"]
		var scl: float = f.get("scale", 1.0)
		var root := Node3D.new()
		add_child(root)
		root.position = pos

		# Flame: hot orange tongues licking upward.
		var flame := CPUParticles3D.new()
		flame.amount = int(30 * density)
		flame.lifetime = 0.5
		flame.preprocess = 0.5 # already lit on level load
		flame.local_coords = false
		flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		flame.emission_sphere_radius = 0.35 * scl
		flame.direction = Vector3.UP
		flame.spread = 16.0
		flame.initial_velocity_min = 1.6 * scl
		flame.initial_velocity_max = 3.4 * scl
		flame.gravity = Vector3(0, 2.0, 0)
		flame.scale_amount_min = 0.5 * scl
		flame.scale_amount_max = 1.1 * scl
		# 4.7 per-particle rotation: random start angle + flicker spin so the
		# tongues writhe instead of rising as identical blobs.
		flame.angle_min = -180.0; flame.angle_max = 180.0
		flame.angular_velocity_min = -120.0; flame.angular_velocity_max = 120.0
		var fcurve := Curve.new()
		fcurve.add_point(Vector2(0.0, 1.0)); fcurve.add_point(Vector2(1.0, 0.0))
		flame.scale_amount_curve = fcurve
		var fgrad := Gradient.new()
		fgrad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		fgrad.colors = PackedColorArray([Color(1.0, 0.9, 0.4, 1.0), Color(1.0, 0.45, 0.12, 0.9), Color(0.5, 0.1, 0.05, 0.0)])
		flame.color_ramp = fgrad
		var fmesh := SphereMesh.new()
		fmesh.radius = 0.18; fmesh.height = 0.36; fmesh.radial_segments = 6; fmesh.rings = 3
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fmat.vertex_color_use_as_albedo = true
		fmesh.material = fmat
		flame.mesh = fmesh
		root.add_child(flame)

		# Smoke column: buoyant grey billows that climb and fade.
		var smoke := CPUParticles3D.new()
		smoke.amount = int(18 * density)
		smoke.lifetime = 2.6
		smoke.preprocess = 2.4 # column already risen on level load
		smoke.local_coords = false
		smoke.direction = Vector3.UP
		smoke.spread = 18.0
		smoke.initial_velocity_min = 1.2 * scl
		smoke.initial_velocity_max = 2.6 * scl
		smoke.gravity = Vector3(0, 1.4, 0)
		smoke.scale_amount_min = 0.8 * scl
		smoke.scale_amount_max = 1.8 * scl
		# Slow tumble so the column reads as turbulent billows, not stacked balls.
		smoke.angle_min = -180.0; smoke.angle_max = 180.0
		smoke.angular_velocity_min = -45.0; smoke.angular_velocity_max = 45.0
		var scurve := Curve.new()
		scurve.add_point(Vector2(0.0, 0.3)); scurve.add_point(Vector2(1.0, 1.0))
		smoke.scale_amount_curve = scurve
		var sgrad := Gradient.new()
		sgrad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
		sgrad.colors = PackedColorArray([Color(0.5, 0.32, 0.2, 0.5), Color(0.22, 0.22, 0.23, 0.45), Color(0.18, 0.18, 0.18, 0.0)])
		smoke.color_ramp = sgrad
		var smesh := SphereMesh.new()
		smesh.radius = 0.5; smesh.height = 1.0; smesh.radial_segments = 6; smesh.rings = 4
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.vertex_color_use_as_albedo = true
		smesh.material = smat
		smoke.mesh = smesh
		root.add_child(smoke)

		# A flickering warm light cast by the flames.
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.22)
		light.omni_range = 8.0 * scl
		light.shadow_enabled = false
		light.position = Vector3(0, 1.0 * scl, 0)
		root.add_child(light)
		var base_e := 2.6 * scl
		var ft := light.create_tween().set_loops()
		ft.tween_callback(func() -> void:
			if is_instance_valid(light):
				light.light_energy = base_e * randf_range(0.6, 1.15))
		ft.tween_interval(0.08)

## Floating holographic propaganda signs (HoloBillboard) projecting AI doctrine
## into the arena. Explicit placements come from def "holograms" (list of
## {pos, text?, color?, size?, height?}); otherwise two are auto-flanked into any
## hostile, non-horde level so the occupation's signage is everywhere. Opt out
## with def "no_holograms". Respects the detail-scale graphics setting.
func _build_holograms(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("detail_scale") and gs.detail_scale() <= 0.0:
		return
	var entries: Array = def.get("holograms", [])
	if entries.is_empty():
		if def.get("friendly", false) or def.get("no_holograms", false) or def.has("horde_spawns"):
			return
		var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
		entries = [
			{"pos": Vector3(-fs.x * 0.32, 0, fs.y * 0.22)},
			{"pos": Vector3(fs.x * 0.30, 0, -fs.y * 0.26)},
		]
	var theme := _theme_color(def)
	var pool: Array = def.get("slogans", []).duplicate()
	if pool.is_empty():
		pool = AI_SLOGANS.duplicate()
	pool.shuffle()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var hb := HoloBillboard.new()
		hb.position = e.get("pos", Vector3.ZERO)
		hb.color = e.get("color", theme)
		hb.text = e.get("text", str(pool[i % pool.size()]))
		if e.has("size"):
			hb.panel_size = e["size"]
		if e.has("height"):
			hb.height = e["height"]
		hb.rotation.y = randf() * TAU
		add_child(hb)

## Two crimson surveillance sweeps on opposite corners: a glowing emitter head
## atop the wall with a slowly rotating, down-tilted spotlight. The occupation
## is watching — and moving light keeps the darker arenas alive.
func _build_beacons(def: Dictionary) -> void:
	if def.get("friendly", false):
		return # resistance-held space: no hostile surveillance sweeps
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var hx := fs.x * 0.5
	var hz := fs.y * 0.5
	var alarm := Color(1.0, 0.22, 0.12)
	var i := 0
	for corner in [Vector3(-hx + 1.4, WALL_HEIGHT + 0.3, -hz + 1.4),
			Vector3(hx - 1.4, WALL_HEIGHT + 0.3, hz - 1.4)]:
		var pivot := Node3D.new()
		pivot.position = corner
		pivot.rotation.y = randf() * TAU
		add_child(pivot)
		var head := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.14
		cm.bottom_radius = 0.2
		cm.height = 0.34
		cm.radial_segments = 10
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.albedo_color = alarm
		hm.emission_enabled = true
		hm.emission = alarm
		hm.emission_energy_multiplier = 3.5
		cm.material = hm
		head.mesh = cm
		pivot.add_child(head)
		var spot := SpotLight3D.new()
		spot.light_color = alarm
		spot.light_energy = 4.5
		spot.spot_range = maxf(fs.x, fs.y) * 0.9
		spot.spot_angle = 13.0
		spot.shadow_enabled = false
		spot.rotation_degrees = Vector3(-34, 0, 0) # tilt the sweep down into the arena
		pivot.add_child(spot)
		var tw := pivot.create_tween().set_loops()
		tw.tween_property(pivot, "rotation:y", TAU, 13.0 + i * 6.0).as_relative()
		i += 1

## Hanging disco rig for party levels (def "disco": [{pos, height?, radius?,
## colors?, speed?}]): a spinning faceted mirror ball plus a ring of coloured
## spotlights sweeping the floor, with faint additive beam cones so the sweep
## reads from across the room (same non-noise cone trick as _build_light_shafts).
## Purely decorative — no colliders, no gameplay effect.
func _build_disco(def: Dictionary) -> void:
	var rigs: Array = def.get("disco", [])
	if rigs.is_empty():
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("detail_scale") and gs.detail_scale() <= 0.0:
		return
	var default_colors := [
		Color(1.0, 0.15, 0.85), Color(0.15, 0.9, 1.0), Color(0.4, 1.0, 0.2),
		Color(1.0, 0.8, 0.1), Color(0.6, 0.2, 1.0), Color(1.0, 0.45, 0.1),
	]
	for i in rigs.size():
		var r: Dictionary = rigs[i]
		var pos: Vector3 = r.get("pos", Vector3.ZERO)
		# Open-sky rigs have no ceiling to hang from, so they auto-switch to a
		# ground mast instead of a drop-rod; a rig can force either explicitly.
		var use_mast: bool = r.get("mast", def.get("open_sky", false))
		var height: float = r.get("height", 5.5)
		if not use_mast:
			height = minf(height, WALL_HEIGHT - 0.3)
		var radius: float = r.get("radius", 14.0)
		var colors: Array = r.get("colors", default_colors)
		var speed: float = r.get("speed", 1.0)

		var pivot := Node3D.new()
		pivot.position = Vector3(pos.x, height, pos.z)
		add_child(pivot)

		if use_mast:
			# Ground mast: a tapered support column from the ground up to the
			# rig, standing in for the ceiling this open-sky level lacks.
			var mast := MeshInstance3D.new()
			var mast_mesh := CylinderMesh.new()
			mast_mesh.top_radius = 0.09
			mast_mesh.bottom_radius = 0.16
			mast_mesh.height = height
			mast_mesh.radial_segments = 8
			mast_mesh.material = _color_material(Color(0.1, 0.11, 0.14), 0.5)
			mast.mesh = mast_mesh
			mast.position = Vector3(0, -height * 0.5, 0)
			pivot.add_child(mast)

			# Solid: built before the deferred navmesh bake (same pattern as
			# _add_light_pylon/_add_streetlamp) so ground robots route around it.
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 0.18
			shape.height = height
			cs.shape = shape
			body.add_child(cs)
			body.position = mast.position
			pivot.add_child(body)
		else:
			# Drop-rod from the ceiling down to the ball — visual only.
			var rod := MeshInstance3D.new()
			var rod_mesh := CylinderMesh.new()
			rod_mesh.top_radius = 0.03
			rod_mesh.bottom_radius = 0.03
			rod_mesh.height = maxf(WALL_HEIGHT - height, 0.2)
			rod_mesh.radial_segments = 6
			rod_mesh.material = MAT_TRIM
			rod.mesh = rod_mesh
			rod.position = Vector3(0, rod_mesh.height * 0.5, 0)
			rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pivot.add_child(rod)

		# Faceted mirror ball: low-poly sphere, dimly emissive metallic skin so
		# it glows rather than reading as a flat grey rock.
		var ball := MeshInstance3D.new()
		var ball_mesh := SphereMesh.new()
		ball_mesh.radius = 0.55
		ball_mesh.height = 1.1
		ball_mesh.radial_segments = 12
		ball_mesh.rings = 6
		var ball_mat := StandardMaterial3D.new()
		ball_mat.albedo_color = Color(0.9, 0.9, 0.95)
		ball_mat.metallic = 0.9
		ball_mat.roughness = 0.15
		ball_mat.emission_enabled = true
		ball_mat.emission = Color(1, 1, 1)
		ball_mat.emission_energy_multiplier = 0.6
		ball_mesh.material = ball_mat
		ball.mesh = ball_mesh
		pivot.add_child(ball)

		for c in colors.size():
			var col: Color = colors[c]
			var ang := TAU * float(c) / float(colors.size())
			var tilt := randf_range(-55.0, -35.0) # downward, so the cone sweeps the floor
			var spot_pivot := Node3D.new()
			spot_pivot.rotation.y = ang
			pivot.add_child(spot_pivot)

			var spot := SpotLight3D.new()
			spot.light_color = col
			spot.light_energy = 3.5
			spot.spot_range = radius
			spot.spot_angle = 16.0
			spot.shadow_enabled = false
			spot.rotation_degrees = Vector3(tilt, 0, 0)
			spot_pivot.add_child(spot)
			# Idle colour life: pulse each spot's energy out of phase so the
			# sweep doesn't read as one flat brightness (tweens only — no
			# per-frame hue cycling).
			var etw := spot.create_tween().set_loops()
			etw.tween_property(spot, "light_energy", 2.5, 1.0 + c * 0.15).set_trans(Tween.TRANS_SINE)
			etw.tween_property(spot, "light_energy", 4.0, 1.0 + c * 0.15).set_trans(Tween.TRANS_SINE)

			# Faint additive beam so the sweep is visible in the air, not just
			# where it lands. Parented straight under the spot so it inherits
			# the tilt; the fixed -90 X correction re-aims the cylinder's
			# default Y-axis onto the spotlight's default -Z aim.
			var beam := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = radius * 0.12
			cone.height = radius * 0.8
			cone.radial_segments = 12
			cone.cap_top = false
			cone.cap_bottom = false
			var beam_mat := StandardMaterial3D.new()
			beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			beam_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			beam_mat.albedo_color = Color(col.r, col.g, col.b, 0.05)
			beam_mat.emission_enabled = true
			beam_mat.emission = col
			beam_mat.emission_energy_multiplier = 0.3
			cone.material = beam_mat
			beam.mesh = cone
			beam.rotation_degrees = Vector3(-90, 0, 0)
			beam.position = Vector3(0, 0, -cone.height * 0.5)
			beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			spot.add_child(beam)

		# Spin the rig; alternate direction per rig so a multi-rig room feels
		# lively rather than uniformly synced.
		var dir := 1.0 if i % 2 == 0 else -1.0
		var tw := pivot.create_tween().set_loops()
		tw.tween_property(pivot, "rotation:y", TAU * dir, 6.0 / maxf(speed, 0.1)).as_relative()

## Open-sky levels get a distant occupied-city ring: dark tower silhouettes
## with sparse lit window slits beyond the walls, over a ground apron so they
## don't float on the sky. Visual only — far outside the play space.
func _build_skyline(def: Dictionary) -> void:
	if not def.get("open_sky", false):
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var base := maxf(fs.x, fs.y) * 0.5
	var apron := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(base * 2.9 + 340.0, base * 2.9 + 340.0) # under the far ring, corners too (Skyline.FAR_GAP)
	apron.mesh = pm
	apron.material_override = _color_material(Color(0.05, 0.05, 0.06), 0.95)
	apron.position = Vector3(0, -0.08, 0)
	add_child(apron)
	# The megacity ring itself: towers, beacons and billboards (Skyline).
	var gs := get_node_or_null("/root/GraphicsSettings")
	var low: bool = gs != null and gs.has_method("is_low") and gs.is_low()
	Skyline.build_for(self, def, _theme_color(def), low)

## The level's hero landmark past the skyline (Landmark, def key `landmark`).
func _build_landmark(def: Dictionary) -> void:
	var gs := get_node_or_null("/root/GraphicsSettings")
	var low: bool = gs != null and gs.has_method("is_low") and gs.is_low()
	Landmark.build_for(self, def, _theme_color(def), low)

## A starfield dome over open-sky levels: one MultiMesh of billboarded points
## at far distance, brightness-varied so the night sky reads as real depth
## instead of a flat gradient. Single draw call; skipped on LOW.
func _build_stars(def: Dictionary) -> void:
	if not def.get("open_sky", false):
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	var density := 1.0
	if gs and gs.has_method("detail_scale"):
		density = gs.detail_scale()
	if density <= 0.0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = int(240 * density)
	for i in mm.instance_count:
		# Random dome point: full azimuth, elevation biased upward and never
		# below ~10 degrees so stars don't poke through the skyline.
		var az := randf() * TAU
		var el := deg_to_rad(randf_range(10.0, 85.0))
		var r := randf_range(300.0, 380.0)
		var pos := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el)) * r
		mm.set_instance_transform(i, Transform3D(Basis(), pos))
		var b := randf_range(0.25, 1.0)
		b = b * b # mostly dim, a few bright — like a real sky
		var warm := randf_range(0.85, 1.0)
		mm.set_instance_color(i, Color(b, b * warm, b * randf_range(0.85, 1.05), 1.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Far outside every cull box on purpose; make sure it never pops out.
	mmi.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 500, 800))
	add_child(mmi)

## Open-sky levels get living air space: occupation craft circling beyond the
## skyline and the odd meteor fall. Skipped on LOW alongside the other dressing.
func _build_sky_traffic(def: Dictionary) -> void:
	if not def.get("open_sky", false):
		return
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("detail_scale") and gs.detail_scale() <= 0.0:
		return
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var traffic := SkyTraffic.new()
	traffic.arena_radius = Vector2(fs.x, fs.y).length() * 0.5
	traffic.accent = _theme_color(def)
	add_child(traffic)

func _build_accents(def: Dictionary) -> void:
	for a in def.get("accents", []):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = a["size"]
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = a["color"]
		m.emission_enabled = true
		m.emission = a["color"]
		m.emission_energy_multiplier = 4.0
		mi.material_override = m
		mi.position = a["pos"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

# ---------- objective / pickups / enemies ----------

## Register the level's task checklist with GameState and spawn whatever objects
## those tasks need (keycards, objective devices). The exit Portal stays sealed
## until GameState.all_tasks_done(). A level with no "tasks" key defaults to the
## classic "eliminate all hostiles".
##
## Mission arcs: a task with "after" (a task id, or an array of ids) is a later
## STAGE — it registers on the checklist immediately (so the portal stays sealed
## and the player sees the plan), but its objects only spawn once every
## prerequisite completes. A task with "reinforce" (an array of enemy specs like
## the level's "enemies" entries) trips an alarm when IT completes: the wave
## pours in as a reaction, so finishing an objective changes the fight.
var _staged_tasks: Array = []
var _reinforce_specs: Array = [] # {id, enemies:[...]}, fired once on completion

func _build_tasks(def: Dictionary) -> void:
	GameState.reset_tasks()
	_staged_tasks.clear()
	_reinforce_specs.clear()
	var tasks: Array = def.get("tasks", [])
	if tasks.is_empty():
		tasks = [{"type": "kill_all"}]
	for t in tasks:
		_register_task_entry(t)
		if t.has("reinforce"):
			_reinforce_specs.append({"id": _task_id(t), "enemies": t["reinforce"], "fired": false})
	for t in tasks:
		if _prereqs_of(t).is_empty():
			_activate_task(t)
		else:
			_staged_tasks.append(t)
	if not _staged_tasks.is_empty() or not _reinforce_specs.is_empty():
		GameState.tasks_changed.connect(_on_tasks_progress)

## The task's checklist id (mirrors the per-type defaults used at registration).
func _task_id(t: Dictionary) -> String:
	match t.get("type", ""):
		"kill_all": return "kill_all"
		"kill_quota": return t.get("id", "quota")
		"key": return t.get("id", "key")
		"destroy_core": return t.get("id", "core")
		"collect_shards": return t.get("id", "shards")
		"hack_terminal", "sabotage": return t.get("id", t.get("type", "hack"))
		"survive": return t.get("id", "survive")
		"hold_zone": return t.get("id", "hold")
		"assassinate": return t.get("id", "hvt")
		"generative_zone": return t.get("id", "guardrails")
		"escape": return t.get("id", "escape")
		"haul": return t.get("id", "haul")
	return t.get("id", "task")

func _prereqs_of(t: Dictionary) -> Array:
	var a = t.get("after", [])
	return [a] if a is String else (a as Array)

## Put the task on the checklist (idempotent) WITHOUT spawning its objects.
## Tasks with unmet-able prerequisites register as `staged` — sealed into the
## exit lock and listed dimmed on the HUD, going live via _activate_task later.
func _register_task_entry(t: Dictionary) -> void:
	var id := _task_id(t)
	var staged := not _prereqs_of(t).is_empty()
	match t.get("type", ""):
		"none":
			pass # sandbox level (e.g. the gun range): no checklist at all
		"kill_all":
			GameState.register_task("kill_all", "Eliminate all hostiles", 0.0, staged)
		"kill_quota":
			var goal: float = float(t.get("count", 10))
			GameState.register_task(id, t.get("label", "Thin the garrison"), goal, staged)
		"collect_shards":
			GameState.register_task(id, t.get("label", "Recover the data shards"),
				float((t.get("points", []) as Array).size()), staged)
		"hack_terminal", "sabotage":
			GameState.register_task(id, t.get("label", "Hack the terminal"), t.get("seconds", 3.0), staged)
		"survive":
			GameState.register_task(id, t.get("label", "Hold out against the assault"), t.get("seconds", 45.0), staged)
		"hold_zone":
			GameState.register_task(id, t.get("label", "Hold the capture zone"), t.get("seconds", 12.0), staged)
		"key":
			GameState.register_task(id, t.get("label", "Recover the access keycard"), 0.0, staged)
		"destroy_core":
			GameState.register_task(id, t.get("label", "Destroy the core"), 0.0, staged)
		"assassinate":
			GameState.register_task(id, t.get("label", "Eliminate the high-value target"), 0.0, staged)
		"generative_zone":
			# Goal 1.0: the manager feeds a 0..1 crossing fraction and completes it
			# when the player reaches the override gate.
			GameState.register_task(id, t.get("label", "Anchor a safe path to the override gate"), 1.0, staged)
		"haul":
			GameState.register_task(id, t.get("label", "Haul the weights to the uplink"), 0.0, staged)
		"escape":
			# No goal meter: the countdown lives in the label (EscapeZone).
			GameState.register_task(id, t.get("label", "Reach extraction before the purge"), 0.0, staged)

## The level's optional challenge (def "bonus": {kind, label, score?}). Never in
## the exit lock: see BonusObjective.
func _build_bonus(def: Dictionary) -> void:
	var b: Dictionary = def.get("bonus", {})
	if b.is_empty():
		return
	var bo := BonusObjective.new()
	bo.name = "BonusObjective"
	bo.kind = String(b.get("kind", "ghost"))
	bo.label = String(b.get("label", ""))
	bo.score = int(b.get("score", 500))
	add_child(bo)

## Spawn the task's world objects / hooks — the stage going "live".
func _activate_task(t: Dictionary) -> void:
	var id := _task_id(t)
	GameState.unstage_task(id)
	# A stage can turn the level's own lighting and weather against the player
	# for as long as it runs (same spec as a survive wave's "weather"): it
	# eases back when this task completes.
	if t.has("weather"):
		_start_weather.call_deferred(t["weather"], id)
	# ...and so can a flood (FloodSurge): it drains when this task completes.
	if t.has("flood"):
		_start_flood.call_deferred(t["flood"], id)
	match t.get("type", ""):
		"kill_quota":
			# Count any kill from activation on; auto-completes at the goal, so
			# there is never a hunt-the-last-drone stall. Bound to this node, so
			# the connection dies with the level.
			GameState.enemy_killed.connect(_on_quota_kill.bind(id))
		"key":
			var k := Keycard.new()
			k.task_id = id
			k.position = t.get("pos", Vector3.ZERO)
			add_child(k)
			_relocate_when_clear(k)
		"destroy_core":
			var core := ObjectiveCore.new()
			core.task_id = id
			if t.has("color"):
				core.core_color = t["color"]
			if t.has("health"):
				core.max_health = t["health"]
			core.jam_shielded = t.get("jam_shielded", false)
			core.position = t.get("pos", Vector3.ZERO)
			add_child(core)
			_relocate_when_clear(core)
		"collect_shards":
			# Points are raw Vector3s in hand-authored defs; the level editor
			# stores them as {"pos": ...} dicts so they drag like any marker.
			for sp in t.get("points", []):
				var shard := ShardPickup.new()
				shard.task_id = id
				shard.position = sp["pos"] if sp is Dictionary else sp
				add_child(shard)
				_relocate_when_clear(shard)
		"hack_terminal", "sabotage":
			var con := HoldConsole.new()
			con.task_id = id
			con.hold_seconds = t.get("seconds", 3.0)
			con.detonate = t.get("type", "") == "sabotage"
			if t.has("color"):
				con.accent = t["color"]
			con.position = t.get("pos", Vector3.ZERO)
			add_child(con)
			_relocate_when_clear(con)
		"survive":
			var timer := SurviveTimer.new()
			timer.task_id = id
			timer.seconds = t.get("seconds", 45.0)
			# Escalating waves make a hold a climax instead of a countdown you
			# can sit out behind cover. Reuses the reinforcement spawner, so a
			# wave pours in with the same FX/scaling as any objective alarm.
			timer.waves = t.get("waves", [])
			timer.wave_due.connect(_on_survive_wave.bind(id))
			add_child(timer)
		"hold_zone":
			var zone := HoldZone.new()
			zone.task_id = id
			zone.hold_seconds = t.get("seconds", 12.0)
			if t.has("radius"):
				zone.radius = t["radius"]
			if t.has("color"):
				zone.accent = t["color"]
			zone.position = t.get("pos", Vector3.ZERO)
			add_child(zone)
			_relocate_when_clear(zone, zone.radius)
		"assassinate":
			_spawn_hvt(t)
		"haul":
			var hp := HaulPayload.new()
			hp.task_id = id
			hp.base_label = t.get("label", "Haul the weights to the uplink")
			hp.deliver_pos = t.get("to", Vector3.ZERO)
			hp.deliver_radius = t.get("radius", 4.0)
			hp.drop_damage = t.get("drop_damage", 30.0)
			if t.has("color"):
				hp.accent = t["color"]
			hp.position = t.get("pos", Vector3.ZERO)
			add_child(hp)
			_relocate_when_clear(hp)
		"escape":
			var ez := EscapeZone.new()
			ez.task_id = id
			ez.base_label = t.get("label", "Reach extraction before the purge")
			ez.seconds = t.get("seconds", 45.0)
			ez.purge_dps = t.get("purge_dps", 18.0)
			ez.hold_seconds = 0.0
			ez.radius = t.get("radius", 4.0)
			ez.accent = t.get("color", Color(0.45, 1.0, 0.55))
			ez.position = t.get("pos", Vector3.ZERO)
			add_child(ez)
			_relocate_when_clear(ez, ez.radius)
		"generative_zone":
			var gz := GenerativeZone.new()
			gz.task_id = id
			gz.field_center = t.get("pos", Vector3.ZERO)
			if t.has("field_size"):
				gz.field_size = t["field_size"]
			if t.has("cell"):
				gz.cell = t["cell"]
			if t.has("accent"):
				gz.accent = t["accent"]
			if t.has("hazard_color"):
				gz.hazard_color = t["hazard_color"]
			if t.has("hazard_period"):
				gz.hazard_period = t["hazard_period"]
			if t.has("floor_dot"):
				gz.floor_dot = t["floor_dot"]
			add_child(gz)

# @lat: [[level-system#Objective Placement]]
## Objective items must be reachable. Authored task positions are NOT validated
## against the built geometry, so a def edit (or a building later dropped onto
## the spot) can bury a keycard/console inside a solid box — an impossible
## objective (level 1 shipped one). If the point sits inside world geometry,
## walk outward in rings and return the first clear spot near the navmesh.
## `node` is the task object itself: its own bodies are left out of the test
## (an ObjectiveCore is a world-layer StaticBody, so every core used to find
## itself "buried" and slide 1.5 m). `radius` > 0 marks a zone the player only
## has to stand somewhere inside: it is buried only when its centre AND the
## whole ring at half its radius are solid (uplink's hold ring encircles a mast).
func _reachable_task_pos(pos: Vector3, node: Node = null, radius: float = 0.0) -> Vector3:
	if not is_inside_tree():
		return pos
	var space := get_world_3d().direct_space_state
	var own := _own_bodies(node)
	if _point_clear(space, pos, own) or _ring_clear(space, pos, radius * 0.5, own):
		return pos
	var nav_map := get_world_3d().navigation_map
	for r: float in [1.5, 2.5, 4.0, 6.0, 8.5]:
		for i in 12:
			var ang := TAU * float(i) / 12.0
			var p: Vector3 = pos + Vector3(cos(ang), 0.0, sin(ang)) * r
			if not _point_clear(space, p, own):
				continue
			# Only accept spots the navmesh can actually deliver a player to —
			# unless the bake hasn't landed yet (closest point comes back ZERO),
			# in which case a physically clear spot is the best we can do.
			var on_nav := NavigationServer3D.map_get_closest_point(nav_map, p)
			if on_nav == Vector3.ZERO \
					or Vector2(on_nav.x - p.x, on_nav.z - p.z).length() < 1.5:
				print("Task position %s buried in geometry; relocated to %s" % [pos, p])
				return Vector3(p.x, pos.y, p.z)
	print("Task position %s buried in geometry; no clear spot found" % pos)
	return pos

## Deferred variant for items placed during the build (physics not yet live):
## waits until physics AND the deferred navmesh bake have landed, then applies
## the same burial rescue.
func _relocate_when_clear(node: Node3D, radius: float = 0.0) -> void:
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(node) and is_inside_tree() and node.is_inside_tree():
		node.position = _reachable_task_pos(node.position, node, radius)

## True when nothing solid (world layer) occupies the point at pickup height.
## `exclude` lists body RIDs to ignore (the task object's own collider).
func _point_clear(space: PhysicsDirectSpaceState3D, pos: Vector3, exclude: Array[RID] = []) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = pos + Vector3(0, 1.0, 0)
	q.collision_mask = 1
	q.exclude = exclude
	return space.intersect_point(q, 1).is_empty()

## True when any of 12 points on the ring of radius `r` around `pos` is clear.
func _ring_clear(space: PhysicsDirectSpaceState3D, pos: Vector3, r: float, exclude: Array[RID]) -> bool:
	if r <= 0.0:
		return false
	for i in 12:
		var ang := TAU * float(i) / 12.0
		if _point_clear(space, pos + Vector3(cos(ang), 0.0, sin(ang)) * r, exclude):
			return true
	return false

## RIDs of every physics body in `node`'s subtree (including `node`).
func _own_bodies(node: Node) -> Array[RID]:
	var out: Array[RID] = []
	if node == null:
		return out
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for c in node.find_children("*", "CollisionObject3D", true, false):
		out.append((c as CollisionObject3D).get_rid())
	return out

func _on_quota_kill(_pts: int, _lbl: String, id: String) -> void:
	GameState.advance_task(id, 1.0)

## Reacts to checklist changes: goes through staged tasks whose prerequisites
## just finished (spawning their objects mid-mission) and fires one-shot
## reinforcement alarms for completed tasks that carry them.
func _on_tasks_progress() -> void:
	for i in range(_staged_tasks.size() - 1, -1, -1):
		var t: Dictionary = _staged_tasks[i]
		var ready := true
		for p in _prereqs_of(t):
			if not GameState.is_task_done(p):
				ready = false
				break
		if ready:
			_staged_tasks.remove_at(i)
			# Defer: we're inside a tasks_changed emission — don't mutate mid-signal.
			_activate_task.call_deferred(t)
	for spec in _reinforce_specs:
		if not spec["fired"] and GameState.is_task_done(spec["id"]):
			spec["fired"] = true
			_spawn_reinforcements.call_deferred(spec["enemies"])

## A "survive" wave came due. Announce it (so the escalation reads as authored,
## not as enemies wandering in), pour the enemies in through the same alarm
## spawner, and vent any emergency supplies the wave carries.
func _on_survive_wave(wave: Dictionary, task_id: String = "survive") -> void:
	var label := String(wave.get("label", ""))
	if label != "":
		GameState.wave_incoming.emit(label)
	var flood: Dictionary = wave.get("flood", {})
	if not flood.is_empty():
		_start_flood.call_deferred(flood, task_id)
	var weather: Dictionary = wave.get("weather", {})
	if not weather.is_empty():
		_start_weather.call_deferred(weather, task_id)
	var enemies: Array = wave.get("enemies", [])
	if not enemies.is_empty():
		_spawn_reinforcements.call_deferred(enemies)
	var supplies: Array = wave.get("supplies", [])
	if not supplies.is_empty():
		_vent_supplies.call_deferred(supplies)

## A wave's "flood": hazard beds that telegraph, rise mid-hold and drain when the
## hold completes (FloodSurge). Keys: beds (same spec as the def's "lava"
## entries), warn/rise seconds, warn_title/warn_text and drain_title/drain_text
## for the HUD alerts.
func _start_flood(flood: Dictionary, task_id: String) -> void:
	var fs := FloodSurge.new()
	fs.name = "FloodSurge"
	fs.task_id = task_id
	fs.beds = flood.get("beds", [])
	fs.warn_seconds = float(flood.get("warn", 3.0))
	fs.rise_seconds = float(flood.get("rise", 1.2))
	fs.warn_title = String(flood.get("warn_title", fs.warn_title))
	fs.warn_text = String(flood.get("warn_text", fs.warn_text))
	fs.drain_title = String(flood.get("drain_title", ""))
	fs.drain_text = String(flood.get("drain_text", ""))
	add_child(fs)

## A wave's "weather": the level Environment's fog thickens (and the weather
## particles gust) for the rest of the hold, easing back when it completes
## (WeatherShift). Keys: fog_mult, fog_color, fade, gust, warn_title/warn_text,
## clear_title/clear_text.
func _start_weather(w: Dictionary, task_id: String) -> void:
	var ws := WeatherShift.new()
	ws.name = "WeatherShift"
	ws.task_id = task_id
	ws.env = _env
	ws.weather = get_node_or_null("Weather")
	# A level with no weather of its own can raise some for the storm
	# ("particles": "dust" / "snow" / "rain"): built like the env key, owned
	# by the shift and stopped and freed when the hold is won.
	if ws.weather == null and w.has("particles"):
		var d: Dictionary = LevelDefs.get_def(level_id)
		var tint: Color = w.get("fog_color", (d.get("env", {}) as Dictionary).get("fog", Color(0.5, 0.45, 0.38)))
		_build_weather({"env": {"weather": String(w["particles"]), "fog": tint},
			"floor_size": d.get("floor_size", Vector2(40, 40))})
		ws.weather = get_node_or_null("Weather")
		ws.owns_weather = ws.weather != null
	ws.fog_mult = float(w.get("fog_mult", 4.0))
	ws.blackout = bool(w.get("blackout", false))
	ws.ambient_mult = float(w.get("ambient_mult", 1.0))
	ws.exposure_mult = float(w.get("exposure_mult", 1.0))
	ws.fade = float(w.get("fade", 3.0))
	ws.gust = float(w.get("gust", 1.0))
	if w.has("fog_color"):
		ws.fog_color = w["fog_color"]
	ws.warn_title = String(w.get("warn_title", ws.warn_title))
	ws.warn_text = String(w.get("warn_text", ws.warn_text))
	ws.clear_title = String(w.get("clear_title", ""))
	ws.clear_text = String(w.get("clear_text", ""))
	add_child(ws)

## Emergency stores ejected mid-hold: pickups that pop in ({type, pos}, the same
## spec as the def's "pickups"). Author them where reaching them costs something
## and a long hold stays sustainable without handing the sustain over for free.
func _vent_supplies(supplies: Array) -> void:
	for s in supplies:
		var scene: PackedScene = pickup_scene(s.get("type", s.get("kind", "")))
		if scene == null:
			continue
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		inst.global_position = s.get("pos", Vector3.ZERO)
		# Pop-in, like the horde director's between-wave drops, so it reads as a
		# delivery rather than something that was always lying there.
		inst.scale = Vector3.ONE * 0.2
		inst.create_tween().tween_property(inst, "scale", Vector3.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## An objective tripped the alarm: pour the authored wave in with the same
## machinery as placed enemies (spawn FX, difficulty scaling), staggered so it
## reads as a response, not an ambush that was always standing there.
func _spawn_reinforcements(enemies: Array) -> void:
	AudioBus.play_synth_ui("empty_click", -6.0, 0.55) # low klaxon-ish blip under the cheer
	var delay := 0.5
	for en in enemies:
		var scene: PackedScene = enemy_scene(en.get("type", "drone"))
		if scene == null:
			continue
		var count: int = maxi(1, int(en.get("count", 1)))
		var base_pos: Vector3 = en.get("pos", Vector3.ZERO)
		for j in count:
			var sp := EnemySpawner.new()
			sp.enemy_scene = scene
			sp.spawn_on_ready = true
			sp.spawn_delay = delay
			sp.position = base_pos if count == 1 else base_pos + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
			add_child(sp)
			delay += 0.35 # pour in, don't materialize as a wall

## "assassinate" objective: a single high-value target the player must hunt down
## (the level clears when IT dies, not when the room is empty). It spawns as a
## real Elite — distinct tint/glow, tougher, with a twist (default WARDEN, so it
## walks through suppression and you have to dodge it) — and joins the "objective"
## group so the HUD waypoint guides you to it across the arena. Because the target
## is a live, mobile enemy, exact placement is forgiving: it paths to the player.
func _spawn_hvt(t: Dictionary) -> void:
	var id: String = t.get("id", "hvt")
	GameState.register_task(id, t.get("label", "Eliminate the high-value target"))
	var scene: PackedScene = enemy_scene(t.get("enemy", "brute"))
	if scene == null:
		return
	var hvt := scene.instantiate() as EnemyBase
	if hvt == null:
		return
	hvt.position = t.get("pos", Vector3.ZERO)
	# Apply the affix BEFORE add_child so _ready reads the boosted exports.
	Elite.apply(hvt, t.get("elite", "warden"))
	hvt._health_mult *= float(t.get("bulk", 2.2)) # extra HVT bulk on top of the affix
	hvt.score_value = int(hvt.score_value * 1.5)
	hvt.add_to_group("objective") # HUD waypoint points the player at it
	hvt.add_to_group("hvt")
	add_child(hvt)
	if hvt.hp:
		hvt.hp.died.connect(func(_src): GameState.complete_task(id))

func _build_exit(def: Dictionary) -> void:
	if def.get("no_exit", false):
		return # sandbox: leave via the pause menu instead
	# A locked-until-cleared portal that builds its own animated visuals.
	var portal := Portal.new()
	portal.objective_text = def.get("objective", "Reach the extraction beacon")
	portal.position = def.get("exit", Vector3(0, 1.5, 0))
	add_child(portal)

# Supply pickups (health/ammo/overclock) are NOT placed by the builder:
# they drop from kills instead (EnemyBase._drop_loot). Any "pickups" entries
# in level defs are ignored. Weapons and objective items still get placed.
func _build_weapon_pickup(def: Dictionary) -> void:
	_spawn_weapon_pickup(def.get("weapon", {}))
	# Optional additional weapons to find in the level.
	for w in def.get("extra_weapons", []):
		_spawn_weapon_pickup(w)

func _spawn_weapon_pickup(w: Dictionary) -> void:
	if w.is_empty():
		return
	var ps := load(w["scene"]) as PackedScene
	if ps == null:
		return
	var pk := weapon_pickup_scene().instantiate()
	pk.weapon_scene = ps
	pk.position = w["pos"]
	# Physics isn't live during the build; once it is, nudge the pickup out of
	# any geometry the def accidentally buried it in.
	_relocate_when_clear.call_deferred(pk)
	var col: Color = w.get("color", Color(0.5, 0.8, 1))
	var light := pk.get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_color = col
	var glow := pk.get_node_or_null("Mesh/Glow") as MeshInstance3D
	if glow:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 4.0
		glow.material_override = m
	add_child(pk)

## Hand-placed supply/powerup pickups (def "pickups": [{type|kind, pos}]).
##
## Accepts BOTH spellings on purpose: the level editor emits "kind", but every
## hand-authored campaign def writes "type" (matching "enemies"/"props"). This
## only read "kind", so all ~88 authored campaign pickups silently resolved to
## a null scene and never spawned — GPT Foundry's vault cache and its
## climb-the-tower overclock reward included. tests/pickup_probe guards it.
func _build_pickups(def: Dictionary) -> void:
	for p in def.get("pickups", []):
		var kind: String = p.get("type", p.get("kind", ""))
		var scene: PackedScene = pickup_scene(kind)
		if scene == null:
			continue
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		inst.global_position = p.get("pos", Vector3.ZERO)

## Pop-up range targets (def "targets"): static, sliding, or armored.
func _build_targets(def: Dictionary) -> void:
	for t in def.get("targets", []):
		var dummy := TargetDummy.new()
		dummy.position = t["pos"]
		dummy.max_health = t.get("hp", 60.0)
		dummy.move_range = t.get("move", 0.0)
		dummy.move_speed = t.get("speed", 1.2)
		if t.has("color"):
			dummy.accent = t["color"]
		add_child(dummy)

## Recovered data logs (def "lore"): walk-up terminals that voice a faction
## log through the Broadcast bus while the text types across the screen.
func _build_lore(def: Dictionary) -> void:
	for l in def.get("lore", []):
		var t := LoreTerminal.new()
		t.log_id = l.get("id", "")
		t.title = l.get("title", "RECOVERED LOG")
		t.text = l.get("text", "")
		if l.has("color"):
			t.accent = l["color"]
		t.position = l["pos"]
		add_child(t)

## Endless-siege mode: defs with "horde_spawns" get a wave director instead of
## (or alongside) placed enemies.
func _build_horde(def: Dictionary) -> void:
	var pts: Array = def.get("horde_spawns", [])
	if pts.is_empty():
		return
	var hd := HordeDirector.new()
	hd.spawn_points = pts
	hd.supply_center = def.get("supply_center", Vector3.ZERO)
	add_child(hd)

func _spawn_enemies(def: Dictionary) -> void:
	for en in def.get("enemies", []):
		var scene: PackedScene = enemy_scene(en["type"])
		if scene == null:
			continue
		var trig: float = en.get("trigger", 0.0)
		# "count" spawns a cluster from one entry (swarms): scattered around pos,
		# each its own spawner so they trigger/scale exactly like a single placed one.
		var count: int = maxi(1, int(en.get("count", 1)))
		var base_pos: Vector3 = en["pos"]
		# "pack": entries sharing an id wake as one squad the moment any of them
		# is tripped, so the player meets a mixed group instead of crossing three
		# trigger circles in a row and fighting three robots in sequence.
		var pack: String = String(en.get("pack", ""))
		for j in count:
			var sp := EnemySpawner.new()
			sp.enemy_scene = scene
			sp.position = base_pos if count == 1 else base_pos + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
			sp.pack_id = pack
			if trig > 0.0:
				sp.spawn_on_ready = false
				sp.trigger_radius = trig
			else:
				sp.spawn_on_ready = true
				sp.spawn_delay = 0.4 + j * 0.12 # stagger the cluster so it pours in
			add_child(sp)

func _place_player(def: Dictionary) -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var spawn: Vector3 = def.get("spawn", Vector3(0, 0.5, 0))
	p.global_position = spawn
	# Face the open arena, not whatever wall the spawn corner backs onto: aim
	# at the exit (always across open ground from the spawn), falling back to
	# the level centre. Player forward is -Z, hence atan2(-x, -z).
	var look_at: Vector3 = def.get("exit", Vector3.ZERO)
	var dir := look_at - spawn
	dir.y = 0.0
	if dir.length() > 0.5:
		p.rotation.y = atan2(-dir.x, -dir.z)

func _apply_objective_text(def: Dictionary) -> void:
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("set_objective"):
		var text: String = def.get("objective", "Eliminate the AI and reach the beacon")
		hud.set_objective("%s  ·  [%s]" % [text, GameState.difficulty_label()])

# ---------- navmesh ----------

func _bake_navmesh() -> void:
	if _nav_region and _nav_region.navigation_mesh and is_inside_tree():
		_nav_region.bake_navigation_mesh(false)

var _rebake_queued: bool = false
var nav_rebakes: int = 0 ## Runtime rebakes started (BreakableCover gaps); probes read it.

## A cover block was destroyed: rebake so robots path through the gap. Debounced
## (one bake per burst of breakage) and threaded, so a grenade that levels three
## blocks costs one bake and no frame stall beyond the geometry parse.
func request_nav_rebake() -> void:
	if _rebake_queued:
		return
	_rebake_queued = true
	get_tree().create_timer(0.4).timeout.connect(_rebake_nav)

func _rebake_nav() -> void:
	_rebake_queued = false
	if not is_inside_tree() or _nav_region == null or _nav_region.navigation_mesh == null:
		return
	if _nav_region.is_baking():
		request_nav_rebake() # try again once the running bake lands
		return
	nav_rebakes += 1
	_nav_region.bake_navigation_mesh(true)
