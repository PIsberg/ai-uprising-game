class_name OmegaFx
extends SignatureFx
## The OMEGA-X Annihilator's signature: firing a small sun. On the trigger a
## sphere of light collapses into the muzzle (the gun drawing the shot in); in
## flight the round wears a corona of CORONA_RAYS rays that turn slowly round it;
## and where it lands a pillar of light stands up out of the blast PILLAR_HEIGHT
## tall before the cluster ripples out, then thins and fades. Covered by
## tests/omega_fx_probe.

const IMPLODE_RADIUS := 0.6 ## metres the gathering sphere starts at
const IMPLODE_TIME := 0.12
const CORONA_RAYS := 6
const CORONA_LEN := 0.9 ## metres a ray reaches off the round
const CORONA_SPIN := 2.0 ## rad/s
const PILLAR_HEIGHT := 14.0
const PILLAR_RADIUS := 0.9
const PILLAR_TIME := 0.9

func on_fire() -> void:
	_implode()

func on_projectile(proj: Node3D) -> void:
	if proj == null:
		return
	var c := Corona.new()
	c.name = "OmegaCorona"
	c.set_meta("sig_fx", "omega_corona")
	c.color = _color()
	proj.add_child(c)

func on_projectile_hit(_proj: Node3D, pos: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var col := _color()
	var pillar := Node3D.new()
	pillar.name = "OmegaPillar"
	pillar.set_meta("sig_fx", "omega_pillar")
	root.add_child(pillar)
	pillar.global_position = pos
	var mats: Array[StandardMaterial3D] = []
	# A white-hot core inside a wider halo in the gun's colour.
	for layer in [[PILLAR_RADIUS * 0.35, Color.WHITE, 0.95, 10.0], [PILLAR_RADIUS, col, 0.4, 5.0]]:
		var cm := CylinderMesh.new()
		cm.top_radius = layer[0] * 0.6
		cm.bottom_radius = layer[0]
		cm.height = PILLAR_HEIGHT
		cm.radial_segments = 16
		cm.cap_top = false
		cm.cap_bottom = false
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(layer[1], layer[2])
		m.emission_enabled = true
		m.emission = layer[1]
		m.emission_energy_multiplier = layer[3]
		cm.material = m
		mats.append(m)
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3.UP * PILLAR_HEIGHT * 0.5
		pillar.add_child(mi)
	pillar.scale = Vector3(1.0, 0.05, 1.0)
	var tw := pillar.create_tween()
	tw.tween_property(pillar, "scale", Vector3.ONE, PILLAR_TIME * 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(pillar, "scale", Vector3(0.15, 1.1, 0.15), PILLAR_TIME * 0.8).set_delay(PILLAR_TIME * 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, PILLAR_TIME * 0.8).set_delay(PILLAR_TIME * 0.2)
	tw.chain().tween_callback(pillar.queue_free)

func _color() -> Color:
	var data: WeaponData = weapon.get("data") if is_instance_valid(weapon) else null
	return data.tracer_color if data else Color(1.0, 0.8, 0.35)

## A sphere of light that collapses into the muzzle.
func _implode() -> void:
	var muzzle: Node3D = weapon.get("muzzle")
	if muzzle == null:
		return
	var sm := SphereMesh.new()
	sm.radius = IMPLODE_RADIUS
	sm.height = IMPLODE_RADIUS * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(_color(), 0.15)
	m.emission_enabled = true
	m.emission = _color()
	m.emission_energy_multiplier = 3.0
	sm.material = m
	var mi := MeshInstance3D.new()
	mi.set_meta("sig_fx", "omega_implode")
	mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(mi)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.05, IMPLODE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "albedo_color:a", 0.9, IMPLODE_TIME)
	tw.tween_property(m, "emission_energy_multiplier", 12.0, IMPLODE_TIME)
	tw.chain().tween_callback(mi.queue_free)

## Rides the round: rays turning slowly round it, square to the flight axis.
class Corona extends Node3D:
	var color := Color(1.0, 0.8, 0.35)
	var rays: Array[MeshInstance3D] = []
	var _spin := 0.0

	func _ready() -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(color.lerp(Color.WHITE, 0.4), 0.8)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 6.0
		for i in OmegaFx.CORONA_RAYS:
			var q := QuadMesh.new()
			# Long along X, tapering is left to the additive falloff.
			q.size = Vector2(OmegaFx.CORONA_LEN, 0.05)
			q.center_offset = Vector3(OmegaFx.CORONA_LEN * 0.5, 0, 0)
			q.material = m
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			rays.append(mi)
		_tick(0.0)

	func _process(delta: float) -> void:
		_tick(delta)

	func _tick(delta: float) -> void:
		_spin += delta * OmegaFx.CORONA_SPIN
		# In the round's XY plane (its local Z is the flight axis).
		for i in rays.size():
			rays[i].rotation = Vector3(0.0, 0.0, _spin + TAU * i / rays.size())

	## Each ray's tip in world space (for probes).
	func tips() -> Array[Vector3]:
		var out: Array[Vector3] = []
		for r in rays:
			out.append(r.to_global(Vector3(OmegaFx.CORONA_LEN, 0, 0)))
		return out
