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

var _bg: ColorRect
var _header: Label
var _body: Label
var _prompt: Label
var _static: AudioStreamPlayer

var _phase: int = 0
var _pt: float = 0.0     # time within the current phase
var _line: int = 0
var _line_t: float = 0.0 # time within the current line's typing
var _completed: String = ""
var _fade: float = 0.0

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
	_body.add_theme_font_size_override("font_size", 22)
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
			_bg.color.a = minf(0.9, _bg.color.a + delta * 1.4)
			if _bg.color.a >= 0.9:
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
			_bg.color.a = a * 0.9
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
