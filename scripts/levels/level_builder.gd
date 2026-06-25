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

const ENEMY_SCENES := {
	"drone": preload("res://scenes/enemies/drone.tscn"),
	"android": preload("res://scenes/enemies/android.tscn"),
	"mech": preload("res://scenes/enemies/mech.tscn"),
	"spider": preload("res://scenes/enemies/spider.tscn"),
	"terminator": preload("res://scenes/enemies/terminator.tscn"),
	"colossus": preload("res://scenes/enemies/colossus.tscn"),
	"titan": preload("res://scenes/enemies/titan.tscn"),
	"alien": preload("res://scenes/enemies/alien.tscn"),
	"sniper": preload("res://scenes/enemies/sniper.tscn"),
	"seeker": preload("res://scenes/enemies/seeker.tscn"),
	"overseer": preload("res://scenes/enemies/overseer.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
	"archon": preload("res://scenes/enemies/archon.tscn"),
	"mender": preload("res://scenes/enemies/mender.tscn"),
	"skitter": preload("res://scenes/enemies/skitter.tscn"),
	"strider": preload("res://scenes/enemies/strider.tscn"),
	"gunner": preload("res://scenes/enemies/gunner.tscn"),
	"raptor": preload("res://scenes/enemies/raptor.tscn"),
	"vacuum": preload("res://scenes/enemies/vacuum.tscn"),
	"reaper": preload("res://scenes/enemies/reaper.tscn"),
	"hunter": preload("res://scenes/enemies/hunter.tscn"),
	"sentinel": preload("res://scenes/enemies/sentinel.tscn"),
	"mauler": preload("res://scenes/enemies/mauler.tscn"),
	"ravager": preload("res://scenes/enemies/ravager.tscn"),
	"warmech": preload("res://scenes/enemies/warmech.tscn"),
}
const NIGHT_SKY_SHADER := preload("res://shaders/night_sky.gdshader")

const PROP_SCENES := {
	"car": preload("res://scenes/props/car.tscn"),
	"fence": preload("res://scenes/props/fence.tscn"),
	"crate": preload("res://scenes/props/crate.tscn"),
	"barrel": preload("res://scenes/props/barrel.tscn"),
	"server": preload("res://scenes/props/server_rack.tscn"),
	"terminal": preload("res://scenes/props/terminal.tscn"),
	"monitors": preload("res://scenes/props/monitor_bank.tscn"),
	"canister": preload("res://scenes/props/gas_canister.tscn"),
	"lamp": preload("res://scenes/props/lamp_post.tscn"),
	"locker": preload("res://scenes/props/locker.tscn"),
	"shelves": preload("res://scenes/props/shelves.tscn"),
	"desk": preload("res://scenes/props/desk.tscn"),
	"dish": preload("res://scenes/props/satellite_dish.tscn"),
	"tree": preload("res://scenes/props/tree.tscn"),
	"tree_small": preload("res://scenes/props/tree_small.tscn"),
	# Procedural nature / water / obstacle props (SimpleProp) for the editor.
	"pine": preload("res://scenes/props/pine.tscn"),
	"dead_tree": preload("res://scenes/props/dead_tree.tscn"),
	"bush": preload("res://scenes/props/bush.tscn"),
	"grass": preload("res://scenes/props/grass.tscn"),
	"flowers": preload("res://scenes/props/flowers.tscn"),
	"reeds": preload("res://scenes/props/reeds.tscn"),
	"fern": preload("res://scenes/props/fern.tscn"),
	"mushroom": preload("res://scenes/props/mushroom.tscn"),
	"log": preload("res://scenes/props/log.tscn"),
	"stump": preload("res://scenes/props/stump.tscn"),
	"rock": preload("res://scenes/props/rock.tscn"),
	"boulder": preload("res://scenes/props/boulder.tscn"),
	"rubble": preload("res://scenes/props/rubble.tscn"),
	"river": preload("res://scenes/props/river.tscn"),
	"pond": preload("res://scenes/props/pond.tscn"),
	"barrier": preload("res://scenes/props/barrier.tscn"),
	"sandbags": preload("res://scenes/props/sandbags.tscn"),
	"planter": preload("res://scenes/props/planter.tscn"),
	"hydrant": preload("res://scenes/props/hydrant.tscn"),
	"dumpster": preload("res://scenes/props/dumpster.tscn"),
	"cone": preload("res://scenes/props/cone.tscn"),
	"bench": preload("res://scenes/props/bench.tscn"),
	"pillar": preload("res://scenes/props/pillar.tscn"),
	"statue": preload("res://scenes/props/statue.tscn"),
	"crate_stack": preload("res://scenes/props/crate_stack.tscn"),
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
const WEAPON_PICKUP := preload("res://scenes/pickups/weapon_pickup.tscn")
## Fixed supply/powerup pickups the editor can place (def "pickups": [{kind,pos}]).
## In campaign play supplies drop from kills; the editor uses these to hand-place.
const PICKUP_SCENES := {
	"health": preload("res://scenes/pickups/health_pack.tscn"),
	"ammo": preload("res://scenes/pickups/ammo_box.tscn"),
	"overclock": preload("res://scenes/pickups/overclock.tscn"),
	"overdrive": preload("res://scenes/pickups/overdrive.tscn"),
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

func _ready() -> void:
	var def := _resolve_def()
	if def.is_empty():
		push_error("LevelBuilder: unknown level_id '%s'" % level_id)
		return
	_build_environment(def)
	_build_geometry(def)
	_build_wall_details(def)
	_build_buildings(def)
	_build_ramps(def)
	_build_platforms(def)
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
	_build_rubble(def)
	_build_fires(def)
	_build_weather(def)
	_build_lightning(def)
	_build_beacons(def)
	_build_holograms(def)
	_build_skyline(def)
	_build_sky_traffic(def)
	_build_stars(def)
	_build_tasks(def)
	_build_exit(def)
	_build_weapon_pickup(def)
	_build_pickups(def)
	_build_targets(def)
	_build_lore(def)
	_spawn_enemies(def)
	_build_horde(def)
	_place_player(def)
	_build_set_piece(def)
	_build_lava(def)
	_apply_objective_text(def)
	GameState.apply_level_scaling(self) # difficulty: tune enemy/pickup counts
	_bake_navmesh.call_deferred()

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
	# MUCH darker baseline than the defs ask for: the world lives in shadow and
	# every light source — fixtures, muzzle flashes, bolts, explosions, pickup
	# glows — gets to carve its own pool out of the dark.
	env.ambient_light_energy = e.get("ambient_energy", 0.4) * 0.38
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
	env.glow_intensity = e.get("glow", 0.62)
	env.glow_strength = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.25 # low enough that enemy emissives halo in the dark
	env.glow_hdr_scale = 1.0
	# Soft filmic halo around emissives — narrow kernel keeps the scene crisp.
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.55)

	env.fog_enabled = true
	env.fog_light_color = e.get("fog", Color(0.45, 0.5, 0.55))
	# Interiors: darken the distance fog so far walls recede into shadow instead of
	# washing out into a bright themed band (open-sky levels keep their bright haze
	# so the sky/horizon reads). Big readability + depth win for enclosed arenas.
	if not def.get("open_sky", false):
		env.fog_light_color = env.fog_light_color.darkened(0.5)
	env.fog_density = e.get("fog_density", 0.01)
	env.fog_aerial_perspective = 0.12
	env.fog_sky_affect = 0.3

	# Volumetric fog is for interior atmosphere / god-rays. Outdoors it floods
	# the open space with sun in-scatter (a milky veil), so exteriors use only
	# the cheap distance fog above.
	if not def.get("open_sky", false):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = minf(e.get("fog_density", 0.01), 0.012) * 0.5
		# Showcase levels can thicken the haze so light shafts/god-rays read.
		if e.has("volumetric_density"):
			env.volumetric_fog_density = e["volumetric_density"]
		# A darker, less milky veil: the near-white albedo washed enclosed arenas
		# into a flat bright haze. This keeps god-rays/shafts readable but lets the
		# space hold shadow and depth.
		env.volumetric_fog_albedo = Color(0.34, 0.37, 0.43)
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_gi_inject = 0.25
	else:
		env.volumetric_fog_enabled = false

	# Filmic grade: gentle teal shadows / warm highlights, lifted contrast.
	# Levels can override per-theme (def "env": brightness/contrast/saturation).
	env.adjustment_enabled = true
	env.adjustment_brightness = e.get("brightness", 0.84)
	env.adjustment_contrast = e.get("contrast", 1.12)
	env.adjustment_saturation = e.get("saturation", 1.06)
	
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
	sun.light_energy = e.get("sun_energy", 1.0) * 0.5 # weak key: the placed lamps carry the scene
	sun.light_angular_distance = 1.2 # sun disc size -> soft penumbra shadows
	sun.shadow_enabled = true
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)

	# Shadowed-light budget per tier: every shadowed omni re-renders the scene
	# up to 6 times, so LOW casts none, MEDIUM only the first two, HIGH all.
	var shadow_budget := 99
	if gs and gs.has_method("tier"):
		shadow_budget = [0, 2, 99, 99][gs.tier()]
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
			light = omni
		add_child(light)
		# Every light gets a visible SOURCE instead of hanging disembodied:
		# ceiling luminaires indoors, slim floodlight pylons outdoors.
		if indoor:
			_add_light_fixture(l["pos"], l.get("color", Color(1, 1, 1)))
		else:
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
	elif def.has("floor_color"):
		floor_mat = _color_material(def["floor_color"], 0.95)
		floor_surf = "surf_dirt" if def.get("open_sky", false) else "surf_concrete"
	_add_box(Vector3(0, -0.2, 0), Vector3(fs.x, 0.4, fs.y), floor_mat, floor_surf)
	# Perimeter walls — weathered concrete outdoors, panels indoors.
	var wall_mat: Material = MAT_WALL_OUT if def.get("open_sky", false) else MAT_WALL
	_add_box(Vector3(0, WALL_HEIGHT * 0.5, -hz), Vector3(fs.x, WALL_HEIGHT, 1.0), wall_mat, "surf_concrete")
	_add_box(Vector3(0, WALL_HEIGHT * 0.5, hz), Vector3(fs.x, WALL_HEIGHT, 1.0), wall_mat, "surf_concrete")
	_add_box(Vector3(-hx, WALL_HEIGHT * 0.5, 0), Vector3(1.0, WALL_HEIGHT, fs.y), wall_mat, "surf_concrete")
	_add_box(Vector3(hx, WALL_HEIGHT * 0.5, 0), Vector3(1.0, WALL_HEIGHT, fs.y), wall_mat, "surf_concrete")
	if not def.get("open_sky", false):
		_add_box(Vector3(0, WALL_HEIGHT + 0.2, 0), Vector3(fs.x, 0.4, fs.y), MAT_CEIL, "surf_metal")
	# Interior cover / pillars — alternate two plate materials so adjacent
	# crates/machinery don't read as copies of one box.
	var cover_i := 0
	for w in def.get("walls", []):
		_add_box(w["pos"], w["size"], MAT_PROP if cover_i % 2 == 0 else MAT_PROP_B, "surf_metal")
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
	# Heavy real-time GI is High-quality only. Balanced/Low skip it entirely.
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
	else:
		# Indoor levels: a baked VoxelGI covering the play space.
		var vgi := VoxelGI.new()
		vgi.size = Vector3(fs.x + 4.0, 8.0, fs.y + 4.0)
		vgi.position = Vector3(0, 4, 0)
		add_child(vgi)
		# The headless/dummy renderer cannot bake; only bake in the real game.
		if DisplayServer.get_name() != "headless":
			vgi.bake.call_deferred()

	# Reflection probe: grounded, off-screen reflections on metal robots/floors
	# that SSR (screen-space only) can't provide. Box-projected to the arena.
	var rp := ReflectionProbe.new()
	rp.size = Vector3(fs.x + 2.0, 14.0, fs.y + 2.0)
	rp.position = Vector3(0, 5.0, 0)
	rp.box_projection = true
	rp.interior = not open_sky
	rp.max_distance = 0.0
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(rp)

func _add_box(center: Vector3, size: Vector3, mat: Material, surface: String = "surf_concrete") -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	if surface != "":
		body.add_to_group(surface)
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

## A simple opaque PBR material from a colour — used for tinted floors and the
## suburban house bodies (so outdoor levels don't read as grey metal boxes).
func _color_material(color: Color, roughness: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = 0.0
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

func _build_ramps(def: Dictionary) -> void:
	for r in def.get("ramps", []):
		_add_ramp(r["pos"], r["size"], r.get("pitch", 24.0), r.get("yaw", 0.0))

func _add_ramp(center: Vector3, size: Vector3, pitch_deg: float, yaw_deg: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.transform = Transform3D(b, center)
	var mi := MeshInstance3D.new()
	mi.mesh = _beveled_box(size)
	mi.mesh.material = MAT_PROP
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(mi)
	body.add_child(cs)
	add_child(body)

func _build_platforms(def: Dictionary) -> void:
	for p in def.get("platforms", []):
		var mat: Material = MAT_PROP
		if p.has("color"):
			mat = _color_material(p["color"])
		_add_collider_box(p["pos"], p["size"], mat)

## A solid collidable box under the builder root (not the navmesh) — used for
## elevated rooftops/overpasses the player can stand on.
func _add_collider_box(center: Vector3, size: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
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
	add_child(body)

# ---------- destructible props ----------

func _build_props(def: Dictionary) -> void:
	for pr in def.get("props", []):
		var scene: PackedScene = PROP_SCENES.get(pr["type"])
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
func _build_lava(def: Dictionary) -> void:
	for entry in def.get("lava", []):
		var lava := LavaHazard.new()
		lava.size = entry.get("size", Vector2(8, 3))
		if entry.has("dmg"):
			lava.damage_per_tick = entry["dmg"]
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
	var bb := _wall_point(fs, 0, 0.0, WALL_HEIGHT - 1.3, 0.45)
	var board := Node3D.new()
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
	for w in def.get("walls", []):
		var pos: Vector3 = w["pos"]
		var size: Vector3 = w["size"]
		if size.y > 5.0:
			continue # interior dividers reach the ceiling; trim only the cover
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
			_dress_cover_box(pos, size, col, accent_mat)

## Turns a bare cover block into a piece of machinery: four dark corner posts (a
## framed-cabinet read), a recessed vent grille on the face toward the arena
## centre, a near-flush theme-coloured accent groove around the body, and a row
## of bright status pips beside the grille. All visual-only (no colliders).
func _dress_cover_box(pos: Vector3, size: Vector3, theme: Color, accent: Material) -> void:
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
	var grille_w := minf(width * 1.4, width * 2.0 - 0.5)
	var back := BoxMesh.new()
	back.size = Vector3(grille_w, size.y * 0.5, 0.04)
	back.material = MAT_SEAM
	_add_detail_mesh(back, face_center + Vector3(0, -size.y * 0.05, 0), face_yaw)
	var n_slats := 5
	for i in n_slats:
		var sy := -size.y * 0.05 + (float(i) / float(n_slats - 1) - 0.5) * size.y * 0.42
		var slat := BoxMesh.new()
		slat.size = Vector3(grille_w - 0.1, 0.05, 0.07)
		slat.material = MAT_TRIM
		_add_detail_mesh(slat, face_center + Vector3(0, sy, 0) + face_n * 0.02, face_yaw)

	# 3) Theme accent groove around all four faces, at mid-body, near flush.
	#    Uses the shared breathing material so all cover pulses in sync.
	var band_dy := half.y * 0.3
	for nrm in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var nx := absf(nrm.x) > 0.5
		var bd := half.x if nx else half.z
		var bw := (half.z if nx else half.x) * 2.0 - post_w * 2.2
		var band := BoxMesh.new()
		band.size = Vector3(bw, 0.05, 0.015)
		band.material = accent
		_add_detail_mesh(band, pos + nrm * (bd + 0.006) + Vector3(0, band_dy, 0), 0.0 if nx else PI * 0.5)

	# 4) Status pips: a short row of bright theme-coloured lights by the grille top.
	var pip := StandardMaterial3D.new()
	pip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pip.albedo_color = theme
	pip.emission_enabled = true
	pip.emission = theme
	pip.emission_energy_multiplier = 4.0
	var tangent := Vector3(0, 0, 1) if on_x else Vector3(1, 0, 0)
	for i in 3:
		var dot := BoxMesh.new()
		dot.size = Vector3(0.12, 0.12, 0.05)
		dot.material = pip
		_add_detail_mesh(dot, face_center + tangent * (width - 0.35 - float(i) * 0.28) + Vector3(0, half.y - 0.3, 0) + face_n * 0.02, face_yaw)

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
	var x := -fs.x * 0.5 + spacing
	while x < fs.x * 0.5 - 1.0:
		_seam_strip(Vector3(x, 0.008, 0), Vector3(0.16, 0.016, fs.y - 1.4), dark)
		_seam_strip(Vector3(x, 0.013, 0), Vector3(0.045, 0.018, fs.y - 1.4), glow)
		xs.append(x)
		x += spacing
	var z := -fs.y * 0.5 + spacing
	while z < fs.y * 0.5 - 1.0:
		_seam_strip(Vector3(0, 0.008, z), Vector3(fs.x - 1.4, 0.016, 0.16), dark)
		_seam_strip(Vector3(0, 0.013, z), Vector3(fs.x - 1.4, 0.018, 0.045), glow)
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
	for nx in xs:
		for nz in zs:
			_seam_strip(Vector3(nx, 0.015, nz), Vector3(0.22, 0.02, 0.22), node)

func _seam_strip(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

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
					var vent := BoxMesh.new()
					vent.size = Vector3(1.1, 0.8, 0.12)
					vent.material = MAT_TRIM
					_add_detail_mesh(vent, base + n * 0.08 + Vector3(0, 2.0, 0), yaw)
					for s in 3:
						var slat := BoxMesh.new()
						slat.size = Vector3(0.95, 0.07, 0.05)
						slat.material = MAT_PROP
						_add_detail_mesh(slat, base + n * 0.12 + Vector3(0, 1.78 + s * 0.22, 0), yaw)
				1:  # junction box with a small status LED
					var jb := _beveled_box(Vector3(0.5, 0.65, 0.22))
					jb.material = MAT_PROP_B
					_add_detail_mesh(jb, base + n * 0.11 + Vector3(0, 1.7, 0), yaw)
					var led_col: Color = [Color(0.3, 1, 0.4), Color(1, 0.7, 0.2), Color(1, 0.3, 0.3)][k % 3]
					var led := BoxMesh.new()
					led.size = Vector3(0.09, 0.09, 0.05)
					led.material = _emissive_material(led_col, 2.4)
					_add_detail_mesh(led, base + n * 0.2 + Vector3(0, 1.86, 0), yaw)
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
					var palette := [Color(0.3, 1, 0.45), Color(0.3, 0.7, 1), Color(1, 0.75, 0.2), Color(1, 0.35, 0.3)]
					for row in 4:
						for coli in 3:
							# A scattered on/off + colour pattern so panels read distinct.
							if (row * 3 + coli + k) % 4 == 0:
								continue
							var dot := BoxMesh.new()
							dot.size = Vector3(0.1, 0.1, 0.04)
							dot.material = _emissive_material(palette[(row + coli + k) % palette.size()], 2.6)
							var dx := lerpf(-0.42, 0.42, coli / 2.0)
							var dy := lerpf(1.72, 2.68, row / 3.0)
							_add_detail_mesh(dot, base + n * 0.16 + along * dx + Vector3(0, dy, 0), yaw)
			x += step
			k += 1

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
func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.metallic = 0.0
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

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
		add_child(p)

## Storm lightning (opt-in via env "lightning": true, or automatic in "rain"
## weather): a hidden sky light periodically double-flashes the whole scene, with
## a thunderclap rolling in a beat later. The "reactive world lighting" cue.
func _build_lightning(def: Dictionary) -> void:
	var e: Dictionary = def.get("env", {})
	if not (bool(e.get("lightning", false)) or str(e.get("weather", "")) in ["rain", "storm"]):
		return
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
	# A quick double-flicker — the characteristic stutter of a real strike.
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", randf_range(3.0, 5.0), 0.04)
	tw.tween_property(flash, "light_energy", 0.5, 0.06)
	tw.tween_property(flash, "light_energy", randf_range(2.0, 4.0), 0.04)
	tw.tween_property(flash, "light_energy", 0.0, 0.28)
	# Thunder rolls in after the flash (sound is slower than light).
	var d := get_tree().create_timer(randf_range(0.6, 1.8))
	d.timeout.connect(func() -> void:
		if has_node("/root/AudioBus"):
			AudioBus.play_synth_ui("thunder", -3.0, randf_range(0.9, 1.1)))

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
	pm.size = Vector2(base * 2.0 + 240.0, base * 2.0 + 240.0)
	apron.mesh = pm
	apron.material_override = _color_material(Color(0.05, 0.05, 0.06), 0.95)
	apron.position = Vector3(0, -0.08, 0)
	add_child(apron)
	var body_mat := _color_material(Color(0.07, 0.075, 0.09), 0.9)
	var win_col := _theme_color(def)
	var win_mat := StandardMaterial3D.new()
	win_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	win_mat.albedo_color = win_col
	win_mat.emission_enabled = true
	win_mat.emission = win_col
	win_mat.emission_energy_multiplier = 1.8
	var steps := 22
	for s in steps:
		var ang := TAU * s / steps + randf_range(-0.06, 0.06)
		var dist := base + randf_range(26.0, 60.0)
		var w := randf_range(6.0, 14.0)
		var h := randf_range(8.0, 30.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(w, h, w)
		bm.material = body_mat
		mi.mesh = bm
		mi.position = Vector3(cos(ang) * dist, h * 0.5 - 0.1, sin(ang) * dist)
		mi.rotation.y = randf_range(0.0, PI)
		# Pure backdrop: 22 towers drawn into the sun's shadow cascades would be
		# the most expensive shadows in the game for silhouettes nobody reads.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Lit window slits: thin emissive columns punched through the tower so
		# a glowing seam shows on both faces — reads as windows from any angle.
		for _j in 2:
			var strip := MeshInstance3D.new()
			var sm := BoxMesh.new()
			sm.size = Vector3(0.4, h * randf_range(0.35, 0.7), w + 0.14)
			sm.material = win_mat
			strip.mesh = sm
			strip.position = Vector3(randf_range(-0.4, 0.4) * w, randf_range(-0.15, 0.1) * h, 0)
			strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.add_child(strip)

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
func _build_tasks(def: Dictionary) -> void:
	GameState.reset_tasks()
	var tasks: Array = def.get("tasks", [])
	if tasks.is_empty():
		tasks = [{"type": "kill_all"}]
	for t in tasks:
		match t.get("type", ""):
			"none":
				pass # sandbox level (e.g. the gun range): no checklist at all
			"kill_all":
				GameState.register_task("kill_all", "Eliminate all hostiles")
			"key":
				var id: String = t.get("id", "key")
				GameState.register_task(id, t.get("label", "Recover the access keycard"))
				var k := Keycard.new()
				k.task_id = id
				k.position = t.get("pos", Vector3.ZERO)
				add_child(k)
			"destroy_core":
				var id: String = t.get("id", "core")
				GameState.register_task(id, t.get("label", "Destroy the core"))
				var core := ObjectiveCore.new()
				core.task_id = id
				if t.has("color"):
					core.core_color = t["color"]
				if t.has("health"):
					core.max_health = t["health"]
				core.position = t.get("pos", Vector3.ZERO)
				add_child(core)
			"collect_shards":
				var id: String = t.get("id", "shards")
				var pts: Array = t.get("points", [])
				GameState.register_task(id, t.get("label", "Recover the data shards"), float(pts.size()))
				for sp in pts:
					var shard := ShardPickup.new()
					shard.task_id = id
					shard.position = sp
					add_child(shard)
			"hack_terminal", "sabotage":
				var id: String = t.get("id", t.get("type", "hack"))
				var secs: float = t.get("seconds", 3.0)
				GameState.register_task(id, t.get("label", "Hack the terminal"), secs)
				var con := HoldConsole.new()
				con.task_id = id
				con.hold_seconds = secs
				con.detonate = t.get("type", "") == "sabotage"
				if t.has("color"):
					con.accent = t["color"]
				con.position = t.get("pos", Vector3.ZERO)
				add_child(con)
			"survive":
				var id: String = t.get("id", "survive")
				var secs: float = t.get("seconds", 45.0)
				GameState.register_task(id, t.get("label", "Hold out against the assault"), secs)
				var timer := SurviveTimer.new()
				timer.task_id = id
				timer.seconds = secs
				add_child(timer)
			"hold_zone":
				var id: String = t.get("id", "hold")
				var secs: float = t.get("seconds", 12.0)
				GameState.register_task(id, t.get("label", "Hold the capture zone"), secs)
				var zone := HoldZone.new()
				zone.task_id = id
				zone.hold_seconds = secs
				if t.has("radius"):
					zone.radius = t["radius"]
				if t.has("color"):
					zone.accent = t["color"]
				zone.position = t.get("pos", Vector3.ZERO)
				add_child(zone)

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
	var pk := WEAPON_PICKUP.instantiate()
	pk.weapon_scene = ps
	pk.position = w["pos"]
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

## Hand-placed supply/powerup pickups (def "pickups": [{kind, pos}]). Campaign
## levels leave this empty (supplies drop from kills); the editor uses it.
func _build_pickups(def: Dictionary) -> void:
	for p in def.get("pickups", []):
		var scene: PackedScene = PICKUP_SCENES.get(p.get("kind", ""))
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
		var scene: PackedScene = ENEMY_SCENES.get(en["type"])
		if scene == null:
			continue
		var trig: float = en.get("trigger", 0.0)
		# "count" spawns a cluster from one entry (swarms): scattered around pos,
		# each its own spawner so they trigger/scale exactly like a single placed one.
		var count: int = maxi(1, int(en.get("count", 1)))
		var base_pos: Vector3 = en["pos"]
		for j in count:
			var sp := EnemySpawner.new()
			sp.enemy_scene = scene
			sp.position = base_pos if count == 1 else base_pos + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
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
