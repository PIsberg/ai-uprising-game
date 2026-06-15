class_name EnemySkitter
extends EnemyBase
## SKITTER — a tiny, fast robotic bug that attacks in swarms. One is trivial
## (paper HP, a weak bite); a dozen pouring across the floor and flanking from
## every angle is a real threat. Built to be cheap and relentless so they can
## come in masses. Real model: the imported Trilobite crawler, shrunk and tinted
## hostile red (RobotModel on $Model drives the Run/Attack clips).

@export var bite_damage: float = 6.0
@export var lunge_speed: float = 12.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 16.0
	move_speed = 12.5          # very fast skitter
	turn_speed = 16.0
	sight_range = 38.0
	sight_angle_deg = 330.0    # near-omnidirectional; the swarm always finds you
	attack_range = 1.9
	preferred_range = 0.8
	attack_cooldown = 0.7
	score_value = 35
	head_radius = 0.3
	flinch_knockback = 0.6
	stagger_threshold = 1.0e9  # too small/fast to stunlock — keeps the swarm relentless
	drop_chance = 0.06         # swarms must not flood the floor with pickups
	hp.max_health = max_health
	hp.current_health = max_health

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		_eye_light.light_energy = 1.0 + recoil * 2.5 + (1.5 if is_enraged() else 0.0)

func _perform_attack() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) <= attack_range:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(bite_damage, self)
		# Quick forward snap on the bite.
		var dir := target.global_position - global_position
		dir.y = 0.0
		dir = dir.normalized()
		velocity.x = dir.x * lunge_speed
		velocity.z = dir.z * lunge_speed
		recoil = 1.0 # plays the Attack clip
		# Gate the SFX so a whole swarm biting doesn't turn into noise mush.
		if randf() < 0.35:
			AudioBus.play_synth_at("impact_metal", global_position, -7.0, 1.9)

## Lean swarm death: a small pop and a quick shrink-out — no topple/debris/scorch,
## so dozens dying at once stays cheap and snappy.
func _on_died(source: Node) -> void:
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	if _damaged_emitter and is_instance_valid(_damaged_emitter):
		_damaged_emitter.queue_free()
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position + Vector3.UP * 0.2
	if randf() < 0.5:
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 0.9)
	var tw := create_tween()
	tw.tween_property(self, "scale", scale * 0.1, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
