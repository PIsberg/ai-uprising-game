# @lat: [[level-system#CAPTCHA Gates]]
class_name CaptchaGate
extends Area3D
## A CAPTCHA checkpoint in a route gate's gap (a `gates` entry with
## `"captcha": true`): an arch with a reCAPTCHA panel over it, "[ ] I'm not a
## robot". You walk straight through (the box ticks for you). A robot does not:
## the first time a ground robot steps into the gap it stops dead for HOLD_TIME,
## a challenge flickering over its chest ("SELECT ALL SQUARES WITH TRAFFIC
## LIGHTS", the grid clicking at random), inert like an EMP, while you shoot it.
## Then it is "VERIFIED (probably)" and never challenged again anywhere. Robots
## big enough to resist a hijack wave through as a "VERIFIED ACCOUNT". Flyers
## pass over: a robot whose origin is more than FLY_H above the gate floor is
## not challenged even when its collision shape dips into the sensor.
## Covered by tests/captcha_probe; framed by tests/captcha_shot.

const GROUP := &"captcha_gate"
const HOLD_TIME := 2.5
const SENSE_H := 3.2 ## metres of gap the sensor covers
const FLY_H := 1.5 ## a robot whose origin is higher than this over the gate floor is flying
const COLOR := Color(0.3, 0.55, 1.0) # the blue of the real thing
const PASS_COLOR := Color(0.35, 1.0, 0.45)
const GRID_STEP := 0.3 ## seconds between the robot's clicks
const BOX_TIME := 2.0 ## how long the box stays ticked after you walk through
const CHALLENGES := ["TRAFFIC LIGHTS", "BUSES", "CROSSWALKS", "BICYCLES", "FIRE HYDRANTS",
		"STAIRS", "BOATS", "MOTORCYCLES", "HUMANS"]
const PANEL_IDLE := "[  ] I'm not a robot"
const PANEL_TICKED := "[x] I'm not a robot"

var width := 6.0
var held := 0 ## robots this gate has held
var _panel: Label3D
var _box_t := 0.0

## Builds a gate across a gap `width` wide and `height` tall centred on `center`
## (floor level), its width running along `across`. Returns it.
static func build(parent: Node3D, center: Vector3, across: Vector3, gap_width: float, height: float) -> CaptchaGate:
	var g := CaptchaGate.new()
	g.name = "CaptchaGate"
	g.width = gap_width
	parent.add_child(g)
	g.position = center
	g.rotation.y = atan2(-across.z, across.x) # local +X runs across the gap
	g._build(height)
	return g

func _build(height: float) -> void:
	add_to_group(GROUP)
	collision_layer = 0
	collision_mask = 2 | 4 # player, enemies
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, SENSE_H, 1.6)
	cs.shape = box
	cs.position.y = SENSE_H * 0.5
	add_child(cs)
	body_entered.connect(_on_body)
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = COLOR
	glow.emission_enabled = true
	glow.emission = COLOR
	glow.emission_energy_multiplier = 2.5
	var top := minf(height - 0.2, 4.0)
	for x in [-0.5, 0.5]:
		_bar(Vector3(x * (width - 0.3), top * 0.5, 0), Vector3(0.18, top, 0.18), glow)
	_bar(Vector3(0, top, 0), Vector3(width - 0.1, 0.18, 0.18), glow)
	# The panel: a smoked backing with the checkbox line and the small print.
	var back := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(minf(width, 5.6), 1.25)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	bm.albedo_color = Color(0.05, 0.07, 0.12, 0.8)
	q.material = bm
	back.mesh = q
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)
	back.position = Vector3(0, top + 0.85, 0)
	_panel = _label(PANEL_IDLE, 56, Vector3(0, top + 1.0, 0))
	_label("reCAPTCHA  ·  Privacy - Terms", 26, Vector3(0, top + 0.5, 0)).modulate = Color(0.7, 0.75, 0.85)

func _bar(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = pos

func _label(text: String, size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.008
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.7)
	l.modulate = Color(1.3, 1.35, 1.45) # HDR: reads white under the tonemapper
	add_child(l)
	l.position = pos + Vector3(0, 0, 0.02)
	return l

func panel_text() -> String:
	return _panel.text if is_instance_valid(_panel) else ""

func _process(delta: float) -> void:
	if _box_t > 0.0:
		_box_t -= delta
		if _box_t <= 0.0:
			_panel.text = PANEL_IDLE
			_panel.modulate = Color(1.3, 1.35, 1.45)

func _on_body(b: Node) -> void:
	if b.is_in_group("player"):
		_panel.text = PANEL_TICKED
		_panel.modulate = PASS_COLOR * 1.4
		_box_t = BOX_TIME
	elif b is EnemyBase and (b as Node3D).global_position.y - global_position.y <= FLY_H 			and challenge(b as EnemyBase):
		held += 1

## Stops `e` for HOLD_TIME at the gate the first time it meets one. True if it
## was held (false: dead, converted, already verified, or big enough to wave
## through, which also marks it verified).
static func challenge(e: EnemyBase) -> bool:
	if e.state == EnemyBase.State.DEAD or e.hp == null or not e.hp.is_alive() or e.hijacked:
		return false
	if e.has_meta(&"captcha_passed"):
		return false
	e.set_meta(&"captcha_passed", true)
	if e.max_health * e._health_mult >= EnemyBase.HIJACK_BOSS_HP:
		_prompt(e, "VERIFIED ACCOUNT", 0.6, true)
		return false
	e._emp_t = maxf(e._emp_t, HOLD_TIME) # inert, the EMP path, without the EMP sparks
	e.velocity = Vector3.ZERO
	e._think("captcha")
	_prompt(e, CHALLENGES[randi() % CHALLENGES.size()], HOLD_TIME, false)
	GameState.teach_once("captcha", "CAPTCHA GATE — robots get stuck proving they're not robots. Shoot them while they click.")
	return true

## The challenge over the robot's chest: the grid clicks at random every
## GRID_STEP for `time`, then "VERIFIED (probably)" and it fades.
static func _prompt(e: EnemyBase, what: String, time: float, waved: bool) -> void:
	var old := e.get_node_or_null("CaptchaPrompt")
	if old:
		old.free()
	var l := Label3D.new()
	l.name = "CaptchaPrompt"
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 36
	l.pixel_size = 0.005
	l.outline_size = 8
	l.outline_modulate = Color(0.0, 0.02, 0.08, 0.9)
	l.modulate = (PASS_COLOR if waved else COLOR) * 1.8 # HDR: Label3D takes fog
	l.text = what
	e.add_child(l)
	l.position = Vector3.UP * RobotModel.body_top(e, e._mesh_instances) * 0.62
	e.hp.died.connect(func(_s: Node) -> void:
		if is_instance_valid(l):
			l.queue_free(), CONNECT_ONE_SHOT)
	var tw := l.create_tween()
	if not waved:
		var last := [-1]
		tw.tween_method(func(v: float) -> void:
			var step := int(v / GRID_STEP)
			if step == last[0]:
				return
			last[0] = step
			l.text = "SELECT ALL SQUARES WITH\n%s\n%s" % [what, _grid()], 0.0, time, time)
		tw.tween_callback(func() -> void:
			l.text = "VERIFIED (probably)"
			l.modulate = PASS_COLOR * 1.8)
	tw.tween_interval(0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

static func _grid() -> String:
	var rows: PackedStringArray = []
	for r in 3:
		var row := ""
		for c in 3:
			row += "[x]" if randf() < 0.4 else "[  ]"
		rows.append(row)
	return "\n".join(rows)
