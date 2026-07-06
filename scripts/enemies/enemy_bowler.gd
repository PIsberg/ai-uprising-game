class_name EnemyBowler
extends EnemyBase
## STRIKER-9 — a heavy pitcher frame (a repainted brute chassis) that BOWLS
## Molten Orbs at you. It holds the high ground — ramp tops, walkway mouths —
## conjures a fresh orb in its fist and hurls it in a flat, skipping arc; the
## orb lands, keeps rolling under its own power, and hunts you. Kill the
## pitcher or you'll drown in bowling balls. Up close it falls back on a
## two-handed shove.

const ORB := preload("res://scenes/enemies/orb.tscn")

@export var throw_speed: float = 16.0
@export var throw_up: float = 5.5
@export var shove_damage: float = 24.0
@export var max_live_orbs: int = 3

var _live_orbs: Array = []

func _ready() -> void:
	super._ready()
	max_health = 340.0
	move_speed = 3.0            # a planted artillery-pitcher, not a chaser
	turn_speed = 4.5
	sight_range = 46.0
	sight_angle_deg = 220.0
	attack_range = 38.0         # its "gun" is a thrown orb
	preferred_range = 18.0
	attack_cooldown = 5.5
	telegraph_time = 0.55       # the big wind-up IS the tell
	score_value = 300
	head_radius = 0.7
	stagger_threshold = 160.0
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 3.0

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	var dist := global_position.distance_to(target.global_position)
	if dist <= 4.5:
		_shove()
		return
	_live_orbs = _live_orbs.filter(func(o): return is_instance_valid(o) and not (o as EnemyBase).state == EnemyBase.State.DEAD)
	if _live_orbs.size() >= max_live_orbs:
		return  # lane's full — wait for a strike before racking another ball
	_throw_orb()

func _throw_orb() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var orb := ORB.instantiate()
	orb.drop_chance = 0.0  # conjured ordnance isn't a loot pinata
	scene.add_child(orb)
	var from := global_position + Vector3.UP * 2.2 - global_transform.basis.z * 1.4
	(orb as Node3D).global_position = from
	# Lead the runner a touch; gravity and the slope do the rest — bowled down
	# a ramp the orb arrives carrying every metre of the drop.
	var predicted: Vector3 = target.global_position
	if "velocity" in target:
		predicted += (target.velocity as Vector3) * 0.4
	var flat := predicted - from
	flat.y = 0.0
	var vel := flat.normalized() * throw_speed + Vector3.UP * throw_up
	(orb as EnemyOrb).launch_throw(vel)
	_live_orbs.append(orb)
	recoil = 1.0  # fires the Punch clip — the bowling swing
	AudioBus.play_synth_at("grenade_throw", global_position, 2.0, 0.7)
	AudioBus.play_synth_at("mech_step", global_position, -2.0, 0.6)
	_speak("atk", 0.4)

func _shove() -> void:
	var d = target.get_node_or_null("Damageable")
	if d and global_position.distance_to(target.global_position) <= 4.8:
		d.apply_damage(shove_damage, self)
		if "velocity" in target:
			var away: Vector3 = target.global_position - global_position
			away.y = 0.0
			target.velocity += away.normalized() * 9.0 + Vector3.UP * 3.0
		if target.has_method("shake"):
			target.shake(0.6)
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.2)
