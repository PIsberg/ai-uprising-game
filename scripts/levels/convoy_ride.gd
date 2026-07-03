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
	["drone", "drone", "raptor"],
	["raptor", "drone", "seeker"],
	["dog", "dog", "drone", "seeker"],
	["raptor", "raptor", "breaker"],
	["strider", "drone", "drone", "mender"],
	["seeker", "seeker", "raptor", "brute"],
	["mech", "drone", "drone", "seeker"],
	["brute", "breaker", "raptor", "drone"],
]
const SCENES := {
	"drone": preload("res://scenes/enemies/drone.tscn"),
	"raptor": preload("res://scenes/enemies/raptor.tscn"),
	"dog": preload("res://scenes/enemies/dog.tscn"),
	"strider": preload("res://scenes/enemies/strider.tscn"),
	"seeker": preload("res://scenes/enemies/seeker.tscn"),
	"breaker": preload("res://scenes/enemies/breaker.tscn"),
	"mender": preload("res://scenes/enemies/mender.tscn"),
	"brute": preload("res://scenes/enemies/brute.tscn"),
	"mech": preload("res://scenes/enemies/mech.tscn"),
}

var _truck: AnimatableBody3D
var _t: float = 0.0
var _wave_t: float = 6.0 # first wave shortly after rollout
var _wave_i: int = 0
var _arrived: bool = false

func _ready() -> void:
	_build_truck()
	_build_highway_scenery()
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
	
	# Cargo cover boxes on the flatbed for cover:
	mk.call(Vector3(-1.7, 1.8, -1.8), Vector3(1.3, 1.1, 1.3), dark)      # front-left cover
	mk.call(Vector3(1.7, 1.9, 2.2), Vector3(1.4, 1.3, 1.4), metal)       # back-right cover
	mk.call(Vector3(0, 1.75, 4.2), Vector3(1.1, 1.0, 1.1), dark)         # back-center cover

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

func _build_highway_scenery() -> void:
	var light_color := Color(1.0, 0.62, 0.22) # Amber sodium highway glow
	var metal_color := Color(0.22, 0.24, 0.28)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = metal_color
	post_mat.metallic = 0.8
	post_mat.roughness = 0.35
	
	var barrier_mat := StandardMaterial3D.new()
	barrier_mat.albedo_color = Color(0.3, 0.3, 0.3)
	barrier_mat.roughness = 0.9
	
	# Shared emissive lamp-head material — the glowing fixture is what makes a
	# streetlight read as lit at night (the OmniLight itself is invisible).
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = light_color
	lamp_mat.emission_enabled = true
	lamp_mat.emission = light_color
	lamp_mat.emission_energy_multiplier = 3.5
	
	for z in range(int(end_z) - 30, int(start_z) + 30, 28):
		for side in [-10.5, 10.5]:
			# Streetlight Post
			var post := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 0.08
			pm.bottom_radius = 0.12
			pm.height = 7.5
			pm.material = post_mat
			post.mesh = pm
			post.position = Vector3(side, 3.75, z)
			add_child(post)
			
			# Streetlight Arm — reaches from the post toward the roadway.
			var toward_road := 1.0 if side < 0 else -1.0
			var arm := MeshInstance3D.new()
			var am := BoxMesh.new()
			am.size = Vector3(2.6, 0.16, 0.16)
			am.material = post_mat
			arm.mesh = am
			arm.position = Vector3(side + 1.3 * toward_road, 7.5, z)
			add_child(arm)
			
			# Streetlight Light Source — hangs off the arm tip, over the lanes.
			var light := OmniLight3D.new()
			light.light_color = light_color
			light.light_energy = 2.4
			light.omni_range = 16.0
			light.position = Vector3(side + 2.6 * toward_road, 7.2, z)
			add_child(light)
			
			# Lamp head at the arm tip, just above the light source.
			var lamp := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = Vector3(0.55, 0.14, 0.32)
			lm.material = lamp_mat
			lamp.mesh = lm
			lamp.position = Vector3(side + 2.45 * toward_road, 7.42, z)
			add_child(lamp)
			
			# Concrete Jersey Barrier along sides
			var barrier := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.6, 0.9, 5.0)
			bm.material = barrier_mat
			barrier.mesh = bm
			barrier.position = Vector3(side * 0.88, 0.45, z + randf_range(-1.0, 1.0))
			barrier.rotation.y = randf_range(-0.06, 0.06)
			add_child(barrier)
			
	# Spawn a few overhead highway sign gantries for scale
	for gz in [120.0, 30.0, -60.0, -140.0]:
		# Left pillar
		var p1 := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.16
		pm.bottom_radius = 0.16
		pm.height = 9.5
		pm.material = post_mat
		p1.mesh = pm
		p1.position = Vector3(-11.0, 4.75, gz)
		add_child(p1)
		
		# Right pillar
		var p2 := MeshInstance3D.new()
		p2.mesh = pm
		p2.position = Vector3(11.0, 4.75, gz)
		add_child(p2)
		
		# Crossbeam
		var beam := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(22.0, 0.4, 0.4)
		bm.material = post_mat
		beam.mesh = bm
		beam.position = Vector3(0, 9.5, gz)
		add_child(beam)
		
		# Sign board
		var board := MeshInstance3D.new()
		var bmesh := BoxMesh.new()
		bmesh.size = Vector3(7.0, 2.0, 0.15)
		var board_mat := StandardMaterial3D.new()
		board_mat.albedo_color = Color(0.08, 0.26, 0.14) # Highway Green
		board_mat.roughness = 0.75
		bmesh.material = board_mat
		board.mesh = bmesh
		board.position = Vector3(-2.2, 8.2, gz)
		add_child(board)

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

## Heavies too slow to chase a 5.5 m/s truck from the roadside — they drop
## straight onto the deck as boarders instead, forcing close-quarters fights
## around the cargo cover boxes.
const BOARDERS := ["brute", "mech"]

func _spawn_wave() -> void:
	var wave: Array = WAVES[_wave_i % WAVES.size()]
	_wave_i += 1
	var tz: float = _truck.global_position.z
	for i in wave.size():
		var scene: PackedScene = SCENES.get(wave[i])
		if scene == null:
			continue
		var e := scene.instantiate() as Node3D
		if wave[i] in BOARDERS:
			# Deck boarding drop: released above the front half of the bed so
			# the truck's forward travel during the fall lands them mid-deck.
			e.position = _truck.global_position \
				+ Vector3(randf_range(-1.5, 1.5), 3.0, randf_range(-4.4, -1.4))
		else:
			var side := -1.0 if i % 2 == 0 else 1.0
			# Flank spawns slightly behind the truck so pursuit reads as a chase.
			e.position = Vector3(side * randf_range(9.0, 14.0), 0.6, tz + randf_range(4.0, 16.0))
		get_tree().current_scene.add_child(e)
