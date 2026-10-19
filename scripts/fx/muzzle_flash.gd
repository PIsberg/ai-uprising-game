extends Node3D
## A gunshot's muzzle flash: three additive cards drawn by
## shaders/muzzle_flash.gdshader, the cheap trick most shooters use instead of a
## ball of light. A front star sits across the bore (a hot core with 4-7 jagged
## petals, a new count and roll every shot) and two side prongs lie along the
## barrel as crossed flame tongues reaching forward. The weapon sets `along_bore`
## (its Muzzle's -Z is the barrel); without it, as on the enemies, whose muzzle
## nodes face anywhere, the flash is one camera-facing star. A pop of spill light
## and a burst of spark darts go with it. Covered by tests/muzzle_flash_probe.

const SHADER: Shader = preload("res://shaders/muzzle_flash.gdshader")
const STAR_SIZE := 0.28 ## metres across the star card at size 1
const PRONG_SIZE := Vector2(0.13, 0.42) ## a prong card's width and reach at size 1
const ENERGY := 4.0
## The star's size multiplier never exceeds this: a big gun's flash at a short
## gun's distance from the eye (the .50) would otherwise fill a third of the
## view. The prongs keep the full size, so heavy guns still read heavier.
const STAR_MAX := 1.35

@export var lifetime: float = 0.06
## Set by the weapon before add_child: a per-weapon flash tint + overall size, so
## a pistol pops a small white flash while an energy cannon belches a big blue one.
@export var tint_color: Color = Color(1.0, 0.78, 0.38)
@export var size_mult: float = 1.0
## Set by the weapon before add_child: this node's -Z is the bore, so build the
## prongs along it and turn the star across it.
@export var along_bore: bool = false

var star: MeshInstance3D = null
var prongs: Array[MeshInstance3D] = []
var _age: float = 0.0
var _size: float = 1.0
var _seed: float = 0.0
## Accessibility: flash-intensity multiplier (1.0 = full, 0 = no strobe light
## at all), cached once so _process doesn't re-touch the autoload every frame.
var _flash_mult: float = 1.0

## The three cards (one when it has no bore to align to).
func cards() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if star:
		out.append(star)
	out.append_array(prongs)
	return out

## This shot's pattern: two flashes with the same value would look the same.
func seed_value() -> float:
	return _seed

func _ready() -> void:
	# No two flashes alike: random roll and petal count, per-shot size jitter.
	_seed = randf() * 1000.0
	_size = randf_range(0.8, 1.3) * size_mult
	var petals := float(randi_range(4, 7))
	var star_size := STAR_SIZE * minf(1.0, STAR_MAX / maxf(0.01, _size))
	star = _card(Vector2(star_size, star_size), 0, petals)
	star.position.z = -0.02
	star.rotation.z = randf() * TAU
	if along_bore:
		# Crossed tongues along the barrel: the quad's +Y turned to -Z puts its
		# bore end (UV.y = 1) at the muzzle and its tip out ahead.
		for roll in [0.0, PI * 0.5]:
			var prong := _card(PRONG_SIZE, 1, petals)
			prong.basis = Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, -PI * 0.5)
			prong.position = Vector3(0, 0, -PRONG_SIZE.y * 0.5)
			prongs.append(prong)
	else:
		(star.material_override as ShaderMaterial).set_shader_parameter("billboard", true)
	# Accessibility: read the flash-intensity slider once up front (headless-safe
	# — GraphicsSettings may be absent under --script). 0 means the strobe light
	# is skipped entirely; the emissive cards + sparks below are unaffected.
	var gs := get_node_or_null("/root/GraphicsSettings")
	_flash_mult = 1.0 if gs == null else gs.flash_energy(1.0)
	# The flash's spill light is the single most-spammed FX light in the game —
	# one per shot, and the node lingered ~0.45 s for the sparks even after the
	# light itself zeroed at `lifetime`. Gate it on the global FX-light budget
	# (over budget: drop it entirely — the cards still read), and either way it's
	# freed the instant it goes dark (see _process) instead of idling in the
	# cluster for the rest of the spark tail.
	for c in get_children():
		if c is OmniLight3D:
			# Accessibility: flash_intensity == 0 means no strobe light at all —
			# free it up front instead of taking an FX-light budget slot for it.
			if _flash_mult <= 0.0 or not FXLights.take():
				c.queue_free()
			else:
				(c as OmniLight3D).light_color = tint_color
				(c as OmniLight3D).light_energy *= _flash_mult # rides the accessibility slider
				(c as OmniLight3D).tree_exited.connect(FXLights.give)
	_tick(0.0)
	_spawn_sparks()

func _card(size: Vector2, shape: int, petals: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tint", tint_color)
	m.set_shader_parameter("energy", ENERGY)
	m.set_shader_parameter("petals", petals)
	m.set_shader_parameter("seed", _seed)
	m.set_shader_parameter("shape", shape)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF # flashes don't shadow
	add_child(mi)
	return mi

func _process(delta: float) -> void:
	_age += delta
	if _age > lifetime:
		# Flash is spent; go dark but linger so the spark burst can finish. FREE the
		# light now (not just zero it) — a dead light idling in the cluster for the
		# 0.45 s spark tail was pure cost, and freeing it returns its budget slot.
		for c in get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false
			elif c is OmniLight3D:
				c.queue_free()
		if _age > 0.45:
			queue_free()
		return
	_tick(_age)

## Pose the flash `age` seconds in: the star swells as it burns out, the
## prongs shoot further forward, the cards fade from the edges in and the light
## pops with a quadratic decay.
func _tick(age: float) -> void:
	var s := 1.0 - age / lifetime
	scale = Vector3.ONE * _size
	if star:
		star.scale = Vector3.ONE * (0.85 + 0.35 * (1.0 - s))
	for p in prongs:
		p.scale = Vector3(1.0, 0.75 + 0.5 * (1.0 - s), 1.0)
		p.position.z = -PRONG_SIZE.y * 0.5 * p.scale.y
	for c in cards():
		(c.material_override as ShaderMaterial).set_shader_parameter("fade", s)
	for c in get_children():
		if c is OmniLight3D:
			# Scaled by the accessibility flash-intensity slider.
			(c as OmniLight3D).light_energy = 9.0 * s * s * _size * _flash_mult

## Hot spark darts spat from the bore — the detail that separates a flat
## "flash card" from a gunshot. One burst per shot, dies with the node.
func _spawn_sparks() -> void:
	var dart := BoxMesh.new()
	dart.size = Vector3(0.012, 0.012, 0.07) # stretched, reads as a streak
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.6, 0.2)
	m.emission_energy_multiplier = 7.0
	dart.material = m

	var gs := get_node_or_null("/root/GraphicsSettings")
	var use_gpu: bool = gs == null or bool(gs.get("gpu_particles_enabled"))
	if use_gpu:
		# GPU path showcases 4.7's scale-over-velocity: the spark is a long hot
		# streak while it's screaming out of the bore, shrinking to a tumbling
		# ember as it slows — instead of a uniform dash.
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = true
		p.amount = 12
		p.lifetime = 0.22
		p.explosiveness = 1.0
		p.draw_pass_1 = dart
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0, -1) # out of the bore
		pm.spread = 13.0
		pm.initial_velocity_min = 7.0
		pm.initial_velocity_max = 16.0
		pm.gravity = Vector3(0, -14.0, 0)
		pm.scale_min = 0.5
		pm.scale_max = 1.0
		pm.scale_over_velocity_min = 5.0
		pm.scale_over_velocity_max = 16.0
		var sv := Curve.new()
		sv.add_point(Vector2(0.0, 0.45)) # slow -> short ember
		sv.add_point(Vector2(1.0, 2.4))  # fast -> long streak
		var svt := CurveTexture.new(); svt.curve = sv
		pm.scale_over_velocity_curve = svt
		# Tumble the dying embers.
		pm.angle_min = -180.0; pm.angle_max = 180.0
		pm.angular_velocity_min = -600.0; pm.angular_velocity_max = 600.0
		p.process_material = pm
		add_child(p)
	else:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.emitting = true
		p.amount = 10
		p.lifetime = 0.22
		p.explosiveness = 1.0
		p.direction = Vector3(0, 0, -1) # out of the bore
		p.spread = 13.0
		p.initial_velocity_min = 7.0
		p.initial_velocity_max = 14.0
		p.gravity = Vector3(0, -14.0, 0)
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.0
		p.angle_min = -180.0; p.angle_max = 180.0
		p.angular_velocity_min = -600.0; p.angular_velocity_max = 600.0
		p.mesh = dart
		add_child(p)
