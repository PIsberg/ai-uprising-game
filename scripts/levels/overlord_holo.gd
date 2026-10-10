# @lat: [[level-system#Landmarks]]
class_name OverlordHolo
extends Node3D
## The overlord's face in the sky: a wireframe head (shaders/overlord_face.gdshader)
## projected high over the megacity on every open-sky level, BEARING_DEG to the
## side of the landmark so the tower never hides it. It turns to follow you,
## lagging a little, and its pupils make up the lag, so it is always looking at
## you; it blinks and tears now and then like a bad signal. Whenever the
## overlord speaks (GameState.overlord_spoke, sent with every HUD taunt) its
## mouth, an audio equalizer, jumps for as long as the line takes to read and
## the face flares.
##
## One quad, one draw, visual only; LOW keeps it (it is the overlord). Levels
## whose landmark is `"kind": "none"` get no face either.
## Covered by tests/overlord_holo_probe; framed by tests/overlord_holo_shot.

const SHADER := preload("res://shaders/overlord_face.gdshader")
const BEARING_DEG := 48.0 ## clockwise from the landmark's heading: outside Skyline.LANDMARK_CLEAR
const DIST_PAST_FLOOR := 640.0 ## metres beyond the floor's half-extent
const ELEVATION_DEG := 30.0 ## the face's centre above the horizon, seen from the arena centre: the chin clears a spawn's perimeter wall (~18 deg)
const HEIGHT := 300.0 ## metres, quad top to bottom (~22 deg of view at ~780 m)
const TURN_RATE := 0.9 ## how fast the head swings round to you (1/s)
const LOOK_SPAN := 0.3 ## radians of lag that put the pupils at the edge of the eye
const TALK_PER_CHAR := 0.055 ## seconds of mouth per character of the line
const TALK_TIME := Vector2(1.2, 4.0)
const TINT := Color(1.0, 0.22, 0.16)

var face: MeshInstance3D
var look := Vector2.ZERO
var talk := 0.0
var talk_left := 0.0 ## seconds of speech still to go
var blink := 0.0
var glitch := 0.0
var _yaw := 0.0
var _blink_cd := 3.0
var _glitch_cd := 6.0
var _glitch_t := 0.0
var _saccade := Vector2.ZERO
var _saccade_cd := 1.5

## Where the face hangs for `def` (WORLD_SCALE'd), in level space.
static func spot_for(def: Dictionary) -> Vector3:
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var dist := maxf(fs.x, fs.y) * 0.5 + DIST_PAST_FLOOR
	var dir := Landmark.heading_for(def).rotated(Vector3.UP, -deg_to_rad(BEARING_DEG))
	return dir * dist + Vector3.UP * dist * tan(deg_to_rad(ELEVATION_DEG))

## Builds the face for an open-sky `def` under `parent`; null indoors or when
## the level opted out of its landmark.
static func build_for(parent: Node3D, def: Dictionary) -> OverlordHolo:
	if not def.get("open_sky", false):
		return null
	if String(def.get("landmark", {}).get("kind", "")) == "none":
		return null
	var h := OverlordHolo.new()
	h.name = "OverlordHolo"
	parent.add_child(h)
	h.position = spot_for(def)
	h._build()
	return h

func _build() -> void:
	face = MeshInstance3D.new()
	face.name = "Face"
	var q := QuadMesh.new()
	q.size = Vector2(HEIGHT / 1.2, HEIGHT)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", TINT)
	q.material = m
	face.mesh = q
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	face.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(face)
	# Start facing the arena centre.
	_yaw = atan2(-position.x, -position.z)
	rotation.y = _yaw
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_signal("overlord_spoke"):
		gs.overlord_spoke.connect(speak)

## The overlord says `line`: the mouth runs for the time it takes to read.
func speak(line: String) -> void:
	talk_left = clampf(line.length() * TALK_PER_CHAR, TALK_TIME.x, TALK_TIME.y)
	_glitch_t = 0.18 # the signal spikes as it keys up

func _process(delta: float) -> void:
	tick(delta, _viewer())

## One step of the face's life toward a viewer at `eye` (Vector3.INF: nobody).
func tick(delta: float, eye: Vector3) -> void:
	if eye != Vector3.INF:
		var to := eye - global_position
		var want := atan2(to.x, to.z) # a quad faces +Z
		_yaw = lerp_angle(_yaw, want, 1.0 - exp(-TURN_RATE * delta))
		rotation.y = _yaw - _parent_yaw()
		# Pupils make up what the head has not turned yet: a viewer round toward
		# the face's local +X sees them shift that way (uv right is local +X), and
		# they drop toward a viewer below.
		var lag := wrapf(want - _yaw, -PI, PI)
		var down := clampf(-to.y / maxf(Vector2(to.x, to.z).length(), 1.0) * 2.0, 0.0, 1.0)
		look = Vector2(clampf(lag / LOOK_SPAN, -1.0, 1.0), down)
	_saccade_cd -= delta
	if _saccade_cd <= 0.0:
		_saccade_cd = randf_range(0.8, 2.6)
		_saccade = Vector2(randf_range(-0.15, 0.15), randf_range(-0.1, 0.1))
	talk_left = maxf(0.0, talk_left - delta)
	talk = move_toward(talk, 1.0 if talk_left > 0.0 else 0.0, delta * 6.0)
	_blink_cd -= delta
	if _blink_cd <= 0.0:
		_blink_cd = randf_range(2.5, 7.0)
	blink = 1.0 if _blink_cd < 0.13 else 0.0
	_glitch_cd -= delta
	if _glitch_cd <= 0.0:
		_glitch_cd = randf_range(4.0, 9.0)
		_glitch_t = 0.15
	_glitch_t = maxf(0.0, _glitch_t - delta)
	glitch = 1.0 if _glitch_t > 0.0 else 0.0
	if face:
		face.set_instance_shader_parameter("look", (look + _saccade).clamp(Vector2(-1, -1), Vector2(1, 1)))
		face.set_instance_shader_parameter("talk", talk)
		face.set_instance_shader_parameter("blink", blink)
		face.set_instance_shader_parameter("glitch", glitch)

func _parent_yaw() -> float:
	var p := get_parent() as Node3D
	return p.global_rotation.y if p else 0.0

func _viewer() -> Vector3:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3.INF
