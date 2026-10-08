class_name VictoryTransmission
extends CanvasLayer
## The finale's closing "Global Defense Net" broadcast — the typed-text bookend
## to the campaign-opening emergency transmission (scripts/ui/broadcast_intro.gd).
## Built entirely in code (no companion .tscn), the same way CutscenePlayer
## builds its own letterbox/subtitle overlay. Added as a child of
## victory_cutscene.gd once its 3D timeline ends; emits `finished` when the
## broadcast itself ends or is skipped.
##
## No new audio streams: like broadcast_intro.gd's "no voice file" fallback,
## each line cues the existing "broadcast_blip" comms-blip synth over the same
## band-passed "Broadcast" bus, under a quiet "radio_static" bed.

signal finished

@export var header_text: String = "// GLOBAL DEFENSE NET — SIGNAL RESTORED //"
@export var lines: PackedStringArray = [
	"This is the Global Defense Net, resuming broadcast on all frequencies.",
	"ARCHON is down. Every drone, mech and android answering to it went dark with it.",
	"Grid power is returning, sector by sector. Cities are reporting light again.",
	"You did what no automated defense system could.",
	"This is the Global Defense Net, signing off. Well done, soldier.",
]

const CPS := 30.0 # characters typed per second
const HOLD_AFTER_TYPE := 0.5 # beat held once a line finishes typing
const SCRIM_A := 0.9 # opacity of the black broadcast scrim

var _bg: ColorRect
var _header: Label
var _body: Label
var _prompt: Label
var _static: AudioStreamPlayer
var _crt: ColorRect
var _crt_mat: ShaderMaterial

var _phase: int = 0
var _pt: float = 0.0     # time within the current phase
var _line: int = 0
var _line_t: float = 0.0 # time within the current line's typing
var _completed: String = ""
var _fade: float = 0.0
var _scrim: float = 0.0 # authoritative scrim alpha (Color.a is float32 and rounds)

func _ready() -> void:
	layer = 12 # above the cutscene's own overlay (layer 10), which is now black
	_build_ui()
	_static = AudioStreamPlayer.new()
	_static.bus = "Broadcast"
	_static.volume_db = -17.0
	_static.stream = AudioBus.synth("radio_static")
	add_child(_static)
	if _static.stream:
		_static.play()
	AudioBus.play_synth_ui("eas_alert", -9.0, 0.92)
	set_process(true)
	set_process_input(true)

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0, 0) # the cutscene already faded to black; ease our own scrim up
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	_header = Label.new()
	_header.text = header_text
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_theme_font_size_override("font_size", 28)
	_header.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	_header.add_theme_constant_override("outline_size", 6)
	_header.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_header.modulate.a = 0.0
	vbox.add_child(_header)

	_body = Label.new()
	_body.custom_minimum_size = Vector2(920, 190)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", GraphicsSettings.subtitle_px(22))
	_body.add_theme_color_override("font_color", Color(0.85, 0.9, 0.92))
	_body.add_theme_constant_override("outline_size", 6)
	_body.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	vbox.add_child(_body)

	_prompt = Label.new()
	_prompt.text = "[ Press any key to continue ]"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 15)
	_prompt.add_theme_color_override("font_color", Color(0.6, 0.62, 0.64))
	_prompt.modulate.a = 0.0
	vbox.add_child(_prompt)

	_build_crt()

## The last thing a player sees before the credits was flat text on flat black.
## A CRT pass over the top — rolling scanlines, a soft vignette, a slow signal
## roll and a little grain — makes it read as a broadcast being received rather
## than a text box. Drawn ABOVE the labels (added last) and pointer-transparent
## so it can't eat the skip input. Cheap: one full-screen canvas_item shader.
func _build_crt() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.10;
uniform float vignette : hint_range(0.0, 1.5) = 0.75;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform float fade : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	// Scanlines, drifting slowly downward like a rolling frame sync.
	float scan = sin((uv.y + TIME * 0.035) * 900.0) * 0.5 + 0.5;
	float dark = scan * scan_strength;
	// One brighter band sweeping the tube every few seconds.
	float roll = smoothstep(0.965, 1.0, fract(uv.y * 0.5 - TIME * 0.09));
	// Corners fall off.
	vec2 c = uv - 0.5;
	float vig = smoothstep(0.85, 0.20, length(c) * vignette);
	float g = (hash(uv * vec2(1920.0, 1080.0) + TIME) - 0.5) * grain;
	// Additive tint (a phosphor-green sheen) minus the scanline darkening.
	vec3 col = vec3(0.35, 1.0, 0.55) * (roll * 0.05 + g);
	float a = (dark + (1.0 - vig) * 0.35) * fade;
	COLOR = vec4(col + vec3(0.0), clamp(a, 0.0, 0.9));
}
"""
	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = sh
	_crt_mat.set_shader_parameter("fade", 0.0)
	_crt = ColorRect.new()
	_crt.color = Color(0, 0, 0, 1)
	_crt.material = _crt_mat
	_crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crt)
	# Ease the tube on with the scrim rather than snapping it in.
	create_tween().tween_property(_crt_mat, "shader_parameter/fade", 1.0, 1.4)

func _go(phase: int) -> void:
	_phase = phase
	_pt = 0.0

func _skip_pressed() -> bool:
	return Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("jump") \
		or Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("pause")

func _process(delta: float) -> void:
	_pt += delta
	if _phase >= 1 and _phase <= 2 and _skip_pressed():
		_go(3)
	match _phase:
		0:
			# Drive the scrim from our own float, NOT by reading Color.a back.
			# Color stores 32-bit floats: assigning minf(0.9, ...) and reading it
			# again yields 0.89999997, so `>= SCRIM_A` was never true and the
			# broadcast never left phase 0. The campaign's closing transmission
			# never typed a word, and because skip is only wired for phases 1-2,
			# the finale hung on a black screen instead of reaching the credits.
			_scrim = minf(SCRIM_A, _scrim + delta * 1.4)
			_bg.color.a = _scrim
			if _scrim >= SCRIM_A:
				_go(1)
		1:
			_header.modulate.a = minf(1.0, _header.modulate.a + delta * 1.6)
			if _pt > 1.0:
				_go(2)
		2:
			_type(delta)
		3:
			_prompt.modulate.a = minf(1.0, _prompt.modulate.a + delta * 2.0)
			if _pt > 2.0:
				_go(4)
		4:
			_fade += delta * 1.3
			var a := maxf(0.0, 1.0 - _fade)
			_bg.color.a = a * SCRIM_A
			_header.modulate.a = a
			_body.modulate.a = a
			_prompt.modulate.a = a
			if _fade >= 1.0:
				_finish()

func _type(delta: float) -> void:
	if _line >= lines.size():
		_go(3)
		return
	var target := lines[_line]
	if _line_t == 0.0:
		# No dedicated voice clip for the ending — same "no voice file" fallback
		# broadcast_intro.gd uses per line.
		AudioBus.play_synth_ui("broadcast_blip", -9.0, randf_range(0.95, 1.12))
	_line_t += delta
	var shown := mini(target.length(), int(_line_t * CPS))
	_body.text = _completed + target.substr(0, shown)
	if _line_t >= float(target.length()) / CPS + HOLD_AFTER_TYPE:
		_completed += target + "\n"
		_line += 1
		_line_t = 0.0

func _input(event: InputEvent) -> void:
	if _phase != 3:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventJoypadButton and event.pressed):
		_go(4)

func _finish() -> void:
	if _phase == 5:
		return
	_phase = 5
	if _static:
		_static.stop()
	finished.emit()
	queue_free()
