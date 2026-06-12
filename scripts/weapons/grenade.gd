class_name Grenade
extends RigidBody3D
## Thrown plasma charge: arcs under gravity, bounces off world geometry, and
## detonates on a fuse timer dealing splash damage to nearby enemies. The
## energy core throbs faster and hotter as the fuse runs down — anyone nearby
## can read exactly how angry it is.

@export var fuse: float = 1.5
const EXPLOSION_SCENE := preload("res://scenes/fx/grenade_explosion.tscn")

@export var damage: float = 20.0
@export var splash_radius: float = 4.5
@export var splash_damage: float = 90.0

var _shooter: Node
var _t: float = 0.0
var _dead: bool = false
var _pulse_phase: float = 0.0
var _core_mat: StandardMaterial3D

func _ready() -> void:
	# Per-instance core material so simultaneous grenades pulse independently.
	var core := get_node_or_null("Core") as MeshInstance3D
	if core and core.mesh and core.mesh.material is StandardMaterial3D:
		_core_mat = core.mesh.material.duplicate()
		core.set_surface_override_material(0, _core_mat)

func throw_grenade(initial_velocity: Vector3, shooter: Node) -> void:
	_shooter = shooter
	linear_velocity = initial_velocity
	# Spin around the fin axis so it flies like thrown tech, not a tumbling rock.
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(8, 14), randf_range(-2, 2))

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta

	# Arming heartbeat: the core and light throb, accelerating from a calm
	# 4Hz toward a frantic ~14Hz as detonation closes in.
	var urgency := clampf(_t / maxf(fuse, 0.01), 0.0, 1.0)
	_pulse_phase += delta * TAU * lerpf(4.0, 14.0, urgency)
	var beat := 0.5 + 0.5 * sin(_pulse_phase)
	if _core_mat:
		_core_mat.emission_energy_multiplier = lerpf(1.2, 3.0, beat) + urgency * 2.0
	var light := get_node_or_null("Light") as OmniLight3D
	if light:
		light.light_energy = lerpf(0.6, 1.8, beat) + urgency * 1.2

	if _t >= fuse:
		_explode()

func _explode() -> void:
	if _dead:
		return
	_dead = true
	var pos := global_position
	# Splash via overlap query (world + enemy); falloff by distance.
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = splash_radius
	q.shape = sphere
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = 0b0000101 # world + enemy
	var hits := space.intersect_shape(q, 24)
	var done := {}
	for h in hits:
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
		var falloff := clampf(1.0 - dist / splash_radius, 0.0, 1.0)
		d.apply_damage((splash_damage + damage) * falloff, _shooter)
	
	# Spawn visual/audio explosion
	var exp_fx := EXPLOSION_SCENE.instantiate()
	get_parent().add_child(exp_fx)
	exp_fx.global_position = pos
	
	queue_free()

