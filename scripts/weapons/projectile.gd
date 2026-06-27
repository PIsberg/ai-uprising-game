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
@export var direct_damage: bool = false ## Apply `damage` to the body it strikes (enemy rounds whose splash mask excludes the player). Off by default so splash weapons don't double-dip.
@export var smoke_trail: bool = false ## Lay down a thick billowing smoke trail behind the round (rockets/missiles).
@export var exhaust_flame: bool = false ## A flickering thruster flame burning off the round's tail (rockets/missiles).
@export var big_detonation: bool = false ## On impact, throw a rising smoke column + extra shrapnel for a heavy-ordnance read.
@export var chain_count: int = 0 ## On detonation, lightning arcs from robot to robot — this many hops — for a cluster-clearing zap.
@export var chain_range: float = 9.0 ## Max gap each lightning hop can bridge to the next robot.
@export var chain_damage: float = 0.0 ## Damage per chained robot (0 = half the splash damage).

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
var _exhaust_mat: StandardMaterial3D
var _exhaust: MeshInstance3D
var _exhaust_t: float = 0.0

func launch(velocity: Vector3, shooter: Node, damage: float, splash_radius: float, splash_damage: float) -> void:
	_velocity = velocity
	_shooter = shooter
	_damage = damage
	_splash_radius = splash_radius
	_splash_damage = splash_damage
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_make_trail()
	if smoke_trail:
		_make_smoke_trail()
	if exhaust_flame:
		_make_exhaust()

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

## A fat, slow-rising column of grey smoke streaming off the round — the
## unmistakable read of a missile in flight. Lives in world space so it hangs in
## the air as the rocket pulls away.
func _make_smoke_trail() -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.9
	p.local_coords = false
	p.spread = 8.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 0.6
	p.gravity = Vector3(0, 0.8, 0) # buoyant — the trail drifts up and lingers
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4)); curve.add_point(Vector2(0.3, 1.0)); curve.add_point(Vector2(1.0, 0.7))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors = PackedColorArray([
		Color(0.9, 0.55, 0.25, 0.55), # hot at the nozzle
		Color(0.4, 0.4, 0.42, 0.5),
		Color(0.3, 0.3, 0.32, 0.0)])  # cools to grey, fades out
	p.color_ramp = grad
	var puff := SphereMesh.new()
	puff.radius = 0.12; puff.height = 0.24; puff.radial_segments = 6; puff.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.vertex_color_use_as_albedo = true
	puff.material = pmat
	p.mesh = puff
	add_child(p)

## A short flickering additive flame cone burning off the round's tail (the
## round travels +Z after look_at, so the flame trails toward -Z... i.e. local
## +Z is forward, the exhaust hangs at the back along -forward).
func _make_exhaust() -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.005
	cm.bottom_radius = 0.07
	cm.height = 0.5
	cm.radial_segments = 8
	_exhaust_mat = StandardMaterial3D.new()
	_exhaust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_exhaust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_exhaust_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_exhaust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_exhaust_mat.albedo_color = Color(1.0, 0.7, 0.3, 0.85)
	_exhaust_mat.emission_enabled = true
	_exhaust_mat.emission = Color(1.0, 0.6, 0.2)
	_exhaust_mat.emission_energy_multiplier = 9.0
	cm.material = _exhaust_mat
	mi.mesh = cm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Cylinder axis is +Y; lay it along the round's local Z (its travel axis) with
	# the wide mouth trailing behind the nose.
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position = Vector3(0, 0, -0.35)
	_exhaust = mi
	add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.5
	light.omni_range = 3.0
	light.shadow_enabled = false
	mi.add_child(light)

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
	if _exhaust:
		# Flicker the thruster length/brightness so the flame guthers and pulses.
		_exhaust_t += delta
		var flick := 0.78 + 0.22 * sin(_exhaust_t * 50.0) + 0.1 * sin(_exhaust_t * 23.0)
		_exhaust.scale = Vector3(flick, 1.0 + 0.3 * flick, flick)
		_exhaust_mat.emission_energy_multiplier = 9.0 * flick

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
	# Enemy rounds (splash mask excludes the player) land their hit here instead.
	if direct_damage and body != null:
		var d := body.get_node_or_null("Damageable")
		var node := body
		while d == null and node != null:
			node = node.get_parent()
			if node:
				d = node.get_node_or_null("Damageable")
		if d:
			d.apply_damage(_damage, _shooter)
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
		if big_detonation:
			_heavy_detonation_fx(scene, pos)
	if cluster_count > 0:
		_spawn_cluster(pos)
	if chain_count > 0:
		_chain_lightning(pos)
	queue_free()

## Chain lightning: hop from the nearest robot to the next-nearest, up to
## chain_count times, zapping each — the wall-clearing payoff of an energy round
## that arcs through a whole pack. Each link draws a jagged bolt that fades out.
func _chain_lightning(origin: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var space := get_world_3d().direct_space_state
	var dmg := chain_damage if chain_damage > 0.0 else _splash_damage * 0.5
	var from := origin
	var hit := {}
	for i in chain_count:
		var q := PhysicsShapeQueryParameters3D.new()
		var sh := SphereShape3D.new()
		sh.radius = chain_range
		q.shape = sh
		q.transform = Transform3D(Basis(), from)
		q.collision_mask = 0b0000100 # enemies only
		var best: Node = null
		var best_d := 1e9
		var best_pos := from
		for h in space.intersect_shape(q, 24):
			var col = h["collider"]
			var d = _damageable_of(col)
			if d == null or hit.has(d) or not (col is Node3D):
				continue
			var cp: Vector3 = (col as Node3D).global_position + Vector3.UP * 0.8
			var gap := from.distance_to(cp)
			if gap < best_d:
				best_d = gap; best = d; best_pos = cp
		if best == null:
			break
		hit[best] = true
		best.apply_damage(dmg, _shooter)
		_spawn_lightning_arc(scene, from, best_pos)
		_spawn_zap_flash(scene, best_pos)   # a bright burst on each robot the bolt hits
		from = best_pos

## Walk up from a collider to the nearest Damageable component (enemies nest it).
func _damageable_of(col: Node):
	var node := col as Node
	while node != null:
		var d = node.get_node_or_null("Damageable")
		if d:
			return d
		node = node.get_parent()
	return null

## A jagged emissive bolt between two points, detached into the scene so it
## survives the projectile freeing, then fades and self-frees.
func _spawn_lightning_arc(scene: Node, a: Vector3, b: Vector3) -> void:
	var root := Node3D.new()
	scene.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Bolt core reads near-white-hot, glowing out to the round's energy colour.
	mat.albedo_color = trail_color.lerp(Color.WHITE, 0.6)
	mat.emission_enabled = true
	mat.emission = trail_color
	mat.emission_energy_multiplier = 16.0
	var segs := 5
	var prev := a
	for s in range(1, segs + 1):
		var t := float(s) / float(segs)
		var point := a.lerp(b, t)
		if s < segs:
			# Jitter perpendicular to the run for that forked-lightning look.
			point += Vector3(randf_range(-0.5, 0.5), randf_range(-0.4, 0.4), randf_range(-0.5, 0.5))
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07; cyl.bottom_radius = 0.07
		cyl.height = prev.distance_to(point); cyl.radial_segments = 6
		cyl.material = mat
		mi.mesh = cyl
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		_stand_between(mi, prev, point)
		prev = point
	var flash := OmniLight3D.new()
	flash.light_color = trail_color
	flash.light_energy = 3.5
	flash.omni_range = 4.0
	root.add_child(flash)
	flash.global_position = b
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
	tw.parallel().tween_property(flash, "light_energy", 0.0, 0.18)
	tw.tween_callback(root.queue_free)

## A bright burst where the chain strikes a robot — sells each link of the zap.
func _spawn_zap_flash(scene: Node, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 0.25; s.height = 0.5; s.radial_segments = 8; s.rings = 5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = trail_color.lerp(Color.WHITE, 0.5)
	m.emission_enabled = true; m.emission = trail_color; m.emission_energy_multiplier = 14.0
	s.material = m
	mi.mesh = s
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = trail_color; light.light_energy = 4.0; light.omni_range = 4.0
	mi.add_child(light)
	scene.add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.2, 0.18).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.18)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.18)
	tw.tween_callback(mi.queue_free)

## Orient + position a cylinder mesh (local +Y axis) to span from a to b. NOTE:
## must assign the whole global_transform — `mi.global_transform.basis = x` writes
## to a value-copy and is silently a no-op (the bug that left arcs un-oriented).
func _stand_between(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var mid := (a + b) * 0.5
	var dir := b - a
	if dir.length() < 0.001:
		mi.global_position = mid
		return
	var up := dir.normalized()
	# Build an orthonormal basis whose Y axis runs along the bolt.
	var arbitrary := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := arbitrary.cross(up).normalized()
	var z := x.cross(up).normalized()
	mi.global_transform = Transform3D(Basis(x, up, z), mid)

## Extra heavy-ordnance dressing on top of the blast scene: a billowing smoke
## column that mushrooms up and lingers, plus a ring of fast shrapnel streaks.
## Built on a detached node so it survives this projectile being freed.
func _heavy_detonation_fx(scene: Node, pos: Vector3) -> void:
	var root := Node3D.new()
	scene.add_child(root)
	root.global_position = pos
	# Rising smoke column — the aftermath plume.
	var smoke := CPUParticles3D.new()
	smoke.one_shot = true
	smoke.emitting = true
	smoke.amount = 26
	smoke.lifetime = 1.8
	smoke.explosiveness = 0.6
	smoke.spread = 40.0
	smoke.direction = Vector3.UP
	smoke.initial_velocity_min = 2.0
	smoke.initial_velocity_max = 5.0
	smoke.gravity = Vector3(0, 1.5, 0) # buoyant — mushrooms upward
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.3)); sc.add_point(Vector2(1.0, 1.0))
	smoke.scale_amount_curve = sc
	var sgrad := Gradient.new()
	sgrad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	sgrad.colors = PackedColorArray([
		Color(0.6, 0.35, 0.2, 0.6), Color(0.25, 0.24, 0.24, 0.55), Color(0.2, 0.2, 0.2, 0.0)])
	smoke.color_ramp = sgrad
	var puff := SphereMesh.new()
	puff.radius = 0.6; puff.height = 1.2; puff.radial_segments = 6; puff.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	puff.material = smat
	smoke.mesh = puff
	root.add_child(smoke)
	# Shrapnel: hot metal streaks hurled out low across the ground.
	var shr := CPUParticles3D.new()
	shr.one_shot = true
	shr.emitting = true
	shr.amount = 24
	shr.lifetime = 0.7
	shr.explosiveness = 1.0
	shr.spread = 80.0
	shr.direction = Vector3.UP
	shr.initial_velocity_min = 9.0
	shr.initial_velocity_max = 18.0
	shr.gravity = Vector3(0, -24.0, 0)
	var dart := BoxMesh.new()
	dart.size = Vector3(0.05, 0.05, 0.22)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = Color(1.0, 0.7, 0.35)
	dmat.emission_enabled = true
	dmat.emission = trail_color
	dmat.emission_energy_multiplier = 6.0
	dart.material = dmat
	shr.mesh = dart
	root.add_child(shr)
	scene.get_tree().create_timer(3.0).timeout.connect(root.queue_free)

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
		# Bind a STATIC callable (not a lambda closing over `self`): this projectile
		# queue_free()s the same frame it spawns the cluster, so any callback bound to
		# it would be auto-disconnected before the staggered timers fire — leaving the
		# carpet silent. The static call survives the projectile's death.
		t.timeout.connect(Projectile._detonate_bomblet.bind(scene, spot, dmg, srad, shooter, tcol))

static func _detonate_bomblet(scene: Node, pos: Vector3, dmg: float, srad: float, shooter: Node, tcol: Color) -> void:
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
