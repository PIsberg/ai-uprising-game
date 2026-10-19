# @lat: [[player#Network Breach]]
class_name NetworkBreach
extends Node
## NETWORK BREACH: the player's remote hack. Hold the breach key (B / D-pad right)
## and time slows to SCAN_SCALE while every networked thing in view is marked;
## release with one under the crosshair and it is taken over, paid for out of a
## BANDWIDTH meter that refills at REGEN. What a breach does is the target's own
## business (its breach()): a sentry turret turns on the robots, an explosive
## barrel goes off, a laser gate goes dark, a firewall drops; a robot is jammed
## (EMP) for JAM_TIME. Bosses and lockdown doors are never offered. A scan ends by
## itself after SCAN_MAX real seconds. The player builds one as its "NetworkBreach"
## child. Covered by tests/network_breach_probe.

const ACTION := "breach"
const MAX_BANDWIDTH := 100.0
const REGEN := 7.0          ## bandwidth per second, paused while scanning
const RANGE := 35.0         ## m from the eye
const VIEW_DEG := 40.0      ## half-angle of what a scan marks
const PICK_DEG := 12.0      ## half-angle the crosshair picks from
const SCAN_SCALE := 0.3     ## Engine.time_scale while scanning
const SCAN_MAX := 3.0       ## real seconds a scan can last
const JAM_TIME := 3.0       ## seconds a breached robot stays jammed
const JAM_COST := 25.0
const COL := Color(0.35, 0.95, 1.0)
const TEACH := "◈ NETWORK BREACH — hold [B] to scan; release on a turret, barrel, laser gate, firewall or robot to take it over."

signal breached(target: Node, label: String)

var bandwidth: float = MAX_BANDWIDTH
var scanning: bool = false
var player: Node3D = null

var _scan_ms := 0
var _hud: CanvasLayer
var _bar_fill: ColorRect
var _bar_label: Label
var _tint: ColorRect
var _marks: Array[Label] = []
var _pick_label: Label

func _ready() -> void:
	player = get_parent() as Node3D
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_B
		InputMap.action_add_event(ACTION, ev)
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_DPAD_RIGHT # D-pad up is the flashlight
		InputMap.action_add_event(ACTION, pad)
	_build_hud()

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.color = Color(COL, 0.10)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	root.add_child(_tint)
	# The meter: a thin bar bottom-centre, under the crosshair line of sight.
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -90
	bar.offset_right = 90
	bar.offset_top = -96
	bar.offset_bottom = -90
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)
	_bar_fill = ColorRect.new()
	_bar_fill.color = COL
	_bar_fill.size = Vector2(180, 6)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_bar_fill)
	_bar_label = Label.new()
	_bar_label.text = tr("BANDWIDTH")
	_bar_label.position = Vector2(0, -18)
	_bar_label.add_theme_font_size_override("font_size", 11)
	_bar_label.add_theme_color_override("font_color", Color(COL, 0.8))
	bar.add_child(_bar_label)
	_pick_label = Label.new()
	_pick_label.add_theme_font_size_override("font_size", 16)
	_pick_label.add_theme_color_override("font_color", COL)
	_pick_label.add_theme_constant_override("outline_size", 5)
	_pick_label.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.08))
	_pick_label.visible = false
	root.add_child(_pick_label)

func _camera() -> Camera3D:
	return player.get("camera") as Camera3D if player else null

## The robot is a boss-class set piece (the same line hijack draws).
static func _boss(e: EnemyBase) -> bool:
	return e.max_health * e._health_mult >= EnemyBase.HIJACK_BOSS_HP

## Whether `n` can be breached at all (range and view aside).
func can_breach(n: Node) -> bool:
	if not is_instance_valid(n):
		return false
	if n is EnemyBase:
		var e := n as EnemyBase
		return e.hp != null and e.hp.is_alive() and not e.hijacked and not _boss(e)
	return n.is_in_group("breachable") and n.has_method("breach") and bool(n.call("breach_ready"))

func cost_of(n: Node) -> float:
	return JAM_COST if n is EnemyBase else float(n.call("breach_cost"))

func label_of(n: Node) -> String:
	if n is EnemyBase:
		return tr("%s: JAM") % (n as EnemyBase)._kill_label()
	return tr(String(n.call("breach_label")))

func _aim_point(n: Node3D) -> Vector3:
	return n.global_position + Vector3.UP * (1.0 if n is EnemyBase else 0.8)

## Breachable things in range, in view and in line of sight, nearest the crosshair first.
func targets() -> Array:
	var cam := _camera()
	if cam == null:
		return []
	var eye := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var cands: Array = get_tree().get_nodes_in_group("breachable") + get_tree().get_nodes_in_group("enemy")
	var out: Array = []
	var space := player.get_world_3d().direct_space_state
	for n in cands:
		if not (n is Node3D) or not can_breach(n):
			continue
		var at := _aim_point(n)
		var to := at - eye
		if to.length() > RANGE or rad_to_deg(fwd.angle_to(to)) > VIEW_DEG:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, at, 1)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var col: Node = hit.get("collider")
			if col != n and not (n as Node).is_ancestor_of(col):
				continue # something solid in between
		out.append(n)
	out.sort_custom(func(a, b): return fwd.angle_to(_aim_point(a) - eye) < fwd.angle_to(_aim_point(b) - eye))
	return out

## The target under the crosshair (within PICK_DEG), or null.
func pick_target() -> Node:
	var cam := _camera()
	var t := targets()
	if t.is_empty() or cam == null:
		return null
	var fwd := -cam.global_transform.basis.z
	var first: Node3D = t[0]
	return first if rad_to_deg(fwd.angle_to(_aim_point(first) - cam.global_position)) <= PICK_DEG else null

## Take `n` over now if it can be and the bandwidth pays for it.
func breach(n: Node) -> bool:
	if not can_breach(n):
		return false
	var cost := cost_of(n)
	if bandwidth < cost:
		AudioBus.play_synth_ui("empty_click", -6.0, 0.7)
		return false
	var label := label_of(n)
	var took := false
	if n is EnemyBase:
		(n as EnemyBase).emp_disable(JAM_TIME)
		took = true
	else:
		took = bool(n.call("breach", player))
	if not took:
		return false
	bandwidth -= cost
	GameState.note_breach() # the finale's SET IT FREE counts these
	breached.emit(n, label)
	GameState.teach_hint.emit(tr("◈ BREACHED · %s") % label)
	AudioBus.play_synth_ui("overlord_glitch", -6.0, 1.4)
	return true

func _start_scan() -> void:
	scanning = true
	_scan_ms = Time.get_ticks_msec()
	_tint.visible = true
	GameState.hit_stop(SCAN_SCALE, SCAN_MAX)
	AudioBus.play_synth_ui("radio_static", -10.0, 1.6)

func _end_scan(fire: bool) -> void:
	scanning = false
	_tint.visible = false
	_pick_label.visible = false
	for m in _marks:
		m.visible = false
	GameState.hit_stop(1.0, 0.01) # a new hit_stop token: time snaps back now
	if fire:
		var t := pick_target()
		if t:
			breach(t)

func _process(delta: float) -> void:
	if player == null:
		return
	var alive: bool = player.get("_dead") != true and GameState.current_state == GameState.State.PLAYING
	if not scanning:
		bandwidth = minf(MAX_BANDWIDTH, bandwidth + REGEN * delta)
	if alive and Input.is_action_just_pressed(ACTION) and not scanning:
		GameState.teach_once("network_breach", TEACH)
		_start_scan()
	if scanning:
		if not alive:
			_end_scan(false)
		elif Input.is_action_just_released(ACTION) or not Input.is_action_pressed(ACTION):
			_end_scan(true)
		elif Time.get_ticks_msec() - _scan_ms > int(SCAN_MAX * 1000.0):
			_end_scan(false)
		else:
			_draw_marks()
	_bar_fill.size.x = 180.0 * bandwidth / MAX_BANDWIDTH
	_bar_fill.color = COL if not scanning else Color(1, 1, 1)

## Mark everything a scan offers; the picked one gets its name and cost.
func _draw_marks() -> void:
	var cam := _camera()
	var t := targets()
	var picked := pick_target()
	while _marks.size() < t.size():
		var m := Label.new()
		m.text = "◇"
		m.add_theme_font_size_override("font_size", 30)
		m.add_theme_color_override("font_color", COL)
		# Dark outline: a thin cyan diamond vanished over a laser gate's yellow JUMP cue
		# on a bright floor (tests/network_breach_shot).
		m.add_theme_constant_override("outline_size", 8)
		m.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.08))
		_tint.get_parent().add_child(m)
		_marks.append(m)
	for i in _marks.size():
		var m := _marks[i]
		m.visible = i < t.size() and cam != null and not cam.is_position_behind(_aim_point(t[i]))
		if m.visible:
			m.position = cam.unproject_position(_aim_point(t[i])) - Vector2(11, 20)
			m.text = "◆" if t[i] == picked else "◇"
	_pick_label.visible = picked != null and cam != null
	if _pick_label.visible:
		var c := cost_of(picked)
		_pick_label.text = "%s   −%d" % [label_of(picked), int(c)]
		_pick_label.add_theme_color_override("font_color", COL if bandwidth >= c else Color(1.0, 0.4, 0.35))
		_pick_label.position = cam.unproject_position(_aim_point(picked)) + Vector2(18, -10)
