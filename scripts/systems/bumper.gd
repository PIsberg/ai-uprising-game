class_name Bumper
# @lat: [[level-system#Bumpers]]
extends Area3D
## A pinball bumper: an orange dome on the floor that throws whoever steps on
## it, the player or a robot, on an arc onto a ring drawn on the floor at `to`.
## Robots are thrown too (EnemyBase.launch), so one chasing you over a bumper
## follows you over. Flyers (a `hover_height`) and boss chassis (500+ authored
## HP) are never thrown, nor a robot already in the air. It reads at a glance:
## chevrons on the low dome point at the ring, the ring marks where you will
## land, the dome squashes and pops with a boing when it fires, and the first
## bumper a player walks up to teaches it once per run.
## Nothing is hurt. A body landing a little off the pad's centre lands the same
## offset from the ring (the throw is parallel). Unlike a JumpPad (player only,
## onto a deck), a bumper is a floor-to-floor throw for everyone.
## Def key `bumpers` (level_builder `_build_bumpers`). tests/bumper_probe.

signal bumped(body: Node)

@export var to: Vector3 = Vector3(0, 0, 8)   ## world landing point (feet)
@export var radius: float = 1.2

const EXTRA_ARC := 0.5     ## m the arc rises past a jump pad's (it throws over things)
const REARM := 0.8         ## s before the same body is thrown again
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4
const TEACH_REACH := 6.0
const TEACH_TEXT := "BUMPER: step on it and it throws you onto the ring its arrows point at. Robots get thrown too."
const COLOR := Color(1.0, 0.55, 0.1)
const DOME_H := 0.35       ## m, the dome's height
const BOSS_HP := 500.0     ## authored health from which a chassis counts as a boss

var _cool := {}
var _dome: MeshInstance3D
var _glow: StandardMaterial3D
var _ring: MeshInstance3D
var _pop := 0.0
var _dome_y := 1.0         ## the dome's resting vertical scale

func _ready() -> void:
	add_to_group("bumper")
	collision_layer = 0
	collision_mask = PLAYER_LAYER | ENEMY_LAYER
	monitoring = true
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 0.8
	cs.shape = cyl
	cs.position = Vector3.UP * 0.4
	add_child(cs)
	_build_visual()

## Whether a robot gets thrown: alive, grounded, not a flyer, not a boss, not
## already in the air.
static func can_throw(robot: EnemyBase) -> bool:
	if robot.state == EnemyBase.State.DEAD or robot.is_launched() or not robot.is_on_floor():
		return false
	if "hover_height" in robot: # a flyer
		return false
	return robot.max_health * robot._health_mult < BOSS_HP

## The ring on the floor that marks where a throw lands.
func landing_marker() -> Node3D:
	return _ring

## Throw `b` if it is the player or a throwable robot standing on the pad and
## not thrown in the last REARM s. Polled every tick (not on entry), so a robot
## that lands on or stops on a bumper is thrown once it is grounded.
func _try(b: Node) -> void:
	var id := b.get_instance_id()
	if float(_cool.get(id, 0.0)) > 0.0:
		return
	var body := b as CharacterBody3D
	if body == null:
		return
	var is_player := b.is_in_group("player")
	var robot := b as EnemyBase
	if not is_player and robot == null:
		return
	if robot != null and not can_throw(robot):
		return
	var from := body.global_position
	var land := to + Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var s := JumpPad.solve(from, land, JumpPad.apex_for(from, land) + EXTRA_ARC, g)
	if not body.has_method("launch"):
		return
	body.launch(s[0], s[1])
	_cool[id] = REARM
	_pop = 1.0
	AudioBus.play_synth_at("pump_action", global_position, 0.0, 1.6)
	AudioBus.play_synth_at("charge", global_position, -4.0, 2.6)
	bumped.emit(b)

func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.12, 0.12, 0.14)
	steel.metallic = 0.7
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = radius
	bm.bottom_radius = radius + 0.12
	bm.height = 0.12
	base.mesh = bm
	base.material_override = steel
	base.position = Vector3.UP * 0.06
	add_child(base)
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = COLOR
	_glow.emission_enabled = true
	_glow.emission = COLOR
	_glow.emission_energy_multiplier = 2.0
	# The dome: a squat cap that squashes and pops when it fires.
	_dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius * 0.8
	sm.height = radius * 0.8
	sm.is_hemisphere = true
	_dome.mesh = sm
	_dome.material_override = _glow
	_dome.position = Vector3.UP * 0.12
	add_child(_dome)
	_dome_y = DOME_H / (radius * 0.8) # a low cap, not a ball: it reads as a pad you step on
	# Chevrons on the dome pointing at the ring.
	var flat := Vector3(to.x - global_position.x, 0.0, to.z - global_position.z)
	var holder := Node3D.new()
	if flat.length() > 0.1:
		holder.rotation.y = atan2(-flat.x, -flat.z)
	add_child(holder)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(1.0, 0.95, 0.8)
	for i in 3:
		var arrow := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(0.55, 0.32, 0.05)
		arrow.mesh = pm
		arrow.material_override = white
		arrow.rotation = Vector3(-PI * 0.5, 0, 0)
		arrow.position = Vector3(0.0, 0.12 + DOME_H + 0.03, -0.1 - 0.32 * float(i - 1))
		holder.add_child(arrow)
	# The landing ring, flat on the floor at `to` (a world point).
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.2
	_ring.mesh = tm
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = COLOR * 1.4 # HDR: reads over a lit floor
	_ring.material_override = ring_mat
	_ring.scale = Vector3(1.0, 0.05, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.top_level = true
	_ring.global_position = to + Vector3.UP * 0.04
	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 1.2
	light.omni_range = 3.5
	light.shadow_enabled = false
	light.position = Vector3.UP * 0.7
	add_child(light)

func _physics_process(delta: float) -> void:
	for k in _cool.keys():
		_cool[k] = float(_cool[k]) - delta
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)
	_pop = maxf(0.0, _pop - delta * 3.0)
	var squash := 1.0 - 0.55 * sin(_pop * PI)
	_dome.scale = Vector3(1.0 + (1.0 - squash) * 0.6, squash * _dome_y, 1.0 + (1.0 - squash) * 0.6)
	for b in get_overlapping_bodies():
		_try(b)
	_glow.emission_energy_multiplier = 2.0 + 6.0 * _pop + 0.6 * sin(Time.get_ticks_msec() / 220.0)
	var pl := GameState.nearest_player(global_position)
	if pl != null:
		var d := pl.global_position - global_position
		d.y = 0.0
		if d.length() <= radius + TEACH_REACH:
			GameState.teach_once("bumper", TEACH_TEXT)
