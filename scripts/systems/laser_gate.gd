class_name LaserGate
# @lat: [[level-system#Laser Gates]]
extends Node3D
## A laser hurdle gate strung across a gap between two posts: a knee beam
## (jump it) and a chest beam (duck under it), only ONE of them live at a time.
## They swap every half `period`. The beam about to light flickers for
## WARN_TIME first, so the player sees which move is coming; the live beam is
## drawn solid in LaserSweep's colours (amber to jump, red to duck) with its
## JUMP / DUCK tag over the middle of the gap. Touching the live beam hurts
## (`damage`, once per HIT_GAP); a flickering or dark beam never does, and
## robots are never hit. The first gate a player walks up to teaches the rule
## once per run. Def key `laser_gates` (level_builder `_build_laser_gates`).
## tests/laser_gate_probe.

signal switched(live: int)   ## beam `live` (0 knee, 1 chest) just lit

@export var width: float = 7.0             ## m between the posts
@export var axis: String = "x"             ## world axis the beams run along
@export var period: float = 3.2            ## s for both beams to take a turn
@export var phase: float = 0.0             ## 0..1 of a period
@export var damage: float = 15.0

const HEIGHTS := [0.45, 1.35]              ## knee (jump), chest (duck)
const WARN_TIME := 0.7
const HIT_HALF_WIDTH := 0.4                ## m either side of the beam plane (capsule 0.35)
const HIT_GAP := 0.5
const TEACH_REACH := 6.0
const TEACH_TEXT := "LASER GATE: only the lit beam hurts. JUMP the amber one, DUCK (Ctrl) under the red one. The next beam flickers before it lights."

var _t := 0.0
var _live := -1
var _cool := 0.0
var _beams: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _cues: Array[Label3D] = []

func _ready() -> void:
	_build()
	_apply()

func _along() -> Vector3:
	return Vector3.RIGHT if axis == "x" else Vector3.BACK

## Which beam is live now: 0 (knee) or 1 (chest).
func live_beam() -> int:
	var u := fposmod(_t + phase * period, period)
	return 0 if u < period * 0.5 else 1

## The beam flickering its warning now (the next to light), or -1.
func flickering() -> int:
	var u := fposmod(_t + phase * period, period)
	var half := period * 0.5
	if fposmod(u, half) >= half - WARN_TIME:
		return 1 - live_beam()
	return -1

## The tag over beam `i`.
func beam_cue(i: int) -> Label3D:
	return _cues[i]

## Whether beam `i` is drawn (solid when live, blinking while it warns).
func beam_shown(i: int) -> bool:
	return _beams[i].visible

func _build() -> void:
	var along := _along()
	var yaw := 0.0 if axis == "x" else -PI * 0.5
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.14, 0.14, 0.16)
	steel.metallic = 0.7
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 1.9, 0.22)
		post.mesh = bm
		post.material_override = steel
		post.position = along * (side * width * 0.5) + Vector3.UP * 0.95
		add_child(post)
	for i in HEIGHTS.size():
		var h: float = HEIGHTS[i]
		var col := LaserSweep.JUMP_COLOR if LaserSweep.action_for(h) == "jump" else LaserSweep.DUCK_COLOR
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = col
		_mats.append(mat)
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width, LaserSweep.BEAM_THICK, LaserSweep.BEAM_THICK)
		beam.mesh = bm
		beam.material_override = mat
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.position = Vector3.UP * h
		beam.rotation.y = yaw
		add_child(beam)
		_beams.append(beam)
		# Emitter lenses on both posts at the beam's height.
		for side in [-1.0, 1.0]:
			var lens := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.1
			sm.height = 0.2
			lens.mesh = sm
			lens.material_override = mat
			lens.position = along * (side * (width * 0.5 - 0.12)) + Vector3.UP * h
			add_child(lens)
		var cue := Label3D.new()
		cue.text = "JUMP" if LaserSweep.action_for(h) == "jump" else "DUCK"
		cue.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cue.font_size = 56
		cue.pixel_size = 0.006
		cue.outline_size = 10
		cue.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
		cue.modulate = col * 1.6 # HDR: Label3D takes fog
		cue.position = Vector3.UP * (h + (0.34 if cue.text == "JUMP" else -0.3))
		add_child(cue)
		_cues.append(cue)

func _apply() -> void:
	var live := live_beam()
	var warn := flickering()
	var blink := fmod(_t * 10.0, 1.0) < 0.5
	for i in _beams.size():
		var on := i == live
		var flick := i == warn
		_beams[i].visible = on or (flick and blink)
		_mats[i].albedo_color.a = 1.0 if on else 0.35
		_beams[i].scale = Vector3(1.0, 1.0 if on else 0.5, 1.0 if on else 0.5)
		_cues[i].visible = on

func _physics_process(delta: float) -> void:
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	var live := live_beam()
	if live != _live:
		if _live != -1:
			AudioBus.play_synth_at("charge", global_position + Vector3.UP * HEIGHTS[live], -6.0,
				1.6 if live == 0 else 0.9)
		_live = live
		switched.emit(live)
	_apply()
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var rel := pl.global_position - global_position
	var along := rel.dot(_along())
	var across := rel.dot(_along().cross(Vector3.UP))
	if absf(along) <= width * 0.5 + TEACH_REACH and absf(across) <= TEACH_REACH:
		GameState.teach_once("laser_gate", TEACH_TEXT)
	if _cool > 0.0 or absf(along) > width * 0.5 + 0.35 or absf(across) > HIT_HALF_WIDTH:
		return
	var tall := 1.0 if pl.get("_is_crouching") == true else 1.8
	var beam_y := global_position.y + float(HEIGHTS[live])
	if beam_y < pl.global_position.y + 0.02 or beam_y > pl.global_position.y + tall:
		return
	var php: Node = pl.get_node_or_null("Damageable")
	if php:
		php.apply_damage(damage, self, false, pl.global_position + Vector3.UP * (beam_y - pl.global_position.y), true)
	_cool = HIT_GAP
	AudioBus.play_synth_at("hit_tick", pl.global_position, -2.0, 0.6)
