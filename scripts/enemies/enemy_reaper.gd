class_name EnemyReaper
extends EnemyBase
## Fast melee killer: glides at the player and lunges into a slashing strike.
## Fragile but lethal up close. Visuals come from a real robot model in
## reaper.tscn. The chassis HOVERS — its walk clip read as a broken shamble,
## so the model floats on an anti-grav cushion (no gait; RobotModel's flyer
## auto-bank tilts it into turns like a wraith) with a gentle bob.

@export var slash_damage: float = 22.0
@export var hover_height: float = 0.42
@export var hover_bob: float = 0.08

var _hover_t: float = 0.0


func _ready() -> void:
	max_health = 62.0
	move_speed = 8.6
	turn_speed = 9.0
	sight_range = 34.0
	sight_angle_deg = 200.0
	attack_range = 3.0
	preferred_range = 1.5
	attack_cooldown = 1.1
	attack_lunge_speed = 12.0
	score_value = 130
	stagger_threshold = 40.0
	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# Anti-grav hover: lift the visual chassis and bob it gently. Set as an
	# ABSOLUTE height over the model base (not +=) so ticks where the base pass
	# skips its re-basing (e.g. EMP-stunned) can't accumulate lift.
	if _visual_root and state != State.DEAD:
		_hover_t += delta
		_visual_root.position.y = _visual_base.y - 0.04 * _flinch \
			+ hover_height + sin(_hover_t * 3.1) * hover_bob


func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -6.0, 1.6)
	_attack_lunge()
