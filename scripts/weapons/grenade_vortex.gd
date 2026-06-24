class_name GrenadeVortex
extends RigidBody3D
## SINGULARITY CHARGE — a thrown void grenade. It arcs and lands like a normal
## grenade, but instead of a single blast it first collapses into a gravity well
## that drags every nearby robot screaming into one writhing knot — then
## detonates, so the splash lands on the whole bunched-up pack at once. The
## answer to "take out many at a time": herd them, then delete them.

const EXPLOSION_SCENE := preload("res://scenes/fx/grenade_explosion.tscn")

@export var fuse: float = 1.05            ## Flight/arming time before it collapses into the well.
@export var implode_time: float = 0.95    ## How long the well pulls before it detonates.
@export var pull_radius: float = 9.5      ## Robots inside this get hauled toward the core.
@export var pull_strength: float = 9.0    ## Inward speed (m/s at full ramp) of the haul-in.
@export var damage: float = 16.0
@export var splash_radius: float = 6.5
@export var splash_damage: float = 130.0  ## Big — and it lands on a clustered pack.

var _shooter: Node
var _t: float = 0.0
var _phase: int = 0                        # 0 = arming flight, 1 = imploding, 2 = done
var _imp_t: float = 0.0
var _core_mat: StandardMaterial3D
var _pulse_phase: float = 0.0
var _vortex: Node3D                        # spinning well VFX, spawned at collapse

func _ready() -> void:
	var core := get_node_or_null("Core") as MeshInstance3D
	if core and core.mesh and core.mesh.material is StandardMaterial3D:
		_core_mat = core.mesh.material.duplicate()
		core.set_surface_override_material(0, _core_mat)

func throw_grenade(initial_velocity: Vector3, shooter: Node) -> void:
	_shooter = shooter
	linear_velocity = initial_velocity
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(8, 14), randf_range(-2, 2))

func _physics_process(delta: float) -> void:
	if _phase == 2:
		return
	_t += delta
	if _phase == 0:
		# Arming: void core throbs an angry violet, accelerating as it arms.
		var urgency := clampf(_t / maxf(fuse, 0.01), 0.0, 1.0)
		_pulse_phase += delta * TAU * lerpf(4.0, 16.0, urgency)
		var beat := 0.5 + 0.5 * sin(_pulse_phase)
		if _core_mat:
			_core_mat.emission_energy_multiplier = lerpf(1.4, 3.6, beat) + urgency * 2.5
		var light := get_node_or_null("Light") as OmniLight3D
		if light:
			light.light_energy = lerpf(0.6, 2.0, beat) + urgency * 1.4
		if _t >= fuse:
			_begin_implosion()
		return
	# Phase 1: the well is open — haul robots inward, then detonate.
	_imp_t += delta
	var ramp := clampf(_imp_t / maxf(implode_time, 0.01), 0.0, 1.0)
	_pull_enemies(delta, ramp)
	if _vortex and is_instance_valid(_vortex):
		_vortex.rotation.y += delta * lerpf(6.0, 22.0, ramp)   # spin faster as it tightens
		_vortex.scale = Vector3.ONE * lerpf(1.0, 0.35, ramp)   # collapses inward
	if _imp_t >= implode_time:
		_detonate()

## Open the gravity well: pin the grenade in place and spawn the spinning vortex.
func _begin_implosion() -> void:
	_phase = 1
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 0.7)
	_spawn_vortex_fx()

## Drag every robot in range toward the core, horizontally, ramping up so they
## accelerate into one tight knot. Position-based so it overrides their walk AI.
func _pull_enemies(delta: float, ramp: float) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = pull_radius
	q.shape = sphere
	q.transform = Transform3D(Basis(), global_position)
	q.collision_mask = 0b0000100  # enemies only
	for h in space.intersect_shape(q, 32):
		var col = h["collider"]
		if not (col is Node3D):
			continue
		var e := col as Node3D
		var to := global_position - e.global_position
		to.y = 0.0
		var dist := to.length()
		if dist < 0.4:
			continue
		# Stronger pull from further out (so the edges get reeled in), ramping over time.
		var step := pull_strength * ramp * delta * clampf(dist / pull_radius + 0.35, 0.0, 1.4)
		e.global_position += to.normalized() * minf(step, dist)

func _detonate() -> void:
	_phase = 2
	var pos := global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = splash_radius
	q.shape = sphere
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 0b0000101  # world + enemy
	var done := {}
	for h in space.intersect_shape(q, 32):
		var col: Node = h["collider"]
		var node := col as Node
		var d = null
		while node:
			d = node.get_node_or_null("Damageable")
			if d:
				break
			node = node.get_parent()
		if d == null or done.has(d):
			continue
		done[d] = true
		var dist: float = (col as Node3D).global_position.distance_to(pos) if col is Node3D else 0.0
		var falloff := clampf(1.0 - dist / splash_radius, 0.25, 1.0)  # min 0.25 — they're bunched, hit hard
		d.apply_damage((splash_damage + damage) * falloff, _shooter)
	var fx := EXPLOSION_SCENE.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = pos
	# A bright violet collapse-flash to sell the implosion payoff.
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.7, 0.4, 1.0)
	flash.light_energy = 12.0
	flash.omni_range = splash_radius * 2.4
	get_parent().add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.35)
	tw.tween_callback(flash.queue_free)
	if _vortex and is_instance_valid(_vortex):
		_vortex.queue_free()
	queue_free()

## The open well: a violet ring of inward-streaking motes around a dark core,
## built procedurally so the grenade carries its own VFX (no scene dependency).
func _spawn_vortex_fx() -> void:
	_vortex = Node3D.new()
	get_parent().add_child(_vortex)
	_vortex.global_position = global_position + Vector3.UP * 0.4
	# Accretion ring.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = pull_radius * 0.5
	torus.outer_radius = pull_radius * 0.62
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.albedo_color = Color(0.6, 0.35, 1.0, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(0.55, 0.3, 1.0)
	rmat.emission_energy_multiplier = 6.0
	torus.material = rmat
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortex.add_child(ring)
	# Motes spiralling inward (emit on a wide disc, pulled toward the centre).
	var p := CPUParticles3D.new()
	p.amount = 64
	p.lifetime = 0.7
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = pull_radius * 0.7
	p.direction = Vector3.ZERO
	p.gravity = Vector3.ZERO
	p.radial_accel_min = -28.0   # negative = sucked toward the emitter origin
	p.radial_accel_max = -18.0
	p.tangential_accel_min = 12.0
	p.tangential_accel_max = 20.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([Color(0.8, 0.6, 1.0, 0.0), Color(0.6, 0.3, 1.0, 0.9)])
	p.color_ramp = grad
	var mote := SphereMesh.new()
	mote.radius = 0.09; mote.height = 0.18; mote.radial_segments = 6; mote.rings = 3
	var mmat := StandardMaterial3D.new()
	mmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mmat.vertex_color_use_as_albedo = true
	mmat.emission_enabled = true
	mmat.emission = Color(0.6, 0.35, 1.0)
	mmat.emission_energy_multiplier = 5.0
	mote.material = mmat
	p.mesh = mote
	_vortex.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.35, 1.0)
	light.light_energy = 3.5
	light.omni_range = pull_radius
	_vortex.add_child(light)
