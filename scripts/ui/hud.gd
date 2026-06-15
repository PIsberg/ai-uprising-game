extends Control

@onready var health_bar: ProgressBar = $Margin/Layout/BottomLeft/HealthRow/HealthBar
@onready var health_label: Label = $Margin/Layout/BottomLeft/HealthRow/HealthLabel
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
var _player_ref: Node3D
var _mag: int = 1
var _mag_size: int = 1
var _reticle_base: Color = Color(1, 1, 1)
var _cross_time: float = 0.0
@onready var damage_overlay: ColorRect = $DamageOverlay
@onready var pause_menu: Control = $PauseMenu
@onready var pause_graphics: Button = $PauseMenu/VBox/PauseGraphics
@onready var pause_volume: HSlider = $PauseMenu/VBox/PauseVolumeRow/PauseVolume
@onready var game_over_menu: Control = $GameOverMenu
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
var _crosshair_base_scale: Vector2 = Vector2.ONE
var _objective_base: String = "" ## Flavour objective text, shown when no task checklist is active.
var _combo_label: Label = null
var _combo_alpha: float = 0.0
var _combo_pop: float = 0.0
var _last_grade: String = ""
var _last_stats: Dictionary = {}
var _auto_advance_armed: bool = false
var _combat_poll: float = 0.0
var _kill_flash: float = 0.0 ## Brief surge on a confirmed kill — drives the ✕ marker + edge flash.
var _kill_edge: TextureRect = null
var _kill_x: Control = null
var _hit_x: Control = null
# Kill-streak milestone callouts (arcade-style words on crossing a tier).
var _streak_label: Label = null
var _streak_alpha: float = 0.0
var _streak_pop: float = 0.0
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
		var wm: WeaponManager = player.get_node_or_null("Head/Camera3D/WeaponHolder")
		if wm:
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
	GameState.player_died.connect(func(): game_over_menu.visible = true)
	GameState.level_completed.connect(_on_level_completed)
	# Hit-marker: pivot the crosshair around its centre so it can pop on a hit.
	crosshair.pivot_offset = crosshair.size * 0.5
	_crosshair_base_scale = crosshair.scale
	GameState.player_dealt_damage.connect(_on_player_dealt_damage)
	GameState.enemy_killed.connect(_on_enemy_killed)
	GameState.objective_blocked.connect(_show_toast)
	GameState.objective_unlocked.connect(_on_objective_unlocked)
	GameState.tasks_changed.connect(_render_objective)
	GameState.task_completed.connect(_on_task_completed)
	GameState.combo_changed.connect(_on_combo_changed)
	GameState.level_graded.connect(_on_level_graded)
	_build_kill_confirm()
	_build_combo_label()
	_build_streak_label()
	_build_overlord_label()
	_build_pause_audio()
	_render_objective()

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
	_build_language_row(vbox)
	if quit:
		vbox.move_child(quit, vbox.get_child_count() - 1)

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

func _audio_slider_row(parent: Node, label: String, val: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(110, 0)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
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
	_overlord_label.add_theme_font_size_override("font_size", 22)
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
	var fighting := false
	if GameState.current_state == GameState.State.PLAYING:
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is EnemyBase and (e.state == EnemyBase.State.CHASE or e.state == EnemyBase.State.ATTACK):
				if e.hp != null and e.hp.is_alive():
					fighting = true
					break
	AudioBus.set_combat(fighting)

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
	if GameState.has_next_level():
		win_title.text = tr("SECTOR CLEARED")
		win_continue.text = "Continue  ▸"
	else:
		win_title.text = tr("AI UPRISING ENDED")
		win_continue.text = "Finish"
	if _last_grade != "":
		var acc := int(round(float(_last_stats.get("accuracy", 0.0)) * 100.0))
		var t := int(round(float(_last_stats.get("time", 0.0))))
		win_title.text += "\n\n" + (tr("RANK  %s") % _last_grade) \
			+ "\n" + (tr("Accuracy %d%%") % acc) \
			+ "   ·   " + (tr("Best Combo ×%d") % int(_last_stats.get("max_combo", 0))) \
			+ "   ·   %02d:%02d" % [t / 60, t % 60]
	# Auto-advance to the next sector after a short beat (the grade is on screen);
	# the Continue button still lets the player skip the wait. The finale waits
	# for a manual Finish so the ending screen isn't rushed.
	if GameState.has_next_level() and not _auto_advance_armed:
		_auto_advance_armed = true
		var tmr := get_tree().create_timer(3.5, true)
		tmr.timeout.connect(_auto_advance)

func _auto_advance() -> void:
	_auto_advance_armed = false
	if win_menu.visible and GameState.current_state == GameState.State.LEVEL_COMPLETE:
		_on_continue_pressed()

func _process(delta: float) -> void:
	_update_combat_music(delta)
	if _damage_alpha > 0.0:
		_damage_alpha = maxf(0.0, _damage_alpha - delta * 1.5)
		damage_overlay.color.a = _damage_alpha
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
					_overlord_say(OVERLORD_TAUNTS[randi() % OVERLORD_TAUNTS.size()])
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
		var pop := 1.0 + _hit_flash * 0.5
		crosshair.scale = _crosshair_base_scale * pop
		# Kills flash red; normal hits flash bright white, easing back to neutral.
		var hit_col := Color(1.0, 0.25, 0.2) if _hit_kill else Color(1.0, 1.0, 1.0)
		crosshair.modulate = Color(1, 1, 1).lerp(hit_col, _hit_flash)
		# Snap-in hit ✕: punches out from the crosshair on contact.
		if _hit_x:
			_hit_x.modulate = Color(1.0, 0.4, 0.35, _hit_flash) if _hit_kill else Color(1, 1, 1, _hit_flash)
			_hit_x.scale = Vector2.ONE * (1.25 - _hit_flash * 0.35)
	if _kill_flash > 0.0:
		_kill_flash = maxf(0.0, _kill_flash - delta * 3.2)
		if _kill_edge:
			_kill_edge.modulate.a = _kill_flash * 0.45
		if _kill_x:
			_kill_x.modulate.a = clampf(_kill_flash * 1.4, 0.0, 1.0)
			var kpop := 0.7 + (1.0 - _kill_flash) * 0.6
			_kill_x.scale = Vector2.ONE * kpop
	pause_menu.visible = GameState.current_state == GameState.State.PAUSED
	_update_crosshair(delta)
	# Low-health danger vignette: red edges pulse harder the closer to death.
	if _low_vig:
		_vig_time += delta
		var danger := clampf((0.4 - _hp_ratio) / 0.4, 0.0, 1.0)
		var a := danger * (0.55 + 0.3 * sin(_vig_time * 5.0)) if danger > 0.0 else 0.0
		_low_vig.modulate.a = a

## Dynamic reticle: widens while moving/firing, tightens when aiming/still.
func _update_crosshair(delta: float) -> void:
	var target := 1.0 # extra px the ticks push outward
	if GameState.current_state == GameState.State.PLAYING and _player_ref and is_instance_valid(_player_ref):
		var speed := Vector2(_player_ref.velocity.x, _player_ref.velocity.z).length()
		target = 1.0 + clampf(speed / 9.0, 0.0, 1.0) * 9.0
		if Input.is_action_pressed("fire"):
			target += 6.0
		if Input.is_action_pressed("aim"):
			target *= 0.25
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
	if event.is_action_pressed("pause"):
		if GameState.current_state == GameState.State.PLAYING:
			GameState.set_state(GameState.State.PAUSED)
			_enter_pause()
		elif GameState.current_state == GameState.State.PAUSED:
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
		var line: String = "%s %s" % ["✔" if t["done"] else "▢", tr(t["label"])]
		if not t["done"] and t.get("goal", 0.0) > 0.0:
			line += " (%d/%d)" % [int(t["progress"]), int(t["goal"])]
		parts.append(line)
	objective_label.text = "   ".join(PackedStringArray(parts))

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

# ---------- ammo block: big numerals + segmented mag bar + grenade pips ----------

const AMMO_SEGS := 12
var _ammo_big: Label
var _ammo_small: Label
var _segs: Array[ColorRect] = []
var _pips: Array[ColorRect] = []

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
	var glabel := Label.new()
	glabel.text = "G "
	glabel.add_theme_font_size_override("font_size", 12)
	glabel.modulate = Color(1, 1, 1, 0.5)
	pips.add_child(glabel)
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
	_mag = mag
	_refresh_ammo_visual(reserve)

func _on_weapon_changed(w: Weapon) -> void:
	if w and w.data:
		weapon_label.text = w.data.display_name
		_mag_size = maxi(1, w.eff_mag_size()) # upgrades grow the bar's full scale
		_mag = w.mag
		_reticle_base = _reticle_hue(w.data.display_name)
		_refresh_ammo_visual(w.reserve)

## Distinct light tint per weapon so each reticle reads differently.
func _reticle_hue(name: String) -> Color:
	var h := float(abs(hash(name)) % 360) / 360.0
	return Color.from_hsv(h, 0.32, 1.0)

func _on_weapon_added(w: Weapon) -> void:
	if w and w.data:
		_show_toast(tr("WEAPON ACQUIRED — ") + w.data.display_name)

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
	grenade_label.text = tr("Grenades (G): %d") % count # hidden node; kept in sync anyway
	for i in _pips.size():
		_pips[i].color = Color(1.0, 0.72, 0.2) if i < count else Color(1, 1, 1, 0.14)

func _on_player_damaged(_amount: float, src: Node) -> void:
	_damage_alpha = 0.55
	# Point an edge wedge toward the attacker; it tracks the world position as the
	# player turns (handled inside the DamageIndicator).
	if src is Node3D and _dmg_indicator:
		_dmg_indicator.flash((src as Node3D).global_position)
	# Badly hurt? The overlord can't resist kicking you while you're down.
	if _player_ref and _player_ref.hp and _player_ref.hp.max_health > 0.0:
		var r: float = _player_ref.hp.current_health / _player_ref.hp.max_health
		if r <= 0.3 and _overlord_time <= 0.0 and randf() < 0.35:
			_overlord_say(OVERLORD_LOWHP[randi() % OVERLORD_LOWHP.size()])

func _on_player_dealt_damage(amount: float, world_pos: Vector3, killed: bool) -> void:
	_hit_flash = 1.0
	_hit_kill = killed
	if killed:
		_kill_flash = 1.0
	# Crisp UI tick on hit; a heftier metallic clang on a kill.
	AudioBus.play_synth_ui("impact_metal" if killed else "broadcast_blip", -7.0, 1.3 if killed else 1.8)
	_spawn_damage_number(amount, world_pos, killed)

## A floating damage number that pops at the hit point and drifts up as it
## fades — the running tally of a firefight, so big hits read as big.
func _spawn_damage_number(amount: float, world_pos: Vector3, killed: bool) -> void:
	if amount < 1.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world_pos):
		return
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = str(int(round(amount)))
	# Bigger + hotter for heavier hits; gold on the killing blow.
	var heavy := clampf(amount / 80.0, 0.0, 1.0)
	lbl.add_theme_font_size_override("font_size", int(lerpf(18.0, 34.0, heavy)) + (8 if killed else 0))
	var col := Color(1.0, 0.85, 0.3) if killed else Color(1.0, 0.95, 0.9).lerp(Color(1.0, 0.55, 0.3), heavy)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	add_child(lbl)
	var sp := cam.unproject_position(world_pos)
	sp += Vector2(randf_range(-14, 14), randf_range(-8, 8)) # scatter so stacks don't overlap
	lbl.position = sp
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", sp.y - 46.0, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.65).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(lbl.queue_free)

func _on_enemy_killed(score: int, label: String) -> void:
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
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.6)
	tw.tween_callback(lbl.queue_free)

func _on_continue_pressed() -> void:
	GameState.advance_level()

func _on_resume_pressed() -> void:
	GameState.set_state(GameState.State.PLAYING)
	_exit_pause()

func _on_quit_pressed() -> void:
	GameState.set_state(GameState.State.MENU)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_pause_graphics_pressed() -> void:
	GraphicsSettings.cycle()
	_refresh_pause_graphics()

func _on_pause_volume_changed(value: float) -> void:
	AudioBus.set_master_volume(value)

func _on_restart_pressed() -> void:
	GameState.load_level(GameState.current_level_path if GameState.current_level_path != "" else "res://scenes/levels/level_01.tscn")
