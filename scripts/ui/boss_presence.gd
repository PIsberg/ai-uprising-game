class_name BossPresence
extends Control
## The boss fight staged as one, on the HUD (hud.gd adds it and hands it the
## boss bar). On GameState.boss_spawned an intro card plays: letterbox bars
## slide in, a warning header, the boss's name and its epithet typed out under
## it, then it all clears. The boss bar is notched at the boss's
## boss_phase_marks() and trails a pale chip of each hit that holds a beat and
## drains. On GameState.boss_phase_changed a banner calls the new phase
## ("PHASE II", "FINAL PHASE"); the world side of that beat (roar ring, quake,
## hit-stop) is EnemyBase._boss_phase_beat's.
##
## The card and banner run on their own clocks in _process, in real time (an
## entrance's hit-stop must not stall them) but at most STEP_MAX per frame: a
## boss's first frame hitches while its materials compile, and a tween on real
## time swallowed that whole frame and skipped the card.

const CARD_IN := 0.35     ## Letterbox and card slide-in (s).
const CARD_HOLD := 2.4    ## Card on screen (s).
const CARD_OUT := 0.5     ## Card and bars clear (s).
const BAR_FRAC := 0.11    ## Letterbox bar height, as a fraction of the screen.
const TRAIL_HOLD := 0.45  ## Seconds the damage trail holds before it drains.
const TRAIL_RATE := 0.6   ## Bar fractions per second it drains at.
const BANNER_IN := 0.25
const BANNER_HOLD := 1.4
const BANNER_OUT := 0.5
const STEP_MAX := 0.05    ## Longest real-time step the card and banner take per frame (s).
const PHASE_TITLES := ["", "", "PHASE II", "PHASE III", "PHASE IV"]
const FINAL_TITLE := "FINAL PHASE"
const HEADER := "⚠ BOSS SIGNATURE DETECTED"
const RED := Color(1.0, 0.24, 0.18)
const AMBER := Color(1.0, 0.62, 0.2)

var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _header: Label
var _title: Label
var _epithet: Label
var _banner: Label
var _banner_sub: Label
var _health_bar: ProgressBar
var _overlay: Control
var _marks: Array = []
var _chip := 1.0
var _chip_hold := 0.0
var _boss_name := ""
var _card_t := -1.0   ## seconds into the intro card, -1 when none is showing
var _banner_t := -1.0 ## seconds into the phase banner, -1 when none is showing

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_top = _letterbox(0.0)
	_bar_bottom = _letterbox(1.0)
	_header = _label(0.66, 18, RED)
	_title = _label(0.70, 64, Color(1.0, 0.95, 0.9))
	_title.add_theme_color_override("font_outline_color", Color(0.45, 0.02, 0.0))
	_title.add_theme_constant_override("outline_size", 10)
	_epithet = _label(0.80, 22, Color(1.0, 0.8, 0.7))
	_banner = _label(0.24, 54, AMBER)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner_sub = _label(0.33, 20, Color(1.0, 0.85, 0.75))
	for l in [_header, _title, _epithet, _banner, _banner_sub]:
		(l as Label).visible = false
	GameState.boss_spawned.connect(_on_boss_spawned)
	GameState.boss_phase_changed.connect(_on_boss_phase_changed)

## The HUD's boss bar: notched and trailed from here on.
func setup(health_bar: ProgressBar) -> void:
	_health_bar = health_bar
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.12, 0.08)
	fill.set_corner_radius_all(2)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.02, 0.02, 0.8)
	back.border_color = Color(1.0, 0.35, 0.25, 0.7)
	back.set_border_width_all(1)
	back.set_corner_radius_all(2)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.add_theme_stylebox_override("background", back)
	_overlay = Control.new()
	_overlay.name = "BossBarMarks"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_bar_marks)
	_health_bar.add_child(_overlay)

func _letterbox(anchor_y: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0, 0, 0, 0.92)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.anchor_left = 0.0
	r.anchor_right = 1.0
	r.anchor_top = anchor_y
	r.anchor_bottom = anchor_y
	add_child(r)
	return r

func _label(anchor_y: float, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = anchor_y
	l.anchor_bottom = anchor_y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _on_boss_spawned(boss: Node) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	_boss_name = String(boss.get("boss_name")) if boss.get("boss_name") != null else "BOSS"
	_marks = boss.call("boss_phase_marks") if boss.has_method("boss_phase_marks") else []
	_chip = 1.0
	_chip_hold = 0.0
	var bhp: Node = boss.get_node_or_null("Damageable")
	if bhp and not bhp.health_changed.is_connected(_on_boss_health):
		bhp.health_changed.connect(_on_boss_health)
	if _overlay:
		_overlay.queue_redraw()
	var epithet := String(boss.get("boss_epithet")) if boss.get("boss_epithet") != null else ""
	_header.text = tr(HEADER)
	_title.text = _boss_name
	_epithet.text = tr(epithet) if epithet != "" else ""
	for l in [_header, _title, _epithet]:
		(l as Label).visible = true
	_card_t = 0.0
	_tick_card(0.0)

func _on_boss_health(cur: float, max_: float) -> void:
	var frac := cur / maxf(max_, 1.0)
	if frac < _chip:
		_chip_hold = TRAIL_HOLD # each hit restarts the hold
	else:
		_chip = frac
	if _overlay:
		_overlay.queue_redraw()

func _on_boss_phase_changed(boss: Node, phase: int, final: bool) -> void:
	var title: String = FINAL_TITLE if final else String(PHASE_TITLES[clampi(phase, 0, PHASE_TITLES.size() - 1)])
	_banner.text = tr(title)
	_banner.add_theme_color_override("font_color", RED if final else AMBER)
	_banner_sub.text = String(boss.get("boss_name")) if is_instance_valid(boss) and boss.get("boss_name") != null else _boss_name
	_banner.visible = true
	_banner_sub.visible = true
	_banner_t = 0.0
	_tick_banner(0.0)

func _process(delta: float) -> void:
	var step := minf(delta / maxf(Engine.time_scale, 0.01), STEP_MAX)
	if _card_t >= 0.0:
		_tick_card(step)
	if _banner_t >= 0.0:
		_tick_banner(step)
	if _health_bar == null or not _health_bar.is_visible_in_tree():
		return
	var frac := float(_health_bar.value) / maxf(float(_health_bar.max_value), 1.0)
	if _chip > frac:
		if _chip_hold > 0.0:
			_chip_hold -= delta
		else:
			_chip = maxf(frac, _chip - TRAIL_RATE * delta)
		_overlay.queue_redraw()

## Bars in, header, name, epithet typed out; hold; all out.
func _tick_card(step: float) -> void:
	_card_t += step
	var t := _card_t
	var out_k := clampf((t - CARD_IN - CARD_HOLD) / CARD_OUT, 0.0, 1.0)
	var keep := 1.0 - out_k
	var in_k := 1.0 - pow(1.0 - clampf(t / CARD_IN, 0.0, 1.0), 3.0) # ease out
	var bar_h := get_viewport_rect().size.y * BAR_FRAC * in_k * keep
	_bar_top.offset_bottom = bar_h
	_bar_bottom.offset_top = -bar_h
	_header.modulate.a = clampf(t / CARD_IN, 0.0, 1.0) * keep
	_title.modulate.a = clampf((t - 0.1) / CARD_IN, 0.0, 1.0) * keep
	_epithet.modulate.a = clampf((t - 0.35) / 0.2, 0.0, 1.0) * keep
	_epithet.visible_ratio = clampf((t - 0.35) / 0.7, 0.0, 1.0)
	if out_k >= 1.0:
		_card_t = -1.0
		for l in [_header, _title, _epithet]:
			(l as Label).visible = false

## Pops in oversized and settles, holds, fades.
func _tick_banner(step: float) -> void:
	_banner_t += step
	var t := _banner_t
	var keep := 1.0 - clampf((t - BANNER_IN - BANNER_HOLD) / BANNER_OUT, 0.0, 1.0)
	_banner.modulate.a = clampf(t / 0.12, 0.0, 1.0) * keep
	_banner_sub.modulate.a = clampf((t - 0.1) / 0.25, 0.0, 1.0) * keep
	var k := clampf(t / BANNER_IN, 0.0, 1.0)
	_banner.pivot_offset = _banner.size * 0.5
	_banner.scale = Vector2.ONE * lerpf(1.6, 1.0, 1.0 - pow(1.0 - k, 3.0))
	if keep <= 0.0:
		_banner_t = -1.0
		_banner.visible = false
		_banner_sub.visible = false

## The trail (pale, from the fill's end to where the bar stood before the
## hits) and a notch at each phase mark.
func _draw_bar_marks() -> void:
	var w := _overlay.size.x
	var h := _overlay.size.y
	var frac := float(_health_bar.value) / maxf(float(_health_bar.max_value), 1.0)
	if _chip > frac:
		_overlay.draw_rect(Rect2(w * frac, 1.0, w * (_chip - frac), h - 2.0), Color(1.0, 0.85, 0.6, 0.75))
	for m in _marks:
		var x := w * float(m)
		var passed := frac <= float(m)
		_overlay.draw_rect(Rect2(x - 1.0, -3.0, 2.0, h + 6.0), Color(1, 1, 1, 0.35) if passed else Color(1, 1, 1, 0.9))
