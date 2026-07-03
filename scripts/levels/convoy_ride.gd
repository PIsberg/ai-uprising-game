class_name ConvoyRide
extends Node3D
## The HIGHWAY BREAKOUT ride: a commandeered flatbed hauler that drives itself
## down the highway while the player fights off pursuit from its deck. The
## truck is an AnimatableBody3D (sync_to_physics) so the player rides it like
## a moving platform; waves of flyers and runners spawn around it as it rolls.

@export var speed: float = 5.5           ## cruise speed, m/s (toward -Z)
@export var start_z: float = 170.0
@export var end_z: float = -170.0
@export var wave_interval: float = 11.0

const WAVES: Array = [
	["drone", "drone"],
	["raptor", "drone"],
	["dog", "dog", "drone"],
	["raptor", "raptor"],
	["strider", "drone", "drone"],
	["seeker", "seeker", "raptor"],
]
const SCENES := {
	"drone": preload("res://scenes/enemies/drone.tscn"),
	"raptor": preload("res://scenes/enemies/raptor.tscn"),
	"dog": preload("res://scenes/enemies/dog.tscn"),
	"strider": preload("res://scenes/enemies/strider.tscn"),
	"seeker": preload("res://scenes/enemies/seeker.tscn"),
}

var _truck: AnimatableBody3D
var _t: float = 0.0
var _wave_t: float = 6.0 # first wave shortly after rollout
var _wave_i: int = 0
var _arrived: bool = false

func _ready() -> void:
	_build_truck()
	_board_player.call_deferred()

func _build_truck() -> void:
	_truck = AnimatableBody3D.new()
	_truck.sync_to_physics = true
	_truck.collision_layer = 1
	_truck.collision_mask = 0
	add_child(_truck)
	_truck.global_position = Vector3(0, 0, start_z)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.30, 0.33, 0.38)
	metal.metallic = 0.7
	metal.roughness = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.14, 0.15, 0.17)
	dark.metallic = 0.5
	dark.roughness = 0.6
	var mk := func(center: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		bm.material = mat
		mi.mesh = bm
		mi.position = center
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = center
		_truck.add_child(mi)
		_truck.add_child(cs)
	# Flatbed deck + low rail ring (keeps the player aboard) + cab up front.
	mk.call(Vector3(0, 1.0, 0), Vector3(5.6, 0.5, 11.0), metal)          # deck
	mk.call(Vector3(0, 1.75, -6.0), Vector3(5.6, 1.0, 1.0), dark)        # front rail/cab back
	mk.call(Vector3(0, 1.6, 5.75), Vector3(5.6, 0.7, 0.5), dark)         # tail rail
	mk.call(Vector3(-3.0, 1.6, 0), Vector3(0.4, 0.7, 12.0), dark)        # left rail
	mk.call(Vector3(3.0, 1.6, 0), Vector3(0.4, 0.7, 12.0), dark)         # right rail
	mk.call(Vector3(0, 2.6, -7.6), Vector3(5.0, 2.6, 2.4), metal)        # cab block
	# Wheels: six dark cylinders (visual only).
	for wz in [-4.5, 0.0, 4.5]:
		for sx in [-2.6, 2.6]:
			var wheel := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.75
			cm.bottom_radius = 0.75
			cm.height = 0.5
			cm.material = dark
			wheel.mesh = cm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(sx, 0.75, wz)
			_truck.add_child(wheel)
	# Headlights + a warm cab light so the rig reads alive at night.
	for sx in [-1.8, 1.8]:
		var hl := SpotLight3D.new()
		hl.light_color = Color(1.0, 0.95, 0.8)
		hl.light_energy = 3.0
		hl.spot_range = 30.0
		hl.spot_angle = 30.0
		hl.position = Vector3(sx, 1.6, -8.8)
		hl.rotation.x = -0.08
		hl.rotation.y = PI
		_truck.add_child(hl)

func _board_player() -> void:
	await get_tree().create_timer(0.6).timeout
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p:
		p.global_position = _truck.global_position + Vector3(0, 1.8, 1.0)

func _physics_process(delta: float) -> void:
	if _arrived:
		return
	_t += delta
	# Ease off the line, cruise, ease into the terminus.
	var z: float = _truck.global_position.z
	var spd := speed
	if _t < 3.0:
		spd = speed * (_t / 3.0)
	elif z < end_z + 20.0:
		spd = maxf(1.2, speed * (z - end_z) / 20.0)
	_truck.global_position.z = maxf(end_z, z - spd * delta)
	if _truck.global_position.z <= end_z + 0.05:
		_arrived = true
		return
	# Pursuit waves, spawned around the rolling truck.
	_wave_t -= delta
	if _wave_t <= 0.0:
		_wave_t = wave_interval
		_spawn_wave()

func _spawn_wave() -> void:
	var wave: Array = WAVES[_wave_i % WAVES.size()]
	_wave_i += 1
	var tz: float = _truck.global_position.z
	for i in wave.size():
		var scene: PackedScene = SCENES.get(wave[i])
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		var side := -1.0 if i % 2 == 0 else 1.0
		# Flank spawns slightly behind the truck so pursuit reads as a chase.
		e.position = Vector3(side * randf_range(9.0, 14.0), 0.6, tz + randf_range(4.0, 16.0))
		get_tree().current_scene.add_child(e)
