class_name SiegeFx
extends SignatureFx
## The SIEGE Chaingun's signature: the GUNNER's arm gun, firing in your hands the
## way it fired on the robot. A cluster of six barrels rings the bore at the
## muzzle; the trigger spins it up and letting go lets it coast down with a
## falling whine (the spin is a look, the gun fires from the first frame). The
## barrels soak heat round by round, from dark steel through the GUNNER's dull
## red to its orange, hold it while the gun runs, and smoke once it stops.
## Every round is a short fast tracer that burns whiter as the barrels heat.
## The gun drops a case and a belt link per round out of its underside instead
## of the shared brass. A stream held on a wall chews it: the hits feed one
## glowing scorch that widens and brightens while the stream stays on it and
## cools when it moves off. Rounds on a robot knock chips off its plating.
## Covered by tests/siege_fx_probe.
##
## BARRELS, SPIN_MAX, HEAT_COLD and HEAT_HOT repeat EnemyGunner's rotor values
## (naming that class here would pull the enemy graph into every gun's load);
## tests/siege_fx_probe pins each pair equal.

const BARRELS := 6
const BARREL_LEN := 0.3 ## metres, tips at the muzzle point
const BARREL_RADIUS := 0.011
const CLUSTER_RADIUS := 0.034 ## barrel centres from the bore
const PROUD := 0.22 ## metres of barrel standing out of the gun's front face
const MUZZLE_LEAD := 0.03 ## Weapon._apply_real_model parks the muzzle point this far ahead of that face
const SPIN_MAX := 30.0 ## rad/s with the trigger down
const SPIN_UP := 0.2 ## seconds from rest to SPIN_MAX
const COAST := 1.6 ## seconds from SPIN_MAX back to rest
const FIRING_GRACE := 0.15 ## seconds after a round the cluster still counts as driven (two rounds at 14/s)
const SOAK_PER_SHOT := 0.025 ## 40 rounds, a third of the belt, from cold to full
const SOAK_COOL := 0.2 ## per second, once the gun stops
const HEAT_COLD := Color(0.9, 0.12, 0.02)
const HEAT_HOT := Color(1.0, 0.42, 0.08)
const GLOW_MAX := 3.2 ## barrel emission at full soak
const TRACER := {"bolt_speed": 210.0, "bolt_length": 1.5, "bolt_width": 1.1}
const TRACER_HOT := Color(1.0, 0.95, 0.75)
const TRACER_HOT_MIX := 0.75 ## how far a fully soaked gun's tracer goes toward TRACER_HOT
const WISP_AT := 0.35 ## soak above which stopped barrels smoke
const WISP_EVERY := 0.22
const CHEW_RADIUS := 0.5 ## a hit this close to a live scorch feeds it
const CHEW_PER_HIT := 0.14
const CHEW_LIFE := 2.5 ## seconds a full scorch takes to cool
const CHEW_MIN_R := 0.12 ## metres across the glow fades out at, one round in
const CHEW_MAX_R := 0.55 ## and at full heat
const MAX_SCORCH := 5
const CHIP_EVERY := 2

## The barrel cluster, on the muzzle (null until the first frame builds it).
var rotor: Node3D = null
## Times the cluster was let go from near full speed (each one whines down).
var wind_downs := 0

var _barrel_mat: StandardMaterial3D = null
var _spin := 0.0
var _soak := 0.0
var _since_fire := 999.0
var _wisp_t := 0.0
var _robot_hits := 0
var _scorches: Array = [] ## live Scorch nodes, oldest first
var _case_mesh: CylinderMesh = null
var _link_mesh: BoxMesh = null
var _chip_mesh: BoxMesh = null

## rad/s the cluster turns at right now.
func spin() -> float:
	return _spin

## 0..1 heat soaked into the barrels.
func soak() -> float:
	return _soak

## The barrels' emission energy right now.
func glow() -> float:
	return _barrel_mat.emission_energy_multiplier if _barrel_mat else 0.0

## The barrels' emission colour right now.
func barrel_color() -> Color:
	return _barrel_mat.emission if _barrel_mat else Color.BLACK

func tracer_style() -> Dictionary:
	var d := TRACER.duplicate()
	d["color"] = _color().lerp(TRACER_HOT, _soak * TRACER_HOT_MIX)
	return d

func owns_brass() -> bool:
	return true

func owns_muzzle_smoke() -> bool:
	return true

func on_fire() -> void:
	_build()
	_since_fire = 0.0
	_soak = minf(1.0, _soak + SOAK_PER_SHOT)
	_eject()

func on_process(delta: float) -> void:
	_build()
	if rotor == null:
		return
	var was_driven := _since_fire < FIRING_GRACE
	_since_fire += delta
	var driven := _since_fire < FIRING_GRACE
	if was_driven and not driven and _spin > SPIN_MAX * 0.8:
		wind_downs += 1
		AudioBus.play_synth_at("drone_hum", rotor.global_position, -9.0, 0.55)
	_spin = move_toward(_spin, SPIN_MAX if driven else 0.0, SPIN_MAX / (SPIN_UP if driven else COAST) * delta)
	rotor.rotate_object_local(Vector3.BACK, _spin * delta)
	if driven:
		_wisp_t = 0.0
	else:
		_soak = maxf(0.0, _soak - SOAK_COOL * delta)
		if _soak >= WISP_AT:
			_wisp_t += delta
			if _wisp_t >= WISP_EVERY:
				_wisp_t = 0.0
				_wisp()
	_barrel_mat.emission = HEAT_COLD.lerp(HEAT_HOT, _soak)
	_barrel_mat.emission_energy_multiplier = _soak * _soak * GLOW_MAX

func on_world_hit(pos: Vector3, normal: Vector3, _dir: Vector3, _surface: String) -> void:
	_chew(pos, normal)

func on_enemy_hit(pos: Vector3, normal: Vector3, _dir: Vector3, _dmg: float, _crit: bool) -> void:
	_robot_hits += 1
	if _robot_hits % CHIP_EVERY == 0:
		_chip(pos, normal)

func _color() -> Color:
	var data: WeaponData = weapon.get("data")
	return data.tracer_color if data else Color(1.0, 0.5, 0.25)

## Six barrels, two clamps and a spindle on the muzzle. The muzzle point moves
## forward first (to PROUD ahead of the gun's front face), so the flash and the tracers leave the barrel tips and
## the cluster stands out of the gun's front face instead of inside it.
func _build() -> void:
	if rotor != null:
		return
	var muzzle: Node3D = weapon.get("muzzle")
	if muzzle == null:
		return
	muzzle.position.z -= PROUD - MUZZLE_LEAD
	rotor = Node3D.new()
	rotor.name = "SiegeRotor"
	rotor.set_meta("sig_fx", "siege_rotor")
	muzzle.add_child(rotor)
	_barrel_mat = StandardMaterial3D.new()
	_barrel_mat.albedo_color = Color(0.09, 0.09, 0.1)
	_barrel_mat.metallic = 0.85
	_barrel_mat.roughness = 0.35
	_barrel_mat.emission_enabled = true
	_barrel_mat.emission = HEAT_COLD
	_barrel_mat.emission_energy_multiplier = 0.0
	var tube := CylinderMesh.new()
	tube.top_radius = BARREL_RADIUS
	tube.bottom_radius = BARREL_RADIUS
	tube.height = BARREL_LEN
	tube.radial_segments = 8
	tube.rings = 1
	tube.material = _barrel_mat
	for i in BARRELS:
		var b := MeshInstance3D.new()
		b.name = "Barrel%d" % i
		b.set_meta("sig_fx", "siege_barrel")
		b.mesh = tube
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * float(i) / float(BARRELS)
		# +Z is back toward the stock: the barrels run from the muzzle point back.
		b.position = Vector3(cos(a) * CLUSTER_RADIUS, sin(a) * CLUSTER_RADIUS, BARREL_LEN * 0.5)
		b.rotation.x = PI * 0.5 # cylinder axis (Y) onto the bore (Z)
		rotor.add_child(b)
	# Clamps and spindle stay dark so the hot barrels read as barrels.
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.metallic = 0.85
	dark.roughness = 0.4
	var clamp_mesh := CylinderMesh.new()
	clamp_mesh.top_radius = CLUSTER_RADIUS + BARREL_RADIUS + 0.003
	clamp_mesh.bottom_radius = clamp_mesh.top_radius
	clamp_mesh.height = 0.018
	clamp_mesh.radial_segments = 12
	clamp_mesh.rings = 1
	clamp_mesh.material = dark
	for z: float in [0.03, PROUD - 0.03]:
		var c := MeshInstance3D.new()
		c.mesh = clamp_mesh
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.position = Vector3(0, 0, z)
		c.rotation.x = PI * 0.5
		rotor.add_child(c)
	var spindle_mesh := CylinderMesh.new()
	spindle_mesh.top_radius = 0.014
	spindle_mesh.bottom_radius = 0.014
	spindle_mesh.height = BARREL_LEN
	spindle_mesh.radial_segments = 8
	spindle_mesh.rings = 1
	spindle_mesh.material = dark
	var spindle := MeshInstance3D.new()
	spindle.mesh = spindle_mesh
	spindle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spindle.position = Vector3(0, 0, BARREL_LEN * 0.5 + 0.004)
	spindle.rotation.x = PI * 0.5
	rotor.add_child(spindle)

## One case and one belt link out of the gun's underside.
func _eject() -> void:
	var root := scene()
	var cam: Camera3D = weapon.get("_active_camera")
	if root == null or cam == null:
		return
	if _case_mesh == null:
		_case_mesh = CylinderMesh.new()
		_case_mesh.top_radius = 0.007
		_case_mesh.bottom_radius = 0.007
		_case_mesh.height = 0.036
		_case_mesh.radial_segments = 6
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color(0.85, 0.62, 0.22)
		brass.metallic = 0.85
		brass.roughness = 0.35
		brass.emission_enabled = true
		brass.emission = Color(0.6, 0.4, 0.12)
		brass.emission_energy_multiplier = 0.4
		_case_mesh.material = brass
		_link_mesh = BoxMesh.new()
		_link_mesh.size = Vector3(0.02, 0.006, 0.014)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color(0.2, 0.2, 0.22)
		steel.metallic = 0.9
		steel.roughness = 0.45
		_link_mesh.material = steel
	var right := cam.global_basis.x
	var up := cam.global_basis.y
	var at := (weapon as Node3D).global_position + right * 0.1 - up * 0.1
	var down := (right * 0.3 - up).normalized()
	_piece(root, at, down, _case_mesh, "siege_case", 1.6, 2.4)
	_piece(root, at - right * 0.02, (right * 0.1 - up).normalized(), _link_mesh, "siege_link", 1.0, 1.6)
	# The case lands a beat later (as the shared brass does); the closure holds
	# only the landing spot, so it still rings if the gun is tossed meanwhile.
	var land := at - Vector3(0, 1.2, 0) + right * randf_range(0.2, 0.5)
	weapon.get_tree().create_timer(randf_range(0.5, 0.75)).timeout.connect(
		func() -> void: AudioBus.play_synth_at("brass_tink", land, -17.0, randf_range(0.8, 1.2)))

func _piece(root: Node, at: Vector3, dir: Vector3, mesh: Mesh, tag: String, v_min: float, v_max: float) -> void:
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", tag)
	p.emitting = true
	p.one_shot = true
	p.amount = 1
	p.lifetime = 1.0
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = dir
	p.spread = 12.0
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.gravity = Vector3(0, -9.0, 0)
	p.angular_velocity_min = -900.0
	p.angular_velocity_max = 900.0
	p.mesh = mesh
	root.add_child(p)
	p.global_position = at
	weapon.get_tree().create_timer(1.3).timeout.connect(p.queue_free)

## A thread of smoke off the barrel tips, thicker the hotter they still are.
func _wisp() -> void:
	var root := scene()
	var muzzle: Node3D = weapon.get("muzzle")
	if root == null or muzzle == null:
		return
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([Color(0.75, 0.72, 0.7, 0.0), Color(0.66, 0.64, 0.63, 0.16 + 0.2 * _soak), Color(0.5, 0.5, 0.52, 0.0)])
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(1.0, 1.0))
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.056
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color.WHITE
	sm.material = smat
	var amount := 2 + int(_soak * 4.0)
	if GraphicsSettings.gpu_particles_enabled:
		amount *= 2
	var p := GraphicsSettings.create_particles(amount, 0.9, 0.3, Vector3.UP, 14.0,
			Vector3(0, 0.5, 0), 0.15, 0.4, 0.7, 1.3, sm, grad, curve)
	p.set_meta("sig_fx", "siege_wisp")
	p.set_meta("soak", _soak)
	root.add_child(p)
	p.global_position = muzzle.global_position
	weapon.get_tree().create_timer(1.2).timeout.connect(p.queue_free)

## A hit near a live scorch feeds it (and drags it toward the hit, so the glow
## follows the stream); a hit anywhere else starts a new one, the oldest going
## when there are more than MAX_SCORCH.
func _chew(pos: Vector3, normal: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var n := normal.normalized()
	# Untyped on purpose: a scorch that cooled and was freed cannot be passed to
	# a `Scorch` parameter (the call errors and the filter returns nothing).
	_scorches = _scorches.filter(func(s) -> bool: return is_instance_valid(s) and not s.is_queued_for_deletion())
	for s: Scorch in _scorches:
		if s.global_position.distance_to(pos) <= CHEW_RADIUS and s.global_basis.y.normalized().dot(n) > 0.7:
			s.global_position = s.global_position.lerp(pos + n * 0.012, 0.25)
			s.feed(CHEW_PER_HIT)
			return
	var sc := Scorch.new()
	sc.name = "SiegeScorch"
	sc.set_meta("sig_fx", "siege_scorch")
	root.add_child(sc)
	var up := Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT
	# Local +Y on the normal: the glow lies flat on the wall.
	sc.global_transform = Transform3D(Basis.looking_at(n, up) * Basis(Vector3.RIGHT, -PI * 0.5), pos + n * 0.012)
	sc.feed(CHEW_PER_HIT)
	_scorches.append(sc)
	while _scorches.size() > MAX_SCORCH:
		(_scorches.pop_front() as Scorch).queue_free()

## A flake of plating knocked off the robot, falling away from the struck face.
func _chip(pos: Vector3, normal: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	if _chip_mesh == null:
		_chip_mesh = BoxMesh.new()
		_chip_mesh.size = Vector3(0.045, 0.006, 0.03)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.16, 0.15, 0.15)
		m.metallic = 0.8
		m.roughness = 0.5
		m.emission_enabled = true
		m.emission = HEAT_HOT
		m.emission_energy_multiplier = 0.8
		_chip_mesh.material = m
	var n := normal.normalized()
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "siege_chip")
	p.emitting = true
	p.one_shot = true
	p.amount = 2
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = (n + Vector3.UP * 0.4).normalized()
	p.spread = 30.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -12.0, 0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.mesh = _chip_mesh
	root.add_child(p)
	p.global_position = pos + n * 0.03
	weapon.get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## The glow where the stream chews a wall: `feed` heats it, time cools it, and
## its size, colour and brightness follow the heat.
class Scorch extends Node3D:
	static var _falloff: GradientTexture2D = null

	var mat: StandardMaterial3D
	var heat := 0.0
	var _disc: MeshInstance3D

	func _init() -> void:
		if _falloff == null:
			var g := Gradient.new()
			# A hot core and a long soft skirt: at HDR energies a shallow falloff
			# clips to a flat hard-edged disc.
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.42), Color(1, 1, 1, 0.1), Color(1, 1, 1, 0)])
			_falloff = GradientTexture2D.new()
			_falloff.gradient = g
			_falloff.fill = GradientTexture2D.FILL_RADIAL
			_falloff.fill_from = Vector2(0.5, 0.5)
			_falloff.fill_to = Vector2(1.0, 0.5)
			_falloff.width = 64
			_falloff.height = 64
		var pm := PlaneMesh.new()
		pm.size = Vector2(2, 2) # scaled to the radius
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture = _falloff
		mat.emission_enabled = true
		mat.emission_texture = _falloff
		pm.material = mat
		_disc = MeshInstance3D.new()
		_disc.mesh = pm
		_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_disc)

	func feed(amount: float) -> void:
		heat = minf(1.0, heat + amount)
		_paint()

	## Metres across the glow reaches from its centre right now.
	func radius() -> float:
		return lerpf(SiegeFx.CHEW_MIN_R, SiegeFx.CHEW_MAX_R, heat)

	func _process(delta: float) -> void:
		_tick(delta)

	func _tick(delta: float) -> void:
		heat -= delta / SiegeFx.CHEW_LIFE
		if heat <= 0.0:
			heat = 0.0
			queue_free()
			return
		_paint()

	func _paint() -> void:
		# Dull red, through the barrels' orange, to yellow-white at full heat.
		var col := Color(0.7, 0.08, 0.02).lerp(SiegeFx.HEAT_HOT, clampf(heat * 2.0, 0.0, 1.0))
		col = col.lerp(Color(1.0, 0.9, 0.6), clampf(heat * 2.0 - 1.0, 0.0, 1.0))
		mat.albedo_color = Color(col, clampf(heat * 4.0, 0.0, 1.0))
		mat.emission = col
		mat.emission_energy_multiplier = 1.5 + 5.0 * heat
		var r := radius()
		_disc.scale = Vector3(r, 1.0, r)
