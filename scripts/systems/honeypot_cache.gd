class_name HoneypotCache
# @lat: [[level-system#Honeypots]]
extends StaticBody3D
## Bait. Looks exactly like a health pack or ammo box (it wears the real
## pickup scene's mesh and light, spins and bobs the same), but every
## GLITCH_MIN..GLITCH_MAX seconds its image tears for GLITCH_LEN: it jumps
## sideways, flashes red and clicks with static. A real pickup never does.
##   - Walk within SPRING_RANGE and it springs: SPRING_DAMAGE to the player and
##     `count` `squad` robots warp in around it (EnemySpawner telegraph). Gone.
##   - Hurt it first (any shot, any splash) and it is defused: DEFUSE_BONUS, and
##     the real pickup it was imitating drops in its place.
## Robots ignore it. Enemy collision layer (4) so player fire finds it; it is
## not in the "enemy" group, so aim assist and the kill count never see it.
## Def key `honeypots` (level_builder `_build_honeypots`). tests/honeypot_probe.

const SPRING_RANGE := 2.6 ## under the 3.4 m at which a real supply drifts to you
const SPRING_DAMAGE := 12.0
const DEFUSE_BONUS := 150
const GLITCH_MIN := 1.6
const GLITCH_MAX := 3.0
const GLITCH_LEN := 0.16
const GLITCH_SHIFT := 0.14
const STATIC_REACH := 14.0 ## the glitch's static click carries this far
const RING_RADIUS := 3.2 ## the squad warps in on this ring around the bait
const RED := Color(1.0, 0.12, 0.1)
const TEACH_TEXT := "HONEYPOT: some supplies are bait. A real one never glitches red. Shoot a suspicious pickup and it gives up the real item."

@export var kind: String = "health" ## health | ammo
@export var squad: String = "skitter"
@export var count: int = 4

var hp: Damageable
var sprung := false
var defused := false
## True for GLITCH_LEN after each tear; the probe samples it.
var glitching := false
var glitch_count := 0
var _pivot: Node3D
var _mesh: Node3D
var _light: OmniLight3D
var _light_color := Color.WHITE
var _light_base := 1.0
var _mesh_home_y := 0.0
var _bob := 0.0
var _next_glitch := 0.0
var _glitch_left := 0.0
var _overlay: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	add_to_group("honeypot")
	_build()
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 1.0e6
	add_child(hp)
	hp.damaged.connect(_on_damaged)
	_bob = randf() * TAU
	_next_glitch = randf_range(GLITCH_MIN, GLITCH_MAX)

## Borrow the real pickup's look: instance its scene, keep its visual nodes,
## drop the Area (so it can never be collected).
func _build() -> void:
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	cs.shape = sh
	cs.position = Vector3.UP * 0.6
	add_child(cs)
	_pivot = Node3D.new()
	add_child(_pivot)
	var scene := LevelBuilder.pickup_scene(kind)
	if scene:
		var real := scene.instantiate()
		# Every visual child (Mesh, GroundRing, Light, ...): one left behind is
		# a giveaway. Only the collision shape stays with the discarded Area.
		for n in real.get_children():
			if not n is CollisionShape3D:
				real.remove_child(n)
				_pivot.add_child(n)
		real.free()
	_mesh = _pivot.get_node_or_null("Mesh") as Node3D
	_light = _pivot.get_node_or_null("Light") as OmniLight3D
	if _mesh:
		_mesh_home_y = _mesh.position.y
		for m in _mesh.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(m as MeshInstance3D)
	if _light:
		_light_color = _light.light_color
		_light_base = _light.light_energy
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.albedo_color = RED
	# The same soft ground shadow a real pickup has.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 0.01
	cm.radial_segments = 14
	cm.rings = 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0, 0, 0, 0.4)
	cm.material = mat
	disc.mesh = cm
	disc.position = Vector3(0, 0.025, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)

func _player() -> Node3D:
	return GameState.nearest_player(global_position)

func _process(delta: float) -> void:
	if sprung or defused:
		return
	# The same spin and bob as Pickup._process.
	_pivot.rotate_y(delta * 1.2)
	_bob += delta * 2.0
	if _mesh:
		_mesh.position.y = _mesh_home_y + sin(_bob) * 0.12
	if _light and not glitching:
		_light.light_energy = _light_base + sin(_bob * 1.5) * _light_base * 0.3
	if glitching:
		_glitch_left -= delta
		if _glitch_left <= 0.0:
			_set_glitch(false)
	else:
		_next_glitch -= delta
		if _next_glitch <= 0.0:
			_next_glitch = randf_range(GLITCH_MIN, GLITCH_MAX)
			_glitch_left = GLITCH_LEN
			_set_glitch(true)

func _set_glitch(on: bool) -> void:
	glitching = on
	for m in _meshes:
		if is_instance_valid(m):
			m.material_overlay = _overlay if on else null
	if _mesh:
		var side := (1.0 if randf() < 0.5 else -1.0) * GLITCH_SHIFT
		_mesh.position.x = side if on else 0.0
		_mesh.scale = Vector3(1.0, 0.7, 1.0) if on else Vector3.ONE
	if _light:
		_light.light_color = RED if on else _light_color
		if on:
			_light.light_energy = _light_base * 1.4
	if on:
		glitch_count += 1
		var p := _player()
		if p and p.global_position.distance_to(global_position) <= STATIC_REACH:
			AudioBus.play_synth_at("radio_static", global_position, -10.0, 1.6)

func _physics_process(_delta: float) -> void:
	if sprung or defused:
		return
	var p := _player()
	if p == null:
		return
	var flat := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z)
	if flat.length() <= SPRING_RANGE and absf(p.global_position.y - global_position.y) < 2.5:
		_spring(p)

func _spring(p: Node3D) -> void:
	sprung = true
	var pd := p.get_node_or_null("Damageable") as Damageable
	if pd:
		pd.apply_damage(SPRING_DAMAGE, self)
	var scene := LevelBuilder.enemy_scene(squad)
	if scene and get_parent():
		# Ring the bait, starting on the far side from the player so the first
		# arrival is in view rather than at their back.
		var away := Vector2(global_position.x - p.global_position.x, global_position.z - p.global_position.z)
		var a0 := away.angle() if away.length() > 0.01 else 0.0
		for i in count:
			var ang := a0 + TAU * float(i) / float(maxi(count, 1))
			var sp := EnemySpawner.new()
			sp.enemy_scene = scene
			sp.spawn_on_ready = true
			sp.spawn_delay = 0.01
			sp.position = position + Vector3(cos(ang), 0.0, sin(ang)) * RING_RADIUS
			get_parent().add_child(sp)
	GameState.skirmish_event.emit("HONEYPOT", tr("It was bait. %d robots incoming.") % count)
	GameState.teach_once("honeypot", TEACH_TEXT)
	AudioBus.play_synth_at("overlord_glitch", global_position, 0.0, 1.0)
	AudioBus.play_synth_at("eas_alert", global_position, -6.0, 1.3)
	_pop(RED)
	queue_free()

func _on_damaged(_amount: float, _source: Node) -> void:
	if sprung or defused:
		return
	defused = true
	GameState.add_score(DEFUSE_BONUS)
	GameState.skirmish_event.emit("HONEYPOT DEFUSED", tr("Nice catch. The real thing is yours. +%d") % DEFUSE_BONUS)
	GameState.teach_once("honeypot", TEACH_TEXT)
	var scene := LevelBuilder.pickup_scene(kind)
	if scene and get_parent():
		var real := scene.instantiate() as Node3D
		get_parent().add_child(real)
		real.global_position = global_position
	AudioBus.play_synth_at("tape_rewind", global_position, -4.0, 1.4)
	_pop(Color(1.0, 0.8, 0.25))
	queue_free()

## A short flash at the bait's spot, parented to the level so it outlives us.
func _pop(col: Color) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 4.0
	l.omni_range = 6.0
	parent.add_child(l)
	l.global_position = global_position + Vector3.UP * 0.8
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.4)
	tw.tween_callback(l.queue_free)

## The death screen's "Taken down by" name and its tip key (player.gd reads it
## off any damage source that has it; hud.gd DEATH_TIPS).
func _kill_label() -> String:
	return "HONEYPOT TRAP"
