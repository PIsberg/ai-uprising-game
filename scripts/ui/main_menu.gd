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

	_fps_btn = Button.new()
	_fps_btn.custom_minimum_size = Vector2(360, 44)
	_fps_btn.text = "Framerate: " + GraphicsSettings.fps_label()
	_fps_btn.pressed.connect(_on_fps_pressed)
	_settings.add_child(_fps_btn)

	var sfx := _add_slider_row("SFX Volume", 0.0, 1.0, 0.05, AudioBus.get_sfx_volume())
	sfx.value_changed.connect(func(v: float): AudioBus.set_sfx_volume(v))

	var music := _add_slider_row("Music Volume", 0.0, 1.0, 0.05, AudioBus.get_music_volume())
	music.value_changed.connect(func(v: float): AudioBus.set_music_volume_linear(v))

	# Keep the Back button at the bottom of the panel.
	if back:
		_settings.move_child(back, _settings.get_child_count() - 1)

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
	_fps_btn.text = "Framerate: " + GraphicsSettings.fps_label()

func _show_panel(which: Control) -> void:
	_main.visible = which == _main
	_diff.visible = which == _diff
	_settings.visible = which == _settings
	_controls.visible = which == _controls

func _refresh_graphics_label() -> void:
	_graphics_btn.text = "Graphics: %s" % GraphicsSettings.quality_label()

# --- main ---
func _on_play_pressed() -> void:
	_show_panel(_diff)

func _on_continue_pressed() -> void:
	GameState.continue_campaign()

func _on_settings_pressed() -> void:
	_show_panel(_settings)

func _on_controls_pressed() -> void:
	_show_panel(_controls)

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
