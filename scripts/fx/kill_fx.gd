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
##
## How the style travels: the weapon tags the victim's Damageable (`kill_fx`)
## for the duration of its apply_damage call (tag/untag below). `died` fires
## synchronously inside that call, so EnemyBase._on_died reads the tag of the
## hit that killed it and nothing else: grenades, hazards and enemy fire never
## tag, so they keep the classic death even on a robot an energy gun softened.
## Bosses (score >= 1000) keep their own deaths. Covered by tests/kill_fx_probe.

enum { NONE, DISINTEGRATE, ELECTROCUTE }

const DISSOLVE_SHADER := preload("res://shaders/dissolve.gdshader")
const DISSOLVE_TIME := 1.0
const SHOCK_TIME := 0.75
const DISSOLVE_EDGE := Color(0.45, 0.9, 1.0)
const SHOCK_COLOR := Color(0.25, 0.55, 1.0)

static func tag(d: Object, style: int) -> void:
	if style != NONE and is_instance_valid(d) and d is Damageable:
		(d as Damageable).kill_fx = style

static func untag(d: Object) -> void:
	if is_instance_valid(d) and d is Damageable:
		(d as Damageable).kill_fx = NONE


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
