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
	"sniper": preload("res://scenes/enemies/sniper.tscn"),
	"seeker": preload("res://scenes/enemies/seeker.tscn"),
	"overseer": preload("res://scenes/enemies/overseer.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
}
const PICKUP_SCENES := {
	"health": preload("res://scenes/pickups/health_pack.tscn"),
	"ammo": preload("res://scenes/pickups/ammo_box.tscn"),
}
const PROP_SCENES := {
	"car": preload("res://scenes/props/car.tscn"),
	"fence": preload("res://scenes/props/fence.tscn"),
	"crate": preload("res://scenes/props/crate.tscn"),
	"barrel": preload("res://scenes/props/barrel.tscn"),
}
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
	_build_gi(def)
	_build_accents(def)
	_build_atmosphere(def)
	_build_tasks(def)
	_build_exit(def)
	_build_pickups(def)
	_build_weapon_pickup(def)
	_spawn_enemies(def)
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
	else:
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = e.get("sky_top", Color(0.1, 0.12, 0.18))
		psm.sky_horizon_color = e.get("sky_horizon", Color(0.3, 0.3, 0.34))
		psm.ground_horizon_color = e.get("sky_horizon", Color(0.3, 0.3, 0.34))
		psm.ground_bottom_color = e.get("ground", Color(0.05, 0.05, 0.07))
		psm.sky_curve = 0.16
		psm.sky_energy_multiplier = e.get("sky_energy", 1.0)
		psm.ground_energy_multiplier = 0.6
		psm.sun_angle_max = 12.0   # crisp sun disc
		psm.sun_curve = 0.06       # tight falloff -> a glowing sun, not a smear
		psm.use_debanding = true
		sky.sky_material = psm
	sky.radiance_size = Sky.RADIANCE_SIZE_128 # sharper image-based reflections
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = e.get("ambient", Color(0.6, 0.65, 0.75))
	env.ambient_light_sky_contribution = e.get("sky_contribution", 0.5)
	env.ambient_light_energy = e.get("ambient_energy", 0.4) * 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.92
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
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.5 # only HDR highlights/emissives bloom; sky stays crisp
	env.glow_hdr_scale = 1.0
	# Soft filmic halo around emissives — narrow kernel keeps the scene crisp.
	env.set("glow_levels/3", 1.0)
	env.set("glow_levels/4", 0.4)

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
		env.volumetric_fog_albedo = Color(0.7, 0.75, 0.8)
		env.volumetric_fog_length = 80.0
		env.volumetric_fog_gi_inject = 0.25
	else:
		env.volumetric_fog_enabled = false

	# Filmic grade: gentle teal shadows / warm highlights, lifted contrast.
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.95
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.06
	
	# Scalability: the chosen quality tier strips back the most expensive
	# screen-space effects so lower-end machines stay smooth. HIGH keeps it all.
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("apply_to_environment"):
		gs.apply_to_environment(env, def.get("open_sky", false))

	_env = env
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = e.get("sun_rot", Vector3(-50, -40, 0))
	sun.light_color = e.get("sun_color", Color(1, 0.95, 0.9))
	sun.light_energy = e.get("sun_energy", 1.0)
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

	for l in def.get("lights", []):
		var omni := OmniLight3D.new()
		omni.position = l["pos"]
		omni.light_color = l.get("color", Color(1, 1, 1))
		omni.light_energy = l.get("energy", 2.0)
		omni.omni_range = l.get("range", 16.0)
		omni.shadow_enabled = true
		omni.shadow_bias = 0.03
		omni.shadow_blur = 1.5
		omni.light_specular = 0.6
		add_child(omni)

	# Atmospheric ambient bed: wind outdoors, industrial room tone indoors.
	var amb := "ambience_wind" if def.get("open_sky", false) else "ambience_drone"
	AudioBus.play_ambience(amb, -22.0)
	# Per-theme music track (def can override; otherwise mapped from level_id).
	var music_id: String = def.get("music", LEVEL_MUSIC.get(level_id, "music_techno"))
	AudioBus.play_music(music_id)

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
	if def.has("floor_color"):
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

## Suburban houses: a coloured collidable box (added to the navmesh as an
## obstacle) plus a non-colliding peaked prism roof on top. Data-driven via the
## def's optional "buildings" list: {pos, size, color?, roof_color?, roof?}.
func _build_buildings(def: Dictionary) -> void:
	for b in def.get("buildings", []):
		var size: Vector3 = b["size"]
		var pos: Vector3 = b["pos"]
		var color: Color = b.get("color", Color(0.7, 0.68, 0.62))
		# House body — solid + collidable so it blocks shots and movement.
		_add_box(pos, size, _color_material(color))
		# Peaked roof (visual only) sitting on top of the body.
		if b.get("roof", true):
			var roof_h: float = b.get("roof_height", maxf(1.2, size.x * 0.35))
			var roof := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(size.x * 1.08, roof_h, size.z * 1.08)
			roof.mesh = pm
			roof.material_override = _color_material(b.get("roof_color", Color(0.35, 0.18, 0.14)))
			roof.position = pos + Vector3(0, size.y * 0.5 + roof_h * 0.5, 0)
			add_child(roof)

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
	p.position = Vector3(0, 3.5, 0)
	add_child(p)

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
	# A locked-until-cleared portal that builds its own animated visuals.
	var portal := Portal.new()
	portal.objective_text = def.get("objective", "Reach the extraction beacon")
	portal.position = def.get("exit", Vector3(0, 1.5, 0))
	add_child(portal)

func _build_pickups(def: Dictionary) -> void:
	for p in def.get("pickups", []):
		var scene: PackedScene = PICKUP_SCENES.get(p["type"])
		if scene == null:
			continue
		var pk := scene.instantiate() as Node3D
		pk.position = p["pos"]
		add_child(pk)

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
	if p:
		p.global_position = def.get("spawn", Vector3(0, 0.5, 0))

func _apply_objective_text(def: Dictionary) -> void:
	var hud := get_node_or_null("HUD")
	if hud and hud.has_method("set_objective"):
		var text: String = def.get("objective", "Eliminate the AI and reach the beacon")
		hud.set_objective("%s  ·  [%s]" % [text, GameState.difficulty_label()])

# ---------- navmesh ----------

func _bake_navmesh() -> void:
	if _nav_region and _nav_region.navigation_mesh and is_inside_tree():
		_nav_region.bake_navigation_mesh(false)
