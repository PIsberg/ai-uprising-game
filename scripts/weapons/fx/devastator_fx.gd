class_name DevastatorFx
extends SignatureFx
## The GRK-X Devastator's signature: a launcher with a back end and a crater.
## Every shot blows a cone of fire and a burst of smoke out of the back of the
## tube (the backblast); where the rocket lands, a ring of dust rolls out across
## the floor to the splash radius, and burning debris litters the crater, small
## fires that burn for DEBRIS_LIFE and die down. Covered by tests/devastator_fx_probe.

const BACKBLAST_LEN := 0.9 ## metres the fire cone reaches out the back
const BACKBLAST_BACK := 0.45 ## metres behind the gun's origin the tube's rear sits
const BACKBLAST_TIME := 0.18
const RING_TIME := 0.45
const DEBRIS := 5
const DEBRIS_LIFE := 3.0
const DEBRIS_SPREAD := 0.6 ## of the splash radius the fires scatter over
const FLOOR_REACH := 3.0 ## metres below the blast a floor still takes the ring and fires

func on_fire() -> void:
	_backblast()

func on_projectile_hit(proj: Node3D, pos: Vector3) -> void:
	var root := scene()
	if root == null or not is_instance_valid(proj):
		return
	var space := proj.get_world_3d().direct_space_state
	var ground: Variant = _floor_below(space, pos)
	if ground == null:
		return
	var data: WeaponData = weapon.get("data") if is_instance_valid(weapon) else null
	var radius := data.splash_radius if data else 5.0
	_dust_ring(root, ground, radius)
	var fires := Debris.new()
	fires.name = "DevastatorDebris"
	fires.set_meta("sig_fx", "burning_debris")
	root.add_child(fires)
	fires.global_position = ground
	for i in DEBRIS:
		var a := TAU * (float(i) + randf_range(-0.3, 0.3)) / DEBRIS
		var r := radius * DEBRIS_SPREAD * randf_range(0.35, 1.0)
		var spot: Variant = _floor_below(space, (ground as Vector3) + Vector3(cos(a) * r, 1.0, sin(a) * r))
		if spot != null:
			fires.add_fire(spot)

func _floor_below(space: PhysicsDirectSpaceState3D, pos: Vector3):
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos - Vector3.UP * FLOOR_REACH)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
		return null
	return hit.position as Vector3

## Fire and smoke out the back of the tube, opposite the bore.
func _backblast() -> void:
	var root := scene()
	var muzzle: Node3D = weapon.get("muzzle")
	if root == null or muzzle == null:
		return
	var back := muzzle.global_basis.z.normalized() # the muzzle's -Z is the bore
	var rear := weapon.global_position + back * BACKBLAST_BACK
	var flame := MeshInstance3D.new()
	flame.set_meta("sig_fx", "backblast")
	var cm := CylinderMesh.new()
	cm.top_radius = 0.28 # the wide mouth, out the back
	cm.bottom_radius = 0.05
	cm.height = BACKBLAST_LEN
	cm.radial_segments = 12
	cm.material = FlameMaterial.make(Color(1.0, 0.85, 0.5), Color(1.0, 0.42, 0.12), 5.0, Vector2(0.0, 10.0), 0.5, 0.22)
	flame.mesh = cm
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	var up := Vector3.UP if absf(back.y) < 0.99 else Vector3.RIGHT
	# The cylinder's +Y (its wide top) turned onto `back`, its base at the tube's rear.
	flame.global_transform = Transform3D(Basis.looking_at(back, up) * Basis(Vector3.RIGHT, -PI * 0.5),
			rear + back * BACKBLAST_LEN * 0.5)
	flame.scale = Vector3(0.5, 0.4, 0.5)
	var tw := flame.create_tween().set_parallel(true)
	tw.tween_property(flame, "scale", Vector3.ONE * 1.2, BACKBLAST_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(e: float) -> void: (cm.material as ShaderMaterial).set_shader_parameter("emission_energy", e),
			5.0, 0.0, BACKBLAST_TIME)
	tw.chain().tween_callback(flame.queue_free)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	grad.colors = PackedColorArray([Color(0.75, 0.7, 0.66, 0.0), Color(0.62, 0.6, 0.58, 0.45), Color(0.5, 0.5, 0.5, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(1.0, 1.6))
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	var amount := 12 if not GraphicsSettings.gpu_particles_enabled else 30
	var smoke := GraphicsSettings.create_particles(amount, 1.3, 0.9, (back + Vector3.UP * 0.15).normalized(), 20.0,
			Vector3(0, 0.6, 0), 5.0, 9.0, 0.7, 1.2, sm, grad, curve)
	smoke.set_meta("sig_fx", "backblast_smoke")
	root.add_child(smoke)
	smoke.global_position = rear
	weapon.get_tree().create_timer(1.6).timeout.connect(smoke.queue_free)

## A flat ring of dust rolling out across the floor to the splash radius.
func _dust_ring(root: Node, at: Vector3, radius: float) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 0.75
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.6, 0.55, 0.48, 0.55)
	tm.material = mat
	var ring := MeshInstance3D.new()
	ring.set_meta("sig_fx", "dust_ring")
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	ring.global_position = at + Vector3.UP * 0.12
	ring.scale = Vector3(0.3, 0.6, 0.3)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 1.4, radius), RING_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, RING_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)

## Small ground fires round a crater: burn for DEBRIS_LIFE, then die down. One
## budgeted light for the lot.
class Debris extends Node3D:
	var fires: Array[MeshInstance3D] = []
	var age := 0.0
	var _light: OmniLight3D = null

	func add_fire(at: Vector3) -> void:
		var h := randf_range(0.3, 0.55)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = randf_range(0.12, 0.2)
		cm.height = h
		cm.radial_segments = 10
		cm.material = FlameMaterial.make(Color(1.0, 0.72, 0.3), Color(1.0, 0.38, 0.1), 4.0, Vector2(0.0, 9.0), 0.5, 0.24)
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = at + Vector3.UP * h * 0.5
		fires.append(mi)
		if _light == null and FXLights.take():
			_light = OmniLight3D.new()
			_light.light_color = Color(1.0, 0.5, 0.18)
			_light.omni_range = 4.0
			_light.position = Vector3.UP * 0.5
			add_child(_light)
			_light.tree_exited.connect(FXLights.give)

	## 1 burning, falling to 0 over the last third of DEBRIS_LIFE.
	func strength() -> float:
		return clampf((DevastatorFx.DEBRIS_LIFE - age) / (DevastatorFx.DEBRIS_LIFE / 3.0), 0.0, 1.0)

	func _process(delta: float) -> void:
		age += delta
		var k := strength()
		if k <= 0.0:
			queue_free()
			return
		for f in fires:
			f.scale = Vector3(1.0, k * randf_range(0.85, 1.1), 1.0)
		if _light:
			_light.light_energy = GraphicsSettings.flash_energy(2.5) * k * randf_range(0.7, 1.0)
