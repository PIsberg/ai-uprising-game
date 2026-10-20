class_name CargoLift
# @lat: [[level-system#Cargo Lifts]]
extends Node3D
## An open cargo lift: a car that rides a four-post shaft between its own
## height (the bottom landing, the node's y) and `top`. Stand on it and after
## a beat it carries you to the other landing; stand by a landing it is not
## at and it comes to you. It waits where it stops. The car is a moving
## AnimatableBody3D on the world layer, so the player stands on it and rides
## with it, and so does anything else. Def key `lifts` (level_builder
## `_build_lifts`). tests/cargo_lift_probe.

@export var size: Vector2 = Vector2(2.6, 2.6) ## Car footprint (x by z) in metres.
@export var top: float = 7.0                  ## Top landing height (car surface), world y.
@export var speed: float = 2.6                ## m/s
@export var board_delay: float = 0.6          ## s a rider stands on the car before it moves

const CAR_THICK := 0.3
const POST := 0.18
const CALL_REACH := 2.4  ## m from the car's edge a player calls it to their landing
const CALL_HEIGHT := 1.6 ## m above a landing the player's feet may be and still call

var _car: AnimatableBody3D
var _ride: Area3D
var _beacon_mat: StandardMaterial3D
var _light: OmniLight3D
var _base := 0.0     ## bottom landing (car surface), local y
var _rise := 0.0     ## top - bottom
var _y := 0.0        ## car surface, local y
var _goal := 0.0
var _board_t := 0.0
var _armed := true   ## a rider must step off before the car moves them again
var _was_moving := false

func _ready() -> void:
	_rise = top - global_position.y
	_build()

func at_top() -> bool:
	return absf(_y - _rise) < 0.02

func at_bottom() -> bool:
	return absf(_y) < 0.02

func _build() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.24, 0.24, 0.25)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.9, 0.62, 0.08)
	paint.roughness = 0.6
	# Shaft: four posts from the floor below the bottom landing to above the top.
	var floor_y := -global_position.y
	var post_h := _rise + 2.6 - floor_y
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(POST, post_h, POST)
			post.mesh = bm
			post.material_override = paint
			post.position = Vector3(sx * (size.x * 0.5 + POST * 0.5), floor_y + post_h * 0.5, sz * (size.y * 0.5 + POST * 0.5))
			add_child(post)
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(size.x + POST * 2.0, 0.35, size.y + POST * 2.0)
	head.mesh = hm
	head.material_override = steel
	head.position = Vector3.UP * (_rise + 2.6)
	add_child(head)
	# The car: a solid deck with a chevron edge and a beacon on a short mast.
	_car = AnimatableBody3D.new()
	_car.collision_layer = 1
	_car.collision_mask = 0
	_car.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, CAR_THICK, size.y)
	cs.shape = box
	cs.position = Vector3.DOWN * CAR_THICK * 0.5
	_car.add_child(cs)
	var deck := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = box.size
	deck.mesh = dm
	deck.material_override = steel
	deck.position = cs.position
	_car.add_child(deck)
	for sz: float in [-1.0, 1.0]:
		var edge := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(size.x, 0.04, 0.16)
		edge.mesh = em
		edge.material_override = paint
		edge.position = Vector3(0, 0.02, sz * (size.y * 0.5 - 0.08))
		_car.add_child(edge)
	var mast := MeshInstance3D.new()
	var mm := CylinderMesh.new()
	mm.top_radius = 0.04
	mm.bottom_radius = 0.04
	mm.height = 1.1
	mast.mesh = mm
	mast.material_override = steel
	mast.position = Vector3(size.x * 0.5 - 0.15, 0.55, -size.y * 0.5 + 0.15)
	_car.add_child(mast)
	var beacon := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	beacon.mesh = sm
	_beacon_mat = StandardMaterial3D.new()
	_beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beacon_mat.albedo_color = Color(1.0, 0.6, 0.1)
	_beacon_mat.emission_enabled = true
	_beacon_mat.emission = Color(1.0, 0.6, 0.1)
	beacon.material_override = _beacon_mat
	beacon.position = mast.position + Vector3.UP * 0.6
	_car.add_child(beacon)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.15)
	_light.omni_range = 5.0
	_light.light_energy = 0.0
	_light.position = beacon.position
	_car.add_child(_light)
	add_child(_car)
	# Who is riding: the player's body inside the space above the deck.
	_ride = Area3D.new()
	_ride.collision_layer = 0
	_ride.collision_mask = 2
	var rcs := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(size.x - 0.2, 1.6, size.y - 0.2)
	rcs.shape = rb
	rcs.position = Vector3.UP * 0.9
	_ride.add_child(rcs)
	_car.add_child(_ride)

func _rider() -> bool:
	for b in _ride.get_overlapping_bodies():
		if is_instance_valid(b) and b.is_in_group("player"):
			return true
	return false

## The landing (0 bottom, _rise top) a player standing next to the shaft is
## at, or -1. A rider on the car does not count.
func _caller_landing() -> float:
	var pl := GameState.nearest_player(global_position)
	if pl == null:
		return -1.0
	var lp := to_local(pl.global_position)
	if absf(lp.x) > size.x * 0.5 + CALL_REACH or absf(lp.z) > size.y * 0.5 + CALL_REACH:
		return -1.0
	for landing: float in [0.0, _rise]:
		if lp.y > landing - 0.4 and lp.y < landing + CALL_HEIGHT:
			return landing
	return -1.0

func _physics_process(delta: float) -> void:
	var riding := _rider()
	if not riding:
		_armed = true
		_board_t = 0.0
	var moving := absf(_goal - _y) > 0.001
	if not moving:
		if riding and _armed:
			_board_t += delta
			if _board_t >= board_delay:
				_goal = _rise if at_bottom() else 0.0
				_armed = false
		elif not riding:
			var call := _caller_landing()
			if call >= 0.0 and absf(call - _y) > 0.02:
				_goal = call
	_y = move_toward(_y, _goal, speed * delta)
	_car.position = Vector3.UP * _y
	moving = absf(_goal - _y) > 0.001
	if moving != _was_moving:
		AudioBus.play_synth_at("servo_step_heavy", _car.global_position, -4.0, 0.6)
		if not moving:
			AudioBus.play_synth_at("impact_metal", _car.global_position, -8.0, 0.55)
	_was_moving = moving
	var blink := 1.0 if moving and fmod(Time.get_ticks_msec() / 400.0, 1.0) < 0.5 else 0.0
	_beacon_mat.emission_energy_multiplier = 1.0 + blink * 5.0
	_light.light_energy = blink * 1.6
