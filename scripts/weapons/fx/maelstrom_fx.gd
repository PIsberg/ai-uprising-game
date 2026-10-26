class_name MaelstromFx
extends SignatureFx
## The .50 Maelstrom's signature: a hand cannon. Its round is a long, fat,
## white-hot streak; two flame tongues spit straight up out of the compensator
## ports on every shot; a ring of smoke rolls forward off the muzzle, widening
## and rising as it fades, instead of the shared puff; a round that lands on a
## robot blows a spray of sparks out of its far side along the round (it
## punches through); and a round into a wall throws a crater burst, a ring of
## dust skidding out along the surface with chunks. Covered by tests/magnum_fx_probe.

const BOLT := {"bolt_speed": 260.0, "bolt_length": 3.0, "bolt_width": 2.2, "color": Color(1.0, 0.86, 0.62)}
const PORT_JET_LEN := 0.16 ## metres each compensator tongue reaches up
const PORT_SPACING := 0.035 ## metres between the two ports along the bore
const RING_RADIUS := 0.06 ## metres: the smoke ring as it leaves
const RING_SPEED := 2.6 ## m/s it rolls forward
const RING_LIFE := 1.3
const RING_GROW := 5.0 ## final scale
const EXIT_DEPTH := 0.6 ## metres behind the hit the exit spray leaves from
const CRATER_DUST := 16

func tracer_style() -> Dictionary:
	return BOLT

func owns_muzzle_smoke() -> bool:
	return true

func on_fire() -> void:
	_port_jets()
	_smoke_ring()

func on_enemy_hit(pos: Vector3, _normal: Vector3, dir: Vector3, dmg: float, _crit: bool) -> void:
	_exit_spray(pos, dir, dmg)

func on_world_hit(pos: Vector3, normal: Vector3, _dir: Vector3, surface: String) -> void:
	_crater(pos, normal, surface)

func _muzzle() -> Node3D:
	return weapon.get("muzzle")

## Two short flame tongues standing straight up from the top of the barrel just
## behind the tip: the compensator venting the blast.
func _port_jets() -> void:
	var muzzle := _muzzle()
	if muzzle == null:
		return
	for i in 2:
		var jet := MeshInstance3D.new()
		jet.set_meta("sig_fx", "port_jet")
		var cm := CylinderMesh.new()
		cm.top_radius = 0.004
		cm.bottom_radius = 0.022
		cm.height = PORT_JET_LEN
		cm.radial_segments = 8
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.78, 0.45, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.25)
		mat.emission_energy_multiplier = 9.0
		cm.material = mat
		jet.mesh = cm
		jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Cylinder axis is +Y already: up out of the top of the barrel.
		jet.position = Vector3(0, PORT_JET_LEN * 0.5 + 0.015, 0.03 + i * PORT_SPACING)
		muzzle.add_child(jet)
		jet.scale = Vector3(1.0, 0.4, 1.0)
		var tw := jet.create_tween().set_parallel(true)
		tw.tween_property(jet, "scale", Vector3(1.3, 1.0, 1.3), 0.05).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
		tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.09)
		tw.chain().tween_callback(jet.queue_free)

## A vortex ring of smoke: a soft torus that leaves the muzzle down the line of
## fire, slowing, widening and drifting up as it fades.
func _smoke_ring() -> void:
	var root := scene()
	var muzzle := _muzzle()
	if root == null or muzzle == null:
		return
	var tm := TorusMesh.new()
	tm.inner_radius = RING_RADIUS * 0.55
	tm.outer_radius = RING_RADIUS
	tm.rings = 24
	tm.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.68, 0.68, 0.7, 0.5)
	tm.material = mat
	var ring := MeshInstance3D.new()
	ring.set_meta("sig_fx", "smoke_ring")
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var fwd := -muzzle.global_basis.z.normalized()
	var start := muzzle.global_position + fwd * 0.12
	var up := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.RIGHT
	# The torus axis (+Y) turned onto the line of fire.
	ring.global_transform = Transform3D(Basis.looking_at(fwd, up) * Basis(Vector3.RIGHT, -PI * 0.5), start)
	var end := start + fwd * RING_SPEED * RING_LIFE * 0.6 + Vector3.UP * 0.35
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "global_position", end, RING_LIFE).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "scale", Vector3.ONE * RING_GROW, RING_LIFE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, RING_LIFE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)

## The round goes on through: sparks and chips blown out of the robot's far
## side along the line of fire, more for a heavier hit.
func _exit_spray(pos: Vector3, dir: Vector3, dmg: float) -> void:
	var root := scene()
	if root == null:
		return
	var d := dir.normalized()
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "exit_spray")
	p.one_shot = true
	p.emitting = true
	p.local_coords = false
	p.amount = clampi(int(10 + dmg * 0.15), 10, 30)
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = d
	p.spread = 18.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 15.0
	p.gravity = Vector3(0, -14.0, 0)
	var dart := BoxMesh.new()
	dart.size = Vector3(0.014, 0.014, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.75, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.3)
	mat.emission_energy_multiplier = 7.0
	dart.material = mat
	p.mesh = dart
	root.add_child(p)
	p.global_position = pos + d * EXIT_DEPTH
	weapon.get_tree().create_timer(0.9).timeout.connect(p.queue_free)

## A crater burst: dust skidding out along the struck surface in a ring, chunks
## kicked off it, a beat of heavier dust where it landed.
func _crater(pos: Vector3, normal: Vector3, surface: String) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized()
	var dust_col := Color(0.55, 0.45, 0.33) if surface == "dirt" else Color(0.7, 0.68, 0.64)
	var node := Node3D.new()
	node.set_meta("sig_fx", "crater")
	root.add_child(node)
	node.global_position = pos + n * 0.04
	var up := Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT
	# Local +Y along the normal: the ring spreads in the local XZ plane.
	node.global_basis = Basis.looking_at(n, up) * Basis(Vector3.RIGHT, -PI * 0.5)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors = PackedColorArray([Color(dust_col, 0.0), Color(dust_col, 0.5), Color(dust_col, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.0))
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color.WHITE
	sm.material = smat
	var ring := CPUParticles3D.new()
	ring.name = "DustRing"
	ring.one_shot = true
	ring.emitting = true
	ring.local_coords = true
	ring.amount = CRATER_DUST
	ring.lifetime = 0.9
	ring.explosiveness = 0.95
	# Flat spray: direction along local +Y tipped fully over (spread 90) and the
	# vertical flattened, so the puffs skid out across the surface.
	ring.direction = Vector3(1, 0, 0)
	ring.spread = 180.0
	ring.flatness = 1.0
	ring.initial_velocity_min = 2.0
	ring.initial_velocity_max = 3.5
	ring.damping_min = 3.0
	ring.damping_max = 4.0
	ring.gravity = Vector3.ZERO
	ring.mesh = sm
	ring.color_ramp = grad
	ring.scale_amount_curve = curve
	node.add_child(ring)
	var chunks := CPUParticles3D.new()
	chunks.one_shot = true
	chunks.emitting = true
	chunks.local_coords = false
	chunks.amount = 8
	chunks.lifetime = 0.7
	chunks.explosiveness = 1.0
	chunks.direction = n
	chunks.spread = 40.0
	chunks.initial_velocity_min = 4.0
	chunks.initial_velocity_max = 8.0
	chunks.gravity = Vector3(0, -18.0, 0)
	chunks.angular_velocity_min = -720.0
	chunks.angular_velocity_max = 720.0
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.06, 0.05, 0.06)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = dust_col.darkened(0.35)
	chunk.material = cmat
	chunks.mesh = chunk
	node.add_child(chunks)
	weapon.get_tree().create_timer(1.3).timeout.connect(node.queue_free)
