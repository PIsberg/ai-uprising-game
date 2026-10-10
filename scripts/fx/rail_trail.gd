# @lat: [[weapons#Rail Trail]]
class_name RailTrail
extends MeshInstance3D
## The ionization trail a railgun round leaves in the air (WeaponData.rail_trail:
## the ARC-9 gauss and the MK-VII Longshot). A tight helix of light coiling round
## the line of the shot, PITCH metres a turn, around a white-hot core; over LIFE
## the coil swells outward and drifts up like smoke while the core burns out
## first, so a shot hangs in the air for a beat and you can read where it came
## from. Down the barrel it is a tunnel of rings.
##
## One mesh, one draw (shaders/rail_trail.gdshader animates it from an `age`
## instance uniform). Capped at MAX_LEN from the muzzle and MAX_LIVE at once.
## Covered by tests/rail_trail_probe; framed by tests/rail_trail_shot.

const SHADER := preload("res://shaders/rail_trail.gdshader")
const GROUP := &"rail_trail"
const LIFE := 1.4
const PITCH := 0.6 ## metres of shot per turn of the coil
const RADIUS := 0.11 ## coil radius at the moment of the shot
const BAND := 0.06 ## width of the coil's band, along the shot
const CORE_W := 0.035
const START := 0.5 ## metres of clear air before the coil starts (not in your face)
const MAX_LEN := 120.0
const MAX_LIVE := 6

var from := Vector3.ZERO
var to := Vector3.ZERO

## Leaves a trail from `a` (the muzzle) to `b` (where the round landed) under
## `parent`, in `col`. Returns it.
static func spawn(parent: Node, a: Vector3, b: Vector3, col: Color) -> RailTrail:
	var live := parent.get_tree().get_nodes_in_group(GROUP).filter(func(n: Node) -> bool:
		return not n.is_queued_for_deletion())
	while live.size() >= MAX_LIVE:
		(live.pop_front() as Node).queue_free()
	if a.distance_to(b) > MAX_LEN:
		b = a + (b - a).normalized() * MAX_LEN
	var rt := RailTrail.new()
	rt.from = a
	rt.to = b
	rt.add_to_group(GROUP)
	rt.mesh = build_mesh(a, b, 8 if GraphicsSettings.is_low() else 14)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("color", col)
	rt.material_override = m
	rt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rt.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# The coil swells and rises in the shader: give the culling box room.
	rt.extra_cull_margin = 1.0
	parent.add_child(rt)
	rt.global_transform = Transform3D(Basis(), a)
	var tw := rt.create_tween()
	tw.tween_method(func(v: float) -> void: rt.set_instance_shader_parameter("age", v), 0.0, 1.0, LIFE)
	tw.tween_callback(rt.queue_free)
	return rt

## The coil and the core, in space relative to `a`. COLOR.a marks the core (1)
## from the coil (0); the coil's NORMAL points out from the axis so the shader
## can swell it.
static func build_mesh(a: Vector3, b: Vector3, seg: int) -> ArrayMesh:
	var d := b - a
	var length := d.length()
	var mesh := ArrayMesh.new()
	if length < START + 0.1:
		return mesh
	d /= length
	var u := d.cross(Vector3.UP)
	if u.length() < 0.01:
		u = d.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := d.cross(u).normalized()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var step := PITCH / float(seg)
	var n := int((length - START) / step)
	for k in n + 1:
		var s := START + k * step
		var ang := s / PITCH * TAU
		var r := u * cos(ang) + v * sin(ang)
		var c := d * s + r * RADIUS
		for side in [-0.5, 0.5]:
			verts.append(c + d * BAND * side)
			norms.append(r)
			uvs.append(Vector2(s, side + 0.5))
			cols.append(Color(1, 1, 1, 0))
		if k > 0:
			var i := k * 2
			idx.append_array([i - 2, i - 1, i, i - 1, i + 1, i])
	# Core: two crossed quads down the axis.
	for w in [u, v]:
		var base := verts.size()
		for p in [[START, -0.5], [START, 0.5], [length, -0.5], [length, 0.5]]:
			verts.append(d * float(p[0]) + w * CORE_W * float(p[1]))
			norms.append(Vector3.ZERO)
			uvs.append(Vector2(float(p[0]), float(p[1]) + 0.5))
			cols.append(Color(1, 1, 1, 1))
		idx.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh
