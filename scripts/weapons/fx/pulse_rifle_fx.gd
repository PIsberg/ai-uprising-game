class_name PulseRifleFx
extends SignatureFx
## The AR-7 Pulse Rifle's signature: a belt-fed rhythm. Every third round is a
## long, bright tracer and the two between it are short dim beads, so sustained
## fire reads as a stream with a pulse in it, the way a tracer belt does. The
## barrel shows its work: past HAZE_HEAT a heat shimmer wobbles the air above
## the muzzle (shaders/heat_haze.gdshader) and thickens as the gun gets hotter,
## and instead of a puff per shot a thin smoke streamer leaves the muzzle, denser
## the hotter the barrel. A round on a robot throws spall: sparks skating off
## along the plating instead of straight back. Covered by tests/rifle_fx_probe.

const TRACER_EVERY := 3 ## every Nth round is the long bright one
const LONG := {"bolt_speed": 170.0, "bolt_length": 3.2, "bolt_width": 1.9}
const SHORT := {"bolt_speed": 190.0, "bolt_length": 0.8, "bolt_width": 0.75}
const HAZE_HEAT := 0.35 ## barrel heat (0..1) at which the shimmer shows
const HAZE_SIZE := Vector2(0.14, 0.26) ## metres: the curtain quad over the muzzle
const HAZE_STRENGTH := 0.018 ## shader strength at full heat
const STREAMER_MIN := 2
const STREAMER_PER_HEAT := 8.0
const SPALL_COLOR := Color(1.0, 0.72, 0.35)

var _round := 0
var _haze: MeshInstance3D = null
var _haze_mat: ShaderMaterial = null

func tracer_style() -> Dictionary:
	_round += 1
	if _round % TRACER_EVERY == 0:
		var d := LONG.duplicate()
		d["color"] = _tracer_color().lerp(Color.WHITE, 0.45)
		return d
	return SHORT

## This round's number since the gun was built (the probe reads the rhythm off it).
func round_index() -> int:
	return _round

func owns_muzzle_smoke() -> bool:
	return true

func on_fire() -> void:
	_streamer()

func on_process(_delta: float) -> void:
	_update_haze()

func on_enemy_hit(pos: Vector3, normal: Vector3, dir: Vector3, dmg: float, _crit: bool) -> void:
	_spall(pos, normal, dir, dmg)

func _tracer_color() -> Color:
	var data: WeaponData = weapon.get("data")
	return data.tracer_color if data else Color(1.0, 0.78, 0.35)

func _heat() -> float:
	var h: Variant = weapon.get("_heat")
	return float(h) if h != null else 0.0

## A thin ribbon of smoke off the muzzle, denser the hotter the barrel.
func _streamer() -> void:
	var root := scene()
	var muzzle: Node3D = weapon.get("muzzle")
	if root == null or muzzle == null:
		return
	var heat := _heat()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors = PackedColorArray([Color(0.7, 0.7, 0.72, 0.0), Color(0.62, 0.62, 0.65, 0.22 + 0.18 * heat), Color(0.5, 0.5, 0.53, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(1.0, 1.0))
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color.WHITE
	sm.material = smat
	var amount := STREAMER_MIN + int(heat * STREAMER_PER_HEAT)
	if GraphicsSettings.gpu_particles_enabled:
		amount *= 2
	var fwd := -muzzle.global_basis.z
	var p := GraphicsSettings.create_particles(amount, 0.8, 0.4, (fwd * 0.6 + Vector3.UP * 0.4).normalized(), 10.0,
			Vector3(0, 0.7, 0), 0.5, 1.2, 0.8, 1.2, sm, grad, curve)
	p.set_meta("sig_fx", "pulse_streamer")
	p.set_meta("heat", heat)
	root.add_child(p)
	p.global_position = muzzle.global_position + fwd * 0.05
	weapon.get_tree().create_timer(1.1).timeout.connect(p.queue_free)

## The shimmer curtain over the muzzle: built once, shown past HAZE_HEAT, its
## strength following the heat.
func _update_haze() -> void:
	var muzzle: Node3D = weapon.get("muzzle")
	if muzzle == null:
		return
	var heat := _heat()
	if _haze == null:
		if heat < HAZE_HEAT:
			return
		_haze = MeshInstance3D.new()
		_haze.set_meta("sig_fx", "heat_haze")
		var q := QuadMesh.new()
		q.size = HAZE_SIZE
		_haze.mesh = q
		_haze_mat = ShaderMaterial.new()
		_haze_mat.shader = load("res://shaders/heat_haze.gdshader")
		_haze_mat.set_shader_parameter("speed", 3.2)
		_haze.material_override = _haze_mat
		_haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A vertical curtain standing on the barrel just behind the tip, its face
		# across the bore so the eye looks through it down the gun.
		_haze.position = Vector3(0, HAZE_SIZE.y * 0.5 + 0.02, 0.06)
		muzzle.add_child(_haze)
	var on := heat >= HAZE_HEAT
	_haze.visible = on
	if on:
		var k := clampf((heat - HAZE_HEAT) / (1.0 - HAZE_HEAT), 0.0, 1.0)
		_haze_mat.set_shader_parameter("strength", HAZE_STRENGTH * (0.35 + 0.65 * k))

## Sparks skating off along the plating: the round's travel projected onto the
## struck face, so they fly across the robot, not back at you.
func _spall(pos: Vector3, normal: Vector3, dir: Vector3, dmg: float) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized()
	var tangent := dir - n * dir.dot(n)
	if tangent.length() < 0.05:
		tangent = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT)
	tangent = tangent.normalized()
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "spall")
	p.one_shot = true
	p.emitting = true
	p.local_coords = false
	p.amount = clampi(8 + int(dmg * 0.2), 8, 18)
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = tangent
	p.spread = 22.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	var dart := BoxMesh.new()
	dart.size = Vector3(0.01, 0.01, 0.07)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = SPALL_COLOR
	mat.emission_enabled = true
	mat.emission = SPALL_COLOR
	mat.emission_energy_multiplier = 6.0
	dart.material = mat
	p.mesh = dart
	root.add_child(p)
	p.global_position = pos + n * 0.02
	weapon.get_tree().create_timer(0.8).timeout.connect(p.queue_free)
