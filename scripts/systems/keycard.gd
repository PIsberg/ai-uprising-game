class_name Keycard
extends Area3D
## A glowing access card the player must recover to unlock the exit. Completes
## the level task whose id it carries (default "key"). Spins and bobs like a
## pickup, and joins the "objective" group so the HUD radar/waypoint guides the
## player to it; once taken, the portal's remaining-task list updates.

@export var task_id: String = "key"

## The kit's textured keycard (same Sci-Fi Essentials Kit as the pickups).
const CARD_MODEL: PackedScene = preload("res://assets/models/pickups/Prop_KeyCard.gltf")

var _taken: bool = false
var _t: float = 0.0
var _card: Node3D
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

	# The textured card model, spinning where the old glowing tile floated.
	# (~0.48 m tall; scaled up so the objective reads from across the level.)
	_card = Node3D.new()
	_card.position = Vector3(0, 1.0, 0)
	add_child(_card)
	var model := CARD_MODEL.instantiate() as Node3D
	model.scale = Vector3.ONE * 1.4
	model.position.y = -0.12 # model origin sits low on the card; recentre
	_card.add_child(model)

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
