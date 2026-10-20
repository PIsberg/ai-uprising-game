class_name Keycard
extends Area3D
# @lat: [[level-system#Hallucinated Keycards]]
## A glowing access card the player must recover to unlock the exit. Completes
## the level task whose id it carries (default "key"). Spins and bobs like a
## pickup, and joins the "objective" group so the HUD radar/waypoint guides the
## player to it; once taken, the portal's remaining-task list updates.
##
## A `decoy` is a card the level's AI hallucinated (a key task's `decoys`): the
## same model, the same waypoint, the same glow. Two tells for the attentive:
## from afar it glitches now and then (the card jumps and its light flicks
## magenta), and inside TAG_RANGE a "[citation needed]" tag hangs over it.
## Touching one completes nothing: it glitches out, the HUD calls it a
## hallucination and its `ambush` (enemy specs, spawned where it stood) pours
## in. Taking the real card dissolves every decoy left, so the waypoint never
## leads to a card that is no longer a lie worth telling.

@export var task_id: String = "key"
@export var decoy: bool = false
## Decoy only: enemy specs (type, count) spawned through the level's
## reinforcement spawner at the decoy's position when it is touched.
var ambush: Array = []

## The kit's textured keycard (same Sci-Fi Essentials Kit as the pickups).
const CARD_MODEL: PackedScene = preload("res://assets/models/pickups/Prop_KeyCard.gltf")
const TAG_RANGE := 6.0
const HALLUCINATION_TITLE := "HALLUCINATION"
## Cycled across decoys (a static counter), so a second decoy reads a new line.
const HALLUCINATION_LINES: Array[String] = [
	"Confidently generated. Not found in any source.",
	"That keycard was plausible. Plausible is not real.",
	"Source: trust me.",
]
static var _lines_used: int = 0

var _taken: bool = false
var _t: float = 0.0
var _card: Node3D
var _light: OmniLight3D
var _tag: Label3D
var _glitch_t: float = 0.0
var _next_glitch: float = 2.0

func _ready() -> void:
	collision_layer = 32
	collision_mask = 2 # player
	add_to_group("objective")
	add_to_group("keycard")
	if decoy:
		add_to_group("keycard_decoy")
	body_entered.connect(_on_body_entered)
	_build_visual()
	_next_glitch = randf_range(1.5, 3.5)

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

	if decoy:
		_tag = Label3D.new()
		_tag.text = "[citation needed]"
		_tag.font_size = 64
		_tag.pixel_size = 0.004
		_tag.modulate = Color(1.0, 0.35, 0.9)
		_tag.outline_size = 10
		_tag.outline_modulate = Color(0, 0, 0, 0.9)
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_tag.position = Vector3(0, 1.85, 0)
		_tag.visible = false
		add_child(_tag)

func _process(delta: float) -> void:
	_t += delta
	if _card:
		_card.rotation.y += delta * 1.6
		_card.position.y = 1.0 + sin(_t * 2.0) * 0.12
	if _light:
		_light.light_energy = 2.4 + sin(_t * 3.0) * 0.6
	if decoy:
		_tick_decoy(delta)

func _tick_decoy(delta: float) -> void:
	# A brief glitch every couple of seconds: the card jumps sideways and the
	# light flicks magenta for 0.12 s.
	_next_glitch -= delta
	if _next_glitch <= 0.0:
		_next_glitch = randf_range(2.0, 4.0)
		_glitch_t = 0.12
	if _glitch_t > 0.0:
		_glitch_t -= delta
		_card.position.x = randf_range(-0.18, 0.18)
		_light.light_color = Color(1.0, 0.3, 0.9)
	else:
		_card.position.x = 0.0
		_light.light_color = Color(1.0, 0.8, 0.3)
	var player := GameState.nearest_player(global_position)
	_tag.visible = player != null and player.global_position.distance_to(global_position) < TAG_RANGE

func _on_body_entered(body: Node) -> void:
	if _taken or not body.is_in_group("player"):
		return
	_taken = true
	if decoy:
		_hallucinate()
		return
	GameState.complete_task(task_id)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("pickup_health", global_position, -1.0, 1.1)
	if body.has_method("notify_pickup"):
		body.notify_pickup("ACCESS KEYCARD ACQUIRED")
	# The real card is in hand: the hallucinations have nothing left to sell.
	for d in get_tree().get_nodes_in_group("keycard_decoy"):
		if d != self and d is Keycard and not (d as Keycard)._taken:
			(d as Keycard)._taken = true
			d.queue_free()
	queue_free()

## A decoy touched: no task, a callout and an ambush where the card stood.
func _hallucinate() -> void:
	GameState.skirmish_event.emit(HALLUCINATION_TITLE, HALLUCINATION_LINES[_lines_used % HALLUCINATION_LINES.size()])
	_lines_used += 1
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 1.4)
	var lvl := get_parent()
	if not ambush.is_empty() and lvl and lvl.has_method("_spawn_reinforcements"):
		var specs: Array = []
		for a in ambush:
			var s: Dictionary = (a as Dictionary).duplicate()
			s["pos"] = global_position
			specs.append(s)
		lvl._spawn_reinforcements(specs)
	queue_free()
