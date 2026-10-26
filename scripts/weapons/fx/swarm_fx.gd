class_name SwarmFx
extends SignatureFx
## The SW-7 Swarm Launcher's signature: a swarm, not three rockets. Each
## micro-rocket's body corkscrews round its true path (the collision stays on
## the path; only the visible rocket spirals), the three of a volley a third of
## a turn apart, each laying its own smoke thread, so a volley braids. A robot a
## rocket has locked on to wears a spinning lock diamond for as long as any
## rocket holds it, so you can see who the swarm is going for; and each rocket
## goes off in a starburst of hot shrapnel streaks. Covered by tests/swarm_fx_probe.

const CORK_RADIUS := 0.14 ## metres the body swings off the true path
const CORK_SPIN := 25.0 ## rad/s: about one turn every 8.5 m at 34 m/s
const LOCK_NAME := "SwarmLock"
const LOCK_SIZE := 0.55 ## metres corner to corner
const LOCK_HOLD := 0.3 ## seconds a lock lingers once no rocket holds it
const SHRAPNEL := 12

var _volley := 0 ## rockets launched, for the phase offset

func on_projectile(proj: Node3D) -> void:
	if proj == null:
		return
	var rig := Cork.new()
	rig.name = "SwarmCork"
	rig.set_meta("sig_fx", "swarm_cork")
	rig.phase = TAU * float(_volley % 3) / 3.0
	_volley += 1
	proj.add_child(rig)

func on_projectile_hit(_proj: Node3D, pos: Vector3) -> void:
	var root := scene()
	if root == null:
		return
	var p := CPUParticles3D.new()
	p.set_meta("sig_fx", "swarm_shrapnel")
	p.one_shot = true
	p.emitting = true
	p.local_coords = false
	p.amount = SHRAPNEL
	p.lifetime = 0.35
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 15.0
	p.gravity = Vector3(0, -10.0, 0)
	var dart := BoxMesh.new()
	dart.size = Vector3(0.012, 0.14, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.25)
	mat.emission_energy_multiplier = 7.0
	dart.material = mat
	p.mesh = dart
	# Streaks fly nose-first: the dart's long Y axis turned onto its velocity.
	p.particle_flag_align_y = true
	root.add_child(p)
	p.global_position = pos
	weapon.get_tree().create_timer(0.8).timeout.connect(p.queue_free)

## Rides one rocket: swings its visible body round the true path and trails a
## smoke thread from it, and keeps a lock diamond on whatever it is homing on.
class Cork extends Node3D:
	var phase := 0.0
	var body: MeshInstance3D = null
	var smoke: CPUParticles3D = null
	var _home := Vector3.ZERO
	var _t := 0.0

	func _ready() -> void:
		for c in get_parent().get_children():
			if c is MeshInstance3D:
				body = c
				break
		if body:
			_home = body.position
			smoke = _thread()
			body.add_child(smoke)
		_tick(0.0)

	func _process(delta: float) -> void:
		_tick(delta)

	## Where the body sits off the path right now, in the rocket's frame.
	func offset() -> Vector3:
		var a := _t * SwarmFx.CORK_SPIN + phase
		# The rocket's local Z is its flight axis (projectile.gd looks along its velocity).
		return Vector3(cos(a), sin(a), 0.0) * SwarmFx.CORK_RADIUS

	func _tick(delta: float) -> void:
		_t += delta
		if body:
			body.position = _home + offset()
		var proj := get_parent()
		var target = proj.get("_homing_target") if proj else null
		if target is Node3D and is_instance_valid(target):
			SwarmFx.Lock.hold(target)

	func _thread() -> CPUParticles3D:
		var p := CPUParticles3D.new()
		p.name = "SmokeThread"
		p.amount = 24
		p.lifetime = 0.6
		p.local_coords = false
		p.emitting = true
		p.direction = Vector3.ZERO
		p.spread = 0.0
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.3
		p.gravity = Vector3(0, 0.4, 0)
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
		grad.colors = PackedColorArray([Color(1.0, 0.7, 0.4, 0.6), Color(0.65, 0.63, 0.62, 0.35), Color(0.55, 0.55, 0.56, 0.0)])
		p.color_ramp = grad
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.4))
		curve.add_point(Vector2(1.0, 1.4))
		p.scale_amount_curve = curve
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 6
		sm.rings = 3
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		sm.material = m
		p.mesh = sm
		return p

## A spinning lock diamond over a robot the swarm is homing on. One per robot;
## every rocket holding it refreshes it, and it goes LOCK_HOLD after the last.
class Lock extends Node3D:
	var since := 0.0
	var _spin := 0.0

	static func hold(target: Node3D) -> void:
		var lock := target.get_node_or_null(SwarmFx.LOCK_NAME) as Lock
		if lock == null:
			lock = Lock.new()
			lock.name = SwarmFx.LOCK_NAME
			lock.set_meta("sig_fx", "swarm_lock")
			target.add_child(lock)
			lock.position = Vector3.UP * 1.1
		lock.since = 0.0

	func _ready() -> void:
		var col := Color(1.0, 0.45, 0.15)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.no_depth_test = true
		mat.albedo_color = Color(col, 0.9)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 5.0
		var half := SwarmFx.LOCK_SIZE * 0.5
		# Four bars on the diamond's edges, in the node's XY plane.
		for i in 4:
			var a := PI * 0.5 * i
			var p0 := Vector2(cos(a), sin(a)) * half
			var p1 := Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * half
			var bm := BoxMesh.new()
			bm.size = Vector3(p0.distance_to(p1), 0.025, 0.005)
			bm.material = mat
			var bar := MeshInstance3D.new()
			bar.mesh = bm
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mid := (p0 + p1) * 0.5
			bar.position = Vector3(mid.x, mid.y, 0.0)
			bar.rotation.z = (p1 - p0).angle()
			add_child(bar)

	func _process(delta: float) -> void:
		since += delta
		if since > SwarmFx.LOCK_HOLD:
			queue_free()
			return
		_spin += delta * 3.0
		var cam := get_viewport().get_camera_3d()
		if cam:
			var to_cam := cam.global_position - global_position
			if to_cam.length() > 0.01:
				var up := Vector3.UP if absf(to_cam.normalized().y) < 0.99 else Vector3.RIGHT
				global_basis = Basis.looking_at(-to_cam.normalized(), up) * Basis(Vector3.BACK, _spin)
