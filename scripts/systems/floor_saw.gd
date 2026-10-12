class_name FloorSaw
# @lat: [[level-system#Floor Saws]]
extends Node3D
## A floor saw: a spinning blade that rises out of a slot in the floor and runs
## it end to end, back and forth, for ever. The slot runs from this node to
## `span` (a horizontal offset); the lane either side of it is painted in
## yellow-and-black stripes, and the stripes are the danger: stand in them
## when the blade comes and it cuts you (`damage`, and you are thrown out of
## the lane); step out of the stripes, or jump it (its top is BLADE_TOP m up,
## under a jump's 1.17 m), and it passes. Robots are never cut: traps are for
## the player. It is always telegraphed: the blade is out and loud,
## the end lamp it is running toward blinks red, and a player standing in its
## lane gets a blip and a flash of the stripes WARN_LEAD s before it reaches
## them (`warned`). The first saw a player walks up to teaches the rule once
## per run. Nothing about it is solid.
## Def key `saws` (level_builder `_build_saws`). tests/floor_saw_probe.

signal warned   ## the blade will reach the player in its lane in WARN_LEAD s

@export var span: Vector3 = Vector3(8, 0, 0)  ## slot end, relative to this node (y ignored)
@export var speed: float = 4.5                ## m/s along the slot
@export var pause: float = 0.5                ## s the blade idles at each end
@export var phase: float = 0.0                ## 0..1 of a round trip
@export var damage: float = 25.0              ## to the player per cut

const RADIUS := 0.75          ## blade radius
const AXLE_Y := 0.1           ## blade centre over the floor (the rest is in the slot)
const BLADE_TOP := RADIUS + AXLE_Y
const LANE_HALF := 0.55       ## m either side of the slot that is striped
const CUT_HALF := 0.42        ## m either side that the blade reaches a body (capsule 0.35)
const CUT_GAP := 0.7          ## s before the same body can be cut again
const WARN_LEAD := 0.7        ## s
const SHOVE := 7.0            ## m/s out of the lane
const TEACH_REACH := 6.0      ## m from the lane where the rule is taught
const TEACH_TEXT := "FLOOR SAW: a blade runs along the striped slot. Step out of the stripes or jump over it."

var _t := 0.0
var _len := 1.0
var _dir := Vector3.RIGHT      ## along the slot, a -> b
var _side := Vector3.BACK      ## across the slot
var _blade_pivot: Node3D
var _blade: Node3D
var _lamp_a: StandardMaterial3D
var _lamp_b: StandardMaterial3D
var _lane_mat: ShaderMaterial
var _sparks: CPUParticles3D
var _whine: AudioStreamPlayer3D
var _cool := {}
var _warn_armed := true
var _flash := 0.0

func _ready() -> void:
	add_to_group("hazard")
	var flat := Vector3(span.x, 0.0, span.z)
	_len = maxf(flat.length(), 0.5)
	_dir = flat / _len
	_side = _dir.cross(Vector3.UP)
	_build()
	_place(blade_offset())

## Seconds for one round trip (run, pause, run back, pause).
func round_trip() -> float:
	return 2.0 * (_len / speed + pause)

## Distance of the blade from this end along the slot, now.
func blade_offset() -> float:
	return _offset_at(_t + phase * round_trip())

## Direction the blade is travelling (+1 toward `span`, -1 back, 0 paused).
func heading() -> float:
	var trip := round_trip()
	var u := fposmod(_t + phase * trip, trip)
	var run := _len / speed
	if u < run:
		return 1.0
	if u < run + pause:
		return 0.0
	if u < 2.0 * run + pause:
		return -1.0
	return 0.0

func _offset_at(t: float) -> float:
	var trip := round_trip()
	var u := fposmod(t, trip)
	var run := _len / speed
	if u < run:
		return u * speed
	if u < run + pause:
		return _len
	if u < 2.0 * run + pause:
		return _len - (u - run - pause) * speed
	return 0.0

## The blade's centre in world space.
func blade_position() -> Vector3:
	return global_position + _dir * blade_offset() + Vector3.UP * AXLE_Y

func _build() -> void:
	var yaw := atan2(-_dir.z, _dir.x)
	# The lane: hazard stripes either side of a dark slot, from end to end.
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float half_w = 0.55;
uniform float flash = 0.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float across = abs(lp.z);
	if (across < 0.1) {
		ALBEDO = vec3(0.01); // the slot
	} else {
		float s = step(0.5, fract((lp.x + lp.z) * 1.4));
		vec3 yel = vec3(0.95, 0.66, 0.05) * (0.6 + flash * 1.6);
		ALBEDO = mix(vec3(0.03), yel, s);
	}
}
"""
	_lane_mat = ShaderMaterial.new()
	_lane_mat.shader = sh
	var pm := PlaneMesh.new()
	pm.size = Vector2(_len + RADIUS * 2.0, LANE_HALF * 2.0)
	var lane := MeshInstance3D.new()
	lane.name = "Lane"
	lane.mesh = pm
	lane.material_override = _lane_mat
	lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lane.position = _dir * (_len * 0.5) + Vector3.UP * 0.025
	lane.rotation.y = yaw
	add_child(lane)
	# End housings with a lamp each: the one the blade runs toward blinks.
	_lamp_a = _housing(-_dir * (RADIUS + 0.35))
	_lamp_b = _housing(_dir * (_len + RADIUS + 0.35))
	# The blade: a disc on an axle across the slot, toothed, with a hot rim.
	_blade_pivot = Node3D.new()
	_blade_pivot.rotation.y = yaw
	add_child(_blade_pivot)
	_blade = Node3D.new()
	_blade_pivot.add_child(_blade)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78)
	steel.metallic = 1.0
	steel.roughness = 0.25
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = RADIUS * 0.92
	cm.bottom_radius = RADIUS * 0.92
	cm.height = 0.06
	cm.radial_segments = 28
	disc.mesh = cm
	disc.material_override = steel
	disc.rotation.x = PI * 0.5 # axis across the slot (local Z)
	_blade.add_child(disc)
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(1.0, 0.35, 0.08)
	hot.emission_enabled = true
	hot.emission = Color(1.0, 0.35, 0.08)
	hot.emission_energy_multiplier = 2.5
	for i in 14:
		var a := TAU * float(i) / 14.0
		var tooth := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.16, 0.16, 0.07)
		tooth.mesh = bm
		tooth.material_override = hot
		tooth.position = Vector3(cos(a), sin(a), 0.0) * (RADIUS * 0.9)
		tooth.rotation.z = a + PI * 0.25
		_blade.add_child(tooth)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.16
	hm.bottom_radius = 0.16
	hm.height = 0.16
	hub.mesh = hm
	hub.material_override = hot
	hub.rotation.x = PI * 0.5
	_blade.add_child(hub)
	for c in _blade.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sparks off the floor where the blade bites.
	_sparks = CPUParticles3D.new()
	_sparks.amount = 24
	_sparks.lifetime = 0.35
	_sparks.direction = Vector3(-1, 0.6, 0)
	_sparks.spread = 25.0
	_sparks.initial_velocity_min = 3.0
	_sparks.initial_velocity_max = 6.0
	_sparks.gravity = Vector3(0, -12, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.75, 0.3)
	sm.material = spark_mat
	_sparks.mesh = sm
	_blade_pivot.add_child(_sparks)
	_whine = AudioStreamPlayer3D.new()
	_whine.stream = AudioBus.synth("drone_hum")
	_whine.volume_db = -8.0
	_whine.pitch_scale = 2.6
	_whine.max_distance = 26.0
	_blade_pivot.add_child(_whine)

func _housing(at: Vector3) -> StandardMaterial3D:
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 0.35, LANE_HALF * 2.0)
	box.mesh = bm
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(0.16, 0.15, 0.14)
	body.metallic = 0.6
	box.material_override = body
	box.position = at + Vector3.UP * 0.175
	box.rotation.y = atan2(-_dir.z, _dir.x)
	add_child(box)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	lamp.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.3, 0.05)
	lamp.material_override = mat
	lamp.position = at + Vector3.UP * 0.45
	add_child(lamp)
	return mat

func _place(off: float) -> void:
	_blade_pivot.position = _dir * off + Vector3.UP * AXLE_Y
	_sparks.position = Vector3(0, -AXLE_Y + 0.03, 0)

func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	var off := blade_offset()
	var head := heading()
	_place(off)
	# Spin with the travel (teeth biting forward), idle-spin while paused.
	_blade.rotation.z -= (12.0 if head != 0.0 else 7.0) * delta * (head if head != 0.0 else 1.0)
	_sparks.emitting = head != 0.0
	_sparks.direction = Vector3(-head, 0.6, 0)
	if _whine.stream and not _whine.playing and is_inside_tree():
		_whine.play()
	var blink := fmod(_t * 5.0, 1.0) < 0.5
	_lamp_b.albedo_color = Color(1.0, 0.1, 0.05) if head > 0.0 and blink else Color(0.5, 0.3, 0.05)
	_lamp_a.albedo_color = Color(1.0, 0.1, 0.05) if head < 0.0 and blink else Color(0.5, 0.3, 0.05)
	_lane_mat.set_shader_parameter("flash", 1.0 if _flash > 0.0 and fmod(_t * 8.0, 1.0) < 0.5 else 0.0)
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		_player_tick(pl, off, head)

## Where `n` stands relative to the slot: (along, across), on the ground plane.
func _lane_coords(n: Node3D) -> Vector2:
	var rel := n.global_position - global_position
	return Vector2(rel.dot(_dir), rel.dot(_side))

## Whether the blade at `off` is in `n`: in the lane, at the blade, under its top.
func _cuts(n: Node3D, off: float) -> bool:
	var c := _lane_coords(n)
	var dy := n.global_position.y - global_position.y
	return absf(c.y) <= CUT_HALF and absf(c.x - off) <= RADIUS * 0.9 \
		and dy > -0.3 and dy < BLADE_TOP - 0.05

func _player_tick(pl: Node3D, off: float, head: float) -> void:
	var c := _lane_coords(pl)
	if absf(c.y) <= LANE_HALF + TEACH_REACH and c.x >= -TEACH_REACH and c.x <= _len + TEACH_REACH:
		GameState.teach_once("floor_saw", TEACH_TEXT)
	var id := pl.get_instance_id()
	if _cuts(pl, off) and float(_cool.get(id, 0.0)) <= 0.0:
		_cool[id] = CUT_GAP
		var php: Node = pl.get_node_or_null("Damageable")
		if php:
			php.apply_damage(damage, self, false, blade_position(), true)
		if "velocity" in pl:
			pl.velocity = _side * (signf(c.y) if c.y != 0.0 else 1.0) * SHOVE + Vector3.UP * 3.0
		AudioBus.play_synth_at("impact_metal", pl.global_position, 2.0, 1.4)
	# Warn a player standing in the lane, once per approach.
	var in_lane := absf(c.y) <= LANE_HALF + 0.2 and c.x >= -RADIUS and c.x <= _len + RADIUS
	var gap := (c.x - off) * head # > 0: the blade is running at them
	if not in_lane or head == 0.0 or gap <= 0.0:
		if head != 0.0 and gap <= -RADIUS:
			_warn_armed = true # it has passed them
		return
	if _warn_armed and (gap - RADIUS) / speed <= WARN_LEAD:
		_warn_armed = false
		_flash = 0.6
		AudioBus.play_synth_at("broadcast_blip", pl.global_position, -3.0, 1.2)
		warned.emit()
