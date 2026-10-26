class_name ArcBolt
extends Node3D
## A jagged electric arc drawn as a chain of thin glowing box segments, not an
## ImmediateMesh line (a line draws one pixel wide whatever the distance, which
## at 4K reads as a hair). `zap(a, b, amp)` lays the chain along a fresh random
## polyline from a to b in world space, widest mid-span, so calling it every
## frame makes the arc crawl. One shared additive material per bolt; `set_alpha`
## fades it. Used by the Cascade's chain links and the Tesla's electrocution cage.

var segments: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _base_alpha := 1.0

## A bolt of `segs` links `width` metres thick in `color` (tinted toward white
## for the hot core).
static func make(segs: int, width: float, color: Color) -> ArcBolt:
	var b := ArcBolt.new()
	b._mat = StandardMaterial3D.new()
	b._mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b._mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b._mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	b._mat.albedo_color = Color(color.lerp(Color.WHITE, 0.45), 1.0)
	b._mat.emission_enabled = true
	b._mat.emission = color
	b._mat.emission_energy_multiplier = 6.0
	var box := BoxMesh.new()
	box.size = Vector3(width, width, 1.0)
	box.material = b._mat
	for i in segs:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true # placed in world space by zap()
		b.add_child(mi)
		b.segments.append(mi)
	return b

## Lay the chain from `a` to `b` (world space) along a new jagged path whose
## kinks stray up to `amp` metres off the straight line, most at mid-span.
func zap(a: Vector3, b: Vector3, amp: float) -> void:
	var n := segments.size()
	if n == 0:
		return
	var d := b - a
	var dist := d.length()
	if dist < 0.001:
		for s in segments:
			s.visible = false
		return
	var dn := d / dist
	var side := dn.cross(Vector3.UP if absf(dn.y) < 0.95 else Vector3.RIGHT).normalized()
	var lift := side.cross(dn).normalized()
	var prev := a
	for i in n:
		var t := float(i + 1) / n
		var p := a + d * t
		if i < n - 1:
			var k := amp * sin(PI * t)
			p += side * randf_range(-k, k) + lift * randf_range(-k, k)
		_stretch(segments[i], prev, p)
		prev = p

## Fade the whole bolt (1 = full).
func set_alpha(a: float) -> void:
	_mat.albedo_color.a = a
	_mat.emission_energy_multiplier = 6.0 * a

func alpha() -> float:
	return _mat.albedo_color.a

## Every segment's two ends in world space, in order (for probes).
func points() -> PackedVector3Array:
	var out := PackedVector3Array()
	for s in segments:
		# looking_at points -Z along the segment, so +Z leads back to its start.
		var half := s.global_basis.z * 0.5
		out.append(s.global_position + half)
		out.append(s.global_position - half)
	return out

func _stretch(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var dn := d / l
	var up := Vector3.UP if absf(dn.y) < 0.99 else Vector3.RIGHT
	mi.extra_cull_margin = l
	mi.global_transform = Transform3D(Basis.looking_at(dn, up) * Basis.from_scale(Vector3(1, 1, l)), (a + b) * 0.5)
