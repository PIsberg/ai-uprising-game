extends Control

@onready var _main: VBoxContainer = $Center/VBox/MainButtons
@onready var _diff: VBoxContainer = $Center/VBox/DiffButtons
@onready var _settings: VBoxContainer = $Center/VBox/SettingsPanel
@onready var _controls: VBoxContainer = $Center/VBox/ControlsPanel
@onready var _continue: Button = $Center/VBox/MainButtons/Continue
@onready var _daily: Button = $Center/VBox/MainButtons/Daily
@onready var _grid: GridContainer = $Center/VBox/SettingsPanel/Grid
@onready var _graphics_label: Label = $Center/VBox/SettingsPanel/Grid/GraphicsRow/Graphics
@onready var _gfx_down: Button = $Center/VBox/SettingsPanel/Grid/GraphicsRow/GfxDown
@onready var _gfx_up: Button = $Center/VBox/SettingsPanel/Grid/GraphicsRow/GfxUp
@onready var _volume: HSlider = $Center/VBox/SettingsPanel/Grid/VolumeRow/VolumeSlider

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.end_daily_op() # back in the menu means no op is running, however it was left
	GameState.set_state(GameState.State.MENU)
	_refresh_daily_button()
	# Continue is only offered when a checkpoint exists, and says WHERE the run
	# resumes (level title, campaign position, difficulty) so a returning player
	# knows what they are stepping back into before they commit.
	_continue.visible = GameState.has_save()
	if _continue.visible:
		var s: Dictionary = GameState.peek_save()
		if not s.is_empty():
			_continue.text = "%s  ·  %s  (%d/%d · %s)" % [tr("Continue"), String(s["title"]),
				int(s["level_index"]) + 1, int(s["campaign_size"]), String(s["difficulty_label"])]
	_volume.value = AudioBus.get_master_volume()
	_refresh_graphics_label()
	_build_extra_settings()
	_show_panel(_main)
	_add_version_label()
	if GraphicsSettings.needs_auto_quality:
		_run_auto_quality_benchmark()
	# Start loading the first (or saved) level behind the menu, so "Begin
	# Operation" / Continue do not sit on the loading screen for the shared
	# robot-model chunk. Deferred one frame so the menu paints first.
	GameState.warm_level_cache.call_deferred()

## A small, dim build-version tag pinned to the bottom-right corner. Reads the
## single source of truth (project.godot `application/config/version`) so bumping
## the version there updates the menu, the exported build, and this label at once.
func _add_version_label() -> void:
	var v := str(ProjectSettings.get_setting("application/config/version", "dev"))
	var lbl := Label.new()
	lbl.text = "v" + v
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.modulate = Color(1.0, 1.0, 1.0, 0.38)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 1.0; lbl.anchor_top = 1.0; lbl.anchor_right = 1.0; lbl.anchor_bottom = 1.0
	lbl.offset_left = -170.0; lbl.offset_top = -34.0; lbl.offset_right = -16.0; lbl.offset_bottom = -10.0
	add_child(lbl)

var _fps_btn: Button

## Adds FOV / sensitivity / invert-Y / framerate controls to the settings panel
## at runtime, wired straight to GraphicsSettings (persisted on change).
func _build_extra_settings() -> void:
	# Preset / Window rows are added FIRST (before any other runtime row) so
	# they land at Grid child indices 2/3, right after the scene's GraphicsRow
	# (index 0) and VolumeRow (index 1) — GridContainer fills 2-per-row in
	# child order, so this keeps them visually adjacent to the quality stepper.
	_add_preset_row()
	_add_window_mode_row()

	# GPU / driver readout, pinned just under the panel title. The fastest way for
	# a player to confirm the game is on their real GPU — a software fallback
	# (missing/old driver) or the wrong integrated chip is the usual cause of
	# unexplained lag, and no quality setting can fix that; a driver update does.
	var gpu_lbl := Label.new()
	gpu_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gpu_lbl.text = GraphicsSettings.gpu_summary()
	if GraphicsSettings.gpu_is_software():
		gpu_lbl.text += "\n" + tr("⚠ Software rendering — install/update your GPU driver for real performance.")
		gpu_lbl.modulate = Color(1.0, 0.55, 0.3)
	elif GraphicsSettings.gpu_is_integrated():
		gpu_lbl.text += "\n" + tr("Integrated GPU — on a laptop, set this game to your High-performance GPU.")
		gpu_lbl.modulate = Color(1.0, 0.85, 0.4)
	_settings.add_child(gpu_lbl)
	_settings.move_child(gpu_lbl, 1) # just below the "Settings" prompt, above the grid
	_build_restart_button()

	var fov_slider := _add_slider_row("Field of View", 60.0, 110.0, 1.0, GraphicsSettings.fov)
	fov_slider.value_changed.connect(func(v: float): GraphicsSettings.set_fov(v))

	var sens_slider := _add_slider_row("Look Sensitivity", 0.2, 3.0, 0.05, GraphicsSettings.sensitivity)
	sens_slider.value_changed.connect(func(v: float): GraphicsSettings.set_sensitivity(v))

	var invert := CheckButton.new()
	invert.text = "Invert Look Y"
	invert.custom_minimum_size = Vector2(360, 44)
	invert.button_pressed = GraphicsSettings.invert_y
	invert.toggled.connect(func(p: bool): GraphicsSettings.set_invert_y(p))
	_grid.add_child(invert)

	var gpu_parts := CheckButton.new()
	gpu_parts.text = "Enable GPU Particles"
	gpu_parts.custom_minimum_size = Vector2(360, 44)
	gpu_parts.button_pressed = GraphicsSettings.gpu_particles_enabled
	gpu_parts.toggled.connect(func(p: bool): GraphicsSettings.set_gpu_particles_enabled(p))
	_grid.add_child(gpu_parts)

	var vol_noise := CheckButton.new()
	vol_noise.text = "Volumetric Noise Shafts"
	vol_noise.custom_minimum_size = Vector2(360, 44)
	vol_noise.button_pressed = GraphicsSettings.volumetric_noise_enabled
	vol_noise.toggled.connect(func(p: bool): GraphicsSettings.set_volumetric_noise_enabled(p))
	_grid.add_child(vol_noise)

	var tri_robots := CheckButton.new()
	tri_robots.text = "Triplanar Damage Robots"
	tri_robots.custom_minimum_size = Vector2(360, 44)
	tri_robots.button_pressed = GraphicsSettings.robot_triplanar_enabled
	tri_robots.toggled.connect(func(p: bool): GraphicsSettings.set_robot_triplanar_enabled(p))
	_grid.add_child(tri_robots)

	var puddles := CheckButton.new()
	puddles.text = "Animated Puddle Ripples"
	puddles.custom_minimum_size = Vector2(360, 44)
	puddles.button_pressed = GraphicsSettings.puddle_ripples_enabled
	puddles.toggled.connect(func(p: bool): GraphicsSettings.set_puddle_ripples_enabled(p))
	_grid.add_child(puddles)

	var post_proc := CheckButton.new()
	post_proc.text = "Advanced Lens Flares & Bloom"
	post_proc.custom_minimum_size = Vector2(360, 44)
	post_proc.button_pressed = GraphicsSettings.advanced_post_process_enabled
	post_proc.toggled.connect(func(p: bool): GraphicsSettings.set_advanced_post_process_enabled(p))
	_grid.add_child(post_proc)

	_add_color_grade_row()

	var area_lights := CheckButton.new()
	area_lights.text = tr("Soft Area Lights (HIGH/ULTRA)")
	area_lights.custom_minimum_size = Vector2(360, 44)
	area_lights.button_pressed = GraphicsSettings.area_lights_enabled
	area_lights.toggled.connect(func(p: bool): GraphicsSettings.set_area_lights_enabled(p))
	_grid.add_child(area_lights)

	var hdr := CheckButton.new()
	hdr.text = tr("HDR Display Output")
	hdr.custom_minimum_size = Vector2(360, 44)
	hdr.button_pressed = GraphicsSettings.hdr_output_enabled
	hdr.toggled.connect(func(p: bool): GraphicsSettings.set_hdr_output_enabled(p))
	_grid.add_child(hdr)

	var show_fps := CheckButton.new()
	show_fps.text = tr("Show FPS Counter")
	show_fps.custom_minimum_size = Vector2(360, 44)
	show_fps.button_pressed = GraphicsSettings.show_fps
	show_fps.toggled.connect(func(p: bool): GraphicsSettings.set_show_fps(p))
	_grid.add_child(show_fps)

	var dof := CheckButton.new()
	dof.text = tr("Depth of Field")
	dof.custom_minimum_size = Vector2(360, 44)
	dof.button_pressed = GraphicsSettings.dof_enabled
	dof.toggled.connect(func(p: bool): GraphicsSettings.set_dof_enabled(p))
	_grid.add_child(dof)

	_fps_btn = Button.new()
	_fps_btn.custom_minimum_size = Vector2(360, 44)
	_fps_btn.text = tr("Framerate: %s") % GraphicsSettings.fps_label()
	_fps_btn.pressed.connect(_on_fps_pressed)
	_grid.add_child(_fps_btn)

	var sfx := _add_slider_row("SFX Volume", 0.0, 1.0, 0.05, AudioBus.get_sfx_volume())
	sfx.value_changed.connect(func(v: float): AudioBus.set_sfx_volume(v))

	var music := _add_slider_row("Music Volume", 0.0, 1.0, 0.05, AudioBus.get_music_volume())
	music.value_changed.connect(func(v: float): AudioBus.set_music_volume_linear(v))

	# Accessibility: scale (or kill) gameplay camera shake.
	var shake := _add_slider_row("Screen Shake", 0.0, 1.0, 0.05, GraphicsSettings.screen_shake)
	shake.value_changed.connect(func(v: float): GraphicsSettings.set_screen_shake(v))

	# Accessibility: scale (or kill) full-screen flashes (photosensitivity safety).
	var flash := _add_slider_row("Flash Intensity", 0.0, 1.0, 0.05, GraphicsSettings.flash_intensity)
	flash.value_changed.connect(func(v: float): GraphicsSettings.set_flash_intensity(v))

	# Accessibility / difficulty assist: scale the damage the player takes.
	var dmg_taken := _add_slider_row("Damage Taken", 0.5, 1.5, 0.05, GraphicsSettings.damage_taken)
	dmg_taken.value_changed.connect(func(v: float): GraphicsSettings.set_damage_taken(v))

	# Accessibility: colourblind correction of the 3D world.
	_add_colorblind_row()

	# Accessibility: gamepad rumble strength (0 = off).
	var rumble := _add_slider_row("Controller Rumble", 0.0, 1.0, 0.05, GraphicsSettings.rumble)
	rumble.value_changed.connect(func(v: float): GraphicsSettings.set_rumble(v))

	# Resolution scale — 1.0 = native/sharp; lower it for performance (FSR2 upscale).
	# A live readout shows the effective internal resolution ("70% · 2688×1512") so
	# the slider reads as the resolution/perf control it actually is.
	var rscale := _add_slider_row("Render Scale", 0.5, 1.0, 0.05, GraphicsSettings.render_scale)
	rscale.custom_minimum_size = Vector2(120, 0) # make room for the readout in the row
	rscale.tooltip_text = tr("Lower = faster. Renders the 3D world at this fraction of screen resolution and upscales it (FSR2). The HUD stays sharp.")
	var rscale_lbl := Label.new()
	rscale_lbl.custom_minimum_size = Vector2(150, 0)
	rscale_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rscale_lbl.text = GraphicsSettings.render_scale_label(GraphicsSettings.render_scale)
	rscale.get_parent().add_child(rscale_lbl)
	rscale.value_changed.connect(func(v: float):
		GraphicsSettings.set_render_scale(v)
		rscale_lbl.text = GraphicsSettings.render_scale_label(v))

	_add_language_row()

	# Accessibility: brightness multiplier on top of whatever a level authored
	# for its own Environment.adjustment_brightness (see GraphicsSettings._apply_brightness).
	var brightness_slider := _add_slider_row("Brightness", 0.5, 1.5, 0.05, GraphicsSettings.brightness)
	brightness_slider.value_changed.connect(func(v: float): GraphicsSettings.set_brightness(v))

	# Accessibility: overlord taunt subtitles + arcade kill callouts (HEADSHOT,
	# streak words) — the HUD reads GraphicsSettings.combat_callouts_enabled
	# before popping them.
	var callouts := CheckButton.new()
	callouts.text = tr("Combat Callouts")
	callouts.custom_minimum_size = Vector2(360, 44)
	callouts.button_pressed = GraphicsSettings.combat_callouts_enabled
	callouts.toggled.connect(func(p: bool): GraphicsSettings.set_combat_callouts_enabled(p))
	_grid.add_child(callouts)

	# Accessibility: floating damage numbers — Damageable reads
	# GraphicsSettings.damage_numbers_enabled.
	var dmg_numbers := CheckButton.new()
	dmg_numbers.text = tr("Damage Numbers")
	dmg_numbers.custom_minimum_size = Vector2(360, 44)
	dmg_numbers.button_pressed = GraphicsSettings.damage_numbers_enabled
	dmg_numbers.toggled.connect(func(p: bool): GraphicsSettings.set_damage_numbers_enabled(p))
	_grid.add_child(dmg_numbers)

	# Accessibility: how big those numbers are on screen.
	var dmg_size := _add_slider_row("Damage Number Size", 0.6, 2.0, 0.1, GraphicsSettings.damage_number_scale)
	dmg_size.value_changed.connect(func(v: float): GraphicsSettings.set_damage_number_scale(v))

	# Accessibility: timed spoken text (cutscene subtitles, overlord taunts, the
	# victory transmission) — applied as each label is built.
	var sub_size := _add_slider_row("Subtitle Size", 0.8, 2.0, 0.1, GraphicsSettings.subtitle_scale)
	sub_size.value_changed.connect(func(v: float): GraphicsSettings.set_subtitle_scale(v))

	var rebind_btn := Button.new()
	rebind_btn.custom_minimum_size = Vector2(360, 48)
	rebind_btn.text = tr("Rebind Controls")
	rebind_btn.pressed.connect(_on_rebind_controls_pressed)
	_grid.add_child(rebind_btn)

	# The overlord's dossier outlives every campaign by design; this is the one way
	# to make it forget (#166). Two presses: the first arms it for a few seconds.
	_wipe_btn = Button.new()
	_wipe_btn.name = "WipeOverlordBtn"
	_wipe_btn.custom_minimum_size = Vector2(360, 48)
	_wipe_btn.pressed.connect(_on_wipe_overlord_pressed)
	_grid.add_child(_wipe_btn)
	_refresh_wipe_btn()
	# (Back lives in the panel VBox below the grid, so it stays at the bottom.)

## Preset picker: a one-shot batch applicator, not a stored state. The row
## always shows a "Preset…" placeholder (selected by default and re-selected
## after every pick) rather than remembering the last preset chosen — any
## manual toggle afterward (turning one effect back on/off) would otherwise
## silently desync a saved preset label from what's actually configured.
func _add_preset_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = tr("Preset")
	lbl.custom_minimum_size = Vector2(150, 0)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_item(tr("Preset…"))
	for label in GraphicsSettings.PRESET_LABELS:
		opt.add_item(tr(label))
	opt.selected = 0 # placeholder — never reflects "the current preset" (see above)
	opt.item_selected.connect(func(idx: int):
		if idx == 0: # the placeholder itself — nothing to apply
			return
		# Placeholder occupies index 0, so preset ids are shifted by one.
		GraphicsSettings.apply_preset(idx - 1)
		get_tree().reload_current_scene())
	row.add_child(lbl)
	row.add_child(opt)
	_grid.add_child(row)

## Window mode picker: Fullscreen (exclusive) / Borderless (windowed
## fullscreen) / Windowed. Applies live via DisplayServer — no scene reload
## needed since nothing about the menu's own layout depends on it.
func _add_window_mode_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = tr("Window")
	lbl.custom_minimum_size = Vector2(150, 0)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in GraphicsSettings.WINDOW_MODE_LABELS:
		opt.add_item(tr(label))
	opt.selected = int(GraphicsSettings.window_mode)
	opt.item_selected.connect(func(idx: int): GraphicsSettings.set_window_mode(idx))
	row.add_child(lbl)
	row.add_child(opt)
	_grid.add_child(row)

## Color-grade picker: an OptionButton over GraphicsSettings' named presets,
## applied live so you can preview the mood shift without leaving the menu.
func _add_color_grade_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = tr("Color Grade")
	lbl.custom_minimum_size = Vector2(150, 0)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in GraphicsSettings.COLOR_GRADE_LABELS:
		opt.add_item(tr(label))
	opt.selected = int(GraphicsSettings.color_grade)
	opt.item_selected.connect(func(idx: int): GraphicsSettings.set_color_grade(idx))
	row.add_child(lbl)
	row.add_child(opt)
	_grid.add_child(row)

## Colourblind picker: corrects the world post-process live (GraphicsSettings).
func _add_colorblind_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = tr("Colourblind Mode")
	lbl.custom_minimum_size = Vector2(150, 0)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in GraphicsSettings.COLORBLIND_LABELS:
		opt.add_item(tr(label))
	opt.selected = int(GraphicsSettings.colorblind_mode)
	opt.item_selected.connect(func(idx: int): GraphicsSettings.set_colorblind_mode(idx))
	row.add_child(lbl)
	row.add_child(opt)
	_grid.add_child(row)

## Language picker: an OptionButton of the available locales. Changing it applies
## the locale immediately and reloads the menu so every runtime-built label
## rebuilds in the new language.
func _add_language_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = "Language"
	lbl.custom_minimum_size = Vector2(150, 0)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # native names stay native
	for entry in GraphicsSettings.LANGUAGES:
		opt.add_item(entry[1])
	opt.selected = GraphicsSettings.language_index()
	opt.item_selected.connect(func(idx: int):
		GraphicsSettings.set_language(GraphicsSettings.LANGUAGES[idx][0])
		get_tree().reload_current_scene())
	row.add_child(lbl)
	row.add_child(opt)
	_grid.add_child(row)

func _add_slider_row(label: String, mn: float, mx: float, step: float, val: float) -> HSlider:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(360, 0)
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(150, 0)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(190, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(s)
	_grid.add_child(row)
	return s

var _wipe_btn: Button
var _wipe_armed_ms: int = -100000
const WIPE_CONFIRM_MS := 4000

func _refresh_wipe_btn() -> void:
	if _wipe_btn == null:
		return
	var reads := int(AIDirector.dossier.get("reads", 0))
	var deaths := int(AIDirector.dossier.get("deaths", 0))
	var empty := reads <= 0 and deaths <= 0
	_wipe_btn.disabled = empty
	if empty:
		_wipe_btn.text = tr("Overlord Memory: empty")
	elif Time.get_ticks_msec() - _wipe_armed_ms < WIPE_CONFIRM_MS:
		_wipe_btn.text = tr("Press again to wipe the overlord's memory")
	else:
		_wipe_btn.text = tr("Wipe Overlord Memory (%d levels; %d deaths on file)") % [reads, deaths]

func _on_wipe_overlord_pressed() -> void:
	if Time.get_ticks_msec() - _wipe_armed_ms < WIPE_CONFIRM_MS:
		_wipe_armed_ms = -100000
		AIDirector.forget_dossier()
		AudioBus.play_synth_ui("overlord_glitch", -6.0, 0.8)
	else:
		_wipe_armed_ms = Time.get_ticks_msec()
		# Fall back to the plain label if the second press never comes.
		get_tree().create_timer(WIPE_CONFIRM_MS / 1000.0 + 0.05).timeout.connect(_refresh_wipe_btn)
	_refresh_wipe_btn()

func _on_fps_pressed() -> void:
	GraphicsSettings.cycle_fps()
	_fps_btn.text = tr("Framerate: %s") % GraphicsSettings.fps_label()

func _show_panel(which: Control) -> void:
	_main.visible = which == _main
	_diff.visible = which == _diff
	_settings.visible = which == _settings
	_controls.visible = which == _controls
	if _levels_panel:
		_levels_panel.visible = which == _levels_panel
	if _keybind_panel:
		_keybind_panel.visible = which == _keybind_panel

# --- cheat: type "warp" anywhere on the menu for a direct level select ---

const CHEAT_WORD := "warp"
var _cheat_buf := ""
var _levels_panel: VBoxContainer
var _keybind_panel: KeybindPanel
var _diff_btns: Array[Button] = []

func _input(event: InputEvent) -> void:
	# While the rebind screen is actively capturing a key/button, ESC belongs
	# to it (cancel-capture) — don't also snap the whole menu back to Main.
	# Both checks matter: KeybindPanel may run its _input before or after ours
	# depending on tree order, so guard on its still-capturing state AND on
	# whether it already marked the event handled (it does for every capture
	# outcome, including cancel).
	if get_viewport().is_input_handled():
		return
	if _keybind_panel and _keybind_panel.visible and _keybind_panel.is_capturing():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	# ESC backs out of any sub-panel (settings / difficulty / controls / levels)
	# to the main menu — these panels can overflow and bury their Back button.
	if k.physical_keycode == KEY_ESCAPE:
		if _main and not _main.visible:
			_show_panel(_main)
			accept_event()
		return
	if k.unicode == 0:
		return
	_cheat_buf = (_cheat_buf + char(k.unicode).to_lower()).right(CHEAT_WORD.length())
	if _cheat_buf == CHEAT_WORD:
		_cheat_buf = ""
		_open_level_select()

func _open_level_select() -> void:
	if _levels_panel == null:
		_build_level_select()
	# The cheat is for testing/showing off — unlock the full bestiary too, so the
	# Encyclopedia immediately shows every enemy (back out and open Enemy Codex).
	GameState.discover_all_enemies()
	_show_panel(_levels_panel)
	AudioBus.play_synth_ui("pickup_health", -6.0, 1.5) # cheat-accepted chirp

## Built lazily — most sessions never see it. One button per campaign level,
## named from its def; jumping uses the normal cutscene/briefing entry path at
## the currently selected difficulty (NORMAL unless a run set it).
func _build_level_select() -> void:
	_levels_panel = VBoxContainer.new()
	_levels_panel.add_theme_constant_override("separation", 10)
	var prompt := Label.new()
	prompt.text = "WARP — SELECT LEVEL"
	prompt.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_levels_panel.add_child(prompt)
	# Difficulty picker — a campaign normally locks the tier at "Begin Operation",
	# but warp is for testing, so let the tester choose what tier the warped-in
	# level runs at. The pick persists into the run via GameState.difficulty.
	_levels_panel.add_child(_build_difficulty_row())
	# Back sits at the TOP so it's always on-screen — the campaign list is long
	# enough to overflow the viewport, which would otherwise bury a bottom Back.
	var back := Button.new()
	back.custom_minimum_size = Vector2(420, 40)
	back.text = "Back to Menu"
	back.pressed.connect(func(): _show_panel(_main))
	_levels_panel.add_child(back)
	# Warp unlocks the whole bestiary (discover_all_enemies above), so offer direct
	# jumps to the codices right here — no need to back out and hunt for the buttons.
	var bestiary := Button.new()
	bestiary.custom_minimum_size = Vector2(420, 40)
	bestiary.text = "▣  Enemy Codex (all unlocked)"
	bestiary.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
	bestiary.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/encyclopedia.tscn"))
	_levels_panel.add_child(bestiary)
	var wcodex := Button.new()
	wcodex.custom_minimum_size = Vector2(420, 40)
	wcodex.text = "▣  Weapon Codex"
	wcodex.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
	wcodex.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/weapon_codex.tscn"))
	_levels_panel.add_child(wcodex)
	# Scroll the (18-level) list so every entry — and the Back button — stays
	# reachable on any screen height.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for i in GameState.campaign().size():
		var path: String = GameState.campaign()[i]
		var id := GameState.level_id_from_path(path)
		var def: Dictionary = LevelDefs.get_def(id)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(420, 44)
		btn.text = "%d.  %s" % [i + 1, def.get("name", "FIRST CONTACT" if id == "01" else id.to_upper())]
		# Warping in is for testing/showing off — hand over the entire arsenal so
		# any level can be tried with every weapon.
		btn.pressed.connect(func():
			GameState.unlock_all_weapons()
			GameState.go_to_level(path))
		list.add_child(btn)
	# Standalone scenarios (not part of the campaign route) — warp can reach these
	# too, so every level in the game is one click away for testing/showing off.
	for sc in [["res://scenes/levels/level_range.tscn", "★  GUN RANGE (sandbox)"],
			["res://scenes/levels/level_horde.tscn", "★  HORDE (survival)"]]:
		var spath: String = sc[0]
		var sbtn := Button.new()
		sbtn.custom_minimum_size = Vector2(420, 44)
		sbtn.text = sc[1]
		sbtn.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
		sbtn.pressed.connect(func():
			GameState.unlock_all_weapons()
			GameState.load_level(spath))
		list.add_child(sbtn)
	_levels_panel.add_child(scroll)
	$Center/VBox.add_child(_levels_panel)

## A row of EASY / NORMAL / HARD toggles for the warp panel. Sets
## GameState.difficulty directly; the active tier shows as the pressed button.
func _build_difficulty_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "DIFFICULTY:"
	lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	row.add_child(lbl)
	_diff_btns.clear()
	for tier in [GameState.Difficulty.EASY, GameState.Difficulty.NORMAL, GameState.Difficulty.HARD]:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, 40)
		b.text = GameState.DIFFICULTY_CONFIG[tier].get("label", "")
		b.pressed.connect(func():
			GameState.difficulty = tier
			_refresh_difficulty_row()
			AudioBus.play_synth_ui("pickup_health", -8.0, 1.2))
		row.add_child(b)
		_diff_btns.append(b)
	_refresh_difficulty_row()
	return row

func _refresh_difficulty_row() -> void:
	var tiers := [GameState.Difficulty.EASY, GameState.Difficulty.NORMAL, GameState.Difficulty.HARD]
	for i in _diff_btns.size():
		_diff_btns[i].button_pressed = GameState.difficulty == tiers[i]

func _refresh_graphics_label() -> void:
	_graphics_label.text = tr("Graphics: %s") % GraphicsSettings.quality_label()
	_gfx_down.disabled = GraphicsSettings.quality == GraphicsSettings.Quality.LOW
	_gfx_up.disabled = GraphicsSettings.quality == GraphicsSettings.Quality.ULTRA
	if _restart_btn:
		_restart_btn.visible = GraphicsSettings.restart_recommended()

## Lowering the tier below the one the game started at only pays off fully after a
## restart (GraphicsSettings.launch_quality, #156), so offer one right there.
var _restart_btn: Button

func _build_restart_button() -> void:
	_restart_btn = Button.new()
	_restart_btn.name = "RestartToApplyBtn"
	_restart_btn.text = tr("Restart to apply the lower quality (full speed-up)")
	_restart_btn.custom_minimum_size = Vector2(360, 44)
	_restart_btn.modulate = Color(1.0, 0.85, 0.45)
	_restart_btn.pressed.connect(GraphicsSettings.restart_game)
	_settings.add_child(_restart_btn)
	_settings.move_child(_restart_btn, 2) # under the GPU readout, above the grid
	_restart_btn.visible = GraphicsSettings.restart_recommended()

## First launch ever (no persisted quality key): runs QualityBenchmark as an
## async child so it never blocks menu interactivity — its SubViewport isn't
## attached anywhere visible, it just renders offscreen behind the menu.
func _run_auto_quality_benchmark() -> void:
	# Cleared BEFORE the benchmark finishes (right here, at start): the
	# language/preset pickers reload the whole scene (see reload_current_scene
	# below), and a reload mid-benchmark must not be able to kick off a second
	# one from the freshly-instanced menu.
	GraphicsSettings.needs_auto_quality = false
	var bench := QualityBenchmark.new()
	bench.finished.connect(_on_auto_quality_finished)
	add_child(bench)

func _on_auto_quality_finished(tier: int) -> void:
	GraphicsSettings.set_quality(tier)
	_refresh_graphics_label()
	_show_auto_quality_toast(GraphicsSettings.LABELS[tier])

## Transient "AUTO QUALITY: <TIER>" banner telling the player what the
## first-run benchmark picked. Fades itself out and frees — no dismiss needed.
func _show_auto_quality_toast(label_text: String) -> void:
	var toast := Label.new()
	toast.text = tr("AUTO QUALITY: %s") % label_text
	toast.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	toast.add_theme_font_size_override("font_size", 24)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.anchor_right = 1.0
	toast.offset_top = 24
	toast.offset_bottom = 60
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(toast, "modulate:a", 0.0, 0.8)
	tween.tween_callback(toast.queue_free)

# --- main ---
func _on_play_pressed() -> void:
	_show_panel(_diff)

func _on_continue_pressed() -> void:
	GameState.continue_campaign()

func _on_map_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/campaign_map.tscn")

## Sandbox firing range: straight in, no cutscene/briefing, doesn't touch the
## campaign checkpoint (load_level only saves for CAMPAIGN levels).
func _on_range_pressed() -> void:
	GameState.load_level("res://scenes/levels/level_range.tscn")

## Endless wave-siege mode; like the range, runs outside the campaign flow.
func _on_horde_pressed() -> void:
	GameState.load_level("res://scenes/levels/level_horde.tscn")

## Today's Daily Op (#172): one seeded level + directive on HARD, outside the campaign.
func _on_daily_pressed() -> void:
	GameState.start_daily_op()

## The button names today's op, and once it is cleared the day's best and the streak.
func _refresh_daily_button() -> void:
	var op: Dictionary = GameState.daily_op_for(GameState.today_string())
	if op.is_empty():
		_daily.visible = false
		return
	var rec: Dictionary = GameState.daily_record()
	var text := "%s  ·  %s  ·  %s" % [tr("Daily Op"), tr(String(op["title"])), tr(String(op["directive_name"]))]
	if bool(rec["cleared_today"]):
		text = "✔ " + text + "  ·  " + (tr("Best %s") % str(rec["best"]))
	if int(rec["streak"]) > 1:
		text += "  ·  " + (tr("%d-day streak") % int(rec["streak"]))
	_daily.text = text
	_daily.tooltip_text = tr(String(op["directive_desc"]))

func _on_settings_pressed() -> void:
	_show_panel(_settings)

func _on_controls_pressed() -> void:
	_show_panel(_controls)

func _on_encyclopedia_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/encyclopedia.tscn")

func _on_weapon_codex_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/weapon_codex.tscn")

func _on_controls_back_pressed() -> void:
	_show_panel(_main)

func _on_quit_pressed() -> void:
	get_tree().quit()

# --- difficulty ---
func _on_back_pressed() -> void:
	_show_panel(_main)

func _on_easy_pressed() -> void:
	GameState.start_campaign(GameState.Difficulty.EASY)

func _on_normal_pressed() -> void:
	GameState.start_campaign(GameState.Difficulty.NORMAL)

func _on_hard_pressed() -> void:
	GameState.start_campaign(GameState.Difficulty.HARD)

# --- settings ---
func _on_graphics_down_pressed() -> void:
	GraphicsSettings.step_quality(-1)
	_refresh_graphics_label()

func _on_graphics_up_pressed() -> void:
	GraphicsSettings.step_quality(1)
	_refresh_graphics_label()

func _on_volume_changed(value: float) -> void:
	AudioBus.set_master_volume(value)

func _on_settings_back_pressed() -> void:
	_show_panel(_main)

## Lazily builds the rebind screen (same lazy-build idiom as _build_level_select)
## and shows it. Built as its own class (scripts/ui/keybind_panel.gd) rather
## than inline like the slider rows above it — it needs its own _input capture
## state machine, which would clutter this file's simple settings idiom.
func _on_rebind_controls_pressed() -> void:
	if _keybind_panel == null:
		_keybind_panel = KeybindPanel.new()
		_keybind_panel.back_pressed.connect(func(): _show_panel(_settings))
		$Center/VBox.add_child(_keybind_panel)
	_show_panel(_keybind_panel)
