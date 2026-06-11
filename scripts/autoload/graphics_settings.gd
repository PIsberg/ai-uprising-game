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
## HIGH   — best looking: native res, all screen-space effects + GI +
##          volumetric fog, soft-high shadows + 8K sun shadow atlas, TAA,
##          dense ambient dust.
enum Quality { LOW, MEDIUM, HIGH }
var quality: Quality = Quality.HIGH

# Display / input preferences (also persisted to settings.cfg). The player reads
# fov / sensitivity / invert_y on spawn; max_fps applies immediately.
var fov: float = 85.0
var sensitivity: float = 1.0 ## Multiplier on the player's base look speed.
var invert_y: bool = false
var max_fps: int = 0 ## 0 = uncapped.

const FPS_OPTIONS := [0, 30, 60, 120, 144]

const SETTINGS_PATH := "user://settings.cfg"
const LABELS := ["LOW", "MEDIUM", "HIGH"]

func _ready() -> void:
	_load_settings()
	_apply_viewport.call_deferred()
	Engine.max_fps = max_fps

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
	return "Uncapped" if max_fps == 0 else "%d FPS" % max_fps

func is_high() -> bool:
	return quality == Quality.HIGH

func is_medium() -> bool:
	return quality == Quality.MEDIUM

func is_low() -> bool:
	return quality == Quality.LOW

func tier() -> int:
	return quality

func set_quality(q: int) -> void:
	quality = clampi(q, 0, Quality.size() - 1) as Quality
	_apply_viewport()
	_save_settings()

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
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.77
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = false
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		Quality.HIGH:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.use_taa = true
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_apply_shadow_quality()

func _apply_shadow_quality() -> void:
	var levels: Array[int] = [
		RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	]
	var dq: int = levels[int(quality)]
	RenderingServer.directional_soft_shadow_filter_set_quality(dq)
	RenderingServer.positional_soft_shadow_filter_set_quality(dq)
	# Shadow atlas budgets: resolution where you can see it (8K sun shadows on
	# HIGH are visibly crisper), memory/fill-rate savings where you can't.
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 8192][int(quality)], true)
	var vp := get_viewport()
	if vp:
		vp.positional_shadow_atlas_size = [2048, 4096, 4096][int(quality)]

# ---------- environment-level (applies at level load) ----------

## Dial a freshly-built level Environment to the active tier. The builder turns
## everything on by default; here we strip back the expensive effects for the
## lower tiers. GI (VoxelGI/SDFGI/reflection probe) is handled separately and is
## HIGH-only (see LevelBuilder._build_gi).
func apply_to_environment(env: Environment, open_sky: bool) -> void:
	if env == null:
		return
	match quality:
		Quality.HIGH:
			env.ssao_enabled = true
			env.ssil_enabled = true
			env.ssr_enabled = true
			env.volumetric_fog_enabled = not open_sky
		Quality.MEDIUM:
			env.ssao_enabled = true
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
		Quality.LOW:
			env.ssao_enabled = false
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
			# Trim the glow kernel to the cheapest few levels on low-end machines.
			env.glow_intensity = 0.3

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		quality = clampi(int(cf.get_value("video", "quality", Quality.HIGH)), 0, Quality.size() - 1) as Quality
		max_fps = maxi(0, int(cf.get_value("video", "max_fps", 0)))
		fov = clampf(float(cf.get_value("display", "fov", 85.0)), 60.0, 110.0)
		sensitivity = clampf(float(cf.get_value("input", "sensitivity", 1.0)), 0.2, 3.0)
		invert_y = bool(cf.get_value("input", "invert_y", false))

func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH) # preserve other sections (e.g. audio volume)
	cf.set_value("video", "quality", int(quality))
	cf.set_value("video", "max_fps", max_fps)
	cf.set_value("display", "fov", fov)
	cf.set_value("input", "sensitivity", sensitivity)
	cf.set_value("input", "invert_y", invert_y)
	cf.save(SETTINGS_PATH)
