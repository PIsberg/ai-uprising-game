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
## The katana comes off its back: drawn to a guard when you are within
## DRAW_RANGE, raised over the right shoulder through the attack wind-up, swung
## through the two cuts (a diagonal down to the left, a flat return to the
## right, each hit landing mid-swing) and sheathed again SHEATHE_AFTER seconds
## after you are gone. The GLB has a handle and a scabbard but no blade, so a
## blade is built; sheathed, it sits inside the scabbard. tests/ronin_katana_probe.

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

# The katana. Handle parts as named in robot-killer_model.glb (the guard is
# Cube_024); the scabbard (Cube_023) stays on the back.
const HANDLE_PARTS := ["Cylinder_003", "Circle_040", "Cube_024"]
const SCABBARD := "Cube_023"
const BLADE_LEN := 1.15
const DRAW_RANGE := 6.0      ## m: draws when the target is this close
const SHEATHE_AFTER := 1.5   ## s with nobody that close before it sheathes
const CUT_TIME := 0.12       ## s per cut's swing
const CUT2_AT := 0.18        ## s into the combo the return cut starts
const COMBO_END := 0.55      ## s into the combo it is back at guard
# Body-frame poses: [guard position, blade direction, cutting edge direction].
const POSE_GUARD := [Vector3(0.32, 1.2, -0.45), Vector3(0.05, 0.75, -0.66), Vector3(0, 0.66, 0.75)]
const POSE_WIND := [Vector3(0.4, 1.65, -0.15), Vector3(0.45, 0.85, 0.25), Vector3(-0.5, 0.0, -0.8)]
const POSE_CUT1 := [Vector3(-0.15, 1.0, -0.5), Vector3(-0.55, -0.45, -0.7), Vector3(-0.6, -0.4, 0.4)]
const POSE_CUT2 := [Vector3(0.35, 1.15, -0.4), Vector3(0.85, 0.05, -0.5), Vector3(0.5, 0.0, 0.85)]
var _sword_ready := false
var _sword_parts: Array = []           ## [MeshInstance3D, rest Transform3D, body->parent Transform3D]
var _guard0 := Vector3.ZERO            ## guard centre, sheathed, body frame
var _rest_basis := Basis.IDENTITY      ## sheathed: y up the handle, z along the edge
var _sword_xf := Transform3D.IDENTITY  ## body-frame motion applied to the whole sword
var _blade: MeshInstance3D
var _blade_rest := Transform3D.IDENTITY
var _drawn := false
var _away_t := 0.0
var _combo_t := -1.0                   ## s into the two-cut combo, < 0 idle
var _trail: MeshInstance3D
var _trail_pts: Array[Vector3] = []

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
	_tick_sword(delta)
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
	if _sword_ready:
		_combo_t = 0.0 # each hit lands mid-swing, on _tick_sword's (physics) clock
	else:
		get_tree().create_timer(CUT_TIME * 0.5).timeout.connect(_cut)
		get_tree().create_timer(CUT2_AT + CUT_TIME * 0.5).timeout.connect(_cut)

func _cut() -> void:
	if state == State.DEAD or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.5)
	recoil = 1.0

## Cut every gun mesh into a left and a right copy (PartRig.split_x, at the
## gap between the guns) and measure each hand's wrist (top of its gun) and
## barrel tip. Runs once RobotModel's deferred fit has landed.
func _split_guns() -> void:
	var first := find_child(GUN_PARTS[0], true, false) as Node3D
	if first == null or not first.is_visible_in_tree():
		return
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
		for q in PartRig.body_points(self, mi):
			lo_x = minf(lo_x, q.x)
			hi_x = maxf(hi_x, q.x)
	var mid := (lo_x + hi_x) * 0.5
	var all_pts: Array = [PackedVector3Array(), PackedVector3Array()]
	var barrel_pts: Array = [PackedVector3Array(), PackedVector3Array()]
	for mi in parts:
		var barrel := String(mi.get_parent().name) in BARREL_PARTS
		var halves := PartRig.split_x(self, mi, mid)
		for hand in 2:
			if halves[hand] == null:
				continue
			(_guns[hand] as Array).append(halves[hand])
			var pts := PartRig.body_points(self, halves[hand][0])
			all_pts[hand] = (all_pts[hand] as PackedVector3Array) + pts # packed arrays copy on read
			if barrel:
				barrel_pts[hand] = (barrel_pts[hand] as PackedVector3Array) + pts
	for hand in 2:
		_pivot[hand] = _band_mean(all_pts[hand], true, 0.03)
		_tip[hand] = _band_mean(barrel_pts[hand], false, 0.02)
	_guns_ready = true

## Mean of the points within `band` m of the highest (`top`) or lowest y.
static func _band_mean(pts: PackedVector3Array, top: bool, band: float) -> Vector3:
	var edge := -INF if top else INF
	for q in pts:
		edge = maxf(edge, q.y) if top else minf(edge, q.y)
	var sel := PackedVector3Array()
	for q in pts:
		if absf(q.y - edge) < band:
			sel.append(q)
	return PartRig.mean(sel)

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
		PartRig.pose(g, lay)
	if muzzle:
		muzzle.global_position = global_transform * (_pivot[h] + r * (_tip[h] - _pivot[h]))
	if _shot_pending and _draw_t >= DRAW_TIME:
		_shot_pending = false
		_shoot()
	if _draw_t >= DRAW_TIME + HOLD_TIME + LOWER_TIME:
		_draw_t = -1.0

## Measure the sheathed sword (after RobotModel's fit) and build the blade.
func _setup_sword() -> void:
	var guard := find_child(HANDLE_PARTS[2], true, false) as Node3D
	var scab := find_child(SCABBARD, true, false) as Node3D
	if guard == null or scab == null or not guard.is_visible_in_tree():
		return
	var inv := global_transform.affine_inverse()
	for n in HANDLE_PARTS:
		var node := find_child(n, true, false)
		if node == null:
			return
		for m in node.find_children("*", "MeshInstance3D", true, false):
			_sword_parts.append(PartRig.entry(self, m as MeshInstance3D))
	_guard0 = _verts_mean(guard, inv, -1.0)
	var bottom := _verts_mean(scab, inv, 0.06) # the scabbard's lowest 6 cm
	var b0 := (bottom - _guard0).normalized()
	var y0 := -b0
	var z0 := (Vector3.FORWARD - y0 * y0.dot(Vector3.FORWARD)).normalized()
	_rest_basis = Basis(y0.cross(z0), y0, z0)
	_blade = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, BLADE_LEN, 0.045)
	_blade.mesh = bm
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.84, 0.88)
	steel.metallic = 0.55
	steel.roughness = 0.22
	steel.emission_enabled = true
	steel.emission = Color(0.75, 0.85, 1.0)
	steel.emission_energy_multiplier = 0.35
	_blade.material_override = steel
	_blade_rest = Transform3D(_rest_basis, _guard0 + b0 * (BLADE_LEN * 0.5 + 0.02))
	_blade.transform = _blade_rest
	add_child(_blade)
	_sword_ready = true

## Mean body-frame position of `node`'s mesh vertices; with `band` >= 0 only
## those within `band` m of the lowest one.
func _verts_mean(node: Node, inv: Transform3D, band: float) -> Vector3:
	var pts: Array[Vector3] = []
	var list: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		list.append(node)
	for m in list:
		var mi := m as MeshInstance3D
		var xf := inv * mi.global_transform
		for p in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			pts.append(xf * (p as Vector3))
	var lo := INF
	for q in pts:
		lo = minf(lo, q.y)
	var c := Vector3.ZERO
	var k := 0
	for q in pts:
		if band < 0.0 or q.y < lo + band:
			c += q
			k += 1
	return c / maxf(k, 1)

## The whole-sword motion that puts the guard at pose[0] with the blade along
## pose[1] and the edge leading along pose[2].
func _sword_pose(pose: Array) -> Transform3D:
	var y := -(pose[1] as Vector3).normalized()
	var e: Vector3 = pose[2]
	var z := (e - y * y.dot(e)).normalized()
	var r := Basis(y.cross(z), y, z) * _rest_basis.inverse()
	return Transform3D(r, (pose[0] as Vector3) - r * _guard0)

## A swing from pose `a` to pose `b`, `f` of the way: the blade turns along
## the arc between them, the guard travels in a line.
func _swing(a: Array, b: Array, f: float) -> Transform3D:
	var from := (a[1] as Vector3).normalized()
	var q := Quaternion(from, (b[1] as Vector3).normalized())
	var dir: Vector3 = Quaternion.IDENTITY.slerp(q, f) * from
	var edge: Vector3 = (a[2] as Vector3).lerp(b[2], f)
	return _sword_pose([(a[0] as Vector3).lerp(b[0], f), dir, edge])

func _tick_sword(delta: float) -> void:
	if not _sword_ready:
		_setup_sword()
		return
	var near: bool = target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) < DRAW_RANGE
	if near or _telegraphing or _combo_t >= 0.0:
		_away_t = 0.0
		_drawn = true
	else:
		_away_t += delta
		if _away_t >= SHEATHE_AFTER:
			_drawn = false
	var goal := Transform3D.IDENTITY
	var rate := 10.0
	if _combo_t >= 0.0:
		var prev := _combo_t
		_combo_t += delta
		var c := _combo_t
		var swinging := c < CUT_TIME or (c >= CUT2_AT and c < CUT2_AT + CUT_TIME)
		if c < CUT_TIME:
			_sword_xf = _swing(POSE_WIND, POSE_CUT1, smoothstep(0.0, 1.0, c / CUT_TIME))
		elif c < CUT2_AT:
			_sword_xf = _sword_pose(POSE_CUT1)
		elif c < CUT2_AT + CUT_TIME:
			_sword_xf = _swing(POSE_CUT1, POSE_CUT2, smoothstep(0.0, 1.0, (c - CUT2_AT) / CUT_TIME))
		if c >= COMBO_END:
			_combo_t = -1.0
		if c < CUT2_AT + CUT_TIME:
			_apply_sword()
			_trail_tick(swinging)
			# Hits land mid-swing, after the pose they land in is drawn.
			for hit: float in [CUT_TIME * 0.5, CUT2_AT + CUT_TIME * 0.5]:
				if prev < hit and c >= hit:
					_cut()
			return
		_trail_tick(false)
		goal = _sword_pose(POSE_GUARD)
		rate = 12.0
	elif _telegraphing:
		goal = _sword_pose(POSE_WIND)
		rate = 18.0
	elif _drawn:
		goal = _sword_pose(POSE_GUARD)
		rate = 12.0
	_sword_xf = _sword_xf.interpolate_with(goal, 1.0 - exp(-rate * delta))
	_apply_sword()

func _apply_sword() -> void:
	for p in _sword_parts:
		PartRig.pose(p, _sword_xf)
	_blade.transform = _sword_xf * _blade_rest

## The slash trail: a ribbon over the outer blade's path while it swings, then
## fading out.
func _trail_tick(swinging: bool) -> void:
	if not swinging:
		if _trail != null:
			var tr := _trail
			_trail = null
			var tw := tr.create_tween()
			tw.tween_property(tr, "transparency", 1.0, 0.22)
			tw.tween_callback(tr.queue_free)
		return
	if _trail == null:
		var scene := get_tree().current_scene
		if scene == null:
			return
		_trail = MeshInstance3D.new()
		_trail.mesh = ImmediateMesh.new()
		_trail.top_level = true
		_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.vertex_color_use_as_albedo = true
		_trail.material_override = mat
		scene.add_child(_trail)
		_trail_pts.clear()
	var bx := _blade.global_transform
	_trail_pts.append(bx * Vector3(0, -BLADE_LEN * 0.05, 0))
	_trail_pts.append(bx * Vector3(0, -BLADE_LEN * 0.5, 0))
	var im := _trail.mesh as ImmediateMesh
	im.clear_surfaces()
	var n := _trail_pts.size() / 2
	if n < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		var ca := Color(1.0, 0.6, 0.45, 0.06 + 0.34 * float(i) / n)
		var cb := Color(1.0, 0.6, 0.45, 0.06 + 0.34 * float(i + 1) / n)
		var quad := [[_trail_pts[i * 2], ca], [_trail_pts[i * 2 + 1], ca], [_trail_pts[i * 2 + 3], cb],
			[_trail_pts[i * 2], ca], [_trail_pts[i * 2 + 3], cb], [_trail_pts[i * 2 + 2], cb]]
		for v in quad:
			im.surface_set_color(v[1])
			im.surface_add_vertex(v[0])
	im.surface_end()
