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

const PLAYER_LAYER := 2
const ENEMY_LAYER := 4

var _t: float = 0.0       ## damage-tick accumulator
var _clock: float = 0.0   ## continuous clock for the glow flicker
var _mat: ShaderMaterial
var _light: OmniLight3D

func _ready() -> void:
	# Burns the PLAYER only (layer 2). Enemies route around the bed via the navmesh
	# carve below — they must never cook to death in it, so they are not monitored
	# here at all. The lava itself is on no layer, so nothing collides with it.
	collision_layer = 0
	collision_mask = PLAYER_LAYER
	monitoring = true
	add_to_group("hazard")

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
	_build_audio()

## The glowing molten surface plane.
func _build_surface() -> void:
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
	obs.height = 2.0
	obs.affect_navigation_mesh = true   # carve the static bake
	obs.avoidance_enabled = false       # static carve only; no RVO jitter
	add_child(obs)

func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = hazard_color if recolor else Color(1.0, 0.45, 0.12)
	_light.light_energy = 2.4
	_light.omni_range = maxf(size.x, size.y) * 0.9 + 4.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)

## A looping bubbling bed so the hazard is recognisable by ear before you reach
## it. Louder/lower for molten lava; thinner and quieter for a recolored coolant
## or acid "river". Skipped while the editor suppresses world SFX.
func _build_audio() -> void:
	if AudioBus.suppress_world_sfx:
		return
	var stream := AudioBus.synth("lava_loop")
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.unit_size = maxf(size.x, size.y) * 0.5 + 2.0
	p.max_distance = 42.0
	p.volume_db = -10.0 if recolor else -6.0
	p.pitch_scale = 1.25 if recolor else 1.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	p.play()

func _process(delta: float) -> void:
	_clock += delta
	if _light:
		# Subtle flicker so the molten glow feels alive.
		_light.light_energy = 2.4 + sin(_clock * 6.0) * 0.3 + sin(_clock * 13.0) * 0.15
	_t += delta
	if _t < tick:
		return
	_t = 0.0
	for body in get_overlapping_bodies():
		var d := body.get_node_or_null("Damageable") as Damageable
		if d and d.is_alive():
			d.apply_damage(damage_per_tick, self)
