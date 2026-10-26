class_name PlasmaFx
extends SignatureFx
## The PL-1 Plasma Launcher's signature: a round that is alive. In flight two
## motes orbit the ball round its line of travel and its outer shell wobbles and
## pulses, so it reads as contained plasma rather than a glowing marble. Where it
## goes off a crown of molten droplets flies out and up, and a pool of plasma
## spreads on the floor below, bubbling, cooling from white-hot through the
## gun's colour to dark over POOL_LIFE. Covered by tests/plasma_fx_probe.

const MOTES := 2
const MOTE_RADIUS := 0.2 ## metres the motes orbit off the round's axis
const MOTE_SPIN := 16.0 ## rad/s
const SHELL_RADIUS := 0.2
const POOL_RADIUS := 0.75
const POOL_LIFE := 3.5
const POOL_DROP := 2.5 ## metres below the blast a floor still takes a pool
const CROWN_DROPS := 18

func on_projectile(proj: Node3D) -> void:
	if proj == null:
		return
	var rig := Orbit.new()
	rig.name = "PlasmaOrbit"
	rig.set_meta("sig_fx", "plasma_orbit")
	rig.color = _color()
	proj.add_child(rig)

func on_projectile_hit(proj: Node3D, pos: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	_crown(root, pos)
	var space: PhysicsDirectSpaceState3D = proj.get_world_3d().direct_space_state if is_instance_valid(proj) else null
	if space == null:
		return
	# Drop from a point pulled back along the round's path: a blast on a wall's
	# face would start the ray on the wall and hit it (with a zero normal).
	var back := Vector3.ZERO
	var vel = proj.get("_velocity") if is_instance_valid(proj) else null
	if vel is Vector3 and (vel as Vector3).length() > 0.01:
		back = -(vel as Vector3).normalized() * 0.3
	var top := pos + back + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(top, top - Vector3.UP * (POOL_DROP + 0.3))
	q.collision_mask = 1 # world only: robots do not hold a pool
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
		return
	var pool := Pool.new()
	pool.name = "PlasmaPool"
	pool.set_meta("sig_fx", "plasma_pool")
	pool.color = _color()
	root.add_child(pool)
	pool.global_position = (hit.position as Vector3) + Vector3.UP * 0.02

func _color() -> Color:
	var data: WeaponData = weapon.get("data") if is_instance_valid(weapon) else null
	return data.tracer_color if data else Color(0.3, 0.85, 0.7)

## Molten droplets flung out and up from the blast, falling back.
func _crown(root: Node, pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "plasma_crown")
	p.one_shot = true
	p.emitting = true
	p.local_coords = false
	p.amount = CROWN_DROPS
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 7.5
	p.gravity = Vector3(0, -16.0, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	sm.radial_segments = 6
	sm.rings = 3
	var col := _color()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col.lerp(Color.WHITE, 0.5)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 7.0
	sm.material = mat
	p.mesh = sm
	root.add_child(p)
	p.global_position = pos
	weapon.get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## Rides the round: MOTES motes circling its line of travel, and a wobbling shell.
class Orbit extends Node3D:
	var color := Color(0.3, 0.85, 0.7)
	var motes: Array[MeshInstance3D] = []
	var shell: MeshInstance3D
	var _t := 0.0

	func _ready() -> void:
		for i in PlasmaFx.MOTES:
			var sm := SphereMesh.new()
			sm.radius = 0.035
			sm.height = 0.07
			sm.radial_segments = 6
			sm.rings = 3
			sm.material = _glow(color.lerp(Color.WHITE, 0.6), 9.0, 1.0)
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			motes.append(mi)
		var ss := SphereMesh.new()
		ss.radius = PlasmaFx.SHELL_RADIUS
		ss.height = PlasmaFx.SHELL_RADIUS * 2.0
		ss.radial_segments = 12
		ss.rings = 6
		ss.material = _glow(color, 3.0, 0.28)
		shell = MeshInstance3D.new()
		shell.mesh = ss
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shell)
		_tick(0.0)

	func _process(delta: float) -> void:
		_tick(delta)

	func _tick(delta: float) -> void:
		_t += delta
		# The round's local Z is its flight axis (projectile.gd faces its velocity).
		for i in motes.size():
			var a := _t * PlasmaFx.MOTE_SPIN + TAU * i / motes.size()
			motes[i].position = Vector3(cos(a), sin(a), 0.0) * PlasmaFx.MOTE_RADIUS
		var w := 1.0 + 0.12 * sin(_t * 23.0)
		var h := 1.0 + 0.12 * sin(_t * 17.0 + 1.3)
		shell.scale = Vector3(w, h, 2.0 - w)

	func _glow(c: Color, energy: float, alpha: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(c, alpha)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		return m

## A molten pool on the floor: spreads out fast, bubbles, cools from white-hot
## through the gun's colour to dark, then frees itself.
class Pool extends Node3D:
	var color := Color(0.3, 0.85, 0.7)
	var disc: MeshInstance3D
	var mat: StandardMaterial3D
	var age := 0.0
	var _light: OmniLight3D = null

	func _ready() -> void:
		var cm := CylinderMesh.new()
		cm.top_radius = PlasmaFx.POOL_RADIUS
		cm.bottom_radius = PlasmaFx.POOL_RADIUS
		cm.height = 0.01
		cm.radial_segments = 24
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		cm.material = mat
		disc = MeshInstance3D.new()
		disc.mesh = cm
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(disc)
		if FXLights.take():
			_light = OmniLight3D.new()
			_light.light_color = color
			_light.omni_range = 2.5
			_light.position = Vector3.UP * 0.3
			add_child(_light)
			_light.tree_exited.connect(FXLights.give)
		_tick(0.0)

	## 1 freshly poured, 0 cold.
	func heat() -> float:
		return clampf(1.0 - age / PlasmaFx.POOL_LIFE, 0.0, 1.0)

	func _process(delta: float) -> void:
		_tick(delta)
		if age >= PlasmaFx.POOL_LIFE:
			queue_free()

	func _tick(delta: float) -> void:
		age += delta
		var k := heat()
		# Spreads to full size in the first 0.15 s, then bubbles.
		var spread := clampf(age / 0.15, 0.25, 1.0)
		var bubble := 1.0 + 0.04 * sin(age * 19.0) * k
		disc.scale = Vector3(spread * bubble, 1.0, spread * (2.0 - bubble))
		# White-hot -> the gun's colour -> dark ember.
		var hot := Color.WHITE.lerp(color, clampf((1.0 - k) * 2.0, 0.0, 1.0))
		var col := hot.lerp(Color(0.05, 0.08, 0.07), clampf((0.5 - k) * 2.0, 0.0, 1.0))
		mat.albedo_color = Color(col, clampf(k * 1.6, 0.0, 0.95))
		mat.emission = col
		mat.emission_energy_multiplier = 6.0 * k * k
		if _light:
			_light.light_energy = GraphicsSettings.flash_energy(2.5) * k
