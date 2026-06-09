class_name Keycard
extends Area3D
## A glowing access card the player must recover to unlock the exit. Completes
## the level task whose id it carries (default "key"). Spins and bobs like a
## pickup, and joins the "objective" group so the HUD radar/waypoint guides the
## player to it; once taken, the portal's remaining-task list updates.

@export var task_id: String = "key"

var _taken: bool = false
var _t: float = 0.0
var _card: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = 32
	collision_mask = 2 # player
	add_to_group("objective")
	add_to_group("keycard")
	body_entered.connect(_on_body_entered)
	_build_visual()

func _build_visual() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 1.4, 1.2)
	cs.shape = bs
	add_child(cs)

	_card = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.34, 0.04)
	_card.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.25)
	mat.emission_energy_multiplier = 2.2
	mat.metallic = 0.6
	mat.roughness = 0.3
	_card.material_override = mat
	_card.position = Vector3(0, 1.0, 0)
	add_child(_card)

	# A little chip detail so it reads as a keycard, not just a tile.
	var chip := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.14, 0.1, 0.05)
	chip.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(0.2, 0.25, 0.3)
	cmat.emission_enabled = true
	cmat.emission = Color(0.4, 0.9, 1.0)
	cmat.emission_energy_multiplier = 3.0
	chip.mesh.material = cmat
	chip.position = Vector3(0.12, 0, 0.01)
	_card.add_child(chip)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.8, 0.3)
	_light.light_energy = 2.4
	_light.omni_range = 6.0
	_light.position = Vector3(0, 1.0, 0)
	add_child(_light)

func _process(delta: float) -> void:
	_t += delta
	if _card:
		_card.rotation.y += delta * 1.6
		_card.position.y = 1.0 + sin(_t * 2.0) * 0.12
	if _light:
		_light.light_energy = 2.4 + sin(_t * 3.0) * 0.6

func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	GameState.complete_task(task_id)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("pickup_health", global_position, -1.0, 1.1)
	if body.has_method("notify_pickup"):
		body.notify_pickup("ACCESS KEYCARD ACQUIRED")
	queue_free()
