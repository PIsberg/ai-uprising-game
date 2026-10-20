class_name WindZone
# @lat: [[level-system#Crosswinds]]
extends Node3D
## A crosswind over a walkway (def key `wind`). Every `period` seconds: calm,
## then `warn` seconds of WARNING (the windsocks at both ends lift and
## flutter, streaks start to run, a whistle rises), then `gust` seconds of
## GUST: a player inside the zone's box (`size` x by z, `height` up from
## `position.y`) is pushed along `dir` at `speed` m/s through
## Player.wind_velocity, which the player applies as its own collision move
## after move_and_slide. Crouching on the floor braces (Player.WIND_BRACE).
## Walking straight into it still makes headway (walk 5.5 m/s vs the default
## 4.0). It moves nothing else and hurts no one: the water does that.
## tests/wind_probe.

enum Phase { CALM, WARN, GUST }

const STREAKS := 14
const TEACH_TEXT := "CROSSWIND: gusts shove you sideways. The windsocks lift before each one: crouch [C] to brace, or lean into it."

@export var size := Vector2(8, 8)
@export var height := 5.0
@export var dir := Vector3(1, 0, 0)
@export var speed := 4.0
@export var period := 6.0
@export var gust := 1.6
@export var warn := 1.0
@export var phase_offset := 0.0 ## 0..1 of a period

var phase: Phase = Phase.CALM
var gusts := 0
var _t := 0.0
var _streaks: Array[MeshInstance3D] = []
var _streak_mat: StandardMaterial3D
var _socks: Array[Node3D] = []
var _taught := false

func _ready() -> void:
	add_to_group("wind_zone")
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.RIGHT
	_t = phase_offset * period
	_build()

func _build() -> void:
	_streak_mat = StandardMaterial3D.new()
	_streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_streak_mat.albedo_color = Color(0.85, 0.92, 1.0, 0.0)
	var face := Basis.looking_at(dir, Vector3.UP)
	for i in STREAKS:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.03, 0.03, 1.6)
		mi.mesh = bm
		mi.material_override = _streak_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.basis = face
		mi.position = Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(0.3, height * 0.7), randf_range(-0.5, 0.5) * size.y)
		add_child(mi)
		_streaks.append(mi)
	# A windsock at each end of the walkway (the zone's long axis, across the wind).
	var across := Vector3(-dir.z, 0.0, dir.x)
	var half := 0.5 * (absf(across.x) * size.x + absf(across.z) * size.y)
	for s in [-1.0, 1.0]:
		_socks.append(_windsock(across * (half - 0.6) * s - dir * 1.2))

func _windsock(at: Vector3) -> Node3D:
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.05
	cm.height = 2.6
	pole.mesh = cm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.52, 0.55)
	steel.metallic = 0.8
	pole.material_override = steel
	pole.position = at + Vector3.UP * 1.3
	add_child(pole)
	var hinge := Node3D.new()
	hinge.position = at + Vector3.UP * 2.5
	hinge.basis = Basis.looking_at(dir, Vector3.UP)
	add_child(hinge)
	var sock := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.22
	cone.bottom_radius = 0.07
	cone.height = 1.1
	sock.mesh = cone
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(1.0, 0.45, 0.1)
	cloth.emission_enabled = true
	cloth.emission = Color(1.0, 0.4, 0.1)
	cloth.emission_energy_multiplier = 0.6
	sock.material_override = cloth
	# Cone axis along the hinge's -Z (downwind), wide end at the pole.
	sock.rotation.x = -PI * 0.5
	sock.position = Vector3(0, 0, -0.55)
	hinge.add_child(sock)
	return hinge

func _player() -> Node3D:
	return GameState.nearest_player(global_position)

func contains(p: Vector3) -> bool:
	var l := p - global_position
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.y * 0.5 and l.y >= -1.0 and l.y <= height

func _phase_at(t: float) -> Phase:
	var u := fposmod(t, period)
	if u >= period - gust:
		return Phase.GUST
	if u >= period - gust - warn:
		return Phase.WARN
	return Phase.CALM

func _physics_process(delta: float) -> void:
	_t += delta
	var ph := _phase_at(_t)
	if ph != phase:
		phase = ph
		if ph == Phase.WARN:
			AudioBus.play_synth_at("ambience_wind", global_position, -6.0, 1.4)
		elif ph == Phase.GUST:
			gusts += 1
			AudioBus.play_synth_at("ambience_wind", global_position, 0.0, 0.9)
	for p in GameState.players():
		var inside := contains((p as Node3D).global_position)
		if inside and not _taught:
			_taught = true
			GameState.teach_once("crosswind", TEACH_TEXT)
		if inside and phase == Phase.GUST and "wind_velocity" in p:
			p.set("wind_velocity", dir * speed)

func _process(delta: float) -> void:
	var k := 0.0
	var lift := 1.25 # radians of droop below horizontal when calm
	match phase:
		Phase.WARN:
			k = 0.25
			lift = 0.6 + 0.25 * sin(Time.get_ticks_msec() * 0.03)
		Phase.GUST:
			k = 0.6
			lift = 0.05 * sin(Time.get_ticks_msec() * 0.05)
	_streak_mat.albedo_color.a = k
	if k > 0.0:
		var run := dir * speed * 3.0 * delta
		var span := 0.5 * (absf(dir.x) * size.x + absf(dir.z) * size.y)
		for s in _streaks:
			s.position += run
			if s.position.dot(dir) > span:
				s.position -= dir * span * 2.0
	for h in _socks:
		h.basis = Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -lift)
