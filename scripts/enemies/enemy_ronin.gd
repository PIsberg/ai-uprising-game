class_name EnemyRonin
extends EnemyBase
## RONIN — a hooded assassin frame (assets/models/robots/robot-killer_model.glb):
## tattered green cloak, one red eye, a katana across its back and a revolver
## hanging in each hand. It STALKS: at range it snaps off single hard revolver slugs, then
## breaks into a flanking dash — a sudden sidestep burst that ruins your aim —
## and closes for a two-cut katana combo. Fast, precise, thinner armour than it
## looks. Kill it before it gets inside your guard.
## The revolvers hang barrel-down in its hands. Each slug is a quick-draw: one
## revolver flicks up about the wrist onto you, fires from its barrel, and drops
## again; the hands take turns. The GLB merges both guns into each of its gun
## meshes, so `_split_guns` cuts them into a left and a right copy at load.
## tests/ronin_revolver_probe.

const SLUG := preload("res://scenes/weapons/projectile_drone.tscn")

@export var slash_damage: float = 20.0     ## Each cut of the two-cut combo.
@export var slug_damage: float = 16.0
@export var slug_speed: float = 55.0
@export var slug_cooldown: float = 2.4
@export var dash_speed: float = 22.0
@export var dash_cooldown: float = 3.0

var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _slug_cd: float = 0.0

# Quick-draw revolvers. The gun meshes (both guns in each) and the two barrel
# meshes whose tips the slugs leave from, named as in robot-killer_model.glb.
const GUN_PARTS := ["Circle_034", "Cube_021", "Circle_035", "Circle_036", "Circle_037", "Cube_017"]
const BARREL_PARTS := ["Circle_034", "Cube_021"]
const DRAW_TIME := 0.1    ## s to flick a revolver up onto the target
const HOLD_TIME := 0.3    ## s it stays up after the shot
const LOWER_TIME := 0.25  ## s to drop it back to the hip
var _guns_ready := false
var _guns: Array = [[], []]          ## per hand: [MeshInstance3D, rest Transform3D, body->parent Transform3D]
var _pivot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO] ## wrist, body frame
var _tip: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   ## barrel tip at rest, body frame
var _hand := 0                       ## hand that draws next (0 = left, 1 = right)
var _draw_t := -1.0                  ## s into the current draw, < 0 when holstered
var _draw_hand := 0
var _shot_pending := false

func _ready() -> void:
	super._ready()
	max_health = 240.0
	move_speed = 8.0
	turn_speed = 10.0
	sight_range = 42.0
	sight_angle_deg = 240.0
	attack_range = 2.8
	preferred_range = 1.6
	attack_cooldown = 1.1
	attack_lunge_speed = 17.0
	telegraph_time = 0.26
	score_value = 320
	stagger_threshold = 60.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 1.0

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		super._physics_process(delta)
		return
	_tick_guns(delta)
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_slug_cd = maxf(0.0, _slug_cd - delta)
	# Mid-dash: ride the burst, ignore nav steering for its duration.
	if _dash_t > 0.0:
		_dash_t -= delta
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed
		_apply_gravity(delta)
		_face_target(delta)
		move_and_slide()
		return
	super._physics_process(delta)
	if target == null or not is_instance_valid(target) or state not in [State.CHASE, State.ATTACK]:
		return
	var dist := global_position.distance_to(target.global_position)
	# Closing from mid range: a sudden angled dash — in and OFF your crosshair.
	if _dash_cd <= 0.0 and dist >= 7.0 and dist <= 18.0 and is_on_floor() and _can_see(target):
		var to := (target.global_position - global_position)
		to.y = 0.0
		_dash_dir = to.normalized().rotated(Vector3.UP, deg_to_rad(35.0 * (1.0 if randf() < 0.5 else -1.0)))
		_dash_t = 0.22
		_dash_cd = dash_cooldown
		AudioBus.play_synth_at("grenade_throw", global_position, -4.0, 1.4)
	# Too far to cut: a single hard revolver slug on a slow, deliberate cadence.
	elif _slug_cd <= 0.0 and dist > 9.0 and _can_see(target) and muzzle != null:
		_fire_slug()

## Start a quick-draw: the slug leaves once the revolver is up (_tick_guns).
## Without split guns (model missing its parts) it fires from the scene muzzle.
func _fire_slug() -> void:
	_slug_cd = slug_cooldown
	if not _guns_ready:
		_shoot()
		return
	if _draw_t >= 0.0:
		return
	_draw_hand = _hand
	_hand = 1 - _hand
	_draw_t = 0.0
	_shot_pending = true

func _shoot() -> void:
	var scene := get_tree().current_scene
	if scene == null or target == null or not is_instance_valid(target) or muzzle == null:
		return
	var proj := SLUG.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.6 - muzzle.global_position).normalized()
	dir = scatter_aim(dir, 1.5)  # an assassin barely misses
	if proj.has_method("launch"):
		proj.launch(dir * slug_speed, self, slug_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -3.0, 0.7)

## Two-cut katana combo: the first cut lands now, the follow-through a beat
## later if you're still inside its reach — dash out between the cuts.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	_attack_lunge()
	_cut()
	get_tree().create_timer(0.18).timeout.connect(_cut)

func _cut() -> void:
	if state == State.DEAD or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.5)
	recoil = 1.0

## Cut every gun mesh into a left and a right copy (by which side of the gap
## between the guns each triangle lies), hide the merged original, and measure
## each hand's wrist (top of its gun) and barrel tip. Runs once RobotModel's
## deferred fit has landed.
func _split_guns() -> void:
	var first := find_child(GUN_PARTS[0], true, false) as Node3D
	if first == null or not first.is_visible_in_tree():
		return
	var inv := global_transform.affine_inverse()
	var parts: Array[MeshInstance3D] = []
	var lo_x := INF
	var hi_x := -INF
	for n in GUN_PARTS:
		var node := find_child(n, true, false)
		if node == null:
			return
		var mi := (node if node is MeshInstance3D else node.find_child("*", true, false)) as MeshInstance3D
		if mi == null or mi.mesh == null:
			return
		parts.append(mi)
		var xf := inv * mi.global_transform
		for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var x: float = (xf * (p as Vector3)).x
			lo_x = minf(lo_x, x)
			hi_x = maxf(hi_x, x)
	var mid := (lo_x + hi_x) * 0.5
	var top_y: Array[float] = [-INF, -INF]
	var tip_y: Array[float] = [INF, INF]
	var tops: Array = [[], []]
	var tips: Array = [[], []]
	for mi in parts:
		var xf := inv * mi.global_transform
		var barrel := String(mi.get_parent().name) in BARREL_PARTS
		for hand in 2:
			var am := ArrayMesh.new()
			var overrides: Array[Material] = []
			for si in mi.mesh.get_surface_count():
				var arr: Array = mi.mesh.surface_get_arrays(si)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
				var keep := PackedInt32Array()
				for t in range(0, idx.size(), 3):
					var c: Vector3 = xf * ((v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0)
					if (c.x > mid) == (hand == 1):
						keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
						for k in 3:
							var q: Vector3 = xf * v[idx[t + k]]
							if q.y > top_y[hand] + 0.03:
								top_y[hand] = q.y
								tops[hand] = []
							if q.y > top_y[hand] - 0.03:
								(tops[hand] as Array).append(q)
							if barrel:
								if q.y < tip_y[hand] - 0.02:
									tip_y[hand] = q.y
									tips[hand] = []
								if q.y < tip_y[hand] + 0.02:
									(tips[hand] as Array).append(q)
				if keep.is_empty():
					continue
				arr[Mesh.ARRAY_INDEX] = keep
				am.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(si), arr)
				am.surface_set_material(am.get_surface_count() - 1, mi.mesh.surface_get_material(si))
				overrides.append(mi.get_surface_override_material(si))
			if am.get_surface_count() == 0:
				continue
			# Same look as the merged original: RobotModel's materials live in
			# its overrides, the GLB's in the mesh.
			var copy := MeshInstance3D.new()
			copy.mesh = am
			copy.material_override = mi.material_override
			for k in overrides.size():
				copy.set_surface_override_material(k, overrides[k])
			copy.transform = mi.transform
			mi.get_parent().add_child(copy)
			_mesh_instances.append(copy)
			var to_parent: Transform3D = (mi.get_parent() as Node3D).global_transform.affine_inverse() * global_transform
			(_guns[hand] as Array).append([copy, copy.transform, to_parent])
		mi.visible = false
	for hand in 2:
		_pivot[hand] = _mean(tops[hand])
		_tip[hand] = _mean(tips[hand])
	_guns_ready = true

static func _mean(pts: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)

## Advance a quick-draw: flick up, fire at the top, hold, drop. The drawn gun
## tracks the target the whole time; the muzzle rides its barrel tip.
func _tick_guns(delta: float) -> void:
	if not _guns_ready:
		_split_guns()
		return
	if _draw_t < 0.0:
		return
	_draw_t += delta
	var w := 0.0
	if _draw_t < DRAW_TIME:
		w = _draw_t / DRAW_TIME
	elif _draw_t < DRAW_TIME + HOLD_TIME:
		w = 1.0
	elif _draw_t < DRAW_TIME + HOLD_TIME + LOWER_TIME:
		w = 1.0 - (_draw_t - DRAW_TIME - HOLD_TIME) / LOWER_TIME
	var h := _draw_hand
	var r := Basis.IDENTITY
	var rest := (_tip[h] - _pivot[h]).normalized()
	if target != null and is_instance_valid(target):
		var aim := global_transform.basis.inverse() * (target.global_position + Vector3.UP * 0.6 - global_transform * _pivot[h])
		if aim.length() > 0.01:
			r = Basis(Quaternion.IDENTITY.slerp(Quaternion(rest, aim.normalized()), smoothstep(0.0, 1.0, w)))
	var lay := Transform3D(r, _pivot[h] - r * _pivot[h])
	for g in _guns[h]:
		var mi := g[0] as MeshInstance3D
		var to_parent := g[2] as Transform3D
		mi.transform = to_parent * lay * to_parent.affine_inverse() * (g[1] as Transform3D)
	if muzzle:
		muzzle.global_position = global_transform * (_pivot[h] + r * (_tip[h] - _pivot[h]))
	if _shot_pending and _draw_t >= DRAW_TIME:
		_shot_pending = false
		_shoot()
	if _draw_t >= DRAW_TIME + HOLD_TIME + LOWER_TIME:
		_draw_t = -1.0
