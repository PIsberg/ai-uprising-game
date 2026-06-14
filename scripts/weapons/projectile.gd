class_name Projectile
extends Area3D

@export var lifetime: float = 4.0
@export var gravity_scale: float = 0.0
@export var trail_color: Color = Color(0.5, 0.9, 1.0) ## Glowing trail + impact flash tint.
@export var energy_pulse: bool = false ## If set, the round's core throbs like an energy bolt.
@export var cluster_count: int = 0 ## On detonation, spawn this many secondary blasts scattered around — a multi-kill carpet.
@export var cluster_radius: float = 6.0 ## How far the bomblets scatter from the impact.
@export var cluster_delay: float = 0.06 ## Stagger between bomblets so it ripples outward.
@export var homing_turn_rate: float = 0.0 ## Radians/sec the round can steer toward a locked target (0 = dumb-fire).
@export var homing_range: float = 42.0 ## Max distance to acquire/keep a homing target.

const SMALL_BLAST := preload("res://scenes/fx/enemy_explosion.tscn")
const BIG_BLAST := preload("res://scenes/fx/grenade_explosion.tscn")

var _velocity: Vector3
var _shooter: Node
var _damage: float = 0.0
var _splash_radius: float = 0.0
var _splash_damage: float = 0.0
var _age: float = 0.0
var _dead: bool = false
var _homing_target: Node3D = null
var _reacquire: float = 0.0

func launch(velocity: Vector3, shooter: Node, damage: float, splash_radius: float, splash_damage: float) -> void:
	_velocity = velocity
	_shooter = shooter
	_damage = damage
	_splash_radius = splash_radius
	_splash_damage = splash_damage
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_make_trail()

## A glowing world-space trail of embers streaming off the round.
func _make_trail() -> void:
	var p := CPUParticles3D.new()
	p.amount = 22
	p.lifetime = 0.45
	p.local_coords = false
	p.spread = 6.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.4
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0)); curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	var mesh := SphereMesh.new()
	mesh.radius = 0.06; mesh.height = 0.12; mesh.radial_segments = 6; mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = trail_color
	mat.emission_enabled = true
	mat.emission = trail_color
	mat.emission_energy_multiplier = 5.0
	mesh.material = mat
	p.mesh = mesh
	add_child(p)

func _physics_process(delta: float) -> void:
	if _dead:
		return
	_age += delta
	if _age > lifetime:
		_explode(global_position)
		return
	if gravity_scale != 0.0:
		_velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_scale * delta
	if homing_turn_rate > 0.0:
		_steer_homing(delta)
	global_position += _velocity * delta
	if _velocity.length_squared() > 0.01:
		look_at(global_position + _velocity, Vector3.UP)
	if energy_pulse:
		var m := _energy_mesh()
		if m:
			m.scale = Vector3.ONE * (1.0 + 0.22 * sin(_age * 30.0))

## Bend the round's velocity toward a locked enemy, re-acquiring the nearest
## valid target a few times a second so a swarm spreads across a pack.
func _steer_homing(delta: float) -> void:
	_reacquire -= delta
	if _reacquire <= 0.0 or not _is_valid_target(_homing_target):
		_reacquire = 0.25
		_homing_target = _find_homing_target()
	if not _is_valid_target(_homing_target):
		return
	var aim := (_homing_target.global_position + Vector3.UP * 0.6) - global_position
	if aim.length_squared() < 0.01:
		return
	var speed := _velocity.length()
	var cur := _velocity.normalized()
	var desired := aim.normalized()
	var max_turn := homing_turn_rate * delta
	var ang := cur.angle_to(desired)
	if ang <= max_turn:
		_velocity = desired * speed
	else:
		var axis := cur.cross(desired)
		if axis.length_squared() < 0.0001:
			axis = Vector3.UP
		_velocity = cur.rotated(axis.normalized(), max_turn) * speed

func _is_valid_target(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var d := t.get_node_or_null("Damageable")
	if d and not d.is_alive():
		return false
	return global_position.distance_to(t.global_position) <= homing_range * 1.4

func _find_homing_target() -> Node3D:
	var best: Node3D = null
	var best_score := -1.0
	var fwd := _velocity.normalized()
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D):
			continue
		var en := e as Node3D
		var d := en.get_node_or_null("Damageable")
		if d == null or not d.is_alive():
			continue
		var to := en.global_position - global_position
		var dist := to.length()
		if dist > homing_range or dist < 0.5:
			continue
		# Favour targets ahead of the round, nearer ones first.
		var ahead := fwd.dot(to / dist)
		if ahead < -0.2:
			continue
		var score := ahead * 2.0 + (1.0 - dist / homing_range)
		if score > best_score:
			best_score = score
			best = en
	return best

func _energy_mesh() -> MeshInstance3D:
	for c in get_children():
		if c is MeshInstance3D:
			return c
	return null

func _on_body_entered(body: Node) -> void:
	if body == _shooter:
		return
	_explode(global_position)

func _on_area_entered(area: Area3D) -> void:
	if area == self:
		return

func _explode(pos: Vector3) -> void:
	if _dead:
		return
	_dead = true
	# Splash damage via overlap query
	if _splash_radius > 0.0:
		var space := get_world_3d().direct_space_state
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := SphereShape3D.new()
		shape.radius = _splash_radius
		query.shape = shape
		query.transform = Transform3D(Basis(), pos)
		query.collision_mask = 0b0000101 # world + enemy
		var results := space.intersect_shape(query, 16)
		for hit in results:
			var col: Node = hit["collider"]
			var d := col.get_node_or_null("Damageable")
			var node := col as Node
			while d == null and node != null:
				node = node.get_parent()
				if node:
					d = node.get_node_or_null("Damageable")
			if d == null:
				continue
			var dist := (col as Node3D).global_position.distance_to(pos) if col is Node3D else 0.0
			var falloff := clampf(1.0 - dist / _splash_radius, 0.0, 1.0)
			d.apply_damage(_splash_damage * falloff + _damage, _shooter)
	# Impact blast: a big boom for splash rounds (rocket), a sharp burst otherwise
	# (plasma), plus a brief colored flash light in the round's energy colour.
	var scene := get_tree().current_scene
	if scene:
		var big := _splash_radius >= 3.0
		var blast := (BIG_BLAST if big else SMALL_BLAST).instantiate()
		scene.add_child(blast)
		(blast as Node3D).global_position = pos
		# Scale heavy blasts up with their splash so big rounds feel weighty.
		if big:
			(blast as Node3D).scale = Vector3.ONE * clampf(_splash_radius / 4.0, 1.0, 2.2)
		var flash := OmniLight3D.new()
		flash.light_color = trail_color
		flash.light_energy = 6.0 if not big else 10.0
		flash.omni_range = maxf(5.0, _splash_radius * 2.5)
		scene.add_child(flash)
		flash.global_position = pos
		var tw := flash.create_tween()
		tw.tween_property(flash, "light_energy", 0.0, 0.3)
		tw.tween_callback(flash.queue_free)
	if cluster_count > 0:
		_spawn_cluster(pos)
	queue_free()

## Carpet bombing: a ring of staggered secondary blasts around the impact, each
## doing its own splash — turns one hit into a wall of explosions that clears a
## whole pack. Scene-tree timers fire them so they ripple outward as we free.
func _spawn_cluster(center: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for i in cluster_count:
		var ang := TAU * float(i) / float(cluster_count) + randf() * 0.4
		var rad := cluster_radius * randf_range(0.45, 1.0)
		var spot := center + Vector3(cos(ang) * rad, randf_range(0.0, 1.5), sin(ang) * rad)
		var shooter := _shooter
		var dmg := _splash_damage * 0.7
		var srad := _splash_radius * 0.55
		var tcol := trail_color
		var t := scene.get_tree().create_timer(cluster_delay * float(i + 1))
		t.timeout.connect(func() -> void:
			_detonate_bomblet(scene, spot, dmg, srad, shooter, tcol))

func _detonate_bomblet(scene: Node, pos: Vector3, dmg: float, srad: float, shooter: Node, tcol: Color) -> void:
	if not is_instance_valid(scene) or not scene is Node3D:
		return
	# Splash query for this bomblet.
	var space: PhysicsDirectSpaceState3D = (scene as Node3D).get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = srad
	query.shape = shape
	query.transform = Transform3D(Basis(), pos)
	query.collision_mask = 0b0000101
	for hit in space.intersect_shape(query, 12):
		var col: Node = hit["collider"]
		var d := col.get_node_or_null("Damageable")
		var node := col as Node
		while d == null and node != null:
			node = node.get_parent()
			if node:
				d = node.get_node_or_null("Damageable")
		if d == null:
			continue
		var dist := (col as Node3D).global_position.distance_to(pos) if col is Node3D else 0.0
		d.apply_damage(dmg * clampf(1.0 - dist / srad, 0.0, 1.0), shooter)
	var blast := BIG_BLAST.instantiate()
	scene.add_child(blast)
	(blast as Node3D).global_position = pos
	(blast as Node3D).scale = Vector3.ONE * clampf(srad / 4.0, 0.7, 1.6)
