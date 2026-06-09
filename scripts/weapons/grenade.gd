class_name Grenade
extends RigidBody3D
## Thrown frag grenade: arcs under gravity, bounces off world geometry, and
## detonates on a fuse timer dealing splash damage to nearby enemies.

@export var fuse: float = 1.5
const EXPLOSION_SCENE := preload("res://scenes/fx/grenade_explosion.tscn")

@export var damage: float = 20.0
@export var splash_radius: float = 4.5
@export var splash_damage: float = 90.0

var _shooter: Node
var _t: float = 0.0
var _dead: bool = false

func throw_grenade(initial_velocity: Vector3, shooter: Node) -> void:
	_shooter = shooter
	linear_velocity = initial_velocity
	angular_velocity = Vector3(randf_range(-7, 7), randf_range(-7, 7), randf_range(-7, 7))

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	
	# Blink warning LED
	var light := get_node_or_null("Light") as OmniLight3D
	if light:
		light.visible = (int(_t / 0.12) % 2) == 0
		
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

