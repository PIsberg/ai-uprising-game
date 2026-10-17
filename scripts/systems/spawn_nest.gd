class_name SpawnNest
# @lat: [[level-system#Spawn Nests]]
extends StaticBody3D
## A brood pod that keeps the fight coming: while the player is within
## WAKE_RANGE it warps out one `kind` robot every INTERVAL seconds (through an
## EnemySpawner, so each arrival is telegraphed), never more than MAX_ALIVE of
## its own alive at once (arrivals still in their telegraph count). You cannot
## outlast it: push in and shoot it apart (HEALTH, paying BONUS) or leave its
## range. Its glow quickens as the next spawn comes due. Walking up teaches the
## rule once. Def key `nests` (level_builder `_build_nests`).
## tests/spawn_nest_probe.

const WAKE_RANGE := 26.0
const INTERVAL := 5.0
const MAX_ALIVE := 3
const HEALTH := 220.0
const BONUS := 150
const TEACH_REACH := 22.0
const TEACH_TEXT := "SPAWN NEST: it keeps hatching robots while you are near it. Destroy the pod or get out of its range."
const COLOR := Color(0.45, 1.0, 0.35)

@export var kind: String = "skitter"

var hp: Damageable
var live: Array[Node3D] = []
var spawned_total := 0
var dead := false
var _pending := 0
var _t := 0.0
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("spawn_nest")
	_build()
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = HEALTH
	add_child(hp)
	hp.died.connect(_on_died)

func _build() -> void:
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.9
	cs.shape = sh
	cs.position = Vector3.UP * 0.8
	add_child(cs)
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.5
	shell.mesh = sm
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.12, 0.1, 0.09)
	skin.roughness = 0.6
	skin.metallic = 0.3
	shell.material_override = skin
	shell.position = Vector3.UP * 0.75
	add_child(shell)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = COLOR
	# Glowing seams around the pod: the brood light inside.
	for i in 4:
		var seam := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.7 - 0.12 * i
		tm.outer_radius = 0.76 - 0.12 * i
		seam.mesh = tm
		seam.material_override = _glow_mat
		seam.position = Vector3.UP * (0.45 + 0.25 * i)
		seam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seam)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 1.2
	_light.omni_range = 5.0
	_light.position = Vector3.UP * 1.0
	add_child(_light)

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

func _physics_process(delta: float) -> void:
	if dead:
		return
	live = live.filter(func(r: Node3D) -> bool:
		return is_instance_valid(r) and not (r is EnemyBase and ((r as EnemyBase).state == EnemyBase.State.DEAD or (r as EnemyBase).hp == null or not (r as EnemyBase).hp.is_alive())))
	var p := _player()
	var awake := p != null and p.global_position.distance_to(global_position) <= WAKE_RANGE
	if p and p.global_position.distance_to(global_position) <= TEACH_REACH:
		GameState.teach_once("spawn_nest", TEACH_TEXT)
	if awake and live.size() + _pending < MAX_ALIVE:
		_t += delta
		if _t >= INTERVAL:
			_t = 0.0
			_hatch()
	var k := clampf(_t / INTERVAL, 0.0, 1.0) if awake else 0.0
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * (2.0 + 10.0 * k))
	_glow_mat.albedo_color = COLOR.lerp(Color.WHITE, 0.5 * k * pulse)
	_light.light_energy = 0.8 + 2.0 * k * pulse

func _hatch() -> void:
	var scene := LevelBuilder.enemy_scene(kind)
	if scene == null or get_parent() == null:
		return
	var sp := EnemySpawner.new()
	sp.enemy_scene = scene
	sp.spawn_on_ready = true
	sp.spawn_delay = 0.01
	var ang := randf() * TAU
	sp.position = position + Vector3(cos(ang), 0.0, sin(ang)) * 1.8
	sp.spawned.connect(_on_spawned)
	_pending += 1
	get_parent().add_child(sp)
	AudioBus.play_synth_at("acid_spit", global_position, -4.0, 0.7)

func _on_spawned(e: Node3D) -> void:
	_pending = maxi(0, _pending - 1)
	spawned_total += 1
	if not dead:
		live.append(e)

func _on_died(_source: Node) -> void:
	if dead:
		return
	dead = true
	GameState.add_score(BONUS)
	GameState.skirmish_event.emit("NEST DESTROYED", tr("No more where those came from. +%d") % BONUS)
	var fx := Destructible.EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 0.8
	AudioBus.play_synth_at("explosion", global_position, 0.0, 0.9)
	queue_free()
