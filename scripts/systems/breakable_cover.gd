class_name BreakableCover
# @lat: [[level-system#Breakable Cover]]
extends StaticBody3D
## A compact cover block from a level's `walls` that can be shot apart.
##
## Cover was permanent, so a firefight never changed the room it was fought in.
## Now it takes damage from player fire and from every explosion, cracks in two
## visible stages (scorch, glowing fracture seams, a lean), and finally shatters:
## chunks and dust, SHRAPNEL that hurts whatever was crouched behind it, a pile of
## rubble where it stood, and a navmesh rebake so robots path through the gap.
## Shooting out the block an enemy hides behind is a tactic, not just scenery.
##
## Built by LevelBuilder._build_geometry for every wall that `qualifies`. It dresses
## itself (rim + accent band) because the level-wide cover trim is batched into
## MultiMeshes that could not be removed along with one block.
##
## Damage scaling (modify_incoming_damage): explosions x SPLASH_MULT, boss slams and
## heavy chassis x BOSS_MULT, ordinary enemy rounds x ENEMY_MULT (a squad shooting at
## you should not erase your cover in seconds).

signal shattered(cover: BreakableCover)

const HP_PER_M3 := 60.0
const HP_MIN := 220.0
const HP_MAX := 1400.0
const SPLASH_MULT := 1.6
const BOSS_MULT := 2.0
const ENEMY_MULT := 0.3
const BOSS_HP := 500.0          ## same tell EnemyBase uses (HIJACK_BOSS_HP): no boss group exists
const SHRAPNEL_RADIUS := 3.6
const SHRAPNEL_DAMAGE := 45.0

## Size window a `walls` entry must fit (world units, after WORLD_SCALE).
const MIN_H := 0.8
const MAX_H := 4.3
const MAX_SPAN := 6.0
const MIN_SPAN := 0.4
const MAX_BASE_Y := 0.35        ## must stand on the floor, not hang off a platform
const CLEARANCE := 0.15         ## an authored point this close to the footprint counts as on it
const BOX_CLEARANCE := 0.4      ## a ramp/platform this close to the footprint may lean on it
const REST_H := 1.2             ## a point or box this far above the top hangs, it does not rest

const IMPACT := preload("res://scenes/fx/impact.tscn")

var size: Vector3 = Vector3.ONE
var stage: int = 0              ## 0 intact, 1 cracked, 2 failing
var hp: Damageable
var _mesh: MeshInstance3D
var _base_mat: Material
var _accent: Color = Color(0.4, 0.8, 1.0)
var _dead: bool = false

## True when a `walls` entry is compact, floor-standing cover with nothing authored
## on, in or leaning against it, so destroying it can never strand a light, a task
## object, a pickup or a ramp in mid-air. `def["breakable_cover"] = false` keeps a
## whole level's cover solid; `"solid": true` on one wall keeps just that one.
static func qualifies(w: Dictionary, def: Dictionary) -> bool:
	return why_not(w, def) == ""

## "" when the wall qualifies, else the reason it stays solid (the probe's census
## prints these, so a level author can see why a block did not become breakable).
static func why_not(w: Dictionary, def: Dictionary) -> String:
	if not def.get("breakable_cover", true):
		return "level opt-out"
	if w.get("solid", false):
		return "solid"
	var pos: Vector3 = w.get("pos", Vector3.ZERO)
	var sz: Vector3 = w.get("size", Vector3.ONE)
	if sz.y < MIN_H:
		return "too low"
	if sz.y > MAX_H:
		return "too tall"
	if maxf(sz.x, sz.z) > MAX_SPAN:
		return "too long"
	if minf(sz.x, sz.z) < MIN_SPAN:
		return "too thin"
	if pos.y - sz.y * 0.5 > MAX_BASE_Y:
		return "off the floor"
	var top := pos.y + sz.y * 0.5
	for key in def:
		if key in ["walls", "env", "lava", "floor_size", "gates"]:
			continue # the walls themselves, sky vectors, hazard beds, partition walls
		if _blocks(def[key], pos, sz, top):
			return "carries " + String(key)
	return ""

## Any authored point on or in the block (inside its footprint, below REST_H over
## its top), or any {pos,size} box beside or over it low enough to lean on it.
static func _blocks(v, pos: Vector3, sz: Vector3, top: float) -> bool:
	if v is Vector3:
		return absf(v.x - pos.x) <= sz.x * 0.5 + CLEARANCE and absf(v.z - pos.z) <= sz.z * 0.5 + CLEARANCE \
			and v.y <= top + REST_H
	if v is Dictionary:
		if v.get("pos") is Vector3 and v.get("size") is Vector3:
			var p: Vector3 = v["pos"]
			var s: Vector3 = v["size"]
			return absf(p.x - pos.x) <= (s.x + sz.x) * 0.5 + BOX_CLEARANCE \
				and absf(p.z - pos.z) <= (s.z + sz.z) * 0.5 + BOX_CLEARANCE \
				and p.y - s.y * 0.5 <= top + REST_H * 0.5
		for k in v:
			if _blocks(v[k], pos, sz, top):
				return true
	elif v is Array:
		for e in v:
			if _blocks(e, pos, sz, top):
				return true
	return false

## Called by the builder before add_child.
func setup(box_size: Vector3, mesh: Mesh, mat: Material, accent: Color) -> void:
	size = box_size
	_base_mat = mat
	_accent = accent
	collision_layer = 1
	collision_mask = 0
	add_to_group("surf_metal")
	add_to_group("destructible")
	add_to_group("breakable_cover")
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.material_override = mat
	add_child(_mesh)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box_size
	cs.shape = bs
	add_child(cs)
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = clampf(box_size.x * box_size.y * box_size.z * HP_PER_M3, HP_MIN, HP_MAX)
	add_child(hp)
	hp.damaged.connect(_on_damaged)
	hp.died.connect(_on_destroyed)
	_dress()

## The rim outline + a theme accent band the batched cover trim would have given it.
func _dress() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = _accent
	var half := size * 0.5
	for e in [
			[Vector3(0, half.y + 0.015, -half.z), Vector3(size.x, 0.03, 0.05)],
			[Vector3(0, half.y + 0.015, half.z), Vector3(size.x, 0.03, 0.05)],
			[Vector3(-half.x, half.y + 0.015, 0), Vector3(0.05, 0.03, size.z)],
			[Vector3(half.x, half.y + 0.015, 0), Vector3(0.05, 0.03, size.z)],
			[Vector3(0, half.y * 0.3, 0), Vector3(size.x + 0.012, 0.05, size.z + 0.012)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		bm.material = m
		mi.mesh = bm
		mi.position = e[0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.add_child(mi)

func modify_incoming_damage(amount: float, source, origin) -> float:
	var mult := SPLASH_MULT if origin != null else 1.0
	if source is Node and (source as Node).is_in_group("enemy"):
		var d: Damageable = (source as Node).get_node_or_null("Damageable")
		if d and d.max_health >= BOSS_HP:
			mult *= BOSS_MULT
		elif origin == null:
			mult *= ENEMY_MULT
	return amount * mult

func _on_damaged(_amount: float, _source: Node) -> void:
	if _dead or hp.max_health <= 0.0:
		return
	var frac := hp.current_health / hp.max_health
	var want := 2 if frac <= 0.33 else (1 if frac <= 0.66 else 0)
	while stage < want:
		stage += 1
		_crack()

## One visible damage step: scorch the block, open glowing fracture seams across
## its faces, knock it off true, and throw sparks and grit.
func _crack() -> void:
	var scorch := StandardMaterial3D.new()
	scorch.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch.albedo_color = Color(0.02, 0.02, 0.02, 0.28 * stage)
	scorch.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_overlay = scorch
	var seam := StandardMaterial3D.new()
	seam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seam.albedo_color = Color(1.0, 0.45, 0.12)
	var half := size * 0.5
	# One new seam on every side face per stage, so the damage reads from any angle.
	for f in 4:
		var on_x := f < 2
		var sgn := 1.0 if f % 2 == 0 else -1.0
		var face := Vector3(sgn * (half.x + 0.012), 0, 0) if on_x else Vector3(0, 0, sgn * (half.z + 0.012))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var span := (size.z if on_x else size.x) * randf_range(0.4, 0.85)
		bm.size = Vector3(0.02, 0.05, span) if on_x else Vector3(span, 0.05, 0.02)
		bm.material = seam
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = face + Vector3(0, randf_range(-half.y, half.y) * 0.7, 0)
		mi.rotation = Vector3(deg_to_rad(randf_range(-35, 35)), 0, 0) if on_x \
			else Vector3(0, 0, deg_to_rad(randf_range(-35, 35)))
		_mesh.add_child(mi)
	# Visual lean only: the collider stays true so the navmesh and cover math hold.
	_mesh.rotation = Vector3(deg_to_rad(randf_range(-2.0, 2.0)) * stage, 0, deg_to_rad(randf_range(-2.0, 2.0)) * stage)
	_mesh.position.y = -0.04 * stage
	_puff(3 + stage * 2)
	AudioBus.play_synth_at("impact_metal", global_position, 1.0, randf_range(0.55, 0.7))

func _puff(n: int) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var half := size * 0.5
	for i in n:
		var fx := IMPACT.instantiate()
		parent.add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(
			randf_range(-half.x, half.x), randf_range(-half.y, half.y) * 0.8, randf_range(-half.z, half.z))

func _on_destroyed(source: Node) -> void:
	if _dead:
		return
	_dead = true
	var parent := get_parent()
	var at := global_position
	var col := Color(0.45, 0.46, 0.5)
	if _base_mat is StandardMaterial3D:
		col = (_base_mat as StandardMaterial3D).albedo_color * Color(0.6, 0.6, 0.62)
	Destructible.burst_debris(parent, at, col, 16 + int(size.x * size.z * 2.0), 5.5)
	_dust(parent, at)
	_puff(5)
	_rubble(parent, at)
	_shrapnel(source, at)
	AudioBus.play_synth_at("explosion", at, 0.0, randf_range(0.45, 0.55))
	AudioBus.play_synth_at("impact_metal", at, 3.0, randf_range(0.5, 0.6))
	var p := get_tree().get_first_node_in_group("player")
	if p is Node3D and p.has_method("shake"):
		var pd := (p as Node3D).global_position.distance_to(at)
		if pd < 12.0:
			p.shake(clampf(1.0 - pd / 12.0, 0.0, 1.0) * 0.5)
	shattered.emit(self)
	queue_free()
	# Robots path through the gap once the block is gone (debounced, threaded).
	get_tree().call_group("level_builder", "request_nav_rebake")

## Flying fragments hurt whatever stood next to the block. Credited to whoever broke
## it, so a player blowing out an enemy's cover scores the shrapnel kill, and
## Damageable's side filter keeps a boss's slam from hurting its own robots.
func _shrapnel(source: Node, at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = SHRAPNEL_RADIUS + maxf(size.x, size.z) * 0.5
	q.shape = s
	q.transform = Transform3D(Basis(), at)
	q.collision_mask = 0b0000110 # player + enemy
	var seen := {}
	for h in space.intersect_shape(q, 24):
		var c: Node = h.get("collider")
		if c == null or c == self:
			continue
		var d = c.get_node_or_null("Damageable")
		if d == null or seen.has(d):
			continue
		seen[d] = true
		var dist := (c as Node3D).global_position.distance_to(at)
		var falloff := clampf(1.0 - dist / s.radius, 0.2, 1.0)
		d.apply_damage(SHRAPNEL_DAMAGE * falloff, source, false, at)

func _dust(parent: Node, at: Vector3) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 18
	p.lifetime = 1.8
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = size * 0.5
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -0.4, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sm.material = mat
	p.mesh = sm
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.53, 0.5, 0.55))
	g.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.4).timeout.connect(p.queue_free)

## A low pile of slabs where the block stood: the room remembers the fight. Visual
## only (no collider), so the rebaked navmesh treats the spot as open floor.
func _rubble(parent: Node, at: Vector3) -> void:
	if parent == null:
		return
	var floor_y := at.y - size.y * 0.5
	var root := Node3D.new()
	root.name = "CoverRubble"
	root.add_to_group("cover_rubble")
	parent.add_child(root)
	root.global_position = Vector3(at.x, floor_y, at.z)
	var dark := StandardMaterial3D.new()
	dark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark.albedo_color = Color(0.02, 0.02, 0.02, 0.45)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var n := clampi(int(size.x * size.z * 1.5), 4, 9)
	for i in n:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.25, 0.7), randf_range(0.08, 0.28), randf_range(0.25, 0.7))
		mi.mesh = bm
		mi.material_override = _base_mat
		mi.material_overlay = dark
		root.add_child(mi)
		mi.position = Vector3(randf_range(-size.x, size.x) * 0.45, bm.size.y * 0.4, randf_range(-size.z, size.z) * 0.45)
		mi.rotation = Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25))
