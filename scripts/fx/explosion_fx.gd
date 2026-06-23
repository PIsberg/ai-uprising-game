class_name ExplosionFX
extends Object
## Shared explosion "anim" layer: the particle systems in the explosion scenes
## provide the debris/smoke, this adds the read — a hot expanding fireball
## core, a ground shockwave ring, a popping (not just fading) light, and a
## proximity camera kick. Everything is built and tweened in code so both
## explosion scenes (and any future ones) stay in sync.

## `size` ~ the blast's visual radius in metres. Call from the FX root's _ready.
static func detonate(root: Node3D, size: float = 2.2, color: Color = Color(1.0, 0.62, 0.25)) -> void:
	_flash(root, size)
	_fireball(root, size, color)
	_shockwave(root, size, color)
	_embers(root, size, color)
	_light_pop(root)
	_kick_player(root, size)

## An instantaneous oversized white blink — the eye can't track the detonation
## frame, so a single bright pop reads as raw energy before the fireball forms.
static func _flash(root: Node3D, size: float) -> void:
	var fl := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# HDR-bright additive sear (>1): on an HDR display this is genuine peak
	# brightness, and everywhere it punches well past the glow threshold so the
	# detonation frame blooms hard instead of just reading as plain white.
	mat.albedo_color = Color(3.0, 3.0, 2.8, 1)
	sm.material = mat
	fl.mesh = sm
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fl.scale = Vector3.ONE * size * 1.6
	root.add_child(fl)
	var tw := fl.create_tween().set_parallel(true)
	tw.tween_property(fl, "scale", Vector3.ONE * size * 2.1, 0.12)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(fl.queue_free)

## A spray of hot ember darts hurled outward — the shrapnel read that turns a
## glowing puff into a detonation. One burst, dies with the FX root.
static func _embers(root: Node3D, size: float, color: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = int(clampf(14.0 * size, 14.0, 60.0))
	p.lifetime = 0.55
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = 5.0 * size
	p.initial_velocity_max = 11.0 * size
	p.gravity = Vector3(0, -16.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	# Tumble the shrapnel and burn it down to a streak — 4.7's richer per-particle
	# scale/rotation makes the darts read as spinning sparks, not sliding dashes.
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -900.0
	p.angular_velocity_max = 900.0
	p.scale_amount_curve = _ember_taper_curve()
	var dart := BoxMesh.new()
	dart.size = Vector3(0.05, 0.05, 0.16) # stretched -> reads as a streak
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 6.0
	dart.material = m
	p.mesh = dart
	root.add_child(p)

## A short-lived smoke plume that boils up where the fireball was — the aftermath
## that tells you something just died here.
static func _smoke(root: Node3D, size: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = int(clampf(8.0 * size, 8.0, 28.0))
	p.lifetime = 1.1
	p.explosiveness = 0.7
	p.spread = 60.0
	p.direction = Vector3.UP
	p.initial_velocity_min = 1.2 * size
	p.initial_velocity_max = 2.6 * size
	p.gravity = Vector3(0, 1.2, 0) # buoyant — rises and slows
	p.scale_amount_min = size * 0.5
	p.scale_amount_max = size * 0.9
	p.scale_amount_curve = _ramp_up_curve()
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 6
	puff.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.12, 0.11, 0.1, 0.55)
	puff.material = m
	p.mesh = puff
	root.add_child(p)

## Particle scale curve that grows from small to full — smoke billowing out.
static func _ramp_up_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(1.0, 1.0))
	return c

## Embers pop to full size then shrink to a dying spark over their lifetime.
static func _ember_taper_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.65, 0.7))
	c.add_point(Vector2(1.0, 0.0))
	return c

## A white-hot core that balloons out and burns off in a tenth of a second —
## the single biggest "explosion, not particle puff" cue.
static func _fireball(root: Node3D, size: float, color: Color) -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.95, 0.8, 0.95) # white-hot at birth
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 13.0 # HDR-hot core: blooms hard, sears on HDR
	sm.material = mat
	ball.mesh = sm
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.scale = Vector3.ONE * 0.25
	root.add_child(ball)
	var tw := ball.create_tween().set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * size, 0.18) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# Cool from white-hot to the blast color as it expands, then burn off fast —
	# a flash should be gone before the smoke takes over.
	tw.tween_property(mat, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.24) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.24)
	tw.chain().tween_callback(ball.queue_free)

## A flattened ring racing outward at ankle height — sells the pressure wave.
static func _shockwave(root: Node3D, size: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.4)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	tm.material = mat
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.3, 0.08, 0.3)
	ring.position = Vector3(0, 0.15, 0)
	root.add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(size * 1.7, 0.05, size * 1.7), 0.32) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.32) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)

## Light pops UP for two frames before decaying — a flash, not a dimmer switch.
static func _light_pop(root: Node3D) -> void:
	var light := root.get_node_or_null("Light") as OmniLight3D
	if light == null:
		return
	var peak := light.light_energy
	light.light_energy = peak * 0.4
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", peak * 1.6, 0.05)
	tw.tween_property(light, "light_energy", 0.0, 0.45) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

## Distance-scaled camera kick so nearby blasts physically land.
static func _kick_player(root: Node3D, size: float) -> void:
	var p := root.get_tree().get_first_node_in_group("player")
	if p == null or not p.has_method("shake"):
		return
	var reach := size * 6.0
	var d := (p as Node3D).global_position.distance_to(root.global_position)
	if d < reach:
		p.shake(clampf(1.0 - d / reach, 0.0, 1.0) * clampf(size / 3.0, 0.35, 0.85))
