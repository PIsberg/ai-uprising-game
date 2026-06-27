extends Control

@onready var _main: VBoxContainer = $Center/VBox/MainButtons
@onready var _diff: VBoxContainer = $Center/VBox/DiffButtons
@onready var _settings: VBoxContainer = $Center/VBox/SettingsPanel
@onready var _controls: VBoxContainer = $Center/VBox/ControlsPanel
@onready var _continue: Button = $Center/VBox/MainButtons/Continue
@onready var _graphics_btn: Button = $Center/VBox/SettingsPanel/Graphics
@onready var _volume: HSlider = $Center/VBox/SettingsPanel/VolumeRow/VolumeSlider

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.set_state(GameState.State.MENU)
	# Continue is only offered when a checkpoint exists.
	_continue.visible = GameState.has_save()
	_volume.value = AudioBus.get_master_volume()
	_refresh_graphics_label()
	_build_extra_settings()
	_show_panel(_main)

var _fps_btn: Button

## Adds FOV / sensitivity / invert-Y / framerate controls to the settings panel
## at runtime, wired straight to GraphicsSettings (persisted on change).
func _build_extra_settings() -> void:
	var back := _settings.get_node_or_null("BackS") as Control

	var fov_slider := _add_slider_row("Field of View", 60.0, 110.0, 1.0, GraphicsSettings.fov)
	fov_slider.value_changed.connect(func(v: float): GraphicsSettings.set_fov(v))

	var sens_slider := _add_slider_row("Look Sensitivity", 0.2, 3.0, 0.05, GraphicsSettings.sensitivity)
	sens_slider.value_changed.connect(func(v: float): GraphicsSettings.set_sensitivity(v))

	var invert := CheckButton.new()
	invert.text = "Invert Look Y"
	invert.custom_minimum_size = Vector2(360, 44)
	invert.button_pressed = GraphicsSettings.invert_y
	invert.toggled.connect(func(p: bool): GraphicsSettings.set_invert_y(p))
	_settings.add_child(invert)

	var gpu_parts := CheckButton.new()
	gpu_parts.text = "Enable GPU Particles"
	gpu_parts.custom_minimum_size = Vector2(360, 44)
	gpu_parts.button_pressed = GraphicsSettings.gpu_particles_enabled
	gpu_parts.toggled.connect(func(p: bool): GraphicsSettings.set_gpu_particles_enabled(p))
	_settings.add_child(gpu_parts)

	var vol_noise := CheckButton.new()
	vol_noise.text = "Volumetric Noise Shafts"
	vol_noise.custom_minimum_size = Vector2(360, 44)
	vol_noise.button_pressed = GraphicsSettings.volumetric_noise_enabled
	vol_noise.toggled.connect(func(p: bool): GraphicsSettings.set_volumetric_noise_enabled(p))
	_settings.add_child(vol_noise)

	var tri_robots := CheckButton.new()
	tri_robots.text = "Triplanar Damage Robots"
	tri_robots.custom_minimum_size = Vector2(360, 44)
	tri_robots.button_pressed = GraphicsSettings.robot_triplanar_enabled
	tri_robots.toggled.connect(func(p: bool): GraphicsSettings.set_robot_triplanar_enabled(p))
	_settings.add_child(tri_robots)

	var puddles := CheckButton.new()
	puddles.text = "Animated Puddle Ripples"
	puddles.custom_minimum_size = Vector2(360, 44)
	puddles.button_pressed = GraphicsSettings.puddle_ripples_enabled
	puddles.toggled.connect(func(p: bool): GraphicsSettings.set_puddle_ripples_enabled(p))
	_settings.add_child(puddles)

	var post_proc := CheckButton.new()
	post_proc.text = "Advanced Lens Flares & Bloom"
	post_proc.custom_minimum_size = Vector2(360, 44)
	post_proc.button_pressed = GraphicsSettings.advanced_post_process_enabled
	post_proc.toggled.connect(func(p: bool): GraphicsSettings.set_advanced_post_process_enabled(p))
	_settings.add_child(post_proc)

	var area_lights := CheckButton.new()
	area_lights.text = tr("Soft Area Lights (HIGH/ULTRA)")
	area_lights.custom_minimum_size = Vector2(360, 44)
	area_lights.button_pressed = GraphicsSettings.area_lights_enabled
	area_lights.toggled.connect(func(p: bool): GraphicsSettings.set_area_lights_enabled(p))
	_settings.add_child(area_lights)

	var hdr := CheckButton.new()
	hdr.text = tr("HDR Display Output")
	hdr.custom_minimum_size = Vector2(360, 44)
	hdr.button_pressed = GraphicsSettings.hdr_output_enabled
	hdr.toggled.connect(func(p: bool): GraphicsSettings.set_hdr_output_enabled(p))
	_settings.add_child(hdr)

	var show_fps := CheckButton.new()
	show_fps.text = tr("Show FPS Counter")
	show_fps.custom_minimum_size = Vector2(360, 44)
	show_fps.button_pressed = GraphicsSettings.show_fps
	show_fps.toggled.connect(func(p: bool): GraphicsSettings.set_show_fps(p))
	_settings.add_child(show_fps)

	var dof := CheckButton.new()
	dof.text = tr("Depth of Field")
	dof.custom_minimum_size = Vector2(360, 44)
	dof.button_pressed = GraphicsSettings.dof_enabled
	dof.toggled.connect(func(p: bool): GraphicsSettings.set_dof_enabled(p))
	_settings.add_child(dof)

	_fps_btn = Button.new()
	_fps_btn.custom_minimum_size = Vector2(360, 44)
	_fps_btn.text = tr("Framerate: %s") % GraphicsSettings.fps_label()
	_fps_btn.pressed.connect(_on_fps_pressed)
	_settings.add_child(_fps_btn)

	var sfx := _add_slider_row("SFX Volume", 0.0, 1.0, 0.05, AudioBus.get_sfx_volume())
	sfx.value_changed.connect(func(v: float): AudioBus.set_sfx_volume(v))

	var music := _add_slider_row("Music Volume", 0.0, 1.0, 0.05, AudioBus.get_music_volume())
	music.value_changed.connect(func(v: float): AudioBus.set_music_volume_linear(v))

	_add_language_row()

	# Keep the Back button at the bottom of the panel.
	if back:
		_settings.move_child(back, _settings.get_child_count() - 1)

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
	_settings.add_child(row)

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
	_settings.add_child(row)
	return s

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

# --- cheat: type "warp" anywhere on the menu for a direct level select ---

const CHEAT_WORD := "warp"
var _cheat_buf := ""
var _levels_panel: VBoxContainer
var _diff_btns: Array[Button] = []

func _input(event: InputEvent) -> void:
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
	_graphics_btn.text = tr("Graphics: %s") % GraphicsSettings.quality_label()

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
func _on_graphics_pressed() -> void:
	GraphicsSettings.cycle()
	_refresh_graphics_label()

func _on_volume_changed(value: float) -> void:
	AudioBus.set_master_volume(value)

func _on_settings_back_pressed() -> void:
	_show_panel(_main)
