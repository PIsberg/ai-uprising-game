extends Node
## Runtime graphics quality with three tiers. Levels consult this at load time
## (heavy screen-space effects, GI, volumetric fog, ambient detail) and the
## viewport reacts immediately (render scale, anti-aliasing, shadow filtering).
## The chosen tier persists to user://settings.cfg so it survives restarts.
##
## LOW    — best performance: FSR2 from 67% internal res, no SSAO/SSIL/SSR/
##          volumetric/GI, hard shadows + small atlases, no ambient dust.
## MEDIUM — balanced: FSR2 from 77% internal res, SSAO only, soft-low shadows,
##          light ambient dust.
## HIGH   — great looking: native res, all screen-space effects + GI +
##          volumetric fog, soft-high shadows + 8K sun shadow atlas, TAA,
##          dense ambient dust.
## ULTRA  — no compromises: HIGH plus MSAA 2x layered under TAA, ultra-soft
##          shadow filtering, an 8K positional shadow atlas, longer SSR
##          marches and ~40% denser ambient detail (dust/stars/puddles/grime).
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
var quality: Quality = Quality.HIGH

# Display / input preferences (also persisted to settings.cfg). The player reads
# fov / sensitivity / invert_y on spawn; max_fps applies immediately.
var fov: float = 85.0
var sensitivity: float = 1.0 ## Multiplier on the player's base look speed.
var invert_y: bool = false
var max_fps: int = 0 ## 0 = uncapped.

# Advanced graphics settings (toggled independently in the settings menu)
var gpu_particles_enabled: bool = true
var volumetric_noise_enabled: bool = true
var robot_triplanar_enabled: bool = true
var puddle_ripples_enabled: bool = true
var advanced_post_process_enabled: bool = true
## Interior ceiling luminaires emit from real rectangular AreaLight3D sources
## (Godot 4.7) instead of a point light, for soft directional pools + correct
## soft shadows. Pricier than an omni, so it only kicks in on HIGH/ULTRA.
var area_lights_enabled: bool = true
## Request HDR display output (Godot 4.7). The renderer already works in HDR
## internally; this lets the swap-chain hand that wider range to an HDR monitor
## instead of clamping to SDR. Off by default — harmless no-op where the
## platform/display can't honor it, but only beneficial on real HDR displays.
var hdr_output_enabled: bool = false
## Gamepad aim friction (eases look speed near a target). On by default; some
## players prefer raw stick aim, so it's toggleable. Mouse aim is never affected.
var aim_assist: bool = true
## Show a live FPS counter in the HUD's top-left corner. Off by default; the HUD
## reads this each frame and shows/hides its counter accordingly.
var show_fps: bool = false
## Cinematic depth-of-field: blurs whatever the player isn't looking at. Off by
## default — full-screen blur can hurt target readability in a shooter; the
## player's DoF overlay polls this each frame.
var dof_enabled: bool = false
## Accessibility: scales all gameplay camera shake (1.0 = full, 0 = none). The
## player reads this each frame and multiplies its trauma by it — for players who
## find heavy screen shake nauseating.
var screen_shake: float = 1.0
## Accessibility: scales the intensity of full-screen flashes — the red damage
## overlay, low-health vignette pulse and kill-edge flash. 1.0 = full, 0 = none.
## The HUD reads this each frame (photosensitivity / epilepsy safety).
var flash_intensity: float = 1.0

const FPS_OPTIONS := [0, 30, 60, 120, 144]

const SETTINGS_PATH := "user://settings.cfg"
const LABELS := ["LOW", "MEDIUM", "HIGH", "ULTRA"]

## Selectable UI languages: [locale code, native display name]. English is the
## default and the fallback for any string a language hasn't translated yet.
const LANGUAGES := [
	["en", "English"],
	["es", "Español"],
	["fr", "Français"],
	["de", "Deutsch"],
	["pt", "Português"],
]
var language: String = "en"

func _ready() -> void:
	_load_settings()
	TranslationServer.set_locale(language)
	_apply_viewport.call_deferred()
	_apply_hdr_output.call_deferred()
	Engine.max_fps = max_fps

## Switch UI language live and persist it. Controls re-translate automatically;
## menus that build text in code should refresh/reload after calling this.
func set_language(code: String) -> void:
	language = code
	TranslationServer.set_locale(code)
	_save_settings()

func language_index() -> int:
	for i in LANGUAGES.size():
		if LANGUAGES[i][0] == language:
			return i
	return 0

func set_fov(v: float) -> void:
	fov = clampf(v, 60.0, 110.0)
	_save_settings()

func set_sensitivity(v: float) -> void:
	sensitivity = clampf(v, 0.2, 3.0)
	_save_settings()

func set_invert_y(v: bool) -> void:
	invert_y = v
	_save_settings()

## y multiplier for look input: -1 when inverted, +1 otherwise.
func look_y_sign() -> float:
	return -1.0 if invert_y else 1.0

func set_max_fps(v: int) -> void:
	max_fps = maxi(0, v)
	Engine.max_fps = max_fps
	_save_settings()

func cycle_fps() -> void:
	var idx := FPS_OPTIONS.find(max_fps)
	set_max_fps(FPS_OPTIONS[(idx + 1) % FPS_OPTIONS.size()] if idx != -1 else 60)

func fps_label() -> String:
	return tr("Uncapped") if max_fps == 0 else tr("%d FPS") % max_fps

## "At least HIGH" — ULTRA inherits everything gated on this.
func is_high() -> bool:
	return quality >= Quality.HIGH

func is_medium() -> bool:
	return quality == Quality.MEDIUM

func is_low() -> bool:
	return quality == Quality.LOW

func tier() -> int:
	return quality

## Build interior lights as AreaLight3D rather than OmniLight3D. Gated to
## HIGH/ULTRA — area lights cost more and the lower tiers want the headroom.
func use_area_lights() -> bool:
	return area_lights_enabled and int(quality) >= Quality.HIGH

## Whether interior area lights may cast shadows (still bounded by the per-tier
## shadowed-light budget at the build site).
func area_light_shadows() -> bool:
	return int(quality) >= Quality.HIGH

func set_quality(q: int) -> void:
	quality = clampi(q, 0, Quality.size() - 1) as Quality
	_apply_viewport()
	_apply_to_live_environment()
	_save_settings()

# ---------- advanced settings triggers ----------

func set_gpu_particles_enabled(v: bool) -> void:
	gpu_particles_enabled = v
	_save_settings()

func set_volumetric_noise_enabled(v: bool) -> void:
	volumetric_noise_enabled = v
	_apply_to_live_light_shafts()
	_save_settings()

func set_robot_triplanar_enabled(v: bool) -> void:
	robot_triplanar_enabled = v
	_apply_to_live_robots()
	_save_settings()

func set_puddle_ripples_enabled(v: bool) -> void:
	puddle_ripples_enabled = v
	_apply_to_live_puddles()
	_save_settings()

func set_advanced_post_process_enabled(v: bool) -> void:
	advanced_post_process_enabled = v
	_apply_to_live_post_process()
	_save_settings()

## Takes effect on the next level load (lights are built at level construction).
func set_area_lights_enabled(v: bool) -> void:
	area_lights_enabled = v
	_save_settings()

## Applies to the live player immediately and persists.
func set_aim_assist(v: bool) -> void:
	aim_assist = v
	var p := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if p and "aim_assist_enabled" in p:
		p.aim_assist_enabled = v
	_save_settings()

## Show/hide the HUD FPS counter (the HUD polls show_fps each frame).
func set_show_fps(v: bool) -> void:
	show_fps = v
	_save_settings()

## Toggle cinematic depth-of-field (the player's DoF overlay polls dof_enabled).
func set_dof_enabled(v: bool) -> void:
	dof_enabled = v
	_save_settings()

## Accessibility: 0..1 scale on gameplay camera shake (the player polls it).
func set_screen_shake(v: float) -> void:
	screen_shake = clampf(v, 0.0, 1.0)
	_save_settings()

## Accessibility: 0..1 scale on full-screen flashes (the HUD polls it).
func set_flash_intensity(v: float) -> void:
	flash_intensity = clampf(v, 0.0, 1.0)
	_save_settings()

## Applies immediately (the swap-chain re-requests HDR live).
func set_hdr_output_enabled(v: bool) -> void:
	hdr_output_enabled = v
	_apply_hdr_output()
	_save_settings()

## Ask the OS/swap-chain for HDR output and let 2D composite in HDR so the UI
## doesn't clip the brighter range. No-op on platforms/displays that decline.
func _apply_hdr_output() -> void:
	# Godot 4.7 properties (parse-checked against the pinned engine): the window
	# asks the OS swap-chain for HDR; the viewport composites 2D/UI in HDR so the
	# brighter range isn't clipped before output. The window honors the request
	# only on capable platforms/displays, otherwise it's a silent no-op.
	var w := get_window()
	if w == null:
		return
	# Guard the property writes: these are 4.7-only. Probing with `in` keeps an
	# older engine (or a headless CI still on 4.6) from hard-erroring on boot
	# instead of degrading to a no-op.
	if "hdr_output_requested" in w:
		w.hdr_output_requested = hdr_output_enabled
	var vp := get_viewport()
	if vp and "use_hdr_2d" in vp:
		vp.use_hdr_2d = hdr_output_enabled

func _apply_to_live_robots() -> void:
	if not is_inside_tree():
		return
	for r in get_tree().get_nodes_in_group("robot_models"):
		if r.has_method("update_advanced_materials"):
			r.update_advanced_materials()
	for s in get_tree().get_nodes_in_group("shield_enemies"):
		if s.has_method("update_shield_settings"):
			s.update_shield_settings()

func _apply_to_live_puddles() -> void:
	if not is_inside_tree():
		return
	for p in get_tree().get_nodes_in_group("puddle_meshes"):
		if p is MeshInstance3D:
			apply_puddle_material_to_node(p)

func _apply_to_live_post_process() -> void:
	if not is_inside_tree():
		return
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("update_post_process_settings"):
		player.update_post_process_settings()

func apply_puddle_material_to_node(p: MeshInstance3D) -> void:
	if puddle_ripples_enabled:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/puddle.gdshader")
		sm.set_shader_parameter("water_color", Color(0.015, 0.022, 0.032, 0.92))
		sm.set_shader_parameter("metallic", 0.9)
		sm.set_shader_parameter("roughness_wet", 0.03)
		sm.set_shader_parameter("wave_scale", 16.0)
		sm.set_shader_parameter("ripple_speed", 1.3)
		sm.set_shader_parameter("ripples_enabled", true)
		p.material_override = sm
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.02, 0.025, 0.035, 0.92)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = 0.85
		mat.roughness = 0.04
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		p.material_override = mat

func _apply_to_live_light_shafts() -> void:
	if not is_inside_tree():
		return
	for mi in get_tree().get_nodes_in_group("light_shaft_meshes"):
		if mi is MeshInstance3D and mi.mesh is CylinderMesh:
			var col: Color = mi.get_meta("light_color", Color.WHITE)
			if volumetric_noise_enabled:
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://shaders/light_shaft.gdshader")
				sm.set_shader_parameter("color", col)
				sm.set_shader_parameter("intensity", 0.35)
				sm.set_shader_parameter("noise_enabled", true)
				mi.mesh.material = sm
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
				mi.mesh.material = m

# ---------- particle instantiation helper ----------

func create_particles(
	amount: int,
	lifetime: float,
	explosiveness: float,
	direction: Vector3,
	spread: float,
	gravity: Vector3,
	vel_min: float,
	vel_max: float,
	scale_min: float,
	scale_max: float,
	mesh: Mesh,
	color_ramp: Gradient = null,
	scale_curve: Curve = null,
	angle_max: float = 0.0,
	angular_velocity_max: float = 0.0
) -> Node3D:
	if gpu_particles_enabled:
		var p := GPUParticles3D.new()
		p.amount = amount
		p.lifetime = lifetime
		p.explosiveness = explosiveness
		p.one_shot = true
		p.emitting = true
		p.local_coords = false
		p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.draw_pass_1 = mesh  # GPUParticles3D draws via draw_pass_N, not a `mesh` property
		
		var pm := ParticleProcessMaterial.new()
		pm.direction = direction
		pm.spread = spread
		pm.gravity = gravity
		pm.initial_velocity_min = vel_min
		pm.initial_velocity_max = vel_max
		pm.scale_min = scale_min
		pm.scale_max = scale_max
		
		# Collision settings for GPUParticles
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_friction = 0.25
		pm.collision_bounce = 0.5
		
		if color_ramp:
			var grad_tex := GradientTexture1D.new()
			grad_tex.gradient = color_ramp
			pm.color_ramp = grad_tex
		if scale_curve:
			var curve_tex := CurveTexture.new()
			curve_tex.curve = scale_curve
			pm.scale_curve = curve_tex
		# Optional spin — 4.7's richer per-particle rotation makes tumbling debris read.
		if angle_max > 0.0:
			pm.angle_min = -angle_max
			pm.angle_max = angle_max
		if angular_velocity_max > 0.0:
			pm.angular_velocity_min = -angular_velocity_max
			pm.angular_velocity_max = angular_velocity_max

		p.process_material = pm
		return p
	else:
		var p := CPUParticles3D.new()
		p.amount = amount
		p.lifetime = lifetime
		p.explosiveness = explosiveness
		p.one_shot = true
		p.emitting = true
		p.local_coords = false
		p.draw_order = CPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		p.mesh = mesh
		p.direction = direction
		p.spread = spread
		p.gravity = gravity
		p.initial_velocity_min = vel_min
		p.initial_velocity_max = vel_max
		p.scale_amount_min = scale_min
		p.scale_amount_max = scale_max
		if color_ramp:
			p.color_ramp = color_ramp
		if scale_curve:
			p.scale_amount_curve = scale_curve
		if angle_max > 0.0:
			p.angle_min = -angle_max
			p.angle_max = angle_max
		if angular_velocity_max > 0.0:
			p.angular_velocity_min = -angular_velocity_max
			p.angular_velocity_max = angular_velocity_max
		return p

## Re-tier the environment of the level that's running RIGHT NOW, so picking a
## quality mid-game visibly strips/restores SSAO/SSR/volumetrics immediately
## instead of waiting for the next level load. The builder tags its
## WorldEnvironment with an "open_sky" meta; hand-authored scenes default to
## indoor rules.
func _apply_to_live_environment() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for we in scene.find_children("*", "WorldEnvironment", true, false):
		var env := (we as WorldEnvironment).environment
		if env:
			apply_to_environment(env, bool(we.get_meta("open_sky", false)))

## Rotate LOW -> MEDIUM -> HIGH -> LOW (drives the single Graphics button).
func cycle() -> void:
	set_quality((int(quality) + 1) % Quality.size())

func quality_label() -> String:
	return LABELS[int(quality)]

## Multiplier some systems use to scale optional detail (ambient particles, etc).
func detail_scale() -> float:
	match quality:
		Quality.LOW: return 0.0
		Quality.MEDIUM: return 0.5
		Quality.ULTRA: return 1.4
		_: return 1.0

# ---------- viewport-level (applies immediately) ----------

func _apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	match quality:
		Quality.LOW:
			# FSR2 reconstructs near-native detail from a lower internal res —
			# sharper than bilinear was at 70%, with more GPU headroom. It has
			# temporal AA built in, so TAA/FXAA stay off.
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.67
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		Quality.MEDIUM:
			# Less aggressive upscale than before (was 0.77) so the distance reads
			# sharper; FSR2 reconstructs the rest.
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.85
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		Quality.HIGH:
			# Native res with MSAA, NOT TAA: TAA's temporal accumulation softens
			# fine distant detail (the "blurry in the distance" look). MSAA keeps
			# edges clean while the image stays crisp.
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_2X
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		Quality.ULTRA:
			# Native res with heavy MSAA — the sharpest, cleanest image. TAA off so
			# the distance stays crisp; 4x MSAA carries the edge anti-aliasing.
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_4X
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_apply_shadow_quality()

func _apply_shadow_quality() -> void:
	var levels: Array[int] = [
		RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		RenderingServer.SHADOW_QUALITY_SOFT_ULTRA,
	]
	var dq: int = levels[int(quality)]
	RenderingServer.directional_soft_shadow_filter_set_quality(dq)
	RenderingServer.positional_soft_shadow_filter_set_quality(dq)
	# Shadow atlas budgets: resolution where you can see it (8K sun shadows on
	# HIGH are visibly crisper), memory/fill-rate savings where you can't.
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192, 8192][int(quality)], true)
	var vp := get_viewport()
	if vp:
		vp.positional_shadow_atlas_size = [2048, 4096, 4096, 8192][int(quality)]

# ---------- environment-level (applies at level load) ----------

## Dial a freshly-built level Environment to the active tier. The builder turns
## everything on by default; here we strip back the expensive effects for the
## lower tiers. GI (VoxelGI/SDFGI/reflection probe) is handled separately and is
## HIGH-only (see LevelBuilder._build_gi).
func apply_to_environment(env: Environment, open_sky: bool) -> void:
	if env == null:
		return
	match quality:
		Quality.ULTRA:
			env.ssao_enabled = true
			env.ssil_enabled = true
			env.ssr_enabled = true
			env.ssr_max_steps = 64 # longer marches: reflections persist further
			env.volumetric_fog_enabled = not open_sky
			_restore_glow(env)
		Quality.HIGH:
			env.ssao_enabled = true
			env.ssil_enabled = true
			env.ssr_enabled = true
			env.volumetric_fog_enabled = not open_sky
			_restore_glow(env)
		Quality.MEDIUM:
			env.ssao_enabled = true
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
			_restore_glow(env)
		Quality.LOW:
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
			# Trim the glow kernel to the cheapest few levels on low-end
			# machines — remembering the authored value for live re-tiering.
			if not env.has_meta("glow_base"):
				env.set_meta("glow_base", env.glow_intensity)
			env.glow_intensity = 0.3

func _restore_glow(env: Environment) -> void:
	if env.has_meta("glow_base"):
		env.glow_intensity = env.get_meta("glow_base")

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		quality = clampi(int(cf.get_value("video", "quality", Quality.HIGH)), 0, Quality.size() - 1) as Quality
		max_fps = maxi(0, int(cf.get_value("video", "max_fps", 0)))
		fov = clampf(float(cf.get_value("display", "fov", 85.0)), 60.0, 110.0)
		sensitivity = clampf(float(cf.get_value("input", "sensitivity", 1.0)), 0.2, 3.0)
		invert_y = bool(cf.get_value("input", "invert_y", false))
		language = String(cf.get_value("locale", "language", "en"))
		
		# Load advanced options
		gpu_particles_enabled = bool(cf.get_value("graphics_adv", "gpu_particles", true))
		volumetric_noise_enabled = bool(cf.get_value("graphics_adv", "volumetric_noise", true))
		robot_triplanar_enabled = bool(cf.get_value("graphics_adv", "robot_triplanar", true))
		puddle_ripples_enabled = bool(cf.get_value("graphics_adv", "puddle_ripples", true))
		advanced_post_process_enabled = bool(cf.get_value("graphics_adv", "advanced_post_process", true))
		area_lights_enabled = bool(cf.get_value("graphics_adv", "area_lights", true))
		aim_assist = bool(cf.get_value("input", "aim_assist", true))
		hdr_output_enabled = bool(cf.get_value("graphics_adv", "hdr_output", false))
		show_fps = bool(cf.get_value("graphics_adv", "show_fps", false))
		dof_enabled = bool(cf.get_value("graphics_adv", "depth_of_field", false))
		screen_shake = float(cf.get_value("graphics_adv", "screen_shake", 1.0))
		flash_intensity = float(cf.get_value("graphics_adv", "flash_intensity", 1.0))

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH) # preserve other sections (e.g. audio volume)
	cf.set_value("video", "quality", int(quality))
	cf.set_value("video", "max_fps", max_fps)
	cf.set_value("display", "fov", fov)
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("input", "invert_y", invert_y)
	cf.set_value("locale", "language", language)
	
	# Save advanced options
	cf.set_value("graphics_adv", "gpu_particles", gpu_particles_enabled)
	cf.set_value("graphics_adv", "volumetric_noise", volumetric_noise_enabled)
	cf.set_value("graphics_adv", "robot_triplanar", robot_triplanar_enabled)
	cf.set_value("graphics_adv", "puddle_ripples", puddle_ripples_enabled)
	cf.set_value("graphics_adv", "advanced_post_process", advanced_post_process_enabled)
	cf.set_value("graphics_adv", "area_lights", area_lights_enabled)
	cf.set_value("input", "aim_assist", aim_assist)
	cf.set_value("graphics_adv", "hdr_output", hdr_output_enabled)
	cf.set_value("graphics_adv", "show_fps", show_fps)
	cf.set_value("graphics_adv", "depth_of_field", dof_enabled)
	cf.set_value("graphics_adv", "screen_shake", screen_shake)
	cf.set_value("graphics_adv", "flash_intensity", flash_intensity)

	cf.save(SETTINGS_PATH)
