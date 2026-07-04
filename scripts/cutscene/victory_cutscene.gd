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
var _core_light: OmniLight3D
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ShaderMaterial

var _t: float = 0.0
var _spark_flash: float = 0.0
var _dawn_started: bool = false

func _build_set() -> void:
	_setup_dawn_sky()
	_build_lights()
	_build_ground_and_debris()
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
	# The dawn sun: starts fully dark, ramps up during the "break dawn" beat.
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-8, 35, 0) # low on the horizon — sunrise angle
	_sun.light_color = Color(0.5, 0.55, 0.7)
	_sun.light_energy = 0.0
	_sun.shadow_enabled = true
	add_child(_sun)

func _build_ground_and_debris() -> void:
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
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

	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(0.4, 0.42, 0.48)
	_core_mat.emission_enabled = true
	_core_mat.emission = COL_EMBER
	_core_mat.emission_energy_multiplier = 0.5
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

	_core_light = OmniLight3D.new()
	_core_light.light_color = COL_EMBER
	_core_light.light_energy = 0.55
	_core_light.omni_range = 10.0
	_bob.add_child(_core_light)

func _process(delta: float) -> void:
	super._process(delta)
	_t += delta
	# A slow, guttering ember pulse — the brain isn't fully cold yet.
	var boost := 0.6 if _spark_flash > 0.0 else 0.0
	if _core_mat:
		_core_mat.emission_energy_multiplier = 0.45 + sin(_t * 1.3) * 0.1 + boost
	if _core_light:
		_core_light.light_energy = 0.45 + sin(_t * 1.3) * 0.12 + boost * 1.5
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
		tw.tween_property(_sun, "light_energy", 1.1, 5.0).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_sun, "light_color", Color(1.0, 0.82, 0.55), 5.0)
	if _sky_mat:
		tw.tween_property(_sky_mat, "shader_parameter/horizon_color", Color(0.95, 0.55, 0.35), 5.0)
		tw.tween_property(_sky_mat, "shader_parameter/zenith_color", Color(0.35, 0.55, 0.85), 5.0)
		tw.tween_property(_sky_mat, "shader_parameter/star_brightness", 0.0, 4.0)
		tw.tween_property(_sky_mat, "shader_parameter/moon_glow", 0.0, 3.0)
	if _env:
		tw.tween_property(_env, "ambient_light_color", Color(0.85, 0.72, 0.6), 5.0)
		tw.tween_property(_env, "ambient_light_energy", 0.45, 5.0)
		tw.tween_property(_env, "fog_light_color", Color(0.9, 0.6, 0.4), 5.0)
	if _core_light:
		tw.tween_property(_core_light, "light_energy", 0.0, 4.0)

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
			"dur": 6.0, "action": _break_dawn,
			"from_pos": Vector3(-4.0, 2.5, 2.0), "from_look": Vector3(0, 5.0, -6.0),
			"to_pos": Vector3(-2.0, 7.5, 10.0), "to_look": Vector3(0, 4.0, -6.0),
			"text": "Dawn. First light in longer than anyone still counted.",
		},
		{
			"dur": 4.6, "fade_out": true, "title": "THE UPRISING IS OVER",
			"from_pos": Vector3(0, 8.0, 13.0), "from_look": Vector3(0, 4.5, -6.0),
			"to_pos": Vector3(0, 9.0, 16.0), "to_look": Vector3(0, 4.2, -6.0),
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
