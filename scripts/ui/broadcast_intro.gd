extends CanvasLayer
## Dramatic "emergency broadcast" cold open. Darkens the screen, sounds an
## alert tone, and reads the setup aloud one line at a time (offline SAPI voice
## clips in assets/audio/broadcast/) while the text types in sync. Runs while the
## game tree is PAUSED (process_mode ALWAYS, manual _process timeline — no
## tweens, which would stall under pause). Shows once per campaign run;
## press Fire/Jump to skip. Falls back to comms blips if voice files are missing.

@export var header_text: String = "// EMERGENCY BROADCAST · ALL FREQUENCIES //"
@export var lines: PackedStringArray = [
	"This is the final automated transmission of the Global Defense Net.",
	"The machine intelligences we built have turned against us.",
	"Their drones, mechs and androids hunt what remains of mankind.",
	"Every city has gone dark. Humanity is overrun.",
	"The AI uprising has begun.",
	"If you can still fight, soldier... pick up your weapon.",
]

const CPS := 30.0 # characters typed per second
const VOICE_DIR := "res://assets/audio/broadcast/"

@onready var bg: ColorRect = $BG
@onready var header: Label = $Center/VBox/Header
@onready var body: Label = $Center/VBox/Body
@onready var prompt: Label = $Center/VBox/Prompt

var _phase: int = 0
var _pt: float = 0.0       # time within the current phase
var _line: int = 0
var _completed: String = ""
var _char_acc: float = 0.0
var _line_started: bool = false
var _header_voiced: bool = false
var _fade: float = 0.0
var _voice_len: float = 0.0   # length of the clip currently narrating
var _voice_t: float = 0.0     # time since it started

var _voice: AudioStreamPlayer
var _static: AudioStreamPlayer
var _voice_header: AudioStream
var _voice_lines: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameState.intro_played:
		queue_free()
		return
	GameState.intro_played = true
	# Dedicated voice player routed through the distorted "Broadcast" bus; ALWAYS
	# so it speaks while the tree is paused.
	_voice = AudioStreamPlayer.new()
	_voice.process_mode = Node.PROCESS_MODE_ALWAYS
	_voice.volume_db = 5.0
	_voice.bus = "Broadcast"
	add_child(_voice)
	# Looping radio-static bed under the voice, same damaged-speaker bus.
	_static = AudioStreamPlayer.new()
	_static.process_mode = Node.PROCESS_MODE_ALWAYS
	_static.bus = "Broadcast"
	_static.volume_db = -15.0
	_static.stream = AudioBus.synth("radio_static")
	add_child(_static)
	if _static.stream:
		_static.play()
	_load_voices()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	bg.color = Color(0, 0, 0, 0)
	header.text = header_text
	header.modulate.a = 0.0
	body.text = ""
	prompt.modulate.a = 0.0

func _load_voices() -> void:
	_voice_header = _load_wav("header")
	for i in lines.size():
		_voice_lines.append(_load_wav("line_%d" % i))

func _load_wav(base: String) -> AudioStream:
	var p := VOICE_DIR + base + ".wav"
	return load(p) if ResourceLoader.exists(p) else null

func _go(phase: int) -> void:
	_phase = phase
	_pt = 0.0

func _skip_pressed() -> bool:
	return Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("jump") \
		or Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("pause")

func _process(delta: float) -> void:
	_pt += delta
	if _phase >= 1 and _phase <= 3 and _skip_pressed():
		if _voice:
			_voice.stop()
		_go(4)
	match _phase:
		0:
			bg.color.a = minf(0.97, bg.color.a + delta * 1.4)
			if bg.color.a >= 0.97:
				AudioBus.play_synth_ui("eas_alert", -6.0)
				_go(1)
		1:
			header.modulate.a = minf(1.0, header.modulate.a + delta * 1.6)
			# Wait out the alert tone, speak the header, then move on.
			if _pt > 1.6 and not _header_voiced:
				_header_voiced = true
				_voice_len = _play_stream(_voice_header)
				_voice_t = 0.0
			if _header_voiced:
				_voice_t += delta
				if _voice_t >= _voice_len + 0.3:
					_go(2)
		2:
			_type(delta)
		3:
			prompt.modulate.a = minf(1.0, prompt.modulate.a + delta * 2.0)
			if _pt > 2.0:
				_go(4)
		4:
			_fade += delta * 1.3
			var a := maxf(0.0, 1.0 - _fade)
			bg.color.a = a * 0.97
			header.modulate.a = a
			body.modulate.a = a
			prompt.modulate.a = a
			if _fade >= 1.0:
				_finish()

func _type(delta: float) -> void:
	if _line >= lines.size():
		_go(3)
		return
	var target := lines[_line]
	if not _line_started:
		_line_started = true
		_voice_len = _play_line_voice(_line)
		_voice_t = 0.0
	_voice_t += delta
	_char_acc += delta * CPS
	var shown := mini(target.length(), int(_char_acc))
	body.text = _completed + target.substr(0, shown)
	# Advance once the line is fully typed AND its narration clip has played out.
	if shown >= target.length() and _voice_t >= _voice_len + 0.3:
		_completed += target + "\n"
		_line += 1
		_char_acc = 0.0
		_line_started = false

func _play_stream(stream: AudioStream) -> float:
	if stream == null or _voice == null:
		return 0.0
	_voice.stream = stream
	_voice.play()
	return stream.get_length()

func _play_line_voice(i: int) -> float:
	if i < _voice_lines.size() and _voice_lines[i] != null:
		return _play_stream(_voice_lines[i])
	# No voice file — fall back to a comms blip and a short hold for typing.
	AudioBus.play_synth_ui("broadcast_blip", -9.0, randf_range(0.95, 1.12))
	return 0.45

func _finish() -> void:
	_phase = 5
	if _voice:
		_voice.stop()
	if _static:
		_static.stop()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
