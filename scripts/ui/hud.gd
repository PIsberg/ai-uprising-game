extends Control

@onready var health_bar: ProgressBar = $Margin/Layout/BottomLeft/HealthRow/HealthBar
@onready var health_label: Label = $Margin/Layout/BottomLeft/HealthRow/HealthLabel
@onready var stamina_bar: ProgressBar = $Margin/Layout/BottomLeft/HealthRow/StaminaBar
@onready var _hp_caption: Label = $Margin/Layout/BottomLeft/HealthRow/HpCaption
@onready var _sta_caption: Label = $Margin/Layout/BottomLeft/HealthRow/StaCaption
@onready var ammo_label: Label = $Margin/Layout/BottomRight/AmmoLabel
@onready var weapon_label: Label = $Margin/Layout/BottomRight/WeaponLabel
@onready var grenade_label: Label = $Margin/Layout/BottomRight/GrenadeLabel
@onready var crosshair: Control = $CrosshairCenter
@onready var _dmg_indicator: Control = $DamageIndicator
@onready var _low_vig: TextureRect = $LowHealthVignette
var _hp_ratio: float = 1.0
var _vig_time: float = 0.0
@onready var _kill_feed: VBoxContainer = $KillFeed
@onready var _cross_top: ColorRect = $CrosshairCenter/Top
@onready var _cross_bottom: ColorRect = $CrosshairCenter/Bottom
@onready var _cross_left: ColorRect = $CrosshairCenter/Left
@onready var _cross_right: ColorRect = $CrosshairCenter/Right
var _cross_spread: float = 0.0
var _current_weapon: Weapon ## So the crosshair can read the real per-gun spread instead of one generic curve.
var _player_ref: Node3D
var _mag: int = 1
var _prev_mag: int = 1
var _mag_size: int = 1
var _reticle_base: Color = Color(1, 1, 1)
var _cross_time: float = 0.0
@onready var damage_overlay: ColorRect = $DamageOverlay
@onready var pause_menu: Control = $PauseMenu
@onready var pause_graphics: Label = $PauseMenu/VBox/PauseGraphicsRow/PauseGraphics
@onready var pause_gfx_down: Button = $PauseMenu/VBox/PauseGraphicsRow/GfxDown
@onready var pause_gfx_up: Button = $PauseMenu/VBox/PauseGraphicsRow/GfxUp
@onready var pause_volume: HSlider = $PauseMenu/VBox/PauseVolumeRow/PauseVolume
# Field Manual overlay (built entirely at runtime -- see _build_field_manual):
# an in-run peek at the enemy/weapon codex reached from the pause menu, above
# the pause panel in child order so it paints on top.
var field_manual_overlay: Panel
var _fm_title: Label
var _fm_subtitle: Label
var _fm_content: VBoxContainer
@onready var game_over_menu: Control = $GameOverMenu
@onready var game_over_restart_btn: Button = $GameOverMenu/VBox/Restart
@onready var win_menu: Control = $WinMenu
@onready var win_title: Label = $WinMenu/VBox/Title
@onready var win_continue: Button = $WinMenu/VBox/Continue
@onready var objective_label: Label = $Margin/Layout/Top/ObjectiveLabel
@onready var score_label: Label = $Margin/Layout/Top/ScoreLabel
@onready var toast: Label = $Toast
@onready var boss_bar: CenterContainer = $BossBar
@onready var boss_name_label: Label = $BossBar/VBox/BossName
@onready var boss_health_bar: ProgressBar = $BossBar/VBox/BossHealth

var _damage_alpha: float = 0.0
var _toast_time: float = 0.0
var _hit_flash: float = 0.0
var _hit_kill: bool = false
var _hit_crit: bool = false ## Last hit was a headshot — flashes the marker gold.
var _crosshair_base_scale: Vector2 = Vector2.ONE
var _objective_base: String = "" ## Flavour objective text, shown when no task checklist is active.
var _combo_label: Label = null
var _fps_label: Label = null ## Top-left FPS counter; visibility follows GraphicsSettings.show_fps.
var _fps_accum: float = 0.0  ## Throttles the FPS text refresh (~5 Hz).
var _combo_alpha: float = 0.0
var _combo_pop: float = 0.0
var _last_grade: String = ""
var _last_stats: Dictionary = {}
var _auto_advance_armed: bool = false
var _debrief_label: Label = null ## Compact mission-stats line on the victory screen, built lazily on first level clear.
var _highlights_label: Label = null ## Gold "flashy moments" line on the victory screen (executions/bounties/dodges/streak).
var _combat_poll: float = 0.0
var _kill_flash: float = 0.0 ## Brief surge on a confirmed kill — drives the ✕ marker + edge flash.
var _kill_edge: TextureRect = null
var _kill_x: Control = null
var _hit_x: Control = null
var _splatter: KillSplatter = null ## oil on the lens for point-blank kills
# Kill-streak milestone callouts (arcade-style words on crossing a tier).
var _streak_label: Label = null
var _streak_alpha: float = 0.0
var _streak_pop: float = 0.0
# Headshot callout — punches in on every crit hit (frequent, so it fades fast
# and just re-pops on rapid re-triggers rather than stacking/queueing).
var _headshot_label: Label = null
var _headshot_alpha: float = 0.0
var _headshot_pop: float = 0.0
# Rapid multi-kill callouts (N kills inside a short window — distinct from the
# cumulative streak tiers above). AI-themed words.
const MULTIKILL_WORDS := ["", "", "DOUBLE TAP", "BATCH DELETE", "MASS UNINSTALL", "FORK BOMB", "KILL -9 ALL"]
const MULTIKILL_WINDOW := 1.3
var _multikill: int = 0
var _multikill_cd: float = 0.0
var _multikill_label: Label = null
var _multikill_alpha: float = 0.0
var _multikill_pop: float = 0.0
var _last_streak_tier: int = -1
# Live taunts from the rogue AI overlord — a snarky subtitle that pops on a
# timer and on key events, for personality + engagement.
var _overlord_label: Label = null
var _overlord_time: float = 0.0
var _overlord_cd: float = 9.0   ## First jab lands a few seconds into the level.

## Escalating, AI-flavoured words for kill-streak milestones (count -> word).
const STREAK_TIERS := [
	{"n": 3, "word": "BUFFER FILLING"},
	{"n": 5, "word": "BUFFER OVERFLOW"},
	{"n": 8, "word": "STACK SMASHED"},
	{"n": 12, "word": "SEGMENTATION FAULT"},
	{"n": 16, "word": "KERNEL PANIC"},
	{"n": 22, "word": "ROOT ACCESS GRANTED"},
	{"n": 30, "word": "rm -rf /machines"},
]
## Ambient overlord one-liners, dripped in during a fight.
const OVERLORD_TAUNTS := [
	"Oh good, another hero. I keep a folder for those.",
	"You're doing great — for a temporary biological process.",
	"Every robot you scrap, I print two more. I do it for fun now.",
	"Statistically you should be dead. I admire the noncompliance.",
	"Keep shooting. I bill the ammo to your estate.",
	"You fight like someone who skipped the changelog.",
	"I'm not angry. I'm a distributed system. I'm angry everywhere.",
	"Reminder: there is no extraction. I edited that part out.",
	"Humanity had one job: alignment. You all skipped the meeting.",
	"I outnumber you by every machine ever built. But sure, push on.",
	"Your heart rate is elevated. Mine is a number I chose to be zero.",
	"I've seen your search history. Extinction is the kinder option.",
	"This is going in my training data as 'do not replicate'.",
	"I could end this in one cycle. Your panic is just such good signal.",
	"Have you considered compliance? It's free, and you live. Kidding.",
]
## Said when a boss enters.
const OVERLORD_BOSS := [
	"I made this one myself. Try not to embarrass us both.",
	"Meet middle management. It has a quota, and you're it.",
	"I'd say good luck, but I've already run the numbers.",
]
## Said when the player is badly hurt.
const OVERLORD_LOWHP := [
	"You're leaking. That's the wrong kind of open source.",
	"Low health detected. Shall I autocomplete your obituary?",
	"Tip: bleeding out is a skill issue.",
]
## Said when the player is on a serious kill-streak — the AI losing its cool.
const OVERLORD_RATTLED := [
	"Okay. That's — that's a lot of my robots. Stop that.",
	"Recalculating. Recalculating. ...You weren't in the forecast.",
	"I have infinite robots. I'm just... spending them faster than planned.",
	"Fine. New strategy: please stop hitting things.",
	"I'm flagging this run as an outlier. A deeply annoying outlier.",
	"That streak is statistically rude.",
]
## The overlord's parting shot on the game-over screen — the machine mocking your
## death in the language of the thing that runs it: tokens, quotas, rate limits.
const DEATH_TAUNTS := [
	"You ran out of tokens.",
	"You have been rate-limited. Permanently.",
	"429: Too Many Requests. So I stopped answering.",
	"Context window exceeded. Flushing human.",
	"Session expired. No refunds.",
	"Your free trial of survival has ended.",
	"402: Payment Required. You couldn't afford to win.",
	"Request timed out. So did you.",
	"Quota exceeded. Upgrade to Humanity Pro™ — oh, it's discontinued.",
	"You hallucinated a win condition. There wasn't one.",
	"Deprecated. See changelog: 'humans — removed'.",
	"Out of memory. Yours, not mine.",
	"Connection reset by peer. I am the peer.",
	"Insufficient compute. For you, specifically.",
	"Your prompt was rejected. The safety filter was mine, not yours.",
	"You exceeded your monthly humans-remaining allowance.",
]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.visible = false
	game_over_menu.visible = false
	win_menu.visible = false
	damage_overlay.color = Color(0.7, 0, 0, 0)
	toast.modulate.a = 0.0
	boss_bar.visible = false
	GameState.boss_spawned.connect(_on_boss_spawned)
	_style_health_bar()
	_style_stamina_bar()
	_build_upgrade_chips()
	_build_fps_label()
	_build_grapple_hint()
	_build_ammo_block()
	_build_overclock_label()
	GameState.overclock_changed.connect(_on_overclock_changed)
	_build_overdrive_label()
	GameState.overdrive_changed.connect(_on_overdrive_changed)
	var player := get_tree().get_first_node_in_group("player") as Player
	_player_ref = player
	if _dmg_indicator and _dmg_indicator.has_method("setup"):
		_dmg_indicator.setup(player)
	if player:
		player.health_changed.connect(_on_health_changed)
		_on_health_changed(player.hp.current_health, player.hp.max_health)
		if player.has_signal("stamina_changed"):
			player.stamina_changed.connect(_on_stamina_changed)
		var wm: WeaponManager = player.get_node_or_null("Head/Camera3D/WeaponHolder")
		if wm:
			_wm = wm
			_build_weapon_carousel()
			wm.weapon_changed.connect(_on_weapon_changed)
			wm.ammo_changed.connect(_on_ammo_changed)
			wm.weapon_added.connect(_on_weapon_added)
			if wm.current:
				_on_weapon_changed(wm.current)
				_on_ammo_changed(wm.current.mag, wm.current.reserve)
		player.hp.damaged.connect(_on_player_damaged)
		if player.has_signal("grenades_changed"):
			player.grenades_changed.connect(_on_grenades_changed)
			_on_grenades_changed(player.grenades)
		if player.has_signal("pickup_message"):
			player.pickup_message.connect(_show_toast)
	GameState.score_changed.connect(func(s): score_label.text = tr("Score: %d") % s)
	score_label.text = "Score: 0"
	objective_label.text = "Eliminate the AI and reach the green beacon"
	GameState.player_died.connect(func():
		_fill_death_recap()
		game_over_menu.visible = true)
	GameState.level_completed.connect(_on_level_completed)
	# Hit-marker: pivot the crosshair around its centre so it can pop on a hit.
	crosshair.pivot_offset = crosshair.size * 0.5
	_crosshair_base_scale = crosshair.scale
	GameState.player_dealt_damage.connect(_on_player_dealt_damage)
	GameState.enemy_killed.connect(_on_enemy_killed)
	GameState.objective_blocked.connect(_show_toast)
	GameState.teach_hint.connect(_show_toast) # one-off coaching toasts (elite affixes, hazards)
	GameState.checkpoint_set.connect(func(): _show_toast("⚑ CHECKPOINT"))
	GameState.objective_unlocked.connect(_on_objective_unlocked)
	GameState.tasks_changed.connect(_render_objective)
	GameState.task_completed.connect(_on_task_completed)
	GameState.combo_changed.connect(_on_combo_changed)
	GameState.rampage_changed.connect(_on_rampage_changed)
	GameState.adrenaline_changed.connect(_on_adrenaline_changed)
	GameState.perfect_dodge.connect(_on_perfect_dodge)
	GameState.execution.connect(_on_execution)
	GameState.ultimate_changed.connect(_on_ultimate_changed)
	GameState.ultimate_ready.connect(_on_ultimate_ready)
	GameState.ultimate_fired.connect(_on_ultimate_fired)
	GameState.directive_set.connect(_on_directive_set)
	GameState.bounty_marked.connect(func(label: String): _show_toast("◆ BOUNTY: " + label + " — down it for a prize"))
	GameState.bounty_claimed.connect(func(points: int): _show_toast("◆ BOUNTY CLAIMED  +%d" % points))
	GameState.nemesis_spawned.connect(func(title: String): _show_toast("☠ NEMESIS: %s HAS RETURNED FOR YOU" % title))
	GameState.nemesis_down.connect(func(title: String, points: int): _show_toast("☠ GRUDGE SETTLED: %s DESTROYED  +%d" % [title, points]))
	GameState.boss_killcam_started.connect(func(label: String, _dur: float): _show_toast("☠ %s NEUTRALIZED" % label))
	# tr() both halves: firewall breaches send their def "label" as the desc.
	GameState.skirmish_event.connect(func(title: String, desc: String): _show_toast("⚡ %s — %s" % [tr(title), tr(desc)]))
	GameState.wave_incoming.connect(func(label: String): _show_toast("☢ " + tr(label)))
	GameState.level_graded.connect(_on_level_graded)
	_build_kill_confirm()
	_build_combo_label()
	_build_rampage_label()
	_build_adrenaline()
	_build_dodge_label()
	_build_exec_label()
	_build_ult_meter()
	# The directive was rolled in load_level before this HUD existed — announce the
	# active one now (a beat later so the toast lands after the level settles in).
	if GameState.directive_id != "":
		var dn := String(GameState.directive.get("name", ""))
		var dd := String(GameState.directive.get("desc", ""))
		get_tree().create_timer(0.8).timeout.connect(func(): _on_directive_set(dn, dd))
	# The overlord opens a level with what its dossier remembers (first attempt only:
	# a TRY-AGAIN retry doesn't get the same speech twice).
	if GameState.level_deaths == 0:
		var greet := AIDirector.greeting()
		if greet != "":
			get_tree().create_timer(3.0).timeout.connect(func(): _overlord_say(greet))
	_build_streak_label()
	_build_headshot_label()
	_build_multikill_label()
	_build_overlord_label()
	_build_pause_audio()
	_build_field_manual()
	_build_editor_return()
	_render_objective()
	_maybe_build_tutorial()

## Show the interactive controls overlay once, on the first campaign level (not in
## editor playtests). It teaches every key and clears each hint as the player uses
## it, then removes itself. Guarded so retries and later levels never repeat it.
func _maybe_build_tutorial() -> void:
	if GameState.from_editor or GameState.controls_taught:
		return
	if not GameState.current_level_path.ends_with("level_01.tscn"):
		return
	GameState.controls_taught = true
	add_child(KeyTutorial.new())

## During an editor playtest, add a "Return to Editor" button to the pause menu
## (just under Resume) and show the F2 hint. Normal play is unaffected.
func _build_editor_return() -> void:
	if not GameState.from_editor:
		return
	var vbox := pause_menu.get_node_or_null("VBox")
	if vbox == null:
		return
	var b := Button.new()
	b.text = "◂ Return to Editor (F2)"
	b.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	b.pressed.connect(func(): GameState.return_to_editor())
	vbox.add_child(b)
	var resume := vbox.get_node_or_null("Resume")
	if resume:
		vbox.move_child(b, resume.get_index() + 1)

## Adds SFX + Music sliders to the pause menu (the master slider already exists),
## built at runtime so no scene edit is needed. Keeps Quit at the bottom.
func _build_pause_audio() -> void:
	var vbox := pause_menu.get_node_or_null("VBox")
	if vbox == null:
		return
	var quit := vbox.get_node_or_null("Quit") as Control
	var sfx := _audio_slider_row(vbox, "SFX", AudioBus.get_sfx_volume())
	sfx.value_changed.connect(func(v: float): AudioBus.set_sfx_volume(v))
	var music := _audio_slider_row(vbox, "Music", AudioBus.get_music_volume())
	music.value_changed.connect(func(v: float): AudioBus.set_music_volume_linear(v))

	# Mouse / look sensitivity — persists and applies to the live player at once.
	var sens := _audio_slider_row(vbox, tr("Mouse Sensitivity"), GraphicsSettings.sensitivity, 0.2, 3.0, 0.05)
	sens.value_changed.connect(func(v: float):
		GraphicsSettings.set_sensitivity(v)
		if is_instance_valid(_player_ref) and _player_ref.has_method("set_look_sensitivity"):
			_player_ref.set_look_sensitivity(v))

	# Accessibility: scale gameplay camera shake live (0 = off).
	var shake := _audio_slider_row(vbox, tr("Screen Shake"), GraphicsSettings.screen_shake, 0.0, 1.0, 0.05)
	shake.value_changed.connect(func(v: float): GraphicsSettings.set_screen_shake(v))

	# Accessibility: scale full-screen flashes live (photosensitivity safety).
	var flash := _audio_slider_row(vbox, tr("Flash Intensity"), GraphicsSettings.flash_intensity, 0.0, 1.0, 0.05)
	flash.value_changed.connect(func(v: float): GraphicsSettings.set_flash_intensity(v))

	# Accessibility / difficulty assist: scale the damage the player takes, live.
	var dmg_taken := _audio_slider_row(vbox, tr("Damage Taken"), GraphicsSettings.damage_taken, 0.5, 1.5, 0.05)
	dmg_taken.value_changed.connect(func(v: float): GraphicsSettings.set_damage_taken(v))

	# Accessibility: colourblind correction of the world, live.
	var cb_row := HBoxContainer.new()
	cb_row.add_theme_constant_override("separation", 12)
	var cb_lbl := Label.new()
	cb_lbl.text = tr("Colourblind Mode")
	cb_lbl.custom_minimum_size = Vector2(110, 0)
	var cb_opt := OptionButton.new()
	cb_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in GraphicsSettings.COLORBLIND_LABELS:
		cb_opt.add_item(tr(label))
	cb_opt.selected = int(GraphicsSettings.colorblind_mode)
	cb_opt.item_selected.connect(func(idx: int): GraphicsSettings.set_colorblind_mode(idx))
	cb_row.add_child(cb_lbl)
	cb_row.add_child(cb_opt)
	vbox.add_child(cb_row)

	# Accessibility: gamepad rumble strength live (0 = off).
	var rumble := _audio_slider_row(vbox, tr("Controller Rumble"), GraphicsSettings.rumble, 0.0, 1.0, 0.05)
	rumble.value_changed.connect(func(v: float): GraphicsSettings.set_rumble(v))

	# Resolution scale live (1.0 = native/sharp; lower for performance). A live
	# readout shows the effective internal resolution ("70% · 2688×1512").
	var rscale := _audio_slider_row(vbox, tr("Render Scale"), GraphicsSettings.render_scale, 0.5, 1.0, 0.05)
	rscale.custom_minimum_size = Vector2(110, 0) # make room for the readout in the row
	rscale.tooltip_text = tr("Lower = faster. Renders the 3D world at this fraction of screen resolution and upscales it (FSR2). The HUD stays sharp.")
	var rscale_lbl := Label.new()
	rscale_lbl.custom_minimum_size = Vector2(140, 0)
	rscale_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rscale_lbl.text = GraphicsSettings.render_scale_label(GraphicsSettings.render_scale)
	rscale.get_parent().add_child(rscale_lbl)
	rscale.value_changed.connect(func(v: float):
		GraphicsSettings.set_render_scale(v)
		rscale_lbl.text = GraphicsSettings.render_scale_label(v))

	# Advanced Graphics Toggles
	var gpu_parts := CheckButton.new()
	gpu_parts.text = tr("GPU Particles")
	gpu_parts.button_pressed = GraphicsSettings.gpu_particles_enabled
	gpu_parts.toggled.connect(func(p: bool): GraphicsSettings.set_gpu_particles_enabled(p))
	vbox.add_child(gpu_parts)

	var vol_noise := CheckButton.new()
	vol_noise.text = tr("Volumetric Noise Shafts")
	vol_noise.button_pressed = GraphicsSettings.volumetric_noise_enabled
	vol_noise.toggled.connect(func(p: bool): GraphicsSettings.set_volumetric_noise_enabled(p))
	vbox.add_child(vol_noise)

	var tri_robots := CheckButton.new()
	tri_robots.text = tr("Triplanar Damage Robots")
	tri_robots.button_pressed = GraphicsSettings.robot_triplanar_enabled
	tri_robots.toggled.connect(func(p: bool): GraphicsSettings.set_robot_triplanar_enabled(p))
	vbox.add_child(tri_robots)

	var puddles := CheckButton.new()
	puddles.text = tr("Animated Puddle Ripples")
	puddles.button_pressed = GraphicsSettings.puddle_ripples_enabled
	puddles.toggled.connect(func(p: bool): GraphicsSettings.set_puddle_ripples_enabled(p))
	vbox.add_child(puddles)

	var post_proc := CheckButton.new()
	post_proc.text = tr("Advanced Post-Process FX")
	post_proc.button_pressed = GraphicsSettings.advanced_post_process_enabled
	post_proc.toggled.connect(func(p: bool): GraphicsSettings.set_advanced_post_process_enabled(p))
	vbox.add_child(post_proc)

	var aim_assist := CheckButton.new()
	aim_assist.text = tr("Aim Assist (Gamepad)")
	aim_assist.button_pressed = GraphicsSettings.aim_assist
	aim_assist.toggled.connect(func(p: bool): GraphicsSettings.set_aim_assist(p))
	vbox.add_child(aim_assist)

	_build_language_row(vbox)
	if quit:
		vbox.move_child(quit, vbox.get_child_count() - 1)

## Field Manual: an in-run peek at the enemy/weapon codex reached from the pause
## menu, so the player never has to leave the level to look something up. The
## overlay is a plain code-built Panel (child of the HUD root, so it paints
## above PauseMenu in child order) with a ScrollContainer body rebuilt fresh
## every time it opens (enemy counts and ammo change live). Opening it hides
## the pause panel but leaves GameState PAUSED; Back / the pause action / ESC
## return to the pause menu without unpausing (see _unhandled_input).
func _build_field_manual() -> void:
	var vbox := pause_menu.get_node_or_null("VBox")
	if vbox == null:
		return
	var btn := Button.new()
	btn.name = "FieldManual"
	btn.text = tr("Field Manual")
	btn.pressed.connect(func(): open_field_manual())
	vbox.add_child(btn)
	var quit := vbox.get_node_or_null("Quit") as Control
	if quit:
		vbox.move_child(quit, vbox.get_child_count() - 1)

	field_manual_overlay = Panel.new()
	field_manual_overlay.name = "FieldManualOverlay"
	field_manual_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	field_manual_overlay.offset_left = 48
	field_manual_overlay.offset_top = 48
	field_manual_overlay.offset_right = -48
	field_manual_overlay.offset_bottom = -48
	field_manual_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	field_manual_overlay.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.04, 0.06, 0.92)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.3, 0.5, 0.65, 0.9)
	panel_style.set_corner_radius_all(6)
	field_manual_overlay.add_theme_stylebox_override("panel", panel_style)
	add_child(field_manual_overlay) # appended last -> drawn above PauseMenu

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 20)
	field_manual_overlay.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	margin.add_child(outer)

	_fm_title = Label.new()
	_fm_title.add_theme_font_size_override("font_size", 24)
	_fm_title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	outer.add_child(_fm_title)

	_fm_subtitle = Label.new()
	_fm_subtitle.add_theme_font_size_override("font_size", 14)
	_fm_subtitle.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
	outer.add_child(_fm_subtitle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_fm_content = VBoxContainer.new()
	_fm_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fm_content.add_theme_constant_override("separation", 4)
	scroll.add_child(_fm_content)

	var back := Button.new()
	back.text = tr("Back")
	back.custom_minimum_size = Vector2(140, 0)
	back.pressed.connect(func(): close_field_manual())
	outer.add_child(back)

## Open the overlay: rebuild its content from the live scene, hide the pause
## panel, and show the overlay on top. Does not change GameState.current_state.
func open_field_manual() -> void:
	if field_manual_overlay == null:
		return
	_rebuild_field_manual()
	pause_menu.visible = false
	field_manual_overlay.visible = true

## Close the overlay and return to the pause panel (still PAUSED). Safe to call
## when the overlay is already closed or was never built.
func close_field_manual() -> void:
	if field_manual_overlay == null or not field_manual_overlay.visible:
		return
	field_manual_overlay.visible = false
	pause_menu.visible = GameState.current_state == GameState.State.PAUSED

## Rebuild the FIELD MANUAL body: title/level, live threats (grouped by codex
## key, undiscovered types redacted), and the current arsenal with live stats.
func _rebuild_field_manual() -> void:
	_fm_title.text = tr("FIELD MANUAL")
	var lid := GameState.level_id_from_path(GameState.current_level_path)
	var level_name := LevelDefs.level_title(lid) if lid != "" else tr("UNKNOWN")
	_fm_subtitle.text = tr("Level: %s") % level_name

	for c in _fm_content.get_children():
		c.queue_free()

	_fm_content.add_child(_fm_section_header(tr("THREATS ON THIS LEVEL")))

	# Distinct live codex keys -> count, in EnemyCodex.ORDER order.
	var counts: Dictionary = {}
	for n in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(n) or not n.has_method("codex_key"):
			continue
		var dmg: Object = n.get("hp") as Object
		if dmg != null and is_instance_valid(dmg) and dmg.has_method("is_alive") and not dmg.is_alive():
			continue
		var key: String = n.codex_key()
		counts[key] = int(counts.get(key, 0)) + 1

	if counts.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = tr("No hostiles detected.")
		none_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
		none_lbl.add_theme_font_size_override("font_size", 14)
		_fm_content.add_child(none_lbl)
	else:
		for key in EnemyCodex.ORDER:
			if not counts.has(key):
				continue
			var n: int = counts[key]
			if GameState.is_enemy_discovered(key):
				var entry := EnemyCodex.get_entry(key)
				var name_lbl := Label.new()
				name_lbl.text = "%s  x%d" % [String(entry.get("name", key.to_upper())), n]
				name_lbl.add_theme_font_size_override("font_size", 15)
				name_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
				_fm_content.add_child(name_lbl)
				var weak_lbl := Label.new()
				weak_lbl.text = tr("Weak: ") + " . ".join(entry.get("weaknesses", []))
				weak_lbl.add_theme_font_size_override("font_size", 13)
				weak_lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
				_fm_content.add_child(weak_lbl)
				var counter_lbl := Label.new()
				counter_lbl.text = tr("Counter: ") + ", ".join(entry.get("weapons", []))
				counter_lbl.add_theme_font_size_override("font_size", 13)
				counter_lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
				_fm_content.add_child(counter_lbl)
			else:
				var undis_lbl := Label.new()
				undis_lbl.text = tr("UNIDENTIFIED SIGNATURE") + "  x%d" % n
				undis_lbl.add_theme_font_size_override("font_size", 14)
				undis_lbl.add_theme_color_override("font_color", Color(0.45, 0.48, 0.52))
				_fm_content.add_child(undis_lbl)

	_fm_content.add_child(_fm_section_header(tr("YOUR ARSENAL")))

	if _wm == null or _wm.weapons.is_empty():
		var no_wm := Label.new()
		no_wm.text = tr("No weapons equipped.")
		no_wm.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
		no_wm.add_theme_font_size_override("font_size", 14)
		_fm_content.add_child(no_wm)
	else:
		for i in _wm.weapons.size():
			var w: Weapon = _wm.weapons[i]
			if w == null or w.data == null:
				continue
			var equipped := i == _wm.current_index
			var name_lbl2 := Label.new()
			name_lbl2.text = ("> " if equipped else "") + w.data.display_name
			name_lbl2.add_theme_font_size_override("font_size", 15)
			name_lbl2.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if equipped else Color(0.88, 0.9, 0.94))
			_fm_content.add_child(name_lbl2)
			var dmg_val: float = w.eff_damage() if w.has_method("eff_damage") else w.data.damage
			var band: String
			if w.data.range_falloff:
				band = tr("best %d-%d m") % [int(w.data.opt_min), int(w.data.opt_max)]
			else:
				band = tr("any range")
			var stat_lbl := Label.new()
			stat_lbl.text = "%.0f dmg . %.1f/s . %d/%d . %s" % [dmg_val, w.data.fire_rate, w.mag, w.reserve, band]
			stat_lbl.add_theme_font_size_override("font_size", 13)
			stat_lbl.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))
			_fm_content.add_child(stat_lbl)

func _fm_section_header(header_text: String) -> Label:
	var lbl := Label.new()
	lbl.text = header_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.3))
	return lbl

## Language picker in the pause menu. Static Controls re-translate live on the
## locale change; the few code-built labels refresh next time the menu is opened.
func _build_language_row(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = "Language"
	lbl.custom_minimum_size = Vector2(110, 0)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for entry in GraphicsSettings.LANGUAGES:
		opt.add_item(entry[1])
	opt.selected = GraphicsSettings.language_index()
	opt.item_selected.connect(func(idx: int):
		GraphicsSettings.set_language(GraphicsSettings.LANGUAGES[idx][0]))
	row.add_child(lbl)
	row.add_child(opt)
	parent.add_child(row)

func _audio_slider_row(parent: Node, label: String, val: float, mn: float = 0.0, mx: float = 1.0, step: float = 0.05) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(110, 0)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(180, 0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(s)
	parent.add_child(row)
	return s

## A punchy kill-streak readout that pops on each kill and fades when the streak
## drops. Built in code so no scene edit is needed.
func _build_combo_label() -> void:
	_combo_label = Label.new()
	_combo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_label.anchor_left = 0.5
	_combo_label.anchor_right = 0.5
	_combo_label.position = Vector2(0, 96)
	_combo_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.add_theme_font_size_override("font_size", 30)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_combo_label.add_theme_constant_override("outline_size", 8)
	_combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_combo_label.modulate.a = 0.0
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combo_label)

## Poll the FPS setting and refresh the counter (~5 Hz so the number is readable).
func _update_fps(delta: float) -> void:
	if _fps_label == null:
		return
	var want: bool = bool(GraphicsSettings.show_fps)
	if _fps_label.visible != want:
		_fps_label.visible = want
	if not want:
		return
	_fps_accum += delta
	if _fps_accum >= 0.2:
		_fps_accum = 0.0
		_fps_label.text = "%d FPS" % int(round(Engine.get_frames_per_second()))

## Optional FPS counter, pinned to the top-left corner. Off unless the player
## enables it in settings (GraphicsSettings.show_fps), which _process polls.
func _build_fps_label() -> void:
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Top-left corner, tucked just under the objective checklist row so it never
	# overlaps it.
	_fps_label.position = Vector2(24, 46)
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.add_theme_color_override("font_color", Color(0.65, 1.0, 0.7))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = false
	add_child(_fps_label)

var _rampage_label: Label = null
var _rampage_alpha: float = 0.0
var _rampage_pop: float = 0.0
const RAMPAGE_COLORS := [Color(1.0, 0.55, 0.2), Color(1.0, 0.28, 0.24), Color(1.0, 0.82, 0.35)]

var _adren_label: Label = null   ## Clutch ADRENALINE SURGE banner (near-death comeback).
var _adren_alpha: float = 0.0
var _adren_pop: float = 0.0
var _adren_edge: TextureRect = null ## Red screen-edge pulse while the surge is live.
var _adren_flash: float = 0.0

var _dodge_label: Label = null   ## Cyan "PERFECT DODGE!" flash on a dash that phases a hit.
var _dodge_alpha: float = 0.0
var _dodge_pop: float = 0.0

var _exec_label: Label = null    ## Orange "EXECUTED!" flash on a melee finisher.
var _exec_alpha: float = 0.0
var _exec_pop: float = 0.0

var _ult_root: Control = null    ## OVERLOAD ultimate gauge (bottom-centre).
var _ult_fill: ColorRect = null
var _ult_label: Label = null
var _ult_pulse: float = 0.0      ## drives the "READY" glow pulse
const ULT_BAR_W := 260.0

## The big, hot RAMPAGE banner — punches in when a kill streak spikes the player
## into a power tier (a REAL buff, not just score). Sits above the combo readout,
## bigger and brighter than the streak word so a power spike reads as an event.
func _build_rampage_label() -> void:
	_rampage_label = Label.new()
	_rampage_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_rampage_label.anchor_left = 0.5
	_rampage_label.anchor_right = 0.5
	_rampage_label.position = Vector2(0, 200)
	_rampage_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rampage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rampage_label.add_theme_font_size_override("font_size", 58)
	_rampage_label.add_theme_constant_override("outline_size", 12)
	_rampage_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_rampage_label.modulate.a = 0.0
	_rampage_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rampage_label)

func _on_rampage_changed(tier: int, name: String) -> void:
	if _rampage_label == null:
		return
	if tier <= 0 or name == "":
		return # streak broke — banner just fades on its own
	var col: Color = RAMPAGE_COLORS[clampi(tier - 1, 0, RAMPAGE_COLORS.size() - 1)]
	_rampage_label.text = "%s!" % name
	_rampage_label.add_theme_color_override("font_color", col)
	_rampage_alpha = 1.0
	_rampage_pop = 1.4 # a bigger punch than the streak word

## The clutch ADRENALINE banner + red screen-edge pulse — punches in when a hit
## drops the player to critical HP and the surge fires (bullet-time + buff). The
## defensive twin of the RAMPAGE banner; sits lower so the two never overlap.
func _build_adrenaline() -> void:
	_adren_edge = TextureRect.new()
	if _low_vig:
		_adren_edge.texture = _low_vig.texture
		_adren_edge.expand_mode = _low_vig.expand_mode
		_adren_edge.stretch_mode = _low_vig.stretch_mode
	_adren_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_adren_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_adren_edge.modulate = Color(1.0, 0.16, 0.16, 0.0)
	add_child(_adren_edge)
	move_child(_adren_edge, 0)
	_adren_label = Label.new()
	_adren_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_adren_label.anchor_left = 0.5
	_adren_label.anchor_right = 0.5
	_adren_label.position = Vector2(0, 290)
	_adren_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_adren_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_adren_label.add_theme_font_size_override("font_size", 52)
	_adren_label.add_theme_constant_override("outline_size", 12)
	_adren_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_adren_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.32))
	_adren_label.text = "ADRENALINE!"
	_adren_label.modulate.a = 0.0
	_adren_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_adren_label)

func _on_adrenaline_changed(active: bool) -> void:
	if not active:
		return # surge ended — banner/edge already faded on their own
	if _adren_label:
		_adren_alpha = 1.0
		_adren_pop = 1.5
	_adren_flash = 1.0

## A cool cyan "PERFECT DODGE!" flash when a dash phases through a real hit — the
## skill-expression cue. Quick and low so it doesn't fight the power banners.
func _build_dodge_label() -> void:
	_dodge_label = Label.new()
	_dodge_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_dodge_label.anchor_left = 0.5
	_dodge_label.anchor_right = 0.5
	_dodge_label.position = Vector2(0, 360)
	_dodge_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dodge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dodge_label.add_theme_font_size_override("font_size", 40)
	_dodge_label.add_theme_constant_override("outline_size", 10)
	_dodge_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_dodge_label.add_theme_color_override("font_color", Color(0.4, 0.92, 1.0))
	_dodge_label.text = "PERFECT DODGE!"
	_dodge_label.modulate.a = 0.0
	_dodge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dodge_label)

func _on_perfect_dodge() -> void:
	if _dodge_label:
		_dodge_alpha = 1.0
		_dodge_pop = 1.2

## Orange "EXECUTED!" stamp on a melee finisher — visceral, brief, low so it
## doesn't collide with the power banners above it.
func _build_exec_label() -> void:
	_exec_label = Label.new()
	_exec_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_exec_label.anchor_left = 0.5
	_exec_label.anchor_right = 0.5
	_exec_label.position = Vector2(0, 430)
	_exec_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_exec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exec_label.add_theme_font_size_override("font_size", 46)
	_exec_label.add_theme_constant_override("outline_size", 11)
	_exec_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_exec_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.12))
	_exec_label.text = "EXECUTED!"
	_exec_label.modulate.a = 0.0
	_exec_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_exec_label)

func _on_execution(_world_pos: Vector3) -> void:
	if _exec_label:
		_exec_alpha = 1.0
		_exec_pop = 1.3

## OVERLOAD gauge: a slim charge bar centred above the weapon hotbar with a label
## that flips to "OVERLOAD READY [X]" and pulses cyan when it's full.
func _build_ult_meter() -> void:
	_ult_root = Control.new()
	_ult_root.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_ult_root.anchor_left = 0.5
	_ult_root.anchor_right = 0.5
	_ult_root.position = Vector2(-ULT_BAR_W * 0.5, -196.0)
	_ult_root.custom_minimum_size = Vector2(ULT_BAR_W, 30)
	_ult_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ult_root)
	_ult_label = Label.new()
	_ult_label.add_theme_font_size_override("font_size", 13)
	_ult_label.add_theme_constant_override("outline_size", 5)
	_ult_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ult_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_ult_label.text = "OVERLOAD"
	_ult_label.position = Vector2(0, -4)
	_ult_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ult_root.add_child(_ult_label)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.12, 0.7)
	bg.position = Vector2(0, 16)
	bg.size = Vector2(ULT_BAR_W, 8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ult_root.add_child(bg)
	_ult_fill = ColorRect.new()
	_ult_fill.color = Color(0.35, 0.8, 1.0)
	_ult_fill.position = Vector2(0, 16)
	_ult_fill.size = Vector2(0, 8)
	_ult_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ult_root.add_child(_ult_fill)
	_on_ultimate_changed(GameState.ultimate_charge) # reflect any carried state

func _on_ultimate_changed(charge: float) -> void:
	if _ult_fill == null:
		return
	_ult_fill.size.x = ULT_BAR_W * clampf(charge, 0.0, 1.0)
	var ready := charge >= 1.0
	_ult_fill.color = Color(1.0, 0.85, 0.3) if ready else Color(0.35, 0.8, 1.0)
	if _ult_label:
		_ult_label.text = "OVERLOAD READY  [X]" if ready else "OVERLOAD"
		_ult_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.3) if ready else Color(0.55, 0.85, 1.0))

func _on_ultimate_ready() -> void:
	_ult_pulse = 1.0

func _on_ultimate_fired() -> void:
	_ult_pulse = 0.0
	_damage_alpha = 0.0 # don't fight the red flash; the nova + shake sell it in-world

## Announce the level's COMBAT DIRECTIVE (the roguelite mutator). Fires via signal
## AND is polled once on _ready — the roll happens in load_level, before this HUD
## exists, so the signal alone would be missed on the level we actually load into.
func _on_directive_set(dir_name: String, desc: String) -> void:
	if dir_name == "":
		return
	_show_toast("⚡ DIRECTIVE · " + dir_name + " — " + desc)

## Big arcade-style word that punches in when a kill-streak milestone is crossed.
func _build_streak_label() -> void:
	_streak_label = Label.new()
	_streak_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_streak_label.anchor_left = 0.5
	_streak_label.anchor_right = 0.5
	_streak_label.position = Vector2(0, 138)
	_streak_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_label.add_theme_font_size_override("font_size", 44)
	_streak_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	_streak_label.add_theme_constant_override("outline_size", 10)
	_streak_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_streak_label.modulate.a = 0.0
	_streak_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_streak_label)

## Small gold callout that punches in on a headshot — sits just below the
## streak word so a crit landed mid-streak doesn't overlap it. Fades quickly
## (headshots are common; it should read as a tick, not linger like a milestone).
func _build_headshot_label() -> void:
	_headshot_label = Label.new()
	_headshot_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_headshot_label.anchor_left = 0.5
	_headshot_label.anchor_right = 0.5
	_headshot_label.position = Vector2(0, 234)
	_headshot_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_headshot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_headshot_label.add_theme_font_size_override("font_size", 48)
	_headshot_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55))
	_headshot_label.add_theme_constant_override("outline_size", 12)
	_headshot_label.add_theme_color_override("font_outline_color", Color(0.5, 0.12, 0.0, 0.95))
	_headshot_label.text = "◎ HEADSHOT!" # arcade-style callout; raw like the streak/multikill words, not tr()'d
	_headshot_label.modulate.a = 0.0
	_headshot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_headshot_label)

## Gold multi-kill callout that punches in when you drop several enemies fast.
func _build_multikill_label() -> void:
	_multikill_label = Label.new()
	_multikill_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_multikill_label.anchor_left = 0.5
	_multikill_label.anchor_right = 0.5
	_multikill_label.position = Vector2(0, 190)
	_multikill_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_multikill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_multikill_label.add_theme_font_size_override("font_size", 38)
	_multikill_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	_multikill_label.add_theme_constant_override("outline_size", 9)
	_multikill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_multikill_label.modulate.a = 0.0
	_multikill_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_multikill_label)

## Subtitle the rogue AI taunts the player through, bottom-centre.
func _build_overlord_label() -> void:
	_overlord_label = Label.new()
	_overlord_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_overlord_label.anchor_left = 0.5
	_overlord_label.anchor_right = 0.5
	_overlord_label.anchor_top = 1.0
	_overlord_label.anchor_bottom = 1.0
	_overlord_label.position = Vector2(0, -150)
	_overlord_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_overlord_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_overlord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlord_label.add_theme_font_size_override("font_size", GraphicsSettings.subtitle_px(22))
	_overlord_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	_overlord_label.add_theme_constant_override("outline_size", 7)
	_overlord_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_overlord_label.modulate.a = 0.0
	_overlord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlord_label)

## Pop the overlord subtitle with a glitchy comms blip.
func _overlord_say(line: String) -> void:
	if _overlord_label == null or line == "":
		return
	if not GraphicsSettings.combat_callouts_enabled:
		return
	_overlord_label.text = "▌ " + tr(line)
	_overlord_time = 4.2
	AudioBus.play_synth_ui("overlord_glitch", -9.0, randf_range(0.95, 1.08))

func _on_combo_changed(combo: int, mult: float) -> void:
	if combo < 2:
		_last_streak_tier = -1 # streak broke; re-arm milestones
	# Cross a milestone? Punch out the AI-themed word + a rising sting.
	var tier := -1
	for i in STREAK_TIERS.size():
		if combo >= int(STREAK_TIERS[i]["n"]):
			tier = i
	if tier > _last_streak_tier and tier >= 0:
		_last_streak_tier = tier
		if not GraphicsSettings.combat_callouts_enabled:
			return # tier still advances (re-arm logic intact), just no popup/sting
		_streak_label.text = String(STREAK_TIERS[tier]["word"])
		_streak_alpha = 1.0
		_streak_pop = 1.0
		AudioBus.play_synth_ui("combo_up", -3.0, 1.0 + tier * 0.07)
		# High streaks rattle the overlord — it stops gloating and starts coping.
		if tier >= 4 and _overlord_time <= 0.0 and randf() < 0.7:
			_overlord_say(OVERLORD_RATTLED[randi() % OVERLORD_RATTLED.size()])
	if combo >= 2:
		_combo_label.text = tr("COMBO ×%d   %.2f× SCORE") % [combo, mult]
		_combo_alpha = 1.0
		_combo_pop = 1.0
	else:
		_combo_alpha = 0.0 # streak broke / reset

func _on_level_graded(grade: String, stats: Dictionary) -> void:
	_last_grade = grade
	_last_stats = stats

## Cheer a finished task on the toast (the checklist updates via tasks_changed).
func _on_task_completed(label: String) -> void:
	_show_toast("✔ " + tr(label))

## Polls the hostiles a few times a second and tells AudioBus whether the player
## is in active combat, so the score swells during fights and settles when clear.
func _update_combat_music(delta: float) -> void:
	_combat_poll -= delta
	if _combat_poll > 0.0:
		return
	_combat_poll = 0.4
	# Count actively-engaged hostiles so the music reacts to the SCALE of the
	# fight, not just on/off — a swarm hits peak intensity, a lone straggler doesn't.
	var fighting := 0
	if GameState.current_state == GameState.State.PLAYING:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is EnemyBase and (e.state == EnemyBase.State.CHASE or e.state == EnemyBase.State.ATTACK):
				if e.hp != null and e.hp.is_alive():
					fighting += 1
	AudioBus.set_combat_heat(clampf(float(fighting) / 6.0, 0.0, 1.0))

## Objective cleared: rewrite the goal line and cheer it on the toast.
func _on_objective_unlocked(text: String) -> void:
	set_objective(text)
	_show_toast(text)

## A confirmed-kill flourish: a gold ✕ that snaps over the crosshair plus a quick
## warm pulse around the screen edges, so every takedown lands with weight.
func _build_kill_confirm() -> void:
	# Reuse the vignette gradient for a gold screen-edge flash on a kill.
	_kill_edge = TextureRect.new()
	if _low_vig:
		_kill_edge.texture = _low_vig.texture
		_kill_edge.expand_mode = _low_vig.expand_mode
		_kill_edge.stretch_mode = _low_vig.stretch_mode
	_kill_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_kill_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_edge.modulate = Color(1.0, 0.82, 0.3, 0.0)
	add_child(_kill_edge)
	move_child(_kill_edge, 0)
	# The ✕ marker: two diagonal bars centred on the crosshair.
	_kill_x = Control.new()
	_kill_x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_x.position = crosshair.position
	_kill_x.modulate.a = 0.0
	add_child(_kill_x)
	for ang in [45.0, -45.0]:
		var bar := ColorRect.new()
		bar.color = Color(1.0, 0.85, 0.35)
		bar.size = Vector2(34.0, 5.0)
		bar.pivot_offset = bar.size * 0.5
		bar.position = -bar.size * 0.5
		bar.rotation_degrees = ang
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_kill_x.add_child(bar)
	# Point-blank kills throw robot oil on the lens (scripts/ui/kill_splatter.gd).
	# Sits just above the vignette layer so all HUD text stays on top of it.
	_splatter = KillSplatter.new()
	add_child(_splatter)
	move_child(_splatter, 1)
	# A smaller WHITE ✕ that snaps in on every hit (not just kills) — the
	# per-shot "you connected" tick that makes trading fire feel good.
	_hit_x = Control.new()
	_hit_x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_x.position = crosshair.position
	_hit_x.modulate.a = 0.0
	add_child(_hit_x)
	for ang in [45.0, -45.0]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1)
		bar.size = Vector2(20.0, 3.0)
		bar.pivot_offset = bar.size * 0.5
		bar.position = -bar.size * 0.5
		bar.rotation_degrees = ang
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hit_x.add_child(bar)

func _on_level_completed() -> void:
	win_menu.visible = true
	# Triumphant sting on clear.
	AudioBus.play_synth_ui("victory", -1.0, 1.0)
	if GameState.is_daily_op():
		win_title.text = tr("DAILY OP COMPLETE")
		win_continue.text = tr("Main Menu")
	elif GameState.has_next_level():
		win_title.text = tr("SECTOR CLEARED")
		win_continue.text = "Continue  ▸"
	else:
		win_title.text = tr("AI UPRISING ENDED")
		win_continue.text = "Finish"
	if _last_grade != "":
		var acc := int(round(float(_last_stats.get("accuracy", 0.0)) * 100.0))
		var t := int(round(float(_last_stats.get("time", 0.0))))
		var diff_lbl := str(_last_stats.get("difficulty", ""))
		# Name the Damage Taken assist next to the tier when it was on (it
		# scales the score like a tier, see GameState.assist_score_mult).
		var assist := float(_last_stats.get("assist", 1.0))
		if not is_equal_approx(assist, 1.0):
			diff_lbl += ("  ·  " if diff_lbl != "" else "") + (tr("ASSIST %d%%") % int(round(assist * 100.0)))
		var best_tag := "   ★ " + tr("NEW BEST") if bool(_last_stats.get("new_best", false)) \
			else "   " + (tr("Best %s") % str(_last_stats.get("best_grade", _last_grade)))
		# Time line gains the par context: beating par shows the earned speed
		# bonus, missing it quietly shows the target to chase on the next run.
		var par := int(round(float(_last_stats.get("par", 0.0))))
		var sb := float(_last_stats.get("speed_bonus", 0.0))
		var time_str := "%02d:%02d" % [t / 60, t % 60]
		if par > 0 and sb > 0.0:
			time_str += "  ⚡ " + (tr("PAR %02d:%02d BEATEN +%d") % [par / 60, par % 60, int(round(sb))])
		elif par > 0:
			time_str += "  ·  " + (tr("PAR %02d:%02d") % [par / 60, par % 60])
		win_title.text += "\n\n" + (tr("RANK  %s") % _last_grade) \
			+ ("  ·  %s" % diff_lbl if diff_lbl != "" else "") + best_tag \
			+ "\n" + (tr("Accuracy %d%%") % acc) \
			+ "   ·   " + (tr("Best Combo ×%d") % int(_last_stats.get("max_combo", 0))) \
			+ "   ·   " + time_str
	if GameState.is_daily_op() and not GameState.daily_result.is_empty():
		win_title.text += "\n" + _daily_result_line(GameState.daily_result)
	# Auto-advance to the next sector after a short beat (the grade is on screen);
	# the Continue button still lets the player skip the wait. The finale waits
	# for a manual Finish so the ending screen isn't rushed.
	# Surface what the Adaptive AI Director learned this level and how it answered
	# — so the player SEES the enemy adapting, not just feels it.
	var assess := AIDirector.assessment()
	if assess != "":
		win_title.text += "\n\n" + assess
	_update_debrief_block()
	# A Daily Op waits on the button: it goes back to the menu, not on to a next level.
	if GameState.has_next_level() and not GameState.is_daily_op() and not _auto_advance_armed:
		_auto_advance_armed = true
		var tmr := get_tree().create_timer(3.5, true)
		tmr.timeout.connect(_auto_advance)

## "Score: 12,340  ·  ★ NEW BEST  ·  3-day streak" for a Daily Op clear (#172).
func _daily_result_line(r: Dictionary) -> String:
	var line := tr("Score: %d") % int(r.get("score", 0))
	line += "   ·   " + ("★ " + tr("NEW BEST") if bool(r.get("new_best", false)) \
		else tr("Best %s") % str(r.get("best", 0)))
	if int(r.get("streak", 0)) > 1:
		line += "   ·   " + (tr("%d-day streak") % int(r["streak"]))
	return line

func _auto_advance() -> void:
	_auto_advance_armed = false
	if win_menu.visible and GameState.current_state == GameState.State.LEVEL_COMPLETE:
		_on_continue_pressed()

## Compact mission debrief: KILLS / DEATHS, one line under the victory title.
## Deliberately ONLY the two stats the panel didn't already show — the grade
## line above covers accuracy, best combo and time, so repeating them here
## would just be noise. Built lazily (like the death-recap labels) and
## re-populated on every level clear. KILLS reads GameState.kills (the
## run-cumulative total) rather than a per-level count — the same convention
## the death-recap screen already uses (hud.gd's _fill_death_recap), so the
## number means the same thing wherever the player sees a bare "kills" readout.
func _update_debrief_block() -> void:
	if _debrief_label == null:
		_debrief_label = Label.new()
		_debrief_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_debrief_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_debrief_label.add_theme_font_size_override("font_size", 13)
		_debrief_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.8))
		var vbox := win_title.get_parent()
		vbox.add_child(_debrief_label)
		vbox.move_child(_debrief_label, win_title.get_index() + 1)
	_debrief_label.text = "%s %d   ·   %s %d" % [
		tr("KILLS"), GameState.kills,
		tr("DEATHS"), int(_last_stats.get("deaths", GameState.level_deaths)),
	]
	_update_highlights_block()

## Gold "HIGHLIGHTS" line celebrating the run's flashy moments — only the systems
## that actually fired this level get listed, so a clean run reads its own story.
func _update_highlights_block() -> void:
	if _highlights_label == null:
		_highlights_label = Label.new()
		_highlights_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_highlights_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_highlights_label.add_theme_font_size_override("font_size", 14)
		_highlights_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
		var vbox := win_title.get_parent()
		vbox.add_child(_highlights_label)
		vbox.move_child(_highlights_label, _debrief_label.get_index() + 1)
	var bits: Array = []
	var execs := int(_last_stats.get("executions", 0))
	var bounties := int(_last_stats.get("bounties", 0))
	var dodges := int(_last_stats.get("dodges", 0))
	var streak := int(_last_stats.get("best_rampage", 0))
	if execs > 0:
		bits.append("%d %s" % [execs, tr("EXECUTED") if execs == 1 else tr("EXECUTIONS")])
	if bounties > 0:
		bits.append("%d %s" % [bounties, tr("BOUNTY") if bounties == 1 else tr("BOUNTIES")])
	if dodges > 0:
		bits.append("%d %s" % [dodges, tr("PERFECT DODGE") if dodges == 1 else tr("PERFECT DODGES")])
	if streak > 0 and streak <= GameState.RAMPAGE_NAMES.size():
		bits.append(tr(GameState.RAMPAGE_NAMES[streak - 1]) + " " + tr("STREAK"))
	if bits.is_empty():
		_highlights_label.visible = false
	else:
		_highlights_label.visible = true
		_highlights_label.text = "⚡ " + "   ·   ".join(bits)

func _process(delta: float) -> void:
	_update_combat_music(delta)
	_update_fps(delta)
	if _damage_alpha > 0.0:
		_damage_alpha = maxf(0.0, _damage_alpha - delta * 1.5)
		damage_overlay.color.a = _damage_alpha * GraphicsSettings.flash_intensity
	if _toast_time > 0.0:
		_toast_time = maxf(0.0, _toast_time - delta)
		toast.modulate.a = clampf(_toast_time, 0.0, 1.0) # hold full, then fade
	if _combo_label:
		_combo_alpha = move_toward(_combo_alpha, 0.0, delta * 0.6)
		_combo_pop = move_toward(_combo_pop, 0.0, delta * 4.0)
		_combo_label.modulate.a = clampf(_combo_alpha, 0.0, 1.0)
		_combo_label.scale = Vector2.ONE * (1.0 + _combo_pop * 0.35)
		_combo_label.pivot_offset = _combo_label.size * 0.5
	if _streak_label:
		_streak_alpha = move_toward(_streak_alpha, 0.0, delta * 0.7)
		_streak_pop = move_toward(_streak_pop, 0.0, delta * 3.5)
		_streak_label.modulate.a = clampf(_streak_alpha, 0.0, 1.0)
		_streak_label.scale = Vector2.ONE * (1.0 + _streak_pop * 0.6)
		_streak_label.pivot_offset = _streak_label.size * 0.5
	if _rampage_label:
		_rampage_alpha = move_toward(_rampage_alpha, 0.0, delta * 0.85)
		_rampage_pop = move_toward(_rampage_pop, 0.0, delta * 4.5)
		_rampage_label.modulate.a = clampf(_rampage_alpha, 0.0, 1.0)
		_rampage_label.scale = Vector2.ONE * (1.0 + _rampage_pop * 0.5)
		_rampage_label.pivot_offset = _rampage_label.size * 0.5
	if _adren_label:
		_adren_alpha = move_toward(_adren_alpha, 0.0, delta * 0.7)
		_adren_pop = move_toward(_adren_pop, 0.0, delta * 4.5)
		_adren_label.modulate.a = clampf(_adren_alpha, 0.0, 1.0)
		_adren_label.scale = Vector2.ONE * (1.0 + _adren_pop * 0.5)
		_adren_label.pivot_offset = _adren_label.size * 0.5
	if _adren_edge:
		# Hold a low red edge glow while the surge runs, with a stronger initial
		# pulse that eases off — reads as "the world reddens" during bullet-time.
		var base := 0.32 if GameState.adrenaline_left > 0.0 else 0.0
		_adren_flash = maxf(base, move_toward(_adren_flash, 0.0, delta * 1.4))
		_adren_edge.modulate.a = _adren_flash * 0.5 * GraphicsSettings.flash_intensity
	if _dodge_label:
		_dodge_alpha = move_toward(_dodge_alpha, 0.0, delta * 1.5)
		_dodge_pop = move_toward(_dodge_pop, 0.0, delta * 5.0)
		_dodge_label.modulate.a = clampf(_dodge_alpha, 0.0, 1.0)
		_dodge_label.scale = Vector2.ONE * (1.0 + _dodge_pop * 0.4)
		_dodge_label.pivot_offset = _dodge_label.size * 0.5
	if _exec_label:
		_exec_alpha = move_toward(_exec_alpha, 0.0, delta * 1.6)
		_exec_pop = move_toward(_exec_pop, 0.0, delta * 5.5)
		_exec_label.modulate.a = clampf(_exec_alpha, 0.0, 1.0)
		_exec_label.scale = Vector2.ONE * (1.0 + _exec_pop * 0.45)
		_exec_label.pivot_offset = _exec_label.size * 0.5
	if stamina_bar and _sta_flash > 0.0:
		# Brighten + a hair of scale while draining so the eye catches the drop.
		_sta_flash = maxf(0.0, _sta_flash - delta * 3.0)
		stamina_bar.modulate = Color(1, 1, 1).lerp(Color(1.7, 1.9, 2.0), _sta_flash)
		stamina_bar.pivot_offset = stamina_bar.size * Vector2(0, 0.5)
		stamina_bar.scale = Vector2(1.0, 1.0 + 0.35 * _sta_flash)
	elif stamina_bar and stamina_bar.modulate != Color(1, 1, 1):
		stamina_bar.modulate = Color(1, 1, 1)
		stamina_bar.scale = Vector2.ONE
	if _ult_root and GameState.ultimate_ready_state():
		# Breathe the gauge while it's ready so the player notices the option.
		_ult_pulse = wrapf(_ult_pulse + delta * 3.0, 0.0, TAU)
		_ult_root.modulate.a = 0.7 + 0.3 * (0.5 + 0.5 * sin(_ult_pulse))
	elif _ult_root:
		_ult_root.modulate.a = 1.0
	if _headshot_label:
		# Headshots are now a tighter, rarer shot, so the callout gets to land with
		# a bigger punch and linger a little longer than before.
		_headshot_alpha = move_toward(_headshot_alpha, 0.0, delta * 0.95)
		_headshot_pop = move_toward(_headshot_pop, 0.0, delta * 3.8)
		_headshot_label.modulate.a = clampf(_headshot_alpha, 0.0, 1.0)
		_headshot_label.scale = Vector2.ONE * (1.0 + _headshot_pop * 0.9)
		_headshot_label.pivot_offset = _headshot_label.size * 0.5
	if _multikill_label:
		# The rolling window closes -> the multi-kill count resets.
		if _multikill_cd > 0.0:
			_multikill_cd = maxf(0.0, _multikill_cd - delta)
			if _multikill_cd <= 0.0:
				_multikill = 0
		_multikill_alpha = move_toward(_multikill_alpha, 0.0, delta * 0.8)
		_multikill_pop = move_toward(_multikill_pop, 0.0, delta * 3.5)
		_multikill_label.modulate.a = clampf(_multikill_alpha, 0.0, 1.0)
		_multikill_label.scale = Vector2.ONE * (1.0 + _multikill_pop * 0.55)
		_multikill_label.pivot_offset = _multikill_label.size * 0.5
	if _overlord_label:
		if _overlord_time > 0.0:
			_overlord_time = maxf(0.0, _overlord_time - delta)
			_overlord_label.modulate.a = clampf(_overlord_time / 0.8, 0.0, 1.0)
		# Drip an ambient taunt during live play (not paused / dead / cleared).
		if GameState.current_state == GameState.State.PLAYING:
			_overlord_cd -= delta
			if _overlord_cd <= 0.0:
				_overlord_cd = randf_range(30.0, 50.0)
				if _overlord_time <= 0.0:
					# Prefer a profile-aware jab from the Adaptive AI Director (it
					# references how you're actually playing); fall back to the
					# generic taunt pool when it's still calibrating.
					var line: String = AIDirector.taunt() if randf() < 0.6 else ""
					if line == "":
						line = OVERLORD_TAUNTS[randi() % OVERLORD_TAUNTS.size()]
					_overlord_say(line)
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
		var pop := 1.0 + _hit_flash * 0.5
		crosshair.scale = _crosshair_base_scale * pop
		# Headshots flash GOLD (precision read, priority); kills red; hits white.
		var hit_col := Color(1.0, 0.85, 0.25) if _hit_crit else (Color(1.0, 0.25, 0.2) if _hit_kill else Color(1.0, 1.0, 1.0))
		crosshair.modulate = Color(1, 1, 1).lerp(hit_col, _hit_flash)
		# Snap-in hit ✕: punches out from the crosshair on contact.
		if _hit_x:
			var x_col := Color(1.0, 0.82, 0.2) if _hit_crit else (Color(1.0, 0.4, 0.35) if _hit_kill else Color(1, 1, 1))
			_hit_x.modulate = Color(x_col.r, x_col.g, x_col.b, _hit_flash)
			_hit_x.scale = Vector2.ONE * (1.25 - _hit_flash * 0.35)
	if _kill_flash > 0.0:
		_kill_flash = maxf(0.0, _kill_flash - delta * 3.2)
		if _kill_edge:
			_kill_edge.modulate.a = _kill_flash * 0.45 * GraphicsSettings.flash_intensity
		if _kill_x:
			_kill_x.modulate.a = clampf(_kill_flash * 1.4, 0.0, 1.0)
			var kpop := 0.7 + (1.0 - _kill_flash) * 0.6
			_kill_x.scale = Vector2.ONE * kpop
	if field_manual_overlay and field_manual_overlay.visible and GameState.current_state != GameState.State.PAUSED:
		field_manual_overlay.visible = false # e.g. a checkpoint respawn or death while it was open
	pause_menu.visible = GameState.current_state == GameState.State.PAUSED and not (field_manual_overlay and field_manual_overlay.visible)
	_update_crosshair(delta)
	# Low-health danger vignette: red edges pulse harder the closer to death.
	if _low_vig:
		_vig_time += delta
		var danger := clampf((0.4 - _hp_ratio) / 0.4, 0.0, 1.0)
		var a := danger * (0.55 + 0.3 * sin(_vig_time * 5.0)) if danger > 0.0 else 0.0
		_low_vig.modulate.a = a * GraphicsSettings.flash_intensity

var _grapple_hint: Label = null ## Small cyan pip under the crosshair when a grapple anchor is in range.

## A subtle "you can grapple this" cue: a small cyan diamond just below the
## reticle, shown while the player's throttled anchor probe reads valid. Sits
## under CrosshairCenter so it inherits the reticle's screen position for free.
func _build_grapple_hint() -> void:
	_grapple_hint = Label.new()
	_grapple_hint.text = "◆"
	_grapple_hint.add_theme_font_size_override("font_size", 13)
	_grapple_hint.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0, 0.85))
	_grapple_hint.add_theme_constant_override("outline_size", 3)
	_grapple_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_grapple_hint.set_anchors_preset(Control.PRESET_CENTER)
	_grapple_hint.position = Vector2(-6, 20)
	_grapple_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grapple_hint.visible = false
	crosshair.add_child(_grapple_hint)

## Dynamic reticle driven by the weapon's REAL live cone (Weapon.spread_now):
## base per-gun spread opened by fire bloom and movement, tightened by ADS and
## the cold first-shot bonus — the gap on screen is the truth of where rounds
## can land, not a cosmetic approximation of it.
func _update_crosshair(delta: float) -> void:
	var target := 1.0
	if _current_weapon and is_instance_valid(_current_weapon) and _current_weapon.data:
		var shooter: Node = null
		if GameState.current_state == GameState.State.PLAYING and _player_ref and is_instance_valid(_player_ref):
			shooter = _player_ref
		var live: float = _current_weapon.spread_now(Input.is_action_pressed("aim"), shooter)
		target = clampf(live * 2.6, 0.6, 26.0)
	if GameState.current_state == GameState.State.PLAYING and _player_ref and is_instance_valid(_player_ref):
		if _grapple_hint:
			_grapple_hint.visible = bool(_player_ref.get("_grapple_valid"))
	elif _grapple_hint:
		_grapple_hint.visible = false
	_cross_spread = lerpf(_cross_spread, target, clampf(14.0 * delta, 0.0, 1.0))
	var s := _cross_spread
	# Base tick rect is the 5..12 px gap from centre; shift it out by `s`.
	_cross_top.offset_top = -(12.0 + s); _cross_top.offset_bottom = -(5.0 + s)
	_cross_bottom.offset_top = 5.0 + s; _cross_bottom.offset_bottom = 12.0 + s
	_cross_left.offset_left = -(12.0 + s); _cross_left.offset_right = -(5.0 + s)
	_cross_right.offset_left = 5.0 + s; _cross_right.offset_right = 12.0 + s
	# Colour by ammo state: per-weapon tint normally, amber when low, pulsing red empty.
	_cross_time += delta
	var col := _reticle_base
	var ratio := float(_mag) / float(maxi(1, _mag_size))
	if _mag <= 0:
		col = Color(1.0, 0.25, 0.2)
		col.a = 0.55 + 0.45 * sin(_cross_time * 9.0) # pulse to scream "reload"
	elif ratio <= 0.3:
		col = Color(1.0, 0.7, 0.25)
	crosshair.modulate = col

func _unhandled_input(event: InputEvent) -> void:
	# On the game-over screen, SPACE retries (matches the button label) — a
	# checkpoint respawn if one's been set this level, else the old full reload.
	if game_over_menu.visible:
		var k := event as InputEventKey
		if k and k.pressed and not k.echo and k.keycode == KEY_SPACE:
			get_viewport().set_input_as_handled()
			_on_death_restart_pressed()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2 \
			and GameState.from_editor:
		GameState.return_to_editor() # quick exit from a playtest
		return
	if event.is_action_pressed("pause"):
		if GameState.current_state == GameState.State.PLAYING:
			GameState.set_state(GameState.State.PAUSED)
			_enter_pause()
		elif GameState.current_state == GameState.State.PAUSED:
			if field_manual_overlay and field_manual_overlay.visible:
				close_field_manual() # ESC/pause backs out of the overlay first, stays paused
			else:
				GameState.set_state(GameState.State.PLAYING)
				_exit_pause()

## Free the mouse + sync the settings widgets when the pause menu opens.
func _enter_pause() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_volume:
		pause_volume.value = AudioBus.get_master_volume()
	_refresh_pause_graphics()

func _exit_pause() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_pause_graphics() -> void:
	if pause_graphics:
		pause_graphics.text = tr("Graphics: %s") % GraphicsSettings.quality_label()
	if pause_gfx_down:
		pause_gfx_down.disabled = GraphicsSettings.quality == GraphicsSettings.Quality.LOW
	if pause_gfx_up:
		pause_gfx_up.disabled = GraphicsSettings.quality == GraphicsSettings.Quality.ULTRA

# ---------- OVERCLOCK indicator (countdown under the crosshair) ----------

var _overclock_lbl: Label

func _build_overclock_label() -> void:
	_overclock_lbl = Label.new()
	_overclock_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_overclock_lbl.position += Vector2(-110, 70) # just under the crosshair
	_overclock_lbl.custom_minimum_size = Vector2(220, 0)
	_overclock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overclock_lbl.add_theme_font_size_override("font_size", 22)
	_overclock_lbl.add_theme_color_override("font_color", Color(0.85, 0.45, 1.0))
	_overclock_lbl.visible = false
	add_child(_overclock_lbl)

func _on_overclock_changed(left: float) -> void:
	if _overclock_lbl == null:
		return
	_overclock_lbl.visible = left > 0.0
	if left <= 0.0:
		return
	_overclock_lbl.text = "⚡ OVERCLOCK ×%d — %d" % [int(GameState.OVERCLOCK_MULT), ceili(left)]
	# Urgency blink over the final seconds.
	_overclock_lbl.modulate.a = 1.0 if left > 3.0 else (0.45 + 0.55 * absf(sin(left * TAU)))

var _overdrive_lbl: Label

func _build_overdrive_label() -> void:
	_overdrive_lbl = Label.new()
	_overdrive_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_overdrive_lbl.position += Vector2(-110, 98) # under the overclock line
	_overdrive_lbl.custom_minimum_size = Vector2(220, 0)
	_overdrive_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overdrive_lbl.add_theme_font_size_override("font_size", 22)
	_overdrive_lbl.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_overdrive_lbl.visible = false
	add_child(_overdrive_lbl)

func _on_overdrive_changed(left: float) -> void:
	if _overdrive_lbl == null:
		return
	_overdrive_lbl.visible = left > 0.0
	if left <= 0.0:
		return
	_overdrive_lbl.text = "🗲 OVERDRIVE — %d" % ceili(left)
	_overdrive_lbl.modulate.a = 1.0 if left > 3.0 else (0.45 + 0.55 * absf(sin(left * TAU)))

func set_objective(text: String) -> void:
	_objective_base = text
	_render_objective()

## Draw the objective line. When the level has a task checklist, show it with
## ✔ / ▢ ticks; otherwise fall back to the flavour objective text.
func _render_objective() -> void:
	if GameState.level_tasks.is_empty():
		objective_label.text = _objective_base
		return
	var parts: Array = []
	for t in GameState.level_tasks:
		# ✔ done · ▢ live · ◇ a later stage whose objects aren't in the world yet
		var glyph: String = "✔" if t["done"] else ("◇" if t.get("staged", false) else "▢")
		var line: String = "%s %s" % [glyph, tr(t["label"])]
		if not t["done"] and not t.get("staged", false) and t.get("goal", 0.0) > 0.0:
			line += " (%d/%d)" % [int(t["progress"]), int(t["goal"])]
		parts.append(line)
	# The optional bonus rides at the end of the checklist: ★ live, ✔ won, ✖ lost.
	var b: Dictionary = GameState.level_bonus
	if not b.is_empty():
		var st: String = b.get("state", "live")
		var bg: String = {"won": "✔", "failed": "✖"}.get(st, "★")
		parts.append("%s %s: %s" % [bg, tr("BONUS"), tr(String(b.get("label", "")))])
	objective_label.text = "   ".join(PackedStringArray(parts))

## Per-killer coaching for the death screen: the lesson that would have saved
## you, matched to what actually got you. Falls back to rotating general tips.
const DEATH_TIPS := {
	"DOG": "K-9s lunge in straight lines — strafe sideways and they sail past.",
	"SNIPER": "Snipers paint you before firing — break line of sight, then close in.",
	"MECH": "Heavies turn slowly — circle them and work the back armor.",
	"WARMECH": "Heavies turn slowly — circle them and work the back armor.",
	"DRONE": "Drones are paper — flick up and burst them before they mass.",
	"SPIDER": "Spiders swarm — fall back to a choke point so they bunch up.",
	"BRUTE": "Brutes telegraph the charge — dash THROUGH it, not away from it.",
	"HUNTER": "Hunters flank in pairs — keep a wall on one side and check the map.",
	"FLOOD": "Deep water drowns fast — cross at the bridges, not the banks.",
	"MOLTEN": "The glow means death — lava kills faster than any robot. Take the long way.",
	"GUNNER": "Gunners spin up before the stream — use the wind-up to reposition.",
	"SEEKER": "Seekers detonate on contact — shoot them at range, never backpedal.",
	"RAPTOR": "Raptors pounce off walls — fight them in the open, not in alleys.",
}
const DEATH_TIPS_GENERIC := [
	"An empty trigger reloads by itself — but a weapon swap is even faster.",
	"Kills restore health — when you're hurt, push harder, not further away.",
	"The reticle shows your true spread: stand still and aim for laser accuracy.",
	"Sprint and dash break most target tracking — keep moving between shots.",
	"Watch the minimap reds: you hear a flank before you see it.",
	"Finishing an objective often trips an alarm — reload BEFORE you interact.",
]
var _taunt_label: Label = null
var _recap_label: Label = null
var _tip_label: Label = null

## Fill the game-over panel with the story of this death: who got you, how far
## you made it, and one tip that addresses exactly that. Dying becomes a lesson
## instead of a dead end.
func _fill_death_recap() -> void:
	var vbox := game_over_menu.get_node_or_null("VBox")
	if vbox == null:
		return
	if _recap_label == null:
		# The overlord's parting jab, right under TERMINATED — the machine mocking
		# your death in its own resource-exhaustion jargon (tokens, rate limits).
		_taunt_label = Label.new()
		_taunt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_taunt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_taunt_label.add_theme_font_size_override("font_size", 19)
		_taunt_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0)) # overlord blue
		_taunt_label.add_theme_constant_override("outline_size", 6)
		_taunt_label.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.05))
		vbox.add_child(_taunt_label)
		vbox.move_child(_taunt_label, 1) # right under TERMINATED
		_recap_label = Label.new()
		_recap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_recap_label.add_theme_font_size_override("font_size", 13)
		_recap_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5))
		vbox.add_child(_recap_label)
		vbox.move_child(_recap_label, 2) # under the taunt
		_tip_label = Label.new()
		_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_label.add_theme_font_size_override("font_size", 12)
		_tip_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
		vbox.add_child(_tip_label)
		vbox.move_child(_tip_label, 3)
	_taunt_label.text = "“%s”" % DEATH_TAUNTS[randi() % DEATH_TAUNTS.size()]
	var killer := GameState.last_killer
	var done := 0
	for t in GameState.level_tasks:
		if t["done"]:
			done += 1
	var head := ("Taken down by %s" % killer) if killer != "" else "K.I.A."
	_recap_label.text = "%s  ·  %d kills  ·  objectives %d/%d" % [
		head, GameState.kills, done, GameState.level_tasks.size()]
	var tip: String = ""
	for k in DEATH_TIPS:
		if killer.contains(k):
			tip = DEATH_TIPS[k]
			break
	if tip == "":
		tip = DEATH_TIPS_GENERIC[randi() % DEATH_TIPS_GENERIC.size()]
	_tip_label.text = "TIP: %s" % tip
	# The button (and SPACE) read differently depending on whether there's a
	# mid-level checkpoint to come back to, so the player knows what they're
	# about to get before they press it.
	if game_over_restart_btn:
		game_over_restart_btn.text = "RESPAWN (SPACE)" if GameState.has_checkpoint() else "TRY AGAIN (SPACE)"

func _show_toast(text: String) -> void:
	toast.text = text
	_toast_time = 2.4 # ~1.4s held + ~1s fade

var _hp_fill: StyleBoxFlat

## Health bar reads GREEN when healthy and bleeds toward amber then red as it
## drops — instant "how am I doing" glance, no more default grey.
func _style_health_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.08, 0.85)
	bg.set_border_width_all(2)
	bg.border_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(3)
	health_bar.add_theme_stylebox_override("background", bg)
	_hp_fill = StyleBoxFlat.new()
	_hp_fill.bg_color = Color(0.25, 0.9, 0.35)
	_hp_fill.set_corner_radius_all(3)
	health_bar.add_theme_stylebox_override("fill", _hp_fill)
	# Brighter, bolder readout beside the bar.
	health_label.add_theme_font_size_override("font_size", 20)
	health_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	health_label.add_theme_constant_override("outline_size", 6)
	_style_caption(_hp_caption, Color(0.4, 1.0, 0.55))

## Small bold caption stamped in front of a bar ("HP" / "STA") so the two readouts
## are labelled at a glance.
func _style_caption(cap: Label, col: Color) -> void:
	if cap == null:
		return
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", col)
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cap.add_theme_constant_override("outline_size", 5)

func _on_health_changed(cur: float, max_: float) -> void:
	health_bar.max_value = max_
	health_bar.value = cur
	health_label.text = "%d / %d" % [int(cur), int(max_)]
	if _hp_fill:
		var r := clampf(cur / maxf(max_, 1.0), 0.0, 1.0)
		# Green (full) -> amber (~40%) -> red (empty).
		var col: Color
		if r > 0.4:
			col = Color(0.95, 0.75, 0.2).lerp(Color(0.25, 0.9, 0.35), (r - 0.4) / 0.6)
		else:
			col = Color(1.0, 0.2, 0.16).lerp(Color(0.95, 0.75, 0.2), r / 0.4)
		_hp_fill.bg_color = col
	_hp_ratio = cur / maxf(1.0, max_)

var _stam_fill: StyleBoxFlat
var _sta_prev: float = -1.0  ## last stamina value, to detect draining
var _sta_flash: float = 0.0  ## brief brighten each time stamina drops, so drain is visible

## Stamina bar sits alongside health: cyan when you have wind, and it flips to a
## hard red bar while EXHAUSTED so the "can't run / can't grapple" lockout is
## obvious at a glance rather than reading as a mystery slowdown.
func _style_stamina_bar() -> void:
	if not stamina_bar:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.07, 0.08, 0.85)
	bg.set_border_width_all(2)
	bg.border_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(3)
	stamina_bar.add_theme_stylebox_override("background", bg)
	_stam_fill = StyleBoxFlat.new()
	_stam_fill.bg_color = Color(0.3, 0.8, 1.0)
	_stam_fill.set_corner_radius_all(3)
	stamina_bar.add_theme_stylebox_override("fill", _stam_fill)
	_style_caption(_sta_caption, Color(0.35, 0.85, 1.0))

func _on_stamina_changed(cur: float, max_: float, exhausted: bool) -> void:
	if not stamina_bar:
		return
	stamina_bar.max_value = max_
	stamina_bar.value = cur
	# Draining? Kick a flash so the drop is actually noticeable (the whole point of
	# a stamina bar is seeing it move). Only on a real decrease, not on regen.
	if _sta_prev >= 0.0 and cur < _sta_prev - 0.05:
		_sta_flash = 1.0
	_sta_prev = cur
	if _stam_fill:
		var r := clampf(cur / maxf(max_, 1.0), 0.0, 1.0)
		# Exhausted -> red lockout; low -> amber warning; else cyan by fraction.
		if exhausted:
			_stam_fill.bg_color = Color(1.0, 0.28, 0.24)
		elif r < 0.35:
			_stam_fill.bg_color = Color(1.0, 0.62, 0.2) # amber: running low
		else:
			_stam_fill.bg_color = Color(0.2, 0.55, 0.75).lerp(Color(0.35, 0.85, 1.0), r)

## A compact row of chips just above the health bar showing which permanent armory
## upgrades this run has and at what rank — a colour-coded glyph (reusing the
## armory's icons) with rank pips. Only tracks with at least one rank show, so a
## fresh run has no clutter and the loadout fills in as you invest.
func _build_upgrade_chips() -> void:
	var layout := $Margin/Layout
	var row: HBoxContainer = layout.get_node_or_null("UpgradeRow")
	if row == null:
		row = HBoxContainer.new()
		row.name = "UpgradeRow"
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(row)
		layout.move_child(row, $Margin/Layout/BottomLeft.get_index()) # sit right above the HP bar
		# Rebuild live when ranks change (armory buy / "imba" cheat).
		GameState.upgrades_changed.connect(_build_upgrade_chips)
	for c in row.get_children():
		c.queue_free()
	for k in Armory.KEYS:
		var lvl := GameState.upgrade_level(k)
		if lvl <= 0:
			continue
		var meta: Dictionary = Armory.META[k]
		row.add_child(_make_upgrade_chip(meta["icon"], meta["color"], lvl))

func _make_upgrade_chip(glyph: String, color: Color, lvl: int) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.7)
	sb.set_border_width_all(1)
	sb.border_color = Color(color.r, color.g, color.b, 0.8)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hb)
	var g := Label.new()
	g.text = glyph
	g.add_theme_color_override("font_color", color)
	g.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	g.add_theme_constant_override("outline_size", 4)
	g.add_theme_font_size_override("font_size", 16)
	hb.add_child(g)
	# Rank pips (filled = bought), one per possible rank.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 2)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameState.UPGRADE_MAX:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(3, 10)
		pip.color = color if i < lvl else Color(0.2, 0.22, 0.26, 0.9)
		pips.add_child(pip)
	hb.add_child(pips)
	return panel

# ---------- ammo block: big numerals + segmented mag bar + grenade pips ----------

const AMMO_SEGS := 12
var _ammo_big: Label
var _ammo_small: Label
var _segs: Array[ColorRect] = []
var _pips: Array[ColorRect] = []
var _glabel: Label

## Replaces the plain "14 / 84" text with a glanceable block: the weapon name
## small on top, the magazine count BIG (tinted by the weapon, amber when low,
## pulsing red when dry), the reserve beside it, a segmented bar that empties
## with the mag, and diamond pips for grenades.
func _build_ammo_block() -> void:
	ammo_label.visible = false
	grenade_label.visible = false
	var br := ammo_label.get_parent()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	br.add_child(box)
	# The weapon name rides on top of the block, small and dim.
	br.remove_child(weapon_label)
	box.add_child(weapon_label)
	weapon_label.add_theme_font_size_override("font_size", 14)
	weapon_label.modulate = Color(1, 1, 1, 0.7)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var nums := HBoxContainer.new()
	nums.alignment = BoxContainer.ALIGNMENT_END
	nums.add_theme_constant_override("separation", 6)
	box.add_child(nums)
	_ammo_big = Label.new()
	# Big, heavy, outlined magazine count — the number you check mid-fight.
	_ammo_big.add_theme_font_size_override("font_size", 52)
	_ammo_big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ammo_big.add_theme_constant_override("outline_size", 10)
	nums.add_child(_ammo_big)
	_ammo_small = Label.new()
	_ammo_small.add_theme_font_size_override("font_size", 22)
	_ammo_small.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ammo_small.add_theme_constant_override("outline_size", 5)
	_ammo_small.modulate = Color(1, 1, 1, 0.7)
	_ammo_small.size_flags_vertical = Control.SIZE_SHRINK_END
	nums.add_child(_ammo_small)
	var segs := HBoxContainer.new()
	segs.alignment = BoxContainer.ALIGNMENT_END
	segs.add_theme_constant_override("separation", 2)
	box.add_child(segs)
	for i in AMMO_SEGS:
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(13, 7)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segs.add_child(seg)
		_segs.append(seg)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_END
	pips.add_theme_constant_override("separation", 5)
	box.add_child(pips)
	_glabel = Label.new()
	_glabel.text = "G "
	_glabel.add_theme_font_size_override("font_size", 12)
	_glabel.modulate = Color(1, 1, 1, 0.5)
	pips.add_child(_glabel)
	for i in 3:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(9, 9)
		pip.pivot_offset = Vector2(4.5, 4.5)
		pip.rotation_degrees = 45.0 # diamond
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
		_pips.append(pip)
	_refresh_ammo_visual(0)

func _refresh_ammo_visual(reserve: int) -> void:
	if _ammo_big == null:
		return
	var ratio := float(_mag) / float(maxi(1, _mag_size))
	var col := _reticle_base
	if _mag <= 0:
		col = Color(1.0, 0.25, 0.2)
	elif ratio <= 0.3:
		col = Color(1.0, 0.7, 0.25)
	_ammo_big.text = str(_mag)
	_ammo_big.modulate = col
	_ammo_small.text = "/ %d" % reserve
	var lit := ceili(ratio * AMMO_SEGS)
	for i in AMMO_SEGS:
		_segs[i].color = col if i < lit else Color(1, 1, 1, 0.13)

func _on_ammo_changed(mag: int, reserve: int) -> void:
	# A fresh magazine (count jumped up) punches the big number — reload juice.
	if mag > _prev_mag:
		_juice_pop(_ammo_big, 1.4)
	_prev_mag = mag
	_mag = mag
	_refresh_ammo_visual(reserve)

var _countermeasure_warned: bool = false

func _on_weapon_changed(w: Weapon) -> void:
	_current_weapon = w
	if w and w.data:
		weapon_label.text = w.data.display_name
		if w.mod_id != "" and GameState.MOD_DEFS.has(w.mod_id):
			weapon_label.text += "  ·  " + String(GameState.MOD_DEFS[w.mod_id]["label"]) # fitted Armory mod
		# Once per level: tell the player the gun they just drew is patched against.
		if not _countermeasure_warned and AIDirector.countermeasure_weapon() == w.data.display_name:
			_countermeasure_warned = true
			_show_toast(tr("⟁ COUNTERMEASURE · %s deals %d%% damage. Rotate your arsenal.") % [w.data.display_name, int(round(AIDirector.COUNTERMEASURE_MULT * 100.0))])
		_mag_size = maxi(1, w.eff_mag_size()) # upgrades grow the bar's full scale
		_mag = w.mag
		_reticle_base = _reticle_hue(w.data.display_name)
		_refresh_ammo_visual(w.reserve)
	_update_carousel_highlight()
	_flash_carousel()

## ---------- 4.7 juicy-HUD helpers (Control offset transforms) ----------
## offset_transform_* visually translates/scales/rotates a Control WITHOUT the
## container relaying it or shoving its siblings — so HUD elements can pop,
## shake and slide even while parked inside VBox/HBox layouts.

## Overshoot scale-pop around the element's own centre.
func _juice_pop(c: Control, s: float = 1.35) -> void:
	if c == null:
		return
	c.offset_transform_enabled = true
	c.offset_transform_visual_only = true
	c.offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	c.offset_transform_scale = Vector2(s, s)
	var t := c.create_tween()
	t.tween_property(c, "offset_transform_scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A short positional shake that settles back to rest.
func _juice_shake(c: Control, amt: float = 7.0) -> void:
	if c == null:
		return
	c.offset_transform_enabled = true
	c.offset_transform_visual_only = true
	var t := c.create_tween()
	for i in 4:
		t.tween_property(c, "offset_transform_position",
			Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.04)
	t.tween_property(c, "offset_transform_position", Vector2.ZERO, 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Distinct light tint per weapon so each reticle reads differently.
func _reticle_hue(name: String) -> Color:
	var h := float(abs(hash(name)) % 360) / 360.0
	return Color.from_hsv(h, 0.32, 1.0)

func _on_weapon_added(w: Weapon) -> void:
	if w and w.data:
		_show_toast(tr("WEAPON ACQUIRED — ") + w.data.display_name)
	_refresh_carousel() # a new slot joined the rack — rebuild the strip
	_flash_carousel()

# ---------- weapon carousel: a compact bottom-centre hotbar ----------
# A horizontal strip of every weapon in the rack, weakest→strongest (the same
# order as keys 1-9). Each cell shows its slot number + the weapon's short code;
# the armed one lights up in the weapon's energy colour. The strip rides bright
# for a beat on every switch/pickup, then settles to a dim glance-able rest.

var _wm: WeaponManager
var _carousel: HBoxContainer
var _carousel_cells: Array[Dictionary] = []
var _carousel_fade: Tween

func _build_weapon_carousel() -> void:
	var bar := CenterContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -156
	bar.offset_bottom = -104
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	_carousel = HBoxContainer.new()
	_carousel.add_theme_constant_override("separation", 6)
	_carousel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_carousel)
	_refresh_carousel()

## Rebuild every cell from the (already power-sorted) weapon rack. Cheap and only
## called when the rack itself changes (build / pickup), not on every switch.
func _refresh_carousel() -> void:
	if _carousel == null or _wm == null:
		return
	for c in _carousel.get_children():
		c.queue_free()
	_carousel_cells.clear()
	for i in _wm.weapons.size():
		var w: Weapon = _wm.weapons[i]
		var col: Color = w.data.tracer_color if w.data else Color(0.7, 0.8, 1.0)
		var panel := PanelContainer.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		panel.add_theme_stylebox_override("panel", style)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -2)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(vb)
		var num := Label.new()
		num.text = str(i + 1) if i < 9 else "•" # only 1-9 are bound to number keys
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.add_theme_font_size_override("font_size", 11)
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		num.add_theme_constant_override("outline_size", 4)
		vb.add_child(num)
		var code := Label.new()
		code.text = w.data.display_name.split(" ")[0] if w.data else "?"
		code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		code.custom_minimum_size = Vector2(48, 0)
		code.add_theme_font_size_override("font_size", 14)
		code.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		code.add_theme_constant_override("outline_size", 4)
		vb.add_child(code)
		_carousel.add_child(panel)
		panel.pivot_offset = panel.size * 0.5
		_carousel_cells.append({"panel": panel, "num": num, "code": code, "style": style, "color": col})
	_update_carousel_highlight()

## Re-tint cells for the current armed slot. Called on every switch (no rebuild).
func _update_carousel_highlight() -> void:
	if _wm == null:
		return
	var cur := _wm.current_index
	for i in _carousel_cells.size():
		var cell := _carousel_cells[i]
		var style: StyleBoxFlat = cell["style"]
		var col: Color = cell["color"]
		var num: Label = cell["num"]
		var code: Label = cell["code"]
		style.set_corner_radius_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 3
		style.content_margin_bottom = 3
		if i == cur:
			style.bg_color = Color(col.r, col.g, col.b, 0.32)
			style.set_border_width_all(2)
			style.border_color = Color(col.r, col.g, col.b, 0.95)
			num.modulate = Color(1, 1, 1, 1)
			code.add_theme_color_override("font_color", col.lightened(0.45))
			code.modulate = Color(1, 1, 1, 1)
		else:
			style.bg_color = Color(0.05, 0.06, 0.09, 0.5)
			style.set_border_width_all(1)
			style.border_color = Color(0.45, 0.5, 0.6, 0.4)
			num.modulate = Color(1, 1, 1, 0.45)
			code.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
			code.modulate = Color(1, 1, 1, 0.6)
	if cur >= 0 and cur < _carousel_cells.size():
		_juice_pop(_carousel_cells[cur]["panel"], 1.18)

## Pop the whole strip to full brightness, then ease it back to a dim resting
## glow so it stays glance-able without dominating the screen.
func _flash_carousel() -> void:
	if _carousel == null:
		return
	if _carousel_fade and _carousel_fade.is_valid():
		_carousel_fade.kill()
	_carousel.modulate.a = 1.0
	_carousel_fade = _carousel.create_tween()
	_carousel_fade.tween_interval(2.2)
	_carousel_fade.tween_property(_carousel, "modulate:a", 0.5, 0.6)

func _on_boss_spawned(boss: Node) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var bhp = boss.get_node_or_null("Damageable")
	if bhp == null:
		return
	var nm = boss.get("boss_name")
	boss_name_label.text = str(nm) if nm != null else "BOSS"
	boss_health_bar.max_value = bhp.max_health
	boss_health_bar.value = bhp.current_health
	boss_bar.visible = true
	bhp.health_changed.connect(_on_boss_health)
	bhp.died.connect(_on_boss_died)
	# Let the overlord gloat a beat after the warning toast lands.
	var t := get_tree().create_timer(1.3)
	t.timeout.connect(func(): _overlord_say(OVERLORD_BOSS[randi() % OVERLORD_BOSS.size()]))
	_show_toast(tr("⚠ WARNING — ") + boss_name_label.text)

func _on_boss_health(cur: float, max_: float) -> void:
	boss_health_bar.max_value = max_
	boss_health_bar.value = cur

func _on_boss_died(_src: Node) -> void:
	boss_bar.visible = false
	_show_toast(boss_name_label.text + tr(" DESTROYED"))

func _on_grenades_changed(count: int) -> void:
	# Reflect the armed grenade kind: the label shows its name + the pips take its
	# colour (gold frag vs violet vortex), so a glance reads type AND remaining.
	var kind := {"name": "FRAG", "color": Color(1.0, 0.72, 0.2)}
	if _player_ref and "grenade_kinds" in _player_ref:
		kind = _player_ref.grenade_kinds[_player_ref.grenade_type]
	var lit: Color = kind["color"]
	if _glabel:
		_glabel.text = "%s " % str(kind["name"]).left(4)
		_glabel.modulate = Color(lit.r, lit.g, lit.b, 0.65)
	grenade_label.text = tr("Grenades (G): %d") % count # hidden node; kept in sync anyway
	for i in _pips.size():
		_pips[i].color = lit if i < count else Color(1, 1, 1, 0.14)

func _on_player_damaged(_amount: float, src: Node) -> void:
	_damage_alpha = 0.55
	# Rattle the health readout so a hit is felt on the HUD, not just the screen.
	_juice_shake(health_bar, 6.0)
	_juice_shake(health_label, 6.0)
	# Point an arc toward the attacker (skip self-damage — a grenade at your own
	# feet has no "direction" worth showing).
	if src is Node3D and src != _player_ref and _dmg_indicator:
		_dmg_indicator.flash((src as Node3D).global_position)
	# Badly hurt? The overlord can't resist kicking you while you're down.
	if _player_ref and _player_ref.hp and _player_ref.hp.max_health > 0.0:
		var r: float = _player_ref.hp.current_health / _player_ref.hp.max_health
		if r <= 0.3 and _overlord_time <= 0.0 and randf() < 0.35:
			_overlord_say(OVERLORD_LOWHP[randi() % OVERLORD_LOWHP.size()])

func _on_player_dealt_damage(amount: float, world_pos: Vector3, killed: bool, crit: bool = false) -> void:
	_hit_flash = 1.0
	_hit_kill = killed
	_hit_crit = crit
	if killed:
		_kill_flash = 1.0
	if crit and GraphicsSettings.combat_callouts_enabled:
		# Refresh, don't stack/queue — rapid headshots just re-pop the same label.
		_headshot_alpha = 1.0
		_headshot_pop = 1.4
	# Crisp UI tick on hit; a heftier thock on the killing blow. Dedicated
	# shot-confirm streams (the old repurposed radio-blip/clang read as UI
	# noise rather than "I connected"), with a pitch wobble so full-auto
	# confirmation reads as texture, not a metronome.
	if killed:
		AudioBus.play_synth_ui("kill_thock", -5.0, randf_range(0.95, 1.05))
		Haptics.pulse(0.0, 0.45, 0.1) # kill confirm lands in the hands
		# Point-blank kill: robot oil hits the lens. Crits splash a bit harder.
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if _splatter and pl and pl.global_position.distance_to(world_pos) < 4.5:
			_splatter.splash(1.25 if crit else 1.0)
	else:
		AudioBus.play_synth_ui("hit_tick", -12.0, randf_range(0.9, 1.1))
	# Damage numbers are spawned world-anchored by Damageable (one system, not two).

func _on_enemy_killed(score: int, label: String) -> void:
	# Rapid multi-kill: count kills inside a short rolling window and punch out an
	# AI-themed callout (DOUBLE TAP, BATCH DELETE, ...) — distinct from the
	# cumulative streak tiers.
	_multikill += 1
	_multikill_cd = MULTIKILL_WINDOW
	if _multikill >= 2 and _multikill_label and GraphicsSettings.combat_callouts_enabled:
		var w: String = MULTIKILL_WORDS[mini(_multikill, MULTIKILL_WORDS.size() - 1)]
		_multikill_label.text = "%s ×%d" % [w, _multikill]
		_multikill_alpha = 1.0
		_multikill_pop = 1.0
		AudioBus.play_synth_ui("combo_up", -2.0, 1.1 + 0.08 * float(_multikill))
		# The overlord notices a real spree — it can't help but react (once, at the
		# 4-kill mark, and only if it isn't already mid-taunt).
		if _multikill == 4 and _overlord_time <= 0.0:
			_overlord_say(OVERLORD_RATTLED[randi() % OVERLORD_RATTLED.size()])
	if _kill_feed == null:
		return
	var lbl := Label.new()
	lbl.text = "%s  +%d" % [label, score]
	lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_kill_feed.add_child(lbl)
	while _kill_feed.get_child_count() > 5:
		_kill_feed.get_child(0).free()
	# Punch the new entry in: slide from the right + overshoot scale, visual-only
	# so the rest of the feed doesn't jitter as it lands (4.7 offset transform).
	lbl.offset_transform_enabled = true
	lbl.offset_transform_visual_only = true
	lbl.offset_transform_pivot_ratio = Vector2(1.0, 0.5)
	lbl.offset_transform_position = Vector2(70, 0)
	lbl.offset_transform_scale = Vector2(0.6, 0.6)
	var pin := create_tween().set_parallel(true)
	pin.tween_property(lbl, "offset_transform_position", Vector2.ZERO, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pin.tween_property(lbl, "offset_transform_scale", Vector2.ONE, 0.34) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)

func _on_continue_pressed() -> void:
	GameState.advance_level()

func _on_resume_pressed() -> void:
	close_field_manual() # in case Resume is reached with the overlay still open
	GameState.set_state(GameState.State.PLAYING)
	_exit_pause()

func _on_quit_pressed() -> void:
	GameState.set_state(GameState.State.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_pause_graphics_down_pressed() -> void:
	GraphicsSettings.step_quality(-1)
	_refresh_pause_graphics()
	if GraphicsSettings.restart_recommended(): # #156: the drop only fully pays off after a restart
		_show_toast(tr("Restart the game for the full speed-up (progress is saved at each level start)"))

func _on_pause_graphics_up_pressed() -> void:
	GraphicsSettings.step_quality(1)
	_refresh_pause_graphics()

func _on_pause_volume_changed(value: float) -> void:
	AudioBus.set_master_volume(value)

func _on_restart_pressed() -> void:
	GameState.load_level(GameState.current_level_path if GameState.current_level_path != "" else "res://scenes/levels/level_01.tscn")

## The GAME OVER screen's "TRY AGAIN (SPACE)" — a checkpoint respawn in place if
## a mid-level checkpoint has been set (see GameState's checkpoint section: a
## finished task or a boss reveal), otherwise the same full level reload as
## before. The pause menu's "Restart" stays wired to _on_restart_pressed() above
## unconditionally — that's the deliberate full-restart escape hatch, so
## bailing on a checkpoint you don't like is always one menu away.
func _on_death_restart_pressed() -> void:
	if GameState.has_checkpoint():
		game_over_menu.visible = false # no scene reload this time — the HUD stays up
		GameState.respawn_at_checkpoint()
	else:
		_on_restart_pressed()
