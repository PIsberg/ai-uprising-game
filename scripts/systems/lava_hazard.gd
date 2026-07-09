class_name LavaHazard
extends Area3D
## A bed of molten lava that forces detours: it carves itself out of the navmesh
## (enemies path around it) and scorches anything standing in it (so the player
## won't cross either). The level builder lays these as streams that partly span
## an arena, leaving a gap you must walk to — a longer route to the exit.
##
## Self-contained: builds its own glowing surface (shaders/lava.gdshader), a
## damage Area3D shape, a NavigationObstacle3D that carves the bake, and a warm
## light. Size is the bed's footprint in metres.

@export var size: Vector2 = Vector2(8.0, 3.0)  ## Footprint (x by z) in metres.
@export var damage_per_tick: float = 26.0      ## Burn applied every tick to anything inside.
@export var tick: float = 0.35                 ## Seconds between burns.
@export var surface_y: float = 0.06            ## Lava surface height above the floor.
## Opt-in recolor: turns the molten bed into a themed "river" (coolant cyan, acid
## green, energy blue, ...) while keeping the same carve-navmesh + burn-player
## path-forcing behaviour. Left off, the bed renders as the original orange lava.
@export var recolor: bool = false
@export var hazard_color: Color = Color(1.0, 0.45, 0.12) ## Glow/light/flow tint when `recolor` is on.
## Water mode: the bed becomes a deep, rippling pool instead of molten rock — a
## translucent blue surface, a cool blue glow, the water ambience loop, and a
## gentler "you're drowning, get out" tick. Same carve-navmesh + push-out-of-it
## machinery; just a different element. Set by the builder for water levels.
@export var water: bool = false

const PLAYER_LAYER := 2
const ENEMY_LAYER := 4

var _t: float = 0.0       ## damage-tick accumulator
var _clock: float = 0.0   ## continuous clock for the glow flicker
var _mat: ShaderMaterial
var _light: OmniLight3D            ## first of _lights (back-compat handle)
var _lights: Array[OmniLight3D] = []
var _embers: GPUParticles3D

func _ready() -> void:
	# Burns the PLAYER only (layer 2). Enemies route around the bed via the navmesh
	# carve below — they must never cook to death in it, so they are not monitored
	# here at all. The lava itself is on no layer, so nothing collides with it.
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	monitoring = true
	add_to_group("hazard")
	if water:
		# Water mode drives its own cool palette unless the level overrode the tint.
		recolor = true
		if hazard_color == Color(1.0, 0.45, 0.12):
			hazard_color = Color(0.2, 0.55, 0.95)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	# A shallow slab a little above and below the surface so a body walking across
	# is reliably caught.
	bs.size = Vector3(size.x, 1.6, size.y)
	cs.shape = bs
	cs.position = Vector3(0, surface_y, 0)
	add_child(cs)

	_build_surface()
	_build_obstacle()
	_build_light()
	_build_embers()
	_build_audio()
	# Default molten lava reads as "hot, don't touch" on its own. A RECOLORED bed
	# (cyan coolant, green acid) or a WATER pool reads as harmless liquid — players
	# walk in and get cooked. Frame those in a pulsing amber hazard border so the
	# danger is unmistakable regardless of the fluid's colour.
	if recolor or water:
		_build_warning_edge()

## The glowing molten surface plane (or, in water mode, a deep blue pool).
func _build_surface() -> void:
	if water:
		_build_water_surface()
		return
	var mesh := PlaneMesh.new()
	mesh.size = size
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/lava.gdshader")
	# Seamless noise the flow shader warps; bed size keeps the molten cells a
	# consistent scale regardless of how big the stream is.
	_mat.set_shader_parameter("noise_texture", FlameMaterial.noise())
	_mat.set_shader_parameter("plane_size", size)
	if recolor:
		# Deeper base for the flowing cells, tinted to the river's colour.
		_mat.set_shader_parameter("base_color", Color(hazard_color.r, hazard_color.g, hazard_color.b) * 0.32)
	mesh.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, surface_y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# A charred rim so the bed reads as sunken molten rock, not a decal.
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(size.x + 0.6, 0.12, size.y + 0.6)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.06, 0.04, 0.04)
	rmat.roughness = 1.0
	rmat.emission_enabled = true
	rmat.emission = Color(hazard_color.r, hazard_color.g, hazard_color.b) * 0.5 if recolor else Color(0.5, 0.12, 0.02)
	rmat.emission_energy_multiplier = 0.4
	rm.material = rmat
	rim.mesh = rm
	rim.position = Vector3(0, surface_y - 0.07, 0)
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)

## A deep-water pool: a translucent, near-mirror blue plane over a darker basin,
## so it reads as water you can fall into (not molten rock). No shader needed —
## a glossy transparent surface plus the cool glow + water ambience sell it.
func _build_water_surface() -> void:
	var tint := hazard_color
	var surf := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = size
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(tint.r, tint.g, tint.b, 0.62)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.04          # glassy, reflective water sheen
	wm.metallic = 0.25
	wm.emission_enabled = true
	wm.emission = Color(tint.r, tint.g, tint.b) * 0.5
	wm.emission_energy_multiplier = 0.25
	mesh.material = wm
	surf.mesh = mesh
	surf.position = Vector3(0, surface_y, 0)
	surf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surf)
	# A dark basin just below so the pool reads as deep, not a painted tile.
	var basin := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x + 0.4, 0.5, size.y + 0.4)
	var basin_mat := StandardMaterial3D.new()
	basin_mat.albedo_color = Color(0.02, 0.05, 0.08)
	basin_mat.roughness = 1.0
	bm.material = basin_mat
	basin.mesh = bm
	basin.position = Vector3(0, surface_y - 0.3, 0)
	basin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(basin)

## A pulsing amber danger frame around the bed perimeter — the universal "hazard,
## do not enter" cue. Makes a benign-looking coolant / acid / water pool read as
## lethal at a glance (amber contrasts against any fluid colour).
func _build_warning_edge() -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var col := Color(1.0, 0.62, 0.05)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.albedo_color = col
	mat.emission = col
	mat.emission_energy_multiplier = 2.5
	var th := 0.3
	var edges := [
		[Vector3(0, 0, -hz), Vector3(size.x, 0.05, th)],
		[Vector3(0, 0, hz), Vector3(size.x, 0.05, th)],
		[Vector3(-hx, 0, 0), Vector3(th, 0.05, size.y)],
		[Vector3(hx, 0, 0), Vector3(th, 0.05, size.y)],
	]
	for e in edges:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		bm.material = mat
		bar.mesh = bm
		var p: Vector3 = e[0]
		bar.position = Vector3(p.x, surface_y + 0.09, p.z)
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bar)
	var tw := create_tween().set_loops()
	tw.tween_property(mat, "emission_energy_multiplier", 4.5, 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mat, "emission_energy_multiplier", 2.0, 0.7).set_trans(Tween.TRANS_SINE)

## Carve the bed out of the baked navmesh so enemies route around it. Present
## before the builder's deferred bake, so the static carve takes.
func _build_obstacle() -> void:
	var obs := NavigationObstacle3D.new()
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	obs.vertices = PackedVector3Array([
		Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz),
		Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
	])
	# Kept low (well under the ~1.2m catwalk deck height) so the carve only
	# removes the open bed at floor level — a bridge/exit-island platform laid
	# directly over a bed (lava_world's exit island sits above one) keeps its
	# own navmesh instead of being eaten by this hazard's obstacle.
	obs.height = 0.9
	obs.affect_navigation_mesh = true   # carve the static bake
	obs.avoidance_enabled = false       # static carve only; no RVO jitter
	add_child(obs)

## Molten light. A single omni at the centre of a long channel is wrong twice
## over: its radius has to span the whole bed (so the falloff is a soft, uniform
## wash instead of a hot trench), and the far ends are lit by a lamp 20 m away.
## Beds are long and thin, so lay a LINE of emitters down the long axis, each
## sized to the bed's WIDTH. GPT Foundry's smelt channels are ~39 m x 5 m — one
## lamp made them read as flat orange carpet; a line makes them read as molten.
## Bounded to LIGHT_MAX (shadowless, so each is cheap, but they are not free).
const LIGHT_MAX := 6

func _build_light() -> void:
	var col := hazard_color if recolor else Color(1.0, 0.45, 0.12)
	var along_x := size.x >= size.y
	var length: float = size.x if along_x else size.y
	var width: float = size.y if along_x else size.x
	# One emitter per ~1.6 bed-widths of length: dense enough that the pools
	# overlap into a continuous channel, sparse enough to stay cheap. Capped by
	# the detail tier — LOW falls back to exactly one lamp (the old behaviour),
	# so a weak GPU never pays for 6 lights per bed on a 4-bed level. Never zero:
	# an unlit molten channel would read as painted orange floor.
	var cap: int = clampi(int(round(1.0 + GraphicsSettings.detail_scale() * 4.0)), 1, LIGHT_MAX)
	var n: int = clampi(int(round(length / maxf(width * 1.6, 1.0))), 1, cap)
	for i in n:
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = _light_energy(0.0, i)
		l.omni_range = width * 0.9 + 5.0
		l.shadow_enabled = false
		# Evenly spaced along the long axis, centred: i=0..n-1 -> -L/2..+L/2,
		# inset by half a step so the end lamps sit inside the bed, not on its lip.
		var t: float = 0.0 if n == 1 else (float(i) + 0.5) / float(n) - 0.5
		var off: float = t * length
		l.position = Vector3(off if along_x else 0.0, 1.2, 0.0 if along_x else off)
		add_child(l)
		_lights.append(l)
	if not _lights.is_empty():
		_light = _lights[0] # kept for any external reference

## Flicker, de-phased per lamp so the channel shimmers along its length instead
## of the whole bed pulsing as one slab.
func _light_energy(clock: float, i: int) -> float:
	var p := float(i) * 1.7
	return 2.4 + sin(clock * 6.0 + p) * 0.3 + sin(clock * 13.0 + p * 0.5) * 0.15

## Embers drifting up off the molten surface. A still, glowing plane reads as a
## painted floor no matter how well it's lit; rising motion is what says "this is
## hot". Only for real molten beds — water pools and recolored coolant/acid
## rivers don't throw sparks (their own warning edge sells them instead).
## Skipped entirely on the LOW detail tier, and the count scales with the bed's
## area so a 39 m smelt channel spits more than a small pool.
func _build_embers() -> void:
	if water or recolor:
		return
	var detail := GraphicsSettings.detail_scale()
	if detail <= 0.0:
		return
	var p := GPUParticles3D.new()
	p.amount = clampi(int(size.x * size.y * 0.5 * detail), 12, 140)
	p.lifetime = 2.6
	p.preprocess = 1.5 # already smouldering when you first see it
	p.local_coords = false
	# GPUParticles are culled by their (tiny, default) AABB unless it's told how
	# far they travel — the classic "particles vanish when you look away" bug.
	p.visibility_aabb = AABB(
		Vector3(-size.x * 0.5 - 1.0, -0.5, -size.y * 0.5 - 1.0),
		Vector3(size.x + 2.0, 5.0, size.y + 2.0))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(size.x * 0.5, 0.05, size.y * 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.gravity = Vector3(0, 0.55, 0) # hot air lifts them
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.7
	pm.scale_min = 0.02
	pm.scale_max = 0.06
	pm.damping_min = 0.2
	pm.damping_max = 0.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.45, 1.0)) # white-hot at birth
	ramp.set_color(1, Color(0.9, 0.22, 0.03, 0.0)) # cools and fades out
	var gtex := GradientTexture1D.new()
	gtex.gradient = ramp
	pm.color_ramp = gtex
	p.process_material = pm

	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# The particle colour ramp arrives as VERTEX COLOUR, so the spark must take
	# its colour AND its fade from it. Do NOT enable emission here: emission adds
	# a constant colour that ignores the ramp's alpha, which renders the embers as
	# opaque squares that never cool or fade (they read as floating confetti).
	# Additive + vertex colour is the glow.
	em.vertex_color_use_as_albedo = true
	em.disable_receive_shadows = true
	# A soft radial dot, so a spark is a spark and not a hard-edged quad.
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	em.albedo_texture = dot
	qm.material = em
	p.draw_pass_1 = qm
	p.position = Vector3(0, surface_y + 0.05, 0)
	add_child(p)
	_embers = p

## A looping bubbling bed so the hazard is recognisable by ear before you reach
## it. Louder/lower for molten lava; thinner and quieter for a recolored coolant
## or acid "river". Skipped while the editor suppresses world SFX.
func _build_audio() -> void:
	if AudioBus.suppress_world_sfx:
		return
	# Water beds murmur a gentle trickle; lava (incl. recolored hazard rivers) bubbles.
	var stream := AudioBus.synth("water_loop" if water else "lava_loop")
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.unit_size = maxf(size.x, size.y) * 0.5 + 2.0
	p.max_distance = 42.0
	p.volume_db = -12.0 if water else (-10.0 if recolor else -6.0)
	p.pitch_scale = 1.0 if water else (1.25 if recolor else 1.0)
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	p.play()

func _process(delta: float) -> void:
	_clock += delta
	# Subtle flicker so the molten glow feels alive; de-phased along the channel.
	for i in _lights.size():
		_lights[i].light_energy = _light_energy(_clock, i)
	_t += delta
	if _t < tick:
		return
	_t = 0.0
	for body in get_overlapping_bodies():
		var d := body.get_node_or_null("Damageable") as Damageable
		if d and d.is_alive():
			d.apply_damage(damage_per_tick, self)
			if body.is_in_group("player"):
				GameState.teach_once("hazard_in",
					"⚠ You're in the %s — get back onto the walkway!" % ("water" if water else "molten sea"))
