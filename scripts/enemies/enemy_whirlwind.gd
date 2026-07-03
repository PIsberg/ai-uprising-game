class_name EnemyWhirlwind
extends EnemyDrone
## WHIRLWIND — a hovering buzzsaw drone: a red core slung between two long whirling
## blade-arms. It floats over the battlefield, then dives in to rake you with its
## spinning arms before pulling back up. No ranged attack — it kills up close.

@export var slash_damage: float = 22.0
@export var spin_speed: float = 7.5 ## rad/s — the buzzsaw whirl

var _spin_mesh: Node3D

func _ready() -> void:
	super._ready()
	max_health = 120.0
	move_speed = 7.2
	sight_range = 40.0
	attack_range = 3.4          # melee reach for the blades
	preferred_range = 3.0       # stays close and dives in
	attack_cooldown = 0.7
	hover_height = 2.2
	hover_amplitude = 0.4
	score_value = 190
	drops_loot = true
	hp.max_health = max_health
	hp.current_health = max_health
	_spin_mesh = get_node_or_null("Model/Mesh")

## A WHIRLWIND has to whirl: spin the blade-arm chassis like a buzzsaw. The
## static model's drooping blade-arms read as a broken, tipped-over wreck
## (in play and on the codex pedestal alike); spinning sells the design.
## _process, not physics, so the codex preview (physics disabled) spins too.
func _process(delta: float) -> void:
	if _spin_mesh and state != State.DEAD:
		_spin_mesh.rotation.y += spin_speed * delta

## Spinning-blade melee instead of the drone's projectile.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	recoil = 1.0
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.7)
