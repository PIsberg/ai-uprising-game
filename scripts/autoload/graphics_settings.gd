# @lat: [[architecture#Autoloads#GraphicsSettings]]
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
## HIGH   — great looking: native res, all screen-space effects + reflection
##          probe + volumetric fog, soft-high shadows + 8K sun shadow atlas,
##          TAA, dense ambient dust.
## ULTRA  — no compromises: HIGH plus a baked VoxelGI real-time bounce pass
##          (indoor levels), MSAA 2x layered under TAA, ultra-soft shadow
##          filtering, an 8K positional shadow atlas, longer SSR marches and
##          ~40% denser ambient detail (dust/stars/puddles/grime).
enum Quality { LOW, MEDIUM, HIGH, ULTRA }
var quality: Quality = Quality.HIGH

## True for exactly one boot: the very first time this install has ever
## loaded settings.cfg (no "video"/"quality" key yet). GPU-name heuristics lie
## constantly (integrated vs discrete naming, driver string differences) — a
## short measured render burn (see QualityBenchmark) behind the main menu is
## honest about what this machine can push, so the menu benchmarks once and
## picks a starting tier instead of guessing. Existing installs never see
## this go true again once a quality key exists. Defaults to HIGH pre-benchmark
## (the fallback if the benchmark can't run, e.g. headless).
var needs_auto_quality: bool = false

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
## Accessibility: scales gamepad rumble (1.0 = full, 0 = off). Mirrored into
## the static Haptics helper so the per-shot call sites stay autoload-free.
var rumble: float = 1.0
## 3D resolution scale, independent of the quality tier. 1.0 = native (sharp, no
## upscaling); below 1.0 renders at a lower internal res and FSR2-upscales (faster,
## softer in the distance). Lets you keep effects low for perf without the blur.
var render_scale: float = 1.0
## Accessibility: brightness multiplier applied on top of whatever a level (or
## the cutscene player) already authored for Environment.adjustment_brightness.
## 1.0 = no change. Read by apply_to_environment() (see _apply_brightness),
## which remembers each Environment's authored base value in metadata so this
## never clobbers a level's own cinematic grading — it only scales it.
var brightness: float = 1.0
## Accessibility: HUD reads this before showing overlord taunt subtitles and
## arcade kill callouts (HEADSHOT / streak words). On by default. NOTE: hud.gd
## is owned by another agent — see report for the exact one-line reads to add.
var combat_callouts_enabled: bool = true
## Accessibility: whether floating damage numbers pop on hit. On by default.
## NOTE: scripts/systems/damageable.gd is the read site — see report handoff.
var damage_numbers_enabled: bool = true

## Named color-grade presets applied by the post-process shader: [tint (R,G,B),
## contrast, saturation]. NEUTRAL is a no-op; the rest each push a distinct mood.
enum ColorGrade { NEUTRAL, COLD_STEEL, WARM_AMBER, HIGH_CONTRAST }
const COLOR_GRADE_LABELS := ["Neutral", "Cold Steel", "Warm Amber", "High Contrast"]
const COLOR_GRADE_PARAMS := {
	ColorGrade.NEUTRAL:       {"tint": Color(1.0, 1.0, 1.0), "contrast": 1.0, "saturation": 1.0},
	ColorGrade.COLD_STEEL:    {"tint": Color(0.9, 0.97, 1.06), "contrast": 1.08, "saturation": 0.88},
	ColorGrade.WARM_AMBER:    {"tint": Color(1.08, 0.98, 0.85), "contrast": 1.05, "saturation": 1.05},
	ColorGrade.HIGH_CONTRAST: {"tint": Color(1.0, 1.0, 1.0), "contrast": 1.28, "saturation": 1.15},
}
var color_grade: ColorGrade = ColorGrade.NEUTRAL

const FPS_OPTIONS := [0, 30, 60, 120, 144]

const SETTINGS_PATH := "user://settings.cfg"
const LABELS := ["LOW", "MEDIUM", "HIGH", "ULTRA"]

## Batch-configure presets for the whole graphics feature set (see apply_preset
## below). Plain int constants rather than an enum — an enum named e.g.
## "QUALITY"/"ULTRA" would collide with the bare Quality.QUALITY/ULTRA constants
## GDScript already exposes in this script's scope.
const PRESET_PERFORMANCE := 0
const PRESET_BALANCED := 1
const PRESET_QUALITY := 2
const PRESET_ULTRA := 3
const PRESET_LABELS := ["Performance", "Balanced", "Quality", "Ultra"]

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

## Window presentation mode. BORDERLESS (a full-screen *window*, no exclusive
## mode switch) is the default because it matches project.godot's existing
## window/size/mode=3 boot default — adding this picker shouldn't change how
## the game already presents itself on a fresh install.
enum WindowMode { FULLSCREEN, BORDERLESS, WINDOWED }
const WINDOW_MODE_LABELS := ["Fullscreen", "Borderless", "Windowed"]
var window_mode: WindowMode = WindowMode.BORDERLESS

# ---------- key rebinding ----------
#
# Ordering guarantee: InputMap actions come from three sources —
#   1) project.godot [input] — present the instant the engine boots, before
#      any script runs.
#   2) GameState._setup_gamepad_bindings() — runs in GameState._ready(). Per
#      project.godot's [autoload] order (GameState, AudioBus, SoundSynth,
#      GraphicsSettings, AIDirector), GameState is always initialized BEFORE
#      GraphicsSettings, so its gamepad defaults are already in InputMap by
#      the time we get here.
#   3) player.gd / weapon_manager.gd — register "dash"/"melee"/"grapple" and
#      "alt_fire" lazily, guarded by `if not InputMap.has_action(...)`, only
#      once their owning node (Player / WeaponManager) enters the tree (i.e.
#      once a level actually loads — NOT at main-menu time).
#
# apply_keybinds() (called from _ready below, synchronously, no defer needed —
# InputMap doesn't need a live viewport/window) closes the gap for (3) itself:
# for every action we know how to rebind, if InputMap doesn't have it yet we
# add it right now with its factory-default (or saved override) events. That
# pre-empts player.gd/weapon_manager.gd's own lazy registration — their guard
# sees the action already exists and no-ops — so a saved override for melee/
# grapple/alt_fire is already live even if the rebind screen is opened (or the
# game just boots to the main menu) before any level has ever been played.

## Rebindable actions shown on the rebind screen, in display order. A few
## (melee/grapple/alt_fire) aren't in project.godot at all — see the ordering
## note above for why apply_keybinds() still handles them safely.
const KEYBIND_ACTIONS := [
	{"action": "move_forward", "label": "Move Forward"},
	{"action": "move_back", "label": "Move Back"},
	{"action": "move_left", "label": "Move Left"},
	{"action": "move_right", "label": "Move Right"},
	{"action": "jump", "label": "Jump"},
	{"action": "sprint", "label": "Sprint"},
	{"action": "crouch", "label": "Crouch"},
	{"action": "dash", "label": "Dash"},
	{"action": "melee", "label": "Melee Shove"},
	{"action": "grapple", "label": "Grapple Hook"},
	{"action": "fire", "label": "Fire"},
	{"action": "aim", "label": "Aim Down Sight"},
	{"action": "alt_fire", "label": "Weapon Alt-Fire"},
	{"action": "reload", "label": "Reload"},
	{"action": "interact", "label": "Interact"},
	{"action": "grenade", "label": "Throw Grenade"},
	{"action": "grenade_cycle", "label": "Cycle Grenade Type"},
	{"action": "weapon_1", "label": "Weapon Slot 1"},
	{"action": "weapon_2", "label": "Weapon Slot 2"},
	{"action": "weapon_3", "label": "Weapon Slot 3"},
	{"action": "weapon_4", "label": "Weapon Slot 4"},
	{"action": "weapon_next", "label": "Next Weapon"},
	{"action": "weapon_prev", "label": "Previous Weapon"},
	{"action": "pause", "label": "Pause"},
]

## action -> Array[InputEvent] the player has customized. Absent = factory
## default (see _factory_default_events). Persisted to settings.cfg — InputEvent
## is a plain built-in Resource (no external UID), so ConfigFile round-trips it
## the same way project.godot itself stores bindings.
var keybind_overrides: Dictionary = {}

func _key(physical_keycode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = physical_keycode
	return e

func _mouse_btn(button_index: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button_index
	return e

func _joy_btn(button_index: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button_index
	return e

func _joy_axis(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e

## The factory-default event set for a rebindable action — mirrors exactly
## what project.godot + GameState._setup_gamepad_bindings + player.gd +
## weapon_manager.gd would otherwise set up between them. This is the "Reset
## to Defaults" baseline and the fallback whenever no override is saved.
func _factory_default_events(action: String) -> Array:
	match action:
		"move_forward": return [_key(KEY_W), _joy_axis(JOY_AXIS_LEFT_Y, -1.0)]
		"move_back": return [_key(KEY_S), _joy_axis(JOY_AXIS_LEFT_Y, 1.0)]
		"move_left": return [_key(KEY_A), _joy_axis(JOY_AXIS_LEFT_X, -1.0)]
		"move_right": return [_key(KEY_D), _joy_axis(JOY_AXIS_LEFT_X, 1.0)]
		"jump": return [_key(KEY_SPACE), _joy_btn(JOY_BUTTON_A)]
		"sprint": return [_key(KEY_SHIFT), _joy_btn(JOY_BUTTON_LEFT_STICK)]
		"crouch": return [_key(KEY_CTRL), _joy_btn(JOY_BUTTON_B)]
		"dash": return [_key(KEY_Q), _joy_btn(JOY_BUTTON_RIGHT_STICK)]
		"melee": return [_key(KEY_F), _joy_btn(JOY_BUTTON_B)]
		"grapple": return [_key(KEY_C), _joy_btn(JOY_BUTTON_LEFT_SHOULDER)]
		"fire": return [_mouse_btn(MOUSE_BUTTON_LEFT), _joy_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
		"aim": return [_mouse_btn(MOUSE_BUTTON_RIGHT), _joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]
		"alt_fire": return [_key(KEY_V), _mouse_btn(MOUSE_BUTTON_XBUTTON1)]
		"reload": return [_key(KEY_R), _joy_btn(JOY_BUTTON_X)]
		"interact": return [_key(KEY_E), _joy_btn(JOY_BUTTON_X)]
		"grenade": return [_key(KEY_G), _joy_btn(JOY_BUTTON_Y)]
		"grenade_cycle": return [_key(KEY_H)]
		"weapon_1": return [_key(KEY_1)]
		"weapon_2": return [_key(KEY_2)]
		"weapon_3": return [_key(KEY_3)]
		"weapon_4": return [_key(KEY_4)]
		"weapon_next": return [_mouse_btn(MOUSE_BUTTON_WHEEL_DOWN), _joy_btn(JOY_BUTTON_RIGHT_SHOULDER)]
		"weapon_prev": return [_mouse_btn(MOUSE_BUTTON_WHEEL_UP), _joy_btn(JOY_BUTTON_LEFT_SHOULDER)]
		"pause": return [_key(KEY_ESCAPE), _joy_btn(JOY_BUTTON_START)]
		_: return []

## Applies every keybindable action's events onto the live InputMap: the saved
## override if the player customized it, otherwise the factory default. Also
## registers any action InputMap doesn't have yet (melee/grapple/alt_fire
## before their first level load) — see the ordering note above.
func apply_keybinds() -> void:
	# First pass: collect all explicit overrides so we know which keys are "taken"
	var all_overrides: Array[InputEvent] = []
	for entry in KEYBIND_ACTIONS:
		var action: String = entry["action"]
		if keybind_overrides.has(action):
			all_overrides.append_array(keybind_overrides[action])
			
	# Second pass: apply to InputMap
	for entry in KEYBIND_ACTIONS:
		var action: String = entry["action"]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			
		var events: Array = []
		if keybind_overrides.has(action):
			events = keybind_overrides[action]
		else:
			# If the user hasn't overridden this action, use factory defaults,
			# BUT filter out any default event that the user stole for an override!
			for def_e in _factory_default_events(action):
				var stolen := false
				for over_e in all_overrides:
					if _events_match(def_e, over_e):
						stolen = true
						break
				if not stolen:
					events.append(def_e)
					
		InputMap.action_erase_events(action)
		for e in events:
			InputMap.action_add_event(action, e)

func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	return false

## Rebinds one "slot" of an action to a freshly captured event: the kb/mouse
## slot (is_gamepad_slot=false) replaces any existing InputEventKey/
## InputEventMouseButton on the action while leaving gamepad events alone; the
## gamepad slot (is_gamepad_slot=true) replaces any existing
## InputEventJoypadButton while leaving kb/mouse/axis events alone.
##
## Conflict policy: SWAP. If another rebindable action already uses the exact
## same event, it's silently stripped from that action (never left ambiguous
## between two actions) and its name is returned so the UI can toast it.
func rebind_action(action: String, is_gamepad_slot: bool, new_event: InputEvent) -> Array[String]:
	var stolen: Array[String] = []
	for other in KEYBIND_ACTIONS:
		var oa: String = other["action"]
		if oa == action or not InputMap.has_action(oa):
			continue
		for e in InputMap.action_get_events(oa):
			if _events_match(e, new_event):
				InputMap.action_erase_event(oa, e)
				keybind_overrides[oa] = InputMap.action_get_events(oa).duplicate()
				stolen.append(other["label"])

	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var kept: Array = []
	for e in InputMap.action_get_events(action):
		if is_gamepad_slot:
			if not (e is InputEventJoypadButton):
				kept.append(e)
		else:
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				kept.append(e)
	kept.append(new_event)
	InputMap.action_erase_events(action)
	for e in kept:
		InputMap.action_add_event(action, e)
	keybind_overrides[action] = kept.duplicate()
	_save_settings()
	return stolen

## Wipes every saved override and restores factory-default binds everywhere.
func reset_keybinds_to_default() -> void:
	keybind_overrides.clear()
	apply_keybinds()
	_save_settings()

func _ready() -> void:
	_load_settings()
	TranslationServer.set_locale(language)
	apply_keybinds() # after GameState's default gamepad injection — see ordering note above
	_apply_viewport.call_deferred()
	_apply_hdr_output.call_deferred()
	_apply_window_mode.call_deferred()
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

## Step quality up/down without wrapping, so a struggling machine can go
## straight from HIGH to MEDIUM without passing through ULTRA.
func step_quality(delta: int) -> void:
	set_quality(int(quality) + delta)

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

## Accessibility: scales a light burst's peak energy by flash_intensity (0 =
## no strobe at all). Shared by every transient FX light (muzzle flash, impact
## pop, explosion pop, projectile detonation, grenade detonation) so a
## photosensitive player who zeroes the slider gets zero strobing point lights,
## not just a dimmer HUD flash.
func flash_energy(peak: float) -> float:
	return peak * flash_intensity

## Accessibility: 0..1 scale on gamepad rumble (0 = off entirely).
func set_rumble(v: float) -> void:
	rumble = clampf(v, 0.0, 1.0)
	Haptics.strength = rumble
	_save_settings()

## 3D resolution scale (0.5..1.0). Applies to the live viewport immediately.
func set_render_scale(v: float) -> void:
	render_scale = clampf(v, 0.5, 1.0)
	_apply_viewport()
	_save_settings()

## One-line GPU + driver-API summary for the settings screen, e.g.
## "NVIDIA GeForce RTX 3060 · Vulkan 1.3.260". Lets a player confirm the game is
## actually running on their real GPU (and see the driver's Vulkan version) —
## the single most common cause of "it's laggy" is the machine quietly running
## on a software rasterizer or the wrong (integrated) GPU.
func gpu_summary() -> String:
	var name := RenderingServer.get_video_adapter_name()
	if name.is_empty():
		return tr("GPU: unavailable (headless)")
	var api := RenderingServer.get_video_adapter_api_version()
	return "GPU: %s%s" % [name, (" · " + api) if not api.is_empty() else ""]

## True when the renderer fell back to CPU/software rasterization (no real GPU
## acceleration) — the driver is missing/outdated or the GPU isn't exposing
## Vulkan. Performance is catastrophic in this state no matter the quality tier,
## so the settings screen flags it loudly and points at a driver update.
func gpu_is_software() -> bool:
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_CPU:
		return true
	var n := RenderingServer.get_video_adapter_name().to_lower()
	for tag in ["llvmpipe", "lavapipe", "software", "basic render", "swiftshader", "warp"]:
		if n.contains(tag):
			return true
	return false

## True when running on an integrated GPU — fine on many machines, but on a
## laptop with a discrete GPU it usually means the game picked the wrong one
## (a soft warning, not an error).
func gpu_is_integrated() -> bool:
	return RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU

## Human-readable readout for the Render Scale slider: the percentage plus the
## effective internal 3D resolution it renders at (window size × scale) — so
## "0.70" reads as "70% · 2688×1512" instead of a bare number. FSR2 upscales that
## back to the native window size; the 2D HUD stays sharp at native regardless.
## Falls back to just the percentage when the window size is unknown (headless).
func render_scale_label(scale: float) -> String:
	var s := clampf(scale, 0.5, 1.0)
	var pct := roundi(s * 100.0)
	var w := DisplayServer.window_get_size()
	if w.x <= 0 or w.y <= 0:
		return "%d%%" % pct
	return "%d%% · %d×%d" % [pct, roundi(w.x * s), roundi(w.y * s)]

## Accessibility: brightness multiplier (0.5..1.5) on top of each Environment's
## own authored adjustment_brightness. Re-tiers the live level's environment
## immediately, same as a quality change.
func set_brightness(v: float) -> void:
	brightness = clampf(v, 0.5, 1.5)
	_apply_to_live_environment()
	_save_settings()

## Accessibility: HUD polls this before popping overlord taunt subtitles /
## arcade kill callouts. See the report for the hud.gd handoff read sites.
func set_combat_callouts_enabled(v: bool) -> void:
	combat_callouts_enabled = v
	_save_settings()

## Accessibility: Damageable polls this before spawning a floating damage
## number. See the report for the damageable.gd handoff read site.
func set_damage_numbers_enabled(v: bool) -> void:
	damage_numbers_enabled = v
	_save_settings()

# ---------- graphics presets ----------

## One-shot batch configuration of the whole graphics feature set (quality tier,
## render scale, and the per-feature toggles). This is deliberately NOT stored
## as "the current preset" anywhere — the settings menu always shows a
## "Preset…" placeholder rather than remembering the last one picked, because
## any single manual toggle afterward (e.g. turning puddles back on) would
## silently desync a saved preset label from what's actually configured.
## Each set_* call below already applies + persists itself, so nothing extra
## is needed at the end.
##
## hdr_output_enabled is NEVER touched here: hdr_output_requested has hung
## headless/dummy display servers in the past (it's a genuine per-display
## capability query, not a pure render setting), so it stays a manual-only
## toggle regardless of preset.
func apply_preset(p: int) -> void:
	match p:
		PRESET_PERFORMANCE:
			set_quality(Quality.LOW)
			set_render_scale(0.67)
			set_gpu_particles_enabled(true)
			set_volumetric_noise_enabled(false)
			set_robot_triplanar_enabled(false)
			set_puddle_ripples_enabled(false)
			set_advanced_post_process_enabled(false)
			set_area_lights_enabled(false)
			set_dof_enabled(false)
		PRESET_BALANCED:
			set_quality(Quality.MEDIUM)
			set_render_scale(0.85)
			set_gpu_particles_enabled(true)
			set_robot_triplanar_enabled(true)
			set_puddle_ripples_enabled(true)
			set_volumetric_noise_enabled(false)
			set_advanced_post_process_enabled(false)
			set_area_lights_enabled(false)
			set_dof_enabled(false)
		PRESET_QUALITY:
			set_quality(Quality.HIGH)
			set_render_scale(1.0)
			set_gpu_particles_enabled(true)
			set_volumetric_noise_enabled(true)
			set_robot_triplanar_enabled(true)
			set_puddle_ripples_enabled(true)
			set_advanced_post_process_enabled(true)
			set_area_lights_enabled(true)
			set_dof_enabled(false)
		PRESET_ULTRA:
			set_quality(Quality.ULTRA)
			set_render_scale(1.0)
			set_gpu_particles_enabled(true)
			set_volumetric_noise_enabled(true)
			set_robot_triplanar_enabled(true)
			set_puddle_ripples_enabled(true)
			set_advanced_post_process_enabled(true)
			set_area_lights_enabled(true)
			set_dof_enabled(false)

## Switches the color-grade preset live and persists it.
func set_color_grade(v: int) -> void:
	color_grade = clampi(v, 0, ColorGrade.size() - 1) as ColorGrade
	_apply_to_live_post_process()
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

# ---------- window mode ----------

## Switches window presentation live and persists it.
func set_window_mode(m: int) -> void:
	window_mode = clampi(m, 0, WindowMode.size() - 1) as WindowMode
	_apply_window_mode()
	_save_settings()

## Applies window_mode via DisplayServer. Guarded for headless (import runs,
## the probe/CI harness) — there's no real window there, and calling these on
## a headless display server is at best a no-op and at worst a crash.
func _apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size := Vector2i(1600, 900)
			DisplayServer.window_set_size(size)
			var screen := DisplayServer.screen_get_size()
			var screen_pos := DisplayServer.screen_get_position()
			DisplayServer.window_set_position(screen_pos + (screen - size) / 2)

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

## Rotate LOW -> MEDIUM -> HIGH -> ULTRA -> LOW (legacy wrap; menus now use
## step_quality so nobody has to pass through ULTRA to reach LOW).
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
	# Anti-aliasing per tier. TAA is OFF on every tier — its temporal accumulation
	# softens fine distant detail (the "blurry in the distance" look); MSAA on the
	# higher tiers carries edge anti-aliasing instead.
	match quality:
		Quality.LOW:
			vp.msaa_3d = Viewport.MSAA_DISABLED
		Quality.MEDIUM:
			vp.msaa_3d = Viewport.MSAA_DISABLED
		Quality.HIGH:
			vp.msaa_3d = Viewport.MSAA_2X
		Quality.ULTRA:
			vp.msaa_3d = Viewport.MSAA_4X
	vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	# Resolution scale is now a USER setting, independent of the quality tier, so you
	# can keep effects low for performance WITHOUT the upscaling blur. 1.0 = native
	# (sharp, bilinear, no upscale); below 1.0 renders smaller and FSR2-reconstructs.
	var rs := clampf(render_scale, 0.5, 1.0)
	vp.scaling_3d_scale = rs
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR if rs >= 0.999 else Viewport.SCALING_3D_MODE_FSR2
	vp.fsr_sharpness = 0.1 # sharper-than-default FSR2 reconstruction (0 = sharpest)
	_apply_shadow_quality()
	_apply_ss_effect_quality()

## SSAO/SSIL kernel quality per tier. The project setting pins these at HIGH
## grade for EVERY tier — measured at tens of ms/frame at 4K on a mid GPU
## (tools/perf_fx_isolate). These are global RenderingServer knobs, so one call
## covers every Environment.
func _apply_ss_effect_quality() -> void:
	var q: int = [
		RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_LOW,
		RenderingServer.ENV_SSAO_QUALITY_MEDIUM,
		RenderingServer.ENV_SSAO_QUALITY_HIGH,
	][int(quality)]
	# Godot-default adaptive/blur/fadeout params; half-res everywhere (the
	# full-res kernels roughly quadruple the cost for a subtle difference).
	RenderingServer.environment_set_ssao_quality(q, true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(q, true, 0.5, 4, 50.0, 300.0)

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
	# ULTRA are visibly crisper), memory/fill-rate savings where you can't.
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096, 8192][int(quality)], true)
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
			# SSIL is ULTRA-only: it's the single most expensive screen-space
			# effect (~30 ms/frame at 4K, tools/perf_fx_isolate) for the
			# subtlest visual contribution of the set.
			env.ssil_enabled = false
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
	_apply_brightness(env)

func _restore_glow(env: Environment) -> void:
	if env.has_meta("glow_base"):
		env.glow_intensity = env.get_meta("glow_base")

## Accessibility brightness slider: scales whatever adjustment_brightness a
## level (or the cutscene player) already authored, remembering that authored
## value in metadata the first time so repeated calls (quality changes, slider
## drags) never compound on themselves.
func _apply_brightness(env: Environment) -> void:
	if not env.has_meta("brightness_base"):
		env.set_meta("brightness_base", env.adjustment_brightness if env.adjustment_enabled else 1.0)
	env.adjustment_enabled = true
	env.adjustment_brightness = float(env.get_meta("brightness_base")) * brightness

func _load_settings() -> void:
	var cf := ConfigFile.new()
	var loaded := cf.load(SETTINGS_PATH) == OK
	if loaded:
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
		rumble = clampf(float(cf.get_value("input", "rumble", 1.0)), 0.0, 1.0)
		render_scale = clampf(float(cf.get_value("video", "render_scale", 1.0)), 0.5, 1.0)
		color_grade = clampi(int(cf.get_value("graphics_adv", "color_grade", ColorGrade.NEUTRAL)), 0, ColorGrade.size() - 1) as ColorGrade
		brightness = clampf(float(cf.get_value("display", "brightness", 1.0)), 0.5, 1.5)
		combat_callouts_enabled = bool(cf.get_value("accessibility", "combat_callouts", true))
		damage_numbers_enabled = bool(cf.get_value("accessibility", "damage_numbers", true))
		window_mode = clampi(int(cf.get_value("display", "window_mode", WindowMode.BORDERLESS)), 0, WindowMode.size() - 1) as WindowMode
		var raw_overrides = cf.get_value("keybinds", "overrides", {})
		keybind_overrides = raw_overrides if raw_overrides is Dictionary else {}
	# Until the player has touched the Render Scale slider, pick a sane default
	# from the screen: native-res 4K is by far the biggest frame cost on modest
	# GPUs (tools/perf_fx_isolate: 0.5 scale more than doubled fps), so very
	# high-res screens start at a ~1440p-equivalent internal res + FSR2 upscale.
	if not (loaded and cf.has_section_key("video", "render_scale")):
		render_scale = _auto_render_scale()
	# First-run-ever (no persisted quality key): flag the main menu to run the
	# QualityBenchmark. `quality` stays at its HIGH default in the meantime —
	# that's the fallback if the benchmark can't run (e.g. headless).
	if not (loaded and cf.has_section_key("video", "quality")):
		needs_auto_quality = true
	# Mirror into the static helper whether or not a settings file existed.
	Haptics.strength = rumble

## First-run render scale: 1.0 (native) up to 1600-row screens, then whatever
## scale gives a ~1440p-tall internal resolution, floored at 0.5.
func _auto_render_scale() -> float:
	var h := DisplayServer.screen_get_size().y
	if h <= 0 or h <= 1600: # headless probes report 0 — keep native
		return 1.0
	return clampf(1440.0 / float(h), 0.5, 1.0)

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
	cf.set_value("input", "rumble", rumble)
	cf.set_value("video", "render_scale", render_scale)
	cf.set_value("graphics_adv", "color_grade", int(color_grade))
	cf.set_value("display", "brightness", brightness)
	cf.set_value("accessibility", "combat_callouts", combat_callouts_enabled)
	cf.set_value("accessibility", "damage_numbers", damage_numbers_enabled)
	cf.set_value("display", "window_mode", int(window_mode))
	cf.set_value("keybinds", "overrides", keybind_overrides)

	cf.save(SETTINGS_PATH)
