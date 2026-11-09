class_name PalmFx
extends SignatureFx
## The PALM Cannon's signature: the gun is a stilt MECH's hand, and it fires like
## one. An iris of RINGS rings stands on the bore ahead of the muzzle: a shot
## throws them open and dark, and they close one after another as the gun's own
## cooldown runs out, so the iris is the ready light. The bolt flies inside a
## halo ring and leaves an echo ring hanging in the air every SHED_EVERY metres.
## Where it goes off a clap ring spreads to the splash radius (the reach of the
## blast, drawn), and the surface it struck keeps a glowing handprint that cools
## over BRAND_LIFE. Covered by tests/palm_fx_probe.

const RINGS := 3
const RING_RADIUS := 0.045 ## metres, a closed iris ring
const RING_FIRST := 0.03 ## metres ahead of the muzzle point, the nearest ring
const RING_GAP := 0.045 ## metres between rings along the bore
const OPEN := 2.4 ## a spent ring's scale
const HALO_RADIUS := 0.24
const SHED_EVERY := 2.5 ## metres of flight between echo rings
const ECHO_LIFE := 0.6
const CLAP_TIME := 0.28
const FINGERS := 5
const PALM_RADIUS := 0.3
const FINGER_LEN := 0.4
const BRAND_LIFE := 4.0
## Render layer of the handprint's meshes. Not layer 1: the blast's own
## ScorchDecal (cull_mask 1) lands on the same spot and charred the print black.
const BRAND_LAYER := 2
## Each finger's angle off straight ahead (rad) and its length as a share of FINGER_LEN; the last is the thumb.
const FINGER_FAN := [[-0.75, 0.8], [-0.3, 1.0], [0.05, 1.08], [0.4, 0.95], [1.15, 0.7]]

var _iris: Iris = null

func on_process(_delta: float) -> void:
	if not is_instance_valid(weapon):
		return
	if not is_instance_valid(_iris):
		var muzzle: Node3D = weapon.get("muzzle")
		if muzzle == null:
			return
		_iris = Iris.new()
		_iris.name = "PalmIris"
		_iris.set_meta("sig_fx", "palm_iris")
		_iris.color = _color()
		muzzle.add_child(_iris)
	# The gun's cooldown is the charge: 1/fire_rate after a shot, 0 when ready.
	var cd: float = weapon.get("_cooldown")
	_iris.set_charge(1.0 - clampf(cd * float(weapon.call("eff_fire_rate")), 0.0, 1.0))

func on_projectile(proj: Node3D) -> void:
	if proj == null:
		return
	var halo := Halo.new()
	halo.name = "PalmHalo"
	halo.set_meta("sig_fx", "palm_halo")
	halo.color = _color()
	halo.root = scene()
	proj.add_child(halo)

func on_projectile_hit(proj: Node3D, pos: Vector3) -> void:
	var root := scene()
	if root == null or not is_instance_valid(proj):
		return
	var halo := proj.get_node_or_null("PalmHalo") as Halo
	if halo:
		halo.shed_to(pos) # the last stretch of flight, which the halo's own frame never saw
	var dir := Vector3.FORWARD
	var vel = proj.get("_velocity")
	if vel is Vector3 and (vel as Vector3).length() > 0.01:
		dir = (vel as Vector3).normalized()
	# The face the bolt struck: a world-only ray along its path through the blast
	# point (a bolt that burst on a robot or in the air finds none).
	var hit := {}
	var world := proj.get_world_3d()
	if world and world.direct_space_state:
		var q := PhysicsRayQueryParameters3D.create(pos - dir * 0.6, pos + dir * 0.9)
		q.collision_mask = 1
		hit = world.direct_space_state.intersect_ray(q)
	var normal := -dir
	var at := pos
	var struck := not hit.is_empty() and (hit.normal as Vector3).length() > 0.5
	if struck:
		normal = (hit.normal as Vector3).normalized()
		at = (hit.position as Vector3) + normal * 0.02
	var data: WeaponData = weapon.get("data") if is_instance_valid(weapon) else null
	var clap := Clap.new()
	clap.set_meta("sig_fx", "palm_clap")
	clap.color = _color()
	clap.radius = data.splash_radius if data and data.splash_radius > 0.0 else 2.0
	clap.transform = Transform3D(_basis_on(normal, dir), at + normal * 0.03)
	root.add_child(clap)
	if not struck:
		return
	var brand := Brand.new()
	brand.name = "PalmBrand"
	brand.set_meta("sig_fx", "palm_brand")
	brand.color = _color()
	brand.transform = Transform3D(_basis_on(normal, dir), at)
	root.add_child(brand)

func _color() -> Color:
	var data: WeaponData = weapon.get("data") if is_instance_valid(weapon) else null
	return data.tracer_color if data else Color(0.55, 0.85, 1.0)

## A basis lying on a face: Y out of it along `normal`, -Z (the way the fingers
## point) up the face on a wall and along the shot on a floor or ceiling.
static func _basis_on(normal: Vector3, dir: Vector3) -> Basis:
	var y := normal.normalized()
	var want := Vector3.UP if absf(y.y) < 0.7 else dir
	var fwd := want - y * want.dot(y)
	if fwd.length() < 0.05:
		fwd = y.cross(Vector3.RIGHT)
		if fwd.length() < 0.05:
			fwd = y.cross(Vector3.FORWARD)
	fwd = fwd.normalized()
	var z := -fwd
	return Basis(y.cross(z).normalized(), y, z)

static func _glow(c: Color, energy: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(c, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m

## A torus ring of `radius` whose axis is the node's local Y.
static func _ring(radius: float, thick: float, mat: Material) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.outer_radius = radius
	tm.inner_radius = maxf(0.001, radius - thick)
	tm.rings = 24
	tm.ring_segments = 6
	tm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## The ready light: RINGS rings on the bore ahead of the muzzle. `charge` 0 is a
## spent shot (every ring OPEN and dark), 1 is ready (tight and bright); between,
## the rings close one after another, the far one first.
class Iris extends Node3D:
	const DIM := 0.5
	const BRIGHT := 6.0
	var color := Color(0.55, 0.85, 1.0)
	var rings: Array[MeshInstance3D] = []
	var charge := 1.0
	var _mats: Array[StandardMaterial3D] = []

	func _ready() -> void:
		for i in PalmFx.RINGS:
			var mat := PalmFx._glow(color, BRIGHT, 0.9)
			var mi := PalmFx._ring(PalmFx.RING_RADIUS, 0.007, mat)
			mi.rotation.x = PI * 0.5 # the torus' axis onto the bore
			mi.position.z = -(PalmFx.RING_FIRST + PalmFx.RING_GAP * i)
			add_child(mi)
			rings.append(mi)
			_mats.append(mat)
		set_charge(charge)

	func set_charge(c: float) -> void:
		charge = clampf(c, 0.0, 1.0)
		for i in rings.size():
			# Ring i's own share of the charge: the far ring (last) closes first.
			var k := clampf(charge * rings.size() - (rings.size() - 1 - i), 0.0, 1.0)
			var s := lerpf(PalmFx.OPEN, 1.0, k)
			rings[i].scale = Vector3(s, 1.0, s)
			_mats[i].emission_energy_multiplier = lerpf(DIM, BRIGHT, k * k)
			_mats[i].albedo_color.a = lerpf(0.25, 0.9, k)

	func energy_of(i: int) -> float:
		return _mats[i].emission_energy_multiplier

## Rides the bolt: one ring square to its flight, and an echo of it left hanging
## in the air every SHED_EVERY metres flown.
class Halo extends Node3D:
	var color := Color(0.55, 0.85, 1.0)
	var root: Node = null
	var ring: MeshInstance3D
	var _last := Vector3.ZERO
	var _t := 0.0

	func _ready() -> void:
		ring = PalmFx._ring(PalmFx.HALO_RADIUS, 0.03, PalmFx._glow(color.lerp(Color.WHITE, 0.4), 5.0, 0.8))
		ring.rotation.x = PI * 0.5 # the bolt's local Z is its flight axis
		add_child(ring)
		_last = global_position

	func _process(delta: float) -> void:
		_t += delta
		var s := 1.0 + 0.1 * sin(_t * 31.0)
		ring.scale = Vector3(s, 1.0, s)
		shed_to(global_position)

	## Leave every echo owed between the last one and `to`.
	func shed_to(to: Vector3) -> void:
		while _last.distance_to(to) >= PalmFx.SHED_EVERY:
			_last = _last.move_toward(to, PalmFx.SHED_EVERY)
			if is_instance_valid(root):
				var e := Echo.new()
				e.set_meta("sig_fx", "palm_echo")
				e.color = color
				e.transform = Transform3D(ring.global_basis.orthonormalized(), _last)
				root.add_child(e)

## A ring left behind in the air: widens and fades over ECHO_LIFE.
class Echo extends Node3D:
	var color := Color(0.55, 0.85, 1.0)
	var age := 0.0
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_mat = PalmFx._glow(color, 3.0, 0.6)
		add_child(PalmFx._ring(PalmFx.HALO_RADIUS, 0.018, _mat))

	func _process(delta: float) -> void:
		age += delta
		var k := clampf(age / PalmFx.ECHO_LIFE, 0.0, 1.0)
		var s := 1.0 + 0.8 * k
		scale = Vector3(s, 1.0, s)
		_mat.albedo_color.a = 0.6 * (1.0 - k)
		_mat.emission_energy_multiplier = 3.0 * (1.0 - k)
		if age >= PalmFx.ECHO_LIFE:
			queue_free()

## The blast's reach, drawn: a ring that spreads to `radius` in CLAP_TIME and fades.
class Clap extends Node3D:
	var color := Color(0.55, 0.85, 1.0)
	var radius := 3.5
	var age := 0.0
	var _mat: StandardMaterial3D

	func _ready() -> void:
		_mat = PalmFx._glow(color.lerp(Color.WHITE, 0.3), 5.0, 0.8)
		add_child(PalmFx._ring(1.0, 0.04, _mat))
		_tick(0.0)

	func _process(delta: float) -> void:
		_tick(delta)
		if age >= PalmFx.CLAP_TIME * 1.6:
			queue_free()

	func _tick(delta: float) -> void:
		age += delta
		var k := clampf(age / PalmFx.CLAP_TIME, 0.0, 1.0)
		var s := lerpf(0.15, 1.0, 1.0 - (1.0 - k) * (1.0 - k)) * radius
		scale = Vector3(s, 1.0, s)
		var fade := clampf(1.0 - (age - PalmFx.CLAP_TIME) / (PalmFx.CLAP_TIME * 0.6), 0.0, 1.0)
		_mat.albedo_color.a = 0.8 * fade
		_mat.emission_energy_multiplier = 5.0 * fade

## The handprint: a palm and FINGERS fingers lying on the struck face (local Y
## out of it, fingers toward -Z), cooling from white-hot through the gun's
## colour to dark, then gone.
class Brand extends Node3D:
	var color := Color(0.55, 0.85, 1.0)
	var palm: MeshInstance3D
	var fingers: Array[MeshInstance3D] = []
	var mat: StandardMaterial3D
	var age := 0.0
	var _light: OmniLight3D = null

	func _ready() -> void:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		var cm := CylinderMesh.new()
		cm.top_radius = PalmFx.PALM_RADIUS
		cm.bottom_radius = PalmFx.PALM_RADIUS
		cm.height = 0.008
		cm.radial_segments = 20
		cm.material = mat
		palm = MeshInstance3D.new()
		palm.mesh = cm
		palm.scale = Vector3(0.9, 1.0, 1.1)
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		palm.layers = PalmFx.BRAND_LAYER
		add_child(palm)
		for f in PalmFx.FINGER_FAN:
			var a: float = f[0]
			var length: float = PalmFx.FINGER_LEN * float(f[1])
			var bm := BoxMesh.new()
			bm.size = Vector3(0.11, 0.008, length)
			bm.material = mat
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = PalmFx.BRAND_LAYER
			# Rooted just inside the palm's rim, reaching out along its own angle.
			mi.position = Vector3(sin(a), 0.0, -cos(a)) * (PalmFx.PALM_RADIUS * 0.85 + length * 0.5)
			mi.rotation.y = -a
			add_child(mi)
			fingers.append(mi)
		if FXLights.take():
			_light = OmniLight3D.new()
			_light.light_color = color
			_light.omni_range = 2.5
			_light.position = Vector3.UP * 0.3
			add_child(_light)
			_light.tree_exited.connect(FXLights.give)
		_tick(0.0)

	## 1 freshly struck, 0 cold.
	func heat() -> float:
		return clampf(1.0 - age / PalmFx.BRAND_LIFE, 0.0, 1.0)

	func _process(delta: float) -> void:
		_tick(delta)
		if age >= PalmFx.BRAND_LIFE:
			queue_free()

	func _tick(delta: float) -> void:
		age += delta
		var k := heat()
		var hot := Color.WHITE.lerp(color, clampf((1.0 - k) * 2.5, 0.0, 1.0))
		var col := hot.lerp(Color(0.04, 0.05, 0.07), clampf((0.5 - k) * 2.0, 0.0, 1.0))
		# Unshaded draws albedo alone, so the heat goes into it: over 1 while hot, which blooms.
		var gain := 1.0 + 2.5 * k * k
		mat.albedo_color = Color(col.r * gain, col.g * gain, col.b * gain, clampf(k * 1.8, 0.0, 0.92))
		mat.emission = col
		mat.emission_energy_multiplier = 5.0 * k * k
		if _light:
			_light.light_energy = GraphicsSettings.flash_energy(2.0) * k
