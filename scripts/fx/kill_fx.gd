# @lat: [[weapons#Kill Styles]]
class_name KillFx
extends RefCounted
## Weapon-specific deaths. Every robot used to die the same way (blast, debris,
## topple, sink) whatever killed it; the weapon that lands the killing blow now
## picks how the chassis goes:
##   DISINTEGRATE (gauss, longshot, plasma, OMEGA) - the robot locks up and burns
##     away top-down behind a glowing edge (shaders/dissolve.gdshader), shedding
##     rising embers, leaving an ash scorch. No wreck, no debris.
##   ELECTROCUTE (tesla, arc coil, tempest) - the robot convulses under crawling
##     arcs and a blue skin flicker for SHOCK_TIME, then blows like a normal kill.
##   SHRED (breacher shotgun, .50 magnum) - the slug lifts the robot off its feet
##     and hurls it SHRED_FLING metres away from the shooter in a tumbling arc,
##     hot scrap spraying out of its back; the classic blast goes off where it
##     lands. A wall behind it cuts the flight short. Flyers get the spray and a
##     kick along the shot instead (EnemyBase._shred_kick).
##   DECAPITATE (a killing HEADSHOT from a gun with no style of its own: pistol,
##     rifle) - the head bone folds into the neck, the head is flung with its
##     eye still lit, the neck fountains sparks, and the headless chassis rocks
##     back for DECAP_TIME before the classic blast (EnemyBase._decapitate).
##     The weapon tags it, not WeaponData; robots with no head bone (rigid
##     models, flyers) fall back to their ordinary death.
##   BLAST (Devastator, Swarm Launcher) - the rocket blows the robot apart:
##     BLAST_LIMBS limbs and the head torn off at once and flung outward, the
##     torso lofted BLAST_LIFT metres and tumbling through two chain-reaction
##     pops, then the classic blast where it comes down (EnemyBase._blast_apart).
##     Flyers detonate in the air instead of falling.
##
## How the style travels: the weapon tags the victim's Damageable (`kill_fx`)
## for the duration of its apply_damage call (tag/untag below). `died` fires
## synchronously inside that call, so EnemyBase._on_died reads the tag of the
## hit that killed it and nothing else: grenades, hazards and enemy fire never
## tag, so they keep the classic death even on a robot an energy gun softened.
## Bosses (score >= 1000) keep their own deaths. Covered by tests/kill_fx_probe.

enum { NONE, DISINTEGRATE, ELECTROCUTE, SHRED, DECAPITATE, BLAST }

const DISSOLVE_SHADER := preload("res://shaders/dissolve.gdshader")
const DISSOLVE_TIME := 1.0
const SHOCK_TIME := 0.75
const DISSOLVE_EDGE := Color(0.45, 0.9, 1.0)
const SHOCK_COLOR := Color(0.25, 0.55, 1.0)
const SHRED_TIME := 0.42
const SHRED_FLING := 3.2
const SHRED_LIFT := 0.8 ## apex of the flight arc above the start, metres
const SHRED_KICK := 9.0 ## m/s a shredded flyer is knocked along the shot
const DECAP_TIME := 0.55
const BLAST_TIME := 0.7
const BLAST_LIFT := 1.6
const BLAST_LIMBS := 4

## Tags `d` with the style and the gun (`weapon`, a WeaponData) of the hit about
## to be applied; untag right after apply_damage returns.
static func tag(d: Object, style: int, weapon: WeaponData = null) -> void:
	if is_instance_valid(d) and d is Damageable:
		(d as Damageable).kill_fx = style
		(d as Damageable).hit_weapon = weapon

static func untag(d: Object) -> void:
	if is_instance_valid(d) and d is Damageable:
		(d as Damageable).kill_fx = NONE
		(d as Damageable).hit_weapon = null


# ---------- DISINTEGRATE ----------

## Burns `enemy` away and frees it. Returns the meshes it converted (the probe
## reads their dissolve progress).
static func disintegrate(enemy: Node3D) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var glows: Array[MeshInstance3D] = []
	for n in enemy.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if _is_glow(mi):
			glows.append(mi) # additive halos/rings: a shader swap would make them opaque
		else:
			meshes.append(mi)
	var box := _world_box(meshes, enemy.global_position)
	for mi in meshes:
		_to_dissolve(mi)
		mi.set_instance_shader_parameter("y_lo", box.position.y)
		mi.set_instance_shader_parameter("y_hi", box.end.y)
	var burn := func(v: float) -> void:
		for mi in meshes:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter("dissolve", v)
	var tw := enemy.create_tween()
	tw.tween_method(burn, 0.0, 1.0, DISSOLVE_TIME)
	# Lifted a hand's width as it goes: the beam is boiling it off the floor.
	tw.parallel().tween_property(enemy, "position:y", enemy.position.y + 0.25, DISSOLVE_TIME)
	for g in glows:
		tw.parallel().tween_callback(g.hide).set_delay(0.25)
	tw.tween_callback(enemy.queue_free)

	var parent := enemy.get_parent()
	if parent:
		_embers(parent, box)
		_flash(parent, box.get_center(), DISSOLVE_EDGE, 5.0, DISSOLVE_TIME)
		var ash := ScorchMark.new()
		ash.radius = clampf(box.size.x * 0.6, 0.8, 2.0)
		parent.add_child(ash)
		ash.global_position = Vector3(box.get_center().x, box.position.y - 0.3, box.get_center().z)
	AudioBus.play_synth_at("charge", box.get_center(), -3.0, 1.7)
	return meshes

static func _is_glow(mi: MeshInstance3D) -> bool:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s) as BaseMaterial3D
		if m and (m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
				or m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED):
			return true
	return false

## Swaps every surface for a dissolve material that copies the look it replaces
## (StandardMaterial3D or the triplanar damaged_robot shader, which use the same
## albedo_tex / albedo_color names).
static func _to_dissolve(mi: MeshInstance3D) -> void:
	for s in mi.mesh.get_surface_count():
		var src := mi.get_active_material(s)
		var sm := ShaderMaterial.new()
		sm.shader = DISSOLVE_SHADER
		var col := Color.WHITE
		var tex: Texture2D = null
		var metal := 0.4
		var rough := 0.6
		if src is BaseMaterial3D:
			col = src.albedo_color
			tex = src.albedo_texture
			metal = src.metallic
			rough = src.roughness
		elif src is ShaderMaterial:
			var c = src.get_shader_parameter("albedo_color")
			if c is Color:
				col = c
			var t = src.get_shader_parameter("albedo_tex")
			if t is Texture2D:
				tex = t
			var mv = src.get_shader_parameter("metallic")
			if mv is float:
				metal = mv
			var rv = src.get_shader_parameter("roughness")
			if rv is float:
				rough = rv
		sm.set_shader_parameter("albedo_color", col)
		sm.set_shader_parameter("albedo_tex", tex)
		sm.set_shader_parameter("has_tex", tex != null)
		sm.set_shader_parameter("metallic", metal)
		sm.set_shader_parameter("roughness", rough)
		sm.set_shader_parameter("edge_color", DISSOLVE_EDGE)
		mi.set_surface_override_material(s, sm)
	mi.material_override = null
	mi.material_overlay = null # battle-damage overlay would otherwise float over the holes

## A reversible _to_dissolve for a robot that comes back whole (DIFFUSION's
## noise-out, a ROLLBACK restore): swaps every chassis surface under `root` onto
## the dissolve shader and returns what it replaced, for restore_dissolve.
## Additive glows just hide. `only_visible` false also takes meshes that are
## hidden right now (a fit_height model hides its mesh until it is fitted).
static func swap_to_dissolve(root: Node, edge: Color, height_bias: float, noise_scale: float,
		only_visible := true) -> Dictionary:
	var saved: Array = []
	var glows: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or (only_visible and not mi.is_visible_in_tree()):
			continue
		if _is_glow(mi):
			glows.append(mi)
			mi.hide()
			continue
		var surf: Array = []
		for s in mi.mesh.get_surface_count():
			surf.append(mi.get_surface_override_material(s))
		saved.append({"mi": mi, "override": mi.material_override, "overlay": mi.material_overlay, "surfaces": surf})
		_to_dissolve(mi)
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as ShaderMaterial
			m.set_shader_parameter("edge_color", edge)
			m.set_shader_parameter("height_bias", height_bias)
			m.set_shader_parameter("noise_scale", noise_scale)
	return {"saved": saved, "glows": glows}

## Sets the dissolve amount (0 whole, 1 gone) on a swap_to_dissolve record, and
## the world-height band a height_bias wipe runs over when `y_band` is given.
static func set_dissolve(rec: Dictionary, v: float, y_band := Vector2.INF) -> void:
	for r in rec.get("saved", []):
		var mi: MeshInstance3D = r["mi"]
		if not is_instance_valid(mi):
			continue
		mi.set_instance_shader_parameter("dissolve", v)
		if y_band != Vector2.INF:
			mi.set_instance_shader_parameter("y_lo", y_band.x)
			mi.set_instance_shader_parameter("y_hi", y_band.y)

## Puts back every material and glow a swap_to_dissolve record replaced.
static func restore_dissolve(rec: Dictionary) -> void:
	for r in rec.get("saved", []):
		var mi: MeshInstance3D = r["mi"]
		if not is_instance_valid(mi):
			continue
		var surf: Array = r["surfaces"]
		for s in surf.size():
			mi.set_surface_override_material(s, surf[s])
		mi.material_override = r["override"]
		mi.material_overlay = r["overlay"]
	for g in rec.get("glows", []):
		if is_instance_valid(g):
			g.show()
	rec.clear()

static func _world_box(meshes: Array[MeshInstance3D], fallback: Vector3) -> AABB:
	var box := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if first:
		box = AABB(fallback, Vector3(1.0, 2.0, 1.0))
	return box

## Embers boiling up off the burn front: emitted through the chassis volume for
## the length of the dissolve, rising and cooling from edge-cyan to ember-orange.
static func _embers(parent: Node, box: AABB) -> void:
	var p := CPUParticles3D.new()
	var low: bool = GraphicsSettings.is_low()
	p.amount = clampi(int(box.size.length() * (14.0 if low else 32.0)), 12, 120)
	p.lifetime = 1.1
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box.size * 0.5
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 2.2, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.97, 1.0, 1.0))
	grad.add_point(0.4, Color(1.0, 0.55, 0.2, 0.9))
	grad.set_color(grad.get_point_count() - 1, Color(1.0, 0.3, 0.1, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	parent.add_child(p)
	p.global_position = box.get_center()
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(DISSOLVE_TIME)
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(p.lifetime + 0.2)
	tw.tween_callback(p.queue_free)

static func _flash(parent: Node, at: Vector3, col: Color, energy: float, fade: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = GraphicsSettings.flash_energy(energy) # accessibility: flash-intensity slider
	l.omni_range = 6.0
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = at
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, fade).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)
	return l


# ---------- ELECTROCUTE ----------

## Convulses `enemy` under arcs for SHOCK_TIME, then calls `then` (the classic
## blast + topple). The overlay and jitter are undone first, so the wreck that
## topples is the ordinary one.
static func electrocute(enemy: Node3D, then: Callable) -> void:
	var meshes: Array[MeshInstance3D] = []
	for n in enemy.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and not _is_glow(mi):
			meshes.append(mi)
	var box := _world_box(meshes, enemy.global_position)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Mixed, not additive: the kill also flares the chassis' red damage glow,
	# and red + additive blue reads pink rather than electric.
	skin.albedo_color = Color(SHOCK_COLOR, 0.0)
	var saved: Array[Material] = []
	for mi in meshes:
		saved.append(mi.material_overlay)
		mi.material_overlay = skin
	var base_rot := enemy.rotation
	var base_pos := enemy.position
	var parent := enemy.get_parent()
	var light: OmniLight3D = null
	if parent:
		light = _flash(parent, box.get_center(), SHOCK_COLOR, 4.0, SHOCK_TIME + 0.1)
	AudioBus.play_synth_at("radio_static", box.get_center(), -2.0, 1.5)

	var spasm := func(k: float) -> void:
		var a := 0.11 * k
		enemy.rotation = base_rot + Vector3(randf_range(-a, a), randf_range(-a, a) * 1.6, randf_range(-a, a))
		enemy.position = base_pos + Vector3(randf_range(-0.03, 0.03), randf_range(0.0, 0.05), randf_range(-0.03, 0.03))
		skin.albedo_color.a = randf_range(0.35, 0.85)
		if is_instance_valid(light):
			light.light_energy *= randf_range(0.6, 1.25)
		if is_instance_valid(parent):
			var b := _world_box(meshes, enemy.global_position)
			_arc(parent, _point_in(b), _point_in(b), b.size.length() * 0.08)
	var finish := func() -> void:
		enemy.rotation = base_rot
		enemy.position = base_pos
		for j in meshes.size():
			if is_instance_valid(meshes[j]):
				meshes[j].material_overlay = saved[j]
		then.call()
	var tw := enemy.create_tween()
	var step := 0.06
	var steps := int(SHOCK_TIME / step)
	for i in steps:
		# Spasms ease a little as it dies.
		tw.tween_callback(spasm.bind(1.0 - float(i) / float(steps) * 0.4))
		tw.tween_interval(step)
	tw.tween_callback(finish)

static func _point_in(b: AABB) -> Vector3:
	return b.position + Vector3(randf(), randf_range(0.15, 0.95), randf()) * b.size

## One short jagged bolt between two points on the chassis, gone in 0.09 s.
static func _arc(parent: Node, a: Vector3, b: Vector3, jitter: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = SHOCK_COLOR.lerp(Color.WHITE, 0.6)
	var segs := 4
	var prev := a
	for s in range(1, segs + 1):
		var point := a.lerp(b, float(s) / float(segs))
		if s < segs:
			point += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * jitter
		var seg_len := prev.distance_to(point)
		if seg_len > 0.01:
			var mi := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.022
			cyl.bottom_radius = 0.022
			cyl.height = seg_len
			cyl.radial_segments = 4
			cyl.rings = 1
			cyl.material = mat
			mi.mesh = cyl
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			var up := (point - prev).normalized()
			var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			var x := side.cross(up).normalized()
			mi.global_transform = Transform3D(Basis(x, up, x.cross(up).normalized()), (prev + point) * 0.5)
		prev = point
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(root.queue_free)


# ---------- SHRED ----------

## Hurls `enemy` along `dir` (the shot's line; flattened) in a short tumbling
## arc, then calls `then` (the classic blast + topple) where it lands. The
## robot's collision is already off, so a ray against the world (layer 1) keeps
## it from flying through a wall.
static func shred(enemy: Node3D, dir: Vector3, then: Callable) -> void:
	dir = _flat(dir, enemy)
	var chest := enemy.global_position + Vector3.UP * 1.0
	var dist := SHRED_FLING
	if enemy.is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(chest, chest + dir * (SHRED_FLING + 0.7), 1)
		var hit := enemy.get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			dist = maxf(0.0, chest.distance_to(hit.position) - 0.7)
	var parent := enemy.get_parent()
	if parent:
		spray(parent, chest, dir)
	AudioBus.play_synth_at("impact_metal", chest, 0.0, 0.55)

	var local_dir := dir
	if parent is Node3D:
		local_dir = ((parent as Node3D).global_basis.inverse() * dir).normalized()
	var start := enemy.position
	var end := start + local_dir * dist
	var base_rot := enemy.rotation
	# Tipped over backwards (same sense as the classic topple, which picks up
	# from here), most at the apex, settling as it comes down.
	var tip := Vector3(local_dir.z, 0.0, -local_dir.x) * deg_to_rad(38.0)
	var spin := randf_range(-0.6, 0.6)
	var fly := func(t: float) -> void:
		var e := 1.0 - (1.0 - t) * (1.0 - t) # fast off the mark, slowing
		enemy.position = start.lerp(end, e) + Vector3.UP * (4.0 * SHRED_LIFT * t * (1.0 - t))
		enemy.rotation = base_rot + tip * sin(t * PI * 0.8) + Vector3(0.0, spin * t, 0.0)
	var tw := enemy.create_tween()
	tw.tween_method(fly, 0.0, 1.0, SHRED_TIME)
	tw.tween_callback(then)

## Hot scrap and sparks out of the exit side of a shredded chassis: chunky
## tumbling shards that fall and cool from orange to soot, plus a fast spark
## fan. Both one-shot and self-freeing.
static func spray(parent: Node, at: Vector3, dir: Vector3) -> void:
	var low: bool = GraphicsSettings.is_low()
	var shards := _burst(parent, at, dir, 10 if low else 22, 26.0, Vector2(4.0, 9.0), 0.9)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.05, 0.13)
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.metallic = 0.6
	sm.roughness = 0.45
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.45, 0.12)
	sm.emission_energy_multiplier = 1.6
	bm.material = sm
	shards.mesh = bm
	shards.gravity = Vector3(0, -16.0, 0)
	shards.angular_velocity_min = -720.0
	shards.angular_velocity_max = 720.0
	shards.scale_amount_min = 0.6
	shards.scale_amount_max = 1.5
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.4))
	g.add_point(0.35, Color(0.55, 0.32, 0.2))
	g.set_color(g.get_point_count() - 1, Color(0.12, 0.11, 0.1))
	shards.color_ramp = g

	var sparks := _burst(parent, at, dir, 14 if low else 36, 34.0, Vector2(9.0, 17.0), 0.35)
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	q.material = pm
	sparks.mesh = q
	sparks.gravity = Vector3(0, -9.0, 0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 1.0
	sparks.scale_amount_max = 3.0
	var sg := Gradient.new()
	sg.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	sg.set_color(sg.get_point_count() - 1, Color(1.0, 0.4, 0.1, 0.0))
	sparks.color_ramp = sg

static func _burst(parent: Node, at: Vector3, dir: Vector3, amount: int, spread: float,
		speed: Vector2, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "ShredScrap"
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.lifetime = life
	p.direction = (dir + Vector3.UP * 0.35).normalized()
	p.spread = spread
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(life + 0.3)
	tw.tween_callback(p.queue_free)
	return p

## `dir` flattened and normalised; with no direction, backwards off the robot's
## facing (EnemyBase turns its -Z toward what it fights).
# ---------- DECAPITATE ----------

## Sparks spurting up out of a severed neck for `time` seconds, then dying off.
static func neck_fountain(parent: Node, at: Vector3, time: float) -> void:
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.name = "NeckFountain"
	p.amount = 18 if GraphicsSettings.is_low() else 44
	p.lifetime = 0.55
	p.direction = Vector3.UP
	p.spread = 22.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.5
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.4
	p.particle_flag_align_y = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.add_point(0.4, Color(1.0, 0.55, 0.15, 0.9))
	g.set_color(g.get_point_count() - 1, Color(1.0, 0.25, 0.05, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(time)
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(p.lifetime + 0.2)
	tw.tween_callback(p.queue_free)

static func _flat(dir: Vector3, enemy: Node3D) -> Vector3:
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = enemy.global_basis.z
		dir.y = 0.0
	return dir.normalized()
