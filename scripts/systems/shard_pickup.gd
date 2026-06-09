class_name ShardPickup
extends Area3D
## One collectible data shard. Each one advances its level task by 1; the task's
## goal is the total number of shards, so the HUD shows (collected/total) and
## auto-completes when the last is grabbed. Spins, glows, joins "objective" so
## the radar guides the player around the map to mop them up.

@export var task_id: String = "shards"

var _taken: bool = false
var _t: float = 0.0
var _mesh: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 32
	collision_mask = 2 # player
	add_to_group("objective")
	add_to_group("shard")
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU
	_build_visual()

func _build_visual() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 1.4, 1.0)
	cs.shape = bs
	add_child(cs)

	_mesh = MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.35, 0.6, 0.35)
	_mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.95, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.metallic = 0.5
	mat.roughness = 0.2
	_mesh.material_override = mat
	_mesh.position = Vector3(0, 0.9, 0)
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = Color(0.4, 0.9, 1.0)
	_light.light_energy = 1.8
	_light.omni_range = 5.0
	_light.position = Vector3(0, 0.9, 0)
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	if _mesh:
		_mesh.rotation.y += delta * 2.0
		_mesh.position.y = 0.9 + sin(_t * 2.2) * 0.12

func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	GameState.advance_task(task_id, 1.0)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("pickup_ammo", global_position, -2.0, 1.3)
	if body.has_method("notify_pickup"):
		body.notify_pickup("DATA SHARD RECOVERED")
	queue_free()
