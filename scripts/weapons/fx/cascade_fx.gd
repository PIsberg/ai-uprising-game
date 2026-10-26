class_name CascadeFx
extends SignatureFx
## The CX-4 Cascade's signature: a tagging gun. Its round is a quick cyan dart,
## and where one lands on a robot a hexagonal tag stamps onto the plating, snaps
## down from twice its size and fades: the mark of a prime. (The prime's own
## fuse ring and the chain's link arcs live in Cascade, since chain-primed
## robots wear them too.) Covered by tests/cascade_fx_probe.

const BOLT := {"bolt_speed": 185.0, "bolt_length": 1.6, "bolt_width": 1.15}
const TAG_RADIUS := 0.22 ## metres: the stamped hexagon at full size
const TAG_TIME := 0.3

func tracer_style() -> Dictionary:
	return BOLT

func on_enemy_hit(pos: Vector3, normal: Vector3, _dir: Vector3, _dmg: float, _crit: bool) -> void:
	_tag(pos, normal)

func _tag(pos: Vector3, normal: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.BACK
	var tm := TorusMesh.new()
	tm.inner_radius = TAG_RADIUS * 0.8
	tm.outer_radius = TAG_RADIUS
	tm.rings = 6
	tm.ring_segments = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(Cascade.COLOR, 0.95)
	mat.emission_enabled = true
	mat.emission = Cascade.COLOR
	mat.emission_energy_multiplier = 7.0
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.set_meta("sig_fx", "cascade_tag")
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	# The torus lies in its XZ plane (axis +Y): turn +Y onto the surface normal.
	var up := Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(n, up) * Basis(Vector3.RIGHT, PI * 0.5), pos + n * 0.03)
	mi.scale = Vector3.ONE * 2.0
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, TAG_TIME * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, TAG_TIME).set_delay(TAG_TIME * 0.3)
	tw.chain().tween_callback(mi.queue_free)
