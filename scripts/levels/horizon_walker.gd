# @lat: [[level-system#Horizon Walkers]]
class_name HorizonWalker
extends Node3D
## A colossal war machine walking the horizon of an open-sky level: the WARMECH
## chassis at SCALE (about 195 m tall, its head clear of a spawn's perimeter wall), out past the megacity's far ring at
## RING_PAST_FLOOR, striding slowly round the arena on its walk clip slowed to
## ANIM_SPEED so its feet keep pace with the ground it covers. Two red eyes
## that cut through any haze, a searchlight cone swept from its head at night,
## and a far-off thud on each footfall. The war is bigger than this arena.
##
## Visual only: no collision, no shadow; the body takes the level's fog, so in
## haze it is a looming silhouette. LOW skips it (a skinned mesh animating).
## Covered by tests/horizon_walker_probe; framed by tests/horizon_walker_shot.

const MODEL := preload("res://assets/models/robots/quaternius_mech_armed.glb")
const WALK := "RobotArmature|Walk"
const SCALE := 75.0
const RING_PAST_FLOOR := 330.0 ## metres beyond the floor's half-extent: past Skyline's far ring
const ANIM_SPEED := 0.3
const STRIDE_SPEED := 9.0 ## metres a second along its arc at ANIM_SPEED (feet roughly planted)
const STEP_EVERY := 0.95 ## seconds between footfalls at ANIM_SPEED
const EYE_COLOR := Color(1.0, 0.15, 0.08)
const EYE_R := 5.0 ## metres: a glint you can pick out at 500 m
const EYE_FWD := 0.58 ## rig units ahead of the Head bone, along the walker's facing
const EYE_SPREAD := 0.13 ## rig units either side
const BEAM_LEN := 150.0 ## the searchlight cone's modelled length, stretched to reach the ground

var radius := 400.0
var angle := 0.0 ## radians round the arena (atan2(x, z) convention)
var dir := 1.0 ## +1 counter-clockwise seen from above, -1 clockwise
var body: Node3D
var _anim: AnimationPlayer
var _step_t := 0.0
var _beam: MeshInstance3D
var _eyes: Array[MeshInstance3D] = []
var _skel: Skeleton3D
var _head := -1

## Builds the walker for an open-sky `def` (WORLD_SCALE'd) under `parent`;
## null indoors, with the landmark opted out, or on LOW.
static func build_for(parent: Node3D, def: Dictionary, is_low: bool) -> HorizonWalker:
	if not def.get("open_sky", false) or is_low:
		return null
	if String(def.get("landmark", {}).get("kind", "")) == "none":
		return null
	var fs: Vector2 = def.get("floor_size", Vector2(40, 40))
	var w := HorizonWalker.new()
	w.name = "HorizonWalker"
	w.radius = maxf(fs.x, fs.y) * 0.5 + RING_PAST_FLOOR
	# Start a quarter turn off the landmark's heading, walking away from it.
	var h := Landmark.heading_for(def)
	w.angle = atan2(h.x, h.z) - PI * 0.5
	w.dir = -1.0
	w.night = def.get("env", {}).has("stars")
	parent.add_child(w)
	w._build()
	w._place()
	return w

var night := false

func _build() -> void:
	body = MODEL.instantiate() as Node3D
	add_child(body)
	body.scale = Vector3.ONE * SCALE
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		m.extra_cull_margin = 40.0
	_anim = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim and _anim.has_animation(WALK):
		_anim.get_animation(WALK).loop_mode = Animation.LOOP_LINEAR
		_anim.play(WALK)
		_anim.speed_scale = ANIM_SPEED
	_find_head()
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = EYE_COLOR * 3.0
	eye_mat.disable_fog = true
	for s in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = EYE_R
		sm.height = EYE_R * 2.0
		sm.radial_segments = 8
		sm.rings = 4
		sm.material = eye_mat
		eye.mesh = sm
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(eye)
		_eyes.append(eye)
	if night:
		_beam = MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.5
		cone.bottom_radius = 26.0
		cone.height = BEAM_LEN
		cone.cap_top = false
		cone.cap_bottom = false
		cone.radial_segments = 16
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		bm.disable_fog = true
		bm.albedo_color = Color(1.0, 0.85, 0.7, 0.07)
		cone.material = bm
		_beam.mesh = cone
		_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_beam)

func _find_head() -> void:
	_skel = body.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skel:
		_head = _skel.find_bone("Head")

## World position of the head (the rig's Head bone as it walks; a fixed height
## without one).
func head_position() -> Vector3:
	if _skel and _head >= 0:
		return _skel.global_transform * _skel.get_bone_global_pose(_head).origin
	return global_position + Vector3.UP * SCALE * 2.7

## The eyes ride the head bone in world space, EYE_FWD ahead of it along the
## walker's facing (the bone's own axes are the rig's, not the face's).
func _place_eyes() -> void:
	var h := head_position()
	var fwd := global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	for i in _eyes.size():
		var s := -1.0 if i == 0 else 1.0
		_eyes[i].global_position = h + fwd * EYE_FWD * SCALE + right * s * EYE_SPREAD * SCALE

## Where it stands at `a` radians round the arena (pure: the probe reads it).
static func point_at(r: float, a: float) -> Vector3:
	return Vector3(sin(a) * r, 0.0, cos(a) * r)

func _place() -> void:
	position = point_at(radius, angle)
	# Faces along its path (the tangent), the model's +Z forward.
	var ahead := point_at(radius, angle + dir * 0.01) - position
	rotation.y = atan2(ahead.x, ahead.z)

func _process(delta: float) -> void:
	tick(delta)

func tick(delta: float) -> void:
	angle += dir * STRIDE_SPEED / radius * delta
	_place()
	_place_eyes()
	_step_t += delta
	if _step_t >= STEP_EVERY:
		_step_t = 0.0
		AudioBus.play_synth_ui("mech_step", -27.0, randf_range(0.42, 0.5))
	if is_instance_valid(_beam):
		# From its head down onto the city between it and the arena, searching.
		var t := Time.get_ticks_msec() / 1000.0
		var head := head_position()
		var aim := global_position.lerp(Vector3(0, global_position.y, 0), 0.45) 				+ Vector3(sin(t * 0.37), 0.0, cos(t * 0.29)) * 60.0
		var xf := Landmark._strut_xform(aim, head) # +Y (the narrow end) at the head
		xf.basis = xf.basis * Basis.from_scale(Vector3(1.0, aim.distance_to(head) / BEAM_LEN, 1.0))
		_beam.global_transform = xf
