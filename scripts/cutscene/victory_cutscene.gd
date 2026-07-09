extends CutscenePlayer
## The finale's victory beat — the payoff for a 22-level campaign, reached only
## from GameState.advance_level() when the campaign runs out of levels (i.e.
## ARCHON just fell). Shows the AGI brain gone dark and cracked in the Mind
## Cathedral, lingers on a last residual spark, then breaks dawn over it as the
## camera pulls back — reusing the existing night-sky shader (shaders/
## night_sky.gdshader) tweened from starfield to sunrise instead of any new art.
##
## _on_finished() (the base calls this once the 3D timeline ends or is skipped)
## layers a VictoryTransmission broadcast on the now-black screen — the "Global
## Defense Net" bookend to the campaign-opening broadcast — then hands off to
## the credits. GameState already cleared the save and set State.MENU before
## loading this scene (see advance_level()); credits.gd is what actually
## returns to main_menu.tscn.

const NIGHT_SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const CREDITS := "res://scenes/ui/credits.tscn"

const COL_DEAD := Color(0.3, 0.36, 0.44)   # cold, dim — the brain's dead glow (emission tint only)
## The circuit-gyri are UNSHADED (always visible, like the living ARCHON's),
## so their base colour alone sets how bright they read — much darker than
## COL_DEAD, or they paint a bright halo no ambient/exposure tuning can fix.
const COL_GYRI_DEAD := Color(0.1, 0.13, 0.2)
const COL_EMBER := Color(1.0, 0.55, 0.22)  # dying embers still guttering in the cracks
const COL_SHARD := Color(0.35, 0.8, 1.0)   # shattered shield glass

var _bob: Node3D
var _shell_mat: StandardMaterial3D
var _gyri_mat: StandardMaterial3D
var _core_mat: StandardMaterial3D
var _crack_mat: StandardMaterial3D
var _core_light: OmniLight3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial
var _sun_disc: MeshInstance3D
var _sun_mat: StandardMaterial3D

var _t: float = 0.0
var _spark_flash: float = 0.0
var _dawn_started: bool = false

func _build_set() -> void:
	_setup_dawn_sky()
	_build_lights()
	_build_ground_and_debris()
	_build_skyline()
	_build_sun_disc()
	_build_dead_brain()

func _get_world_environment() -> WorldEnvironment:
	for c in get_children():
		if c is WorldEnvironment:
			return c
	return null

## Swap the base cutscene's flat BG_COLOR sky for the real night-sky shader
## (starfield + Milky Way + moon) so "dawn breaking" is an actual sunrise, not
## just a lighting trick — the same tool open-sky levels use (LevelBuilder's
## "stars" env key), driven here by hand instead of a level def.
func _setup_dawn_sky() -> void:
	var we := _get_world_environment()
	if we == null:
		return
	_env = we.environment
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = NIGHT_SKY_SHADER
	_sky_mat.set_shader_parameter("zenith_color", Color(0.01, 0.012, 0.03))
	_sky_mat.set_shader_parameter("horizon_color", Color(0.03, 0.03, 0.06))
	_sky_mat.set_shader_parameter("ground_color", Color(0.01, 0.01, 0.02))
	_sky_mat.set_shader_parameter("star_density", 0.09)
	_sky_mat.set_shader_parameter("star_brightness", 2.2)
	_sky_mat.set_shader_parameter("moon_glow", 1.2)
	_sky_mat.set_shader_parameter("moon_dir", Vector3(0.3, 0.35, -0.6))
	sky.sky_material = _sky_mat
	_env.sky = sky
	_env.background_mode = Environment.BG_SKY

func _build_lights() -> void:
	# Cold ambient key while the brain is dead — a moonlit cathedral.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, 25, 0)
	key.light_color = Color(0.4, 0.5, 0.7)
	key.light_energy = 0.3
	add_child(key)
	# The dawn sun rises BEHIND the husk (yaw ~178: the camera sits at +Z looking
	# down -Z at the brain), so first light rims its silhouette and rakes through
	# the volumetric fog as god-rays, instead of flood-lighting it from the front.
	# A sunrise you look INTO is the shot; a sunrise that just tints everything
	# orange is a sepia filter.
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-5, 178, 0) # skimming the horizon, from behind
	_sun.light_color = Color(0.5, 0.55, 0.7)
	_sun.light_energy = 0.0
	_sun.shadow_enabled = true
	_sun.light_specular = 1.4 # hot rim on the wet, metallic plating
	add_child(_sun)

## The sun itself: a bright emissive disc parked below the horizon behind the
## husk, which climbs into view on the dawn beat. The sky shader draws a moon,
## not a sun, and the glow threshold (0.9) means anything this hot blooms into a
## proper flare on its own — no new shader, no lens-flare rig.
func _build_sun_disc() -> void:
	_sun_mat = StandardMaterial3D.new()
	_sun_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sun_mat.emission_enabled = true
	_sun_mat.emission = Color(1.0, 0.72, 0.42)
	_sun_mat.emission_energy_multiplier = 0.0 # dark until dawn
	_sun_mat.albedo_color = Color(1.0, 0.72, 0.42)
	_sun_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var sm := SphereMesh.new()
	sm.radius = 3.4
	sm.height = 6.8
	sm.material = _sun_mat
	_sun_disc = MeshInstance3D.new()
	_sun_disc.mesh = sm
	_sun_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Far behind the husk, sunk below the horizon line to start.
	_sun_disc.position = Vector3(1.5, -7.0, -62.0)
	add_child(_sun_disc)

## A dead city on the horizon. The old set was a bare plane meeting a bare sky,
## so "dawn" had nothing to break OVER and the shot had no sense of scale. Ruined
## towers give the sunrise a skyline to silhouette against — which is the whole
## point of putting the sun behind the camera's subject.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.022, 0.03)
	mat.roughness = 0.95
	mat.metallic = 0.1
	var root := Node3D.new()
	add_child(root)
	for i in 26:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := rng.randf_range(2.0, 6.0)
		var h := rng.randf_range(4.0, 22.0)
		bm.size = Vector3(w, h, rng.randf_range(2.0, 6.0))
		bm.material = mat
		b.mesh = bm
		# Spread along the horizon behind the husk, in two depth ranks.
		var x := rng.randf_range(-55.0, 55.0)
		var z := -42.0 - rng.randf_range(0.0, 26.0)
		# Keep the middle clear so the sun disc isn't buried in a tower.
		if absf(x) < 7.0:
			x += 12.0 * signf(x if absf(x) > 0.01 else 1.0)
		b.position = Vector3(x, h * 0.5 - 1.0, z)
		b.rotation_degrees = Vector3(0, rng.randf_range(-12, 12), rng.randf_range(-1.5, 1.5))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(b)

func _build_ground_and_debris() -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	# 220 m, not 60: the old plane ended at z=-36, so the ruined skyline (and the
	# rising sun behind it) hung over bare sky with a visible edge.
	pm.size = Vector2(220, 220)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.03, 0.035, 0.045)
	fmat.metallic = 0.6
	fmat.roughness = 0.25
	pm.material = fmat
	floor_mi.mesh = pm
	floor_mi.position = Vector3(0, 0, -6.0)
	add_child(floor_mi)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1102 # fixed layout — a cutscene set should look the same every time

	# Broken plating chunks blown off the brain during the fight.
	var chunk_mat := StandardMaterial3D.new()
	chunk_mat.albedo_color = Color(0.12, 0.13, 0.16)
	chunk_mat.roughness = 0.7
	chunk_mat.metallic = 0.5
	for i in 10:
		var chunk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := rng.randf_range(0.3, 0.9)
		bm.size = Vector3(s, s * rng.randf_range(0.3, 0.6), s * rng.randf_range(0.6, 1.2))
		bm.material = chunk_mat
		chunk.mesh = bm
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(2.0, 8.0)
		chunk.position = Vector3(cos(ang) * rad, s * 0.25, -6.0 + sin(ang) * rad)
		chunk.rotation_degrees = Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 360), rng.randf_range(-15, 15))
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(chunk)

	# Shattered shield glass, still faintly glowing.
	var shard_mat := StandardMaterial3D.new()
	shard_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shard_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shard_mat.albedo_color = Color(COL_SHARD.r, COL_SHARD.g, COL_SHARD.b, 0.35)
	shard_mat.emission_enabled = true
	shard_mat.emission = COL_SHARD
	shard_mat.emission_energy_multiplier = 1.1
	for i in 5:
		var shard := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(rng.randf_range(0.4, 0.8), rng.randf_range(0.6, 1.1), 0.06)
		prism.material = shard_mat
		shard.mesh = prism
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(1.5, 5.0)
		shard.position = Vector3(cos(ang) * rad, 0.02, -6.0 + sin(ang) * rad)
		shard.rotation_degrees = Vector3(rng.randf_range(70, 110), rng.randf_range(0, 360), 0)
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shard)

	# Slow drifting ash/embers falling through the whole scene.
	var dust := CPUParticles3D.new()
	dust.amount = 40
	dust.lifetime = 6.0
	dust.emitting = true
	dust.direction = Vector3.DOWN
	dust.spread = 30.0
	dust.initial_velocity_min = 0.2
	dust.initial_velocity_max = 0.6
	dust.gravity = Vector3(0, -0.15, 0)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.2
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(6, 1, 6)
	var dm := QuadMesh.new()
	dm.size = Vector2(0.03, 0.03)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.emission_enabled = true
	dmat.emission = COL_EMBER
	dmat.emission_energy_multiplier = 2.0
	dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.material = dmat
	dust.mesh = dm
	dust.position = Vector3(0, 8.0, -6.0)
	add_child(dust)

## A slumped, cracked-apart echo of EnemyArchon._build_brain — same procedural
## vocabulary (holographic lobes, circuit-gyri, a core, orbiting rings) but
## dead: dim, tilted, no shield. Built fresh here rather than reusing the enemy
## scene since ARCHON is already destroyed in the level itself; this is its
## inert husk afterward, not the fought boss.
func _build_dead_brain() -> void:
	_bob = Node3D.new()
	_bob.position = Vector3(0, 5.5, -6.0)
	_bob.rotation_degrees = Vector3(14, 20, 8) # slumped, dead weight
	add_child(_bob)

	# Opaque, matte dead metal — the living ARCHON's shell was a translucent
	# energy construct, but that reads as a washed-out haze once it's cracked
	# open and lit by real (not holographic) daylight, so the dead husk is a
	# solid scorched chassis instead: same silhouette, no double-blend glow.
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(0.07, 0.08, 0.1)
	_shell_mat.metallic = 0.4
	_shell_mat.roughness = 0.75
	_shell_mat.emission_enabled = true
	_shell_mat.emission = COL_DEAD
	_shell_mat.emission_energy_multiplier = 0.1
	_shell_mat.rim_enabled = true
	_shell_mat.rim = 0.4

	_gyri_mat = StandardMaterial3D.new()
	_gyri_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_gyri_mat.albedo_color = COL_GYRI_DEAD
	_gyri_mat.emission_enabled = true
	_gyri_mat.emission = COL_GYRI_DEAD
	_gyri_mat.emission_energy_multiplier = 0.5

	for side in [-1.0, 1.0]:
		var lobe := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5
		sm.height = 2.4
		sm.radial_segments = 24
		sm.rings = 16
		sm.material = _shell_mat
		lobe.mesh = sm
		lobe.position = Vector3(side * 1.7, -0.15 * absf(side), 0.0) # cracked apart + slumped
		lobe.rotation_degrees = Vector3(side * 6.0, 0, side * 10.0)
		lobe.scale = Vector3(1.0, 1.0, 1.35)
		lobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_bob.add_child(lobe)
		for i in 3:
			var fold := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 1.18 - i * 0.16
			tm.outer_radius = 1.30 - i * 0.16
			tm.rings = 20
			tm.ring_segments = 6
			tm.material = _gyri_mat
			fold.mesh = tm
			fold.position = lobe.position
			fold.rotation_degrees = Vector3(90.0, 0.0, 22.0 * (i + 1) * side)
			fold.scale = Vector3(1.0, 1.0, 1.3)
			fold.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_bob.add_child(fold)
		_add_lobe_cracks(lobe, side)

	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Was a light grey (0.4,0.42,0.48): unshaded, that albedo dominated the faint
	# emission and the "last guttering ember" rendered as a pale grey ball. The
	# core is the one warm thing left alive in the shot — let it be ember-coloured.
	_core_mat.albedo_color = Color(0.28, 0.10, 0.03)
	_core_mat.emission_enabled = true
	_core_mat.emission = COL_EMBER
	_core_mat.emission_energy_multiplier = 1.4
	var core := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.7
	cm.height = 1.4
	cm.material = _core_mat
	core.mesh = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bob.add_child(core)

	var stem := MeshInstance3D.new()
	var stm := CylinderMesh.new()
	stm.top_radius = 0.45
	stm.bottom_radius = 0.18
	stm.height = 1.6
	stm.material = _shell_mat
	stem.mesh = stm
	stem.position = Vector3(0.15, -1.5, 0.05)
	stem.rotation_degrees = Vector3(8, 0, 4)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bob.add_child(stem)

	for r in 2:
		var ring := MeshInstance3D.new()
		var rtm := TorusMesh.new()
		rtm.inner_radius = 2.8 + r * 0.4
		rtm.outer_radius = 2.95 + r * 0.4
		rtm.rings = 40
		rtm.ring_segments = 8
		rtm.material = _gyri_mat
		ring.mesh = rtm
		ring.rotation_degrees = Vector3(70.0 + r * 35.0, r * 40.0, r * 25.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bob.add_child(ring)

	_build_cracks()

	_core_light = OmniLight3D.new()
	_core_light.light_color = COL_EMBER
	_core_light.light_energy = 0.55
	_core_light.omni_range = 10.0
	_bob.add_child(_core_light)

## Ember-lit fissures across the husk. Without them the two lobes read as smooth
## dark beans at every camera angle — nothing says "this thing was broken open".
## They gutter with the core and go out when the sun takes over.
func _ensure_crack_mat() -> void:
	if _crack_mat != null:
		return
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.albedo_color = COL_EMBER
	_crack_mat.emission_enabled = true
	_crack_mat.emission = COL_EMBER
	_crack_mat.emission_energy_multiplier = 1.8

## Cracks parented to the LOBE, in the lobe's own space. Parenting them to _bob
## and doing the sphere maths by hand put them nowhere near the shell: the lobe
## is an oblate spheroid (SphereMesh radius 1.5 but height 2.4, so its vertical
## semi-axis is 1.2, not 1.5), it carries a 1.35x z-scale, and it is rotated.
## As the lobe's child, all three come for free — the crack just sits on the
## unit-ellipsoid surface and inherits the rest.
func _add_lobe_cracks(lobe: MeshInstance3D, side: float) -> void:
	_ensure_crack_mat()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407 + int(side * 13.0)
	var semi := Vector3(1.5, 1.2, 1.5) # the SphereMesh's true semi-axes
	# Five fissures, each a chain of short segments running DOWN a meridian from
	# near the crown. Random per-segment yaw made them read as scattered dashes
	# stuck on the shell; following a meridian makes them read as one split
	# travelling across the surface, which is what a crack is.
	for f in 5:
		var yaw := rng.randf_range(-1.25, 1.25)
		var pitch := rng.randf_range(0.75, 1.25) # start high on the lobe
		var drift := rng.randf_range(-0.10, 0.10)
		var segs := rng.randi_range(3, 5)
		for i in segs:
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			# Thin and tapering — a fissure narrows as it runs out of energy.
			var taper: float = 1.0 - float(i) / float(segs) * 0.55
			bm.size = Vector3(0.032 * taper, 0.012, 0.30)
			bm.material = _crack_mat
			seg.mesh = bm
			var n := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			seg.position = Vector3(n.x * semi.x, n.y * semi.y, n.z * semi.z) * 1.012
			# Aim local -Z at the centre (that is the surface normal), then swing
			# 90 deg about local X. This drops the box's length (its Z size) into
			# the tangent plane, pointing along the meridian — the direction the
			# fissure travels. A further 90 deg about local Y would lay each
			# segment ACROSS the path instead, and the crack renders as a ladder
			# of rungs rather than a line.
			seg.look_at_from_position(seg.position, Vector3.ZERO, Vector3.UP)
			seg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lobe.add_child(seg)
			pitch -= 0.20
			yaw += drift

func _build_cracks() -> void:
	_ensure_crack_mat()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407
	# The central fissure where the lobes were split apart, plus splinters
	# radiating over each lobe's crown.
	# The seam down the split between the lobes. (Surface cracks are built per
	# lobe in _build_dead_brain, parented to the lobe itself — see _add_lobe_cracks.)
	# The split itself: a hot seam down the gap between the lobes.
	for i in 4:
		var seam := MeshInstance3D.new()
		var sb := BoxMesh.new()
		# Kept short and low: taller bars poked out of the husk's silhouette and
		# read as a glowing rod balanced between the lobes, not as a hot split.
		sb.size = Vector3(0.05, rng.randf_range(0.30, 0.62), 0.05)
		sb.material = _crack_mat
		seam.mesh = sb
		seam.position = Vector3(rng.randf_range(-0.16, 0.16), rng.randf_range(-0.15, 0.62),
			rng.randf_range(-0.9, 0.9))
		seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bob.add_child(seam)

func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	# A slow, guttering ember pulse — the brain isn't fully cold yet.
	#
	# Stops at dawn, and this is not cosmetic: _break_dawn() tweens the core's
	# emission and the core light down to nothing, but this ran every frame and
	# overwrote both. The ember never actually went out — it kept pulsing under
	# the sunrise the whole way into the credits.
	if not _dawn_started:
		var boost := 0.6 if _spark_flash > 0.0 else 0.0
		if _core_mat:
			_core_mat.emission_energy_multiplier = 1.3 + sin(_t * 1.3) * 0.3 + boost
		if _core_light:
			_core_light.light_energy = 0.45 + sin(_t * 1.3) * 0.12 + boost * 1.5
		if _crack_mat:
			_crack_mat.emission_energy_multiplier = 2.0 + sin(_t * 1.7) * 0.5 + boost
	if _spark_flash > 0.0:
		_spark_flash = maxf(0.0, _spark_flash - delta * 2.0)

## A last residual electrical discharge — the brain twitching once more before
## it truly goes dark. Custom-tailored (not ExplosionFX, which is sized for an
## enemy death, not a lingering spark).
func _residual_spark() -> void:
	_spark_flash = 1.0
	shake_camera(0.25)
	AudioBus.play_synth_at("broadcast_blip", _bob.global_position, -6.0, 0.6)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 18
	p.lifetime = 0.7
	p.explosiveness = 0.9
	p.spread = 100.0
	p.direction = Vector3.DOWN
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -3.0, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var dart := BoxMesh.new()
	dart.size = Vector3(0.03, 0.03, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = COL_EMBER
	m.emission_energy_multiplier = 5.0
	dart.material = m
	p.mesh = dart
	_bob.add_child(p)
	p.position = Vector3(0, -0.5, 0)

## Sunrise: the night sky shader fades its stars/moon while the horizon warms,
## the dawn sun ramps up, and the ambient/fog light tint follows it — the
## brain's last ember finally loses to real daylight.
func _break_dawn() -> void:
	if _dawn_started:
		return
	_dawn_started = true
	var tw := create_tween().set_parallel(true)
	if _sun:
		# Hot and hard. This is the key light now, and it is behind the husk.
		tw.tween_property(_sun, "light_energy", 1.7, 5.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_sun, "light_color", Color(1.0, 0.74, 0.45), 5.0)
	if _sun_disc:
		# The disc climbs out of the ruins and ignites.
		tw.tween_property(_sun_disc, "position", Vector3(1.5, 4.2, -62.0), 5.6) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(_sun_mat, "emission_energy_multiplier", 2.0, 4.0) \
			.set_trans(Tween.TRANS_QUAD)
	if _sky_mat:
		# Graded sky: molten at the horizon, still-cool blue overhead. A single
		# warm colour everywhere is what made the old dawn read as a sepia wash.
		tw.tween_property(_sky_mat, "shader_parameter/horizon_color", Color(1.0, 0.42, 0.16), 5.0)
		tw.tween_property(_sky_mat, "shader_parameter/zenith_color", Color(0.10, 0.22, 0.48), 5.0)
		tw.tween_property(_sky_mat, "shader_parameter/star_brightness", 0.0, 4.0)
		tw.tween_property(_sky_mat, "shader_parameter/moon_glow", 0.0, 2.5)
	if _env:
		# Ambient stays cool and LOW so the warm sun does the lighting and the
		# husk keeps a dark silhouette. The old dawn pushed ambient to a bright
		# warm (0.85,0.72,0.6) at 0.45 energy, which flat-filled every surface.
		tw.tween_property(_env, "ambient_light_color", Color(0.34, 0.40, 0.58), 5.0)
		tw.tween_property(_env, "ambient_light_energy", 0.34, 5.0)
		# Warm, thicker haze: the backlight rakes through it as god-rays.
		tw.tween_property(_env, "fog_light_color", Color(1.0, 0.55, 0.28), 5.0)
		tw.tween_property(_env, "fog_density", 0.010, 5.0)
		tw.tween_property(_env, "volumetric_fog_albedo", Color(1.0, 0.72, 0.5), 5.0)
		tw.tween_property(_env, "volumetric_fog_density", 0.028, 5.0)
	# The machine's last heat finally loses to real daylight.
	if _core_light:
		tw.tween_property(_core_light, "light_energy", 0.0, 4.0)
	if _crack_mat:
		tw.tween_property(_crack_mat, "emission_energy_multiplier", 0.0, 4.5)
	if _core_mat:
		tw.tween_property(_core_mat, "emission_energy_multiplier", 0.05, 4.5)

func _shots() -> Array:
	return [
		{
			"dur": 4.6, "fade_in": true,
			"from_pos": Vector3(5.0, 7.5, 7.5), "from_look": Vector3(0, 5.3, -6.0),
			"to_pos": Vector3(2.5, 6.6, 4.0), "to_look": Vector3(0, 5.4, -6.0),
			"text": "ARCHON has gone silent.",
		},
		{
			"dur": 4.2, "action": _residual_spark,
			"orbit": {"center": Vector3(0, 5.5, -6.0), "radius": 7.0, "height": 1.0,
				"from_deg": -50.0, "to_deg": 40.0},
			"text": "The signal that turned every machine against us — extinguished.",
		},
		{
			# Low and close, craning up as the sun clears the ruins behind the
			# husk — the shot is looking INTO the sunrise, past the silhouette.
			"dur": 6.0, "action": _break_dawn,
			"from_pos": Vector3(-3.2, 1.6, 1.5), "from_look": Vector3(0, 5.2, -6.0),
			"to_pos": Vector3(-1.2, 6.4, 8.0), "to_look": Vector3(0, 5.6, -6.0),
			"text": "Dawn. First light in longer than anyone still counted.",
		},
		{
			# The old final shot crawled from z=13 to z=16 — the last five seconds
			# of a 22-level campaign were a still frame. Now it pulls back and
			# cranes up hard, opening the husk, the skyline and the sun into one
			# wide, and the title lands on the reveal.
			"dur": 5.4, "fade_out": true, "title": "THE UPRISING IS OVER",
			"from_pos": Vector3(0.5, 6.0, 9.0), "from_look": Vector3(0, 5.2, -6.0),
			"to_pos": Vector3(2.0, 11.0, 21.0), "to_look": Vector3(0, 4.2, -8.0),
			"text": "The machines have stopped.",
		},
	]

## The 3D timeline just ended (or was skipped) on a faded-to-black screen —
## layer the closing broadcast on top of it, then move on to the credits.
func _on_finished() -> void:
	var xmit := VictoryTransmission.new()
	add_child(xmit)
	xmit.finished.connect(func() -> void:
		get_tree().change_scene_to_file(CREDITS))
