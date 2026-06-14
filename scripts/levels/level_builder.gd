extends Node3D
## Data-driven level constructor. Reads a definition from LevelDefs keyed by
## `level_id` and builds the whole playable space at runtime: themed sky/fog/
## lighting, floor + walls + cover, accent strips, the exit beacon, pickups and
## enemy spawners — then bakes a navmesh so ground robots can path.
##
## Keeping levels as data (not hand-authored .tscn) makes them compact, easy to
## tweak, and trivial to validate headless.

@export var level_id: String = "gpt"

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
]
const WEAPON_PICKUP := preload("res://scenes/pickups/weapon_pickup.tscn")
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
	var def := LevelDefs.get_def(level_id)
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
	_build_gi(def)
	_build_accents(def)
	_build_atmosphere(def)
	_build_light_shafts(def)
	_build_accent_strips(def)
	_build_signage(def)
	_build_floor_seams(def)
	_build_grime(def)
	_build_cover_trim(def)
	_build_puddles(def)
	_build_pipes(def)
	_build_rubble(def)
	_build_beacons(def)
	_build_skyline(def)
	_build_sky_traffic(def)
	_build_stars(def)
	_build_tasks(def)
	_build_exit(def)
	_build_weapon_pickup(def)
	_build_targets(def)
	_build_lore(def)
	_spawn_enemies(def)
	_build_horde(def)
	_place_player(def)
	_build_set_piece(def)
	_apply_objective_text(def)
	GameState.apply_level_scaling(self) # difficulty: tune enemy/pickup counts
	_bake_navmesh.call_deferred()

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
	env.fog_density = e.get("fog_density", 0.01)
	env.fog_aerial_perspective = 0.25
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
		env.volumetric_fog_albedo = Color(0.7, 0.75, 0.8)
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
	var li := 0
	for l in def.get("lights", []):
		var omni := OmniLight3D.new()
		omni.position = l["pos"]
		omni.light_color = l.get("color", Color(1, 1, 1))
		# Slightly hotter than authored: with the ambient cut, these are the
		# scene's primary illumination and their pools must read.
		omni.light_energy = l.get("energy", 2.0) * 1.2
		omni.omni_range = l.get("range", 16.0)
		omni.shadow_enabled = li < shadow_budget
		omni.shadow_bias = 0.03
		omni.shadow_blur = 1.5
		omni.light_specular = 0.6
		add_child(omni)
		# Every light gets a visible SOURCE instead of hanging disembodied:
		# ceiling luminaires indoors, slim floodlight pylons outdoors.
		if not def.get("open_sky", false):
			_add_light_fixture(l["pos"], l.get("color", Color(1, 1, 1)))
		else:
			_add_light_pylon(l["pos"], l.get("color", Color(1, 1, 1)))
		# The last placed light gets a faulty-wiring flicker: occupied
		# infrastructure failing, and motion in otherwise static lighting.
		if li == def.get("lights", []).size() - 1:
			_flicker_light(omni)
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

	# Atmospheric ambient bed: wind outdoors, industrial room tone indoors.
	var amb := "ambience_wind" if def.get("open_sky", false) else "ambience_drone"
	AudioBus.play_ambience(amb, -22.0)
	# Per-theme music track (def can override; otherwise mapped from level_id).
	var music_id: String = def.get("music", LEVEL_MUSIC.get(level_id, "music_techno"))
	AudioBus.play_music(music_id)

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
func _flicker_light(light: OmniLight3D) -> void:
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
		add_child(mi)

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

## Panel seams ruled across interior floors: thin recess-dark strips every few
## metres in both axes. Breaks the monotony of a large single-material slab and
## makes the floor read as constructed deck plating. A handful of long boxes.
func _build_floor_seams(def: Dictionary) -> void:
	if def.get("open_sky", false):
		return # outdoor asphalt/dirt isn't panelled
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var mat := _color_material(Color(0.07, 0.075, 0.09), 0.9)
	var spacing := 6.5
	var x := -fs.x * 0.5 + spacing
	while x < fs.x * 0.5 - 1.0:
		_seam_strip(Vector3(x, 0.008, 0), Vector3(0.1, 0.016, fs.y - 1.4), mat)
		x += spacing
	var z := -fs.y * 0.5 + spacing
	while z < fs.y * 0.5 - 1.0:
		_seam_strip(Vector3(0, 0.008, z), Vector3(fs.x - 1.4, 0.016, 0.1), mat)
		z += spacing

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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.025, 0.035, 0.92)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.85
	mat.roughness = 0.04
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	for i in count:
		var p := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(randf_range(1.6, 3.6), randf_range(1.2, 2.8))
		pm.material = mat
		p.mesh = pm
		p.position = Vector3(randf_range(-fs.x * 0.42, fs.x * 0.42), 0.012, randf_range(-fs.y * 0.42, fs.y * 0.42))
		p.rotation.y = randf() * TAU
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)

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
		var sp := EnemySpawner.new()
		sp.enemy_scene = scene
		sp.position = en["pos"]
		var trig: float = en.get("trigger", 0.0)
		if trig > 0.0:
			sp.spawn_on_ready = false
			sp.trigger_radius = trig
		else:
			sp.spawn_on_ready = true
			sp.spawn_delay = 0.4 # let the navmesh bake land first
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
