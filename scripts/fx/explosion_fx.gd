class_name ExplosionFX
extends Object
## Shared explosion "anim" layer: the particle systems in the explosion scenes
## provide the debris/smoke, this adds the read — a hot expanding fireball
## core, a ground shockwave ring, a popping (not just fading) light, and a
## proximity camera kick. Everything is built and tweened in code so both
## explosion scenes (and any future ones) stay in sync.

## `size` ~ the blast's visual radius in metres. Call from the FX root's _ready.
static func detonate(root: Node3D, size: float = 2.2, color: Color = Color(1.0, 0.62, 0.25)) -> void:
	_fireball(root, size, color)
	_shockwave(root, size, color)
	_light_pop(root)
	_kick_player(root, size)

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
	mat.emission_energy_multiplier = 7.0
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
