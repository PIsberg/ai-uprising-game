class_name EnemyEnforcer
extends EnemyAndroid
## ENFORCER — the AI's armoured riot trooper, built on the mech-police chassis with
## a braced scifi rifle. Tougher and more accurate than a stock android: it holds
## its ground, takes measured bursts, and shrugs off chip damage.
##
## Signature move: the SUPPRESSION LASER — between bursts it locks on and drags
## a sustained GREEN cutting beam across you for a second. It burns fast, but
## the vivid green line telegraphs exactly where not to stand: break the line
## of sight or strafe hard and the sweep wastes itself.

const LASER_COLOR := Color(0.35, 1.0, 0.4)

@export var laser_dps: float = 22.0
@export var laser_duration: float = 1.1
@export var laser_cooldown: float = 6.0

var _laser: ElectricBeam
var _laser_t: float = 0.0
var _laser_cd: float = 3.0 # first sweep comes a few seconds into the fight
var _laser_tick: float = 0.0

func _ready() -> void:
	super._ready()
	max_health = 210.0
	move_speed = 4.2
	turn_speed = 7.0
	attack_range = 30.0
	preferred_range = 16.0
	hitscan_damage = 11.0
	burst_count = 4
	score_value = 240
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 3.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		_stop_laser()
		return
	_laser_cd = maxf(0.0, _laser_cd - delta)
	if _laser_t > 0.0:
		_laser_t -= delta
		_sweep_laser(delta)
		if _laser_t <= 0.0:
			_stop_laser()
		return
	if target and is_instance_valid(target) and _laser_cd <= 0.0 \
			and state in [State.CHASE, State.ATTACK] and _can_see(target):
		_laser_t = laser_duration
		_laser_cd = laser_cooldown
		AudioBus.play_synth_at("overlord_glitch", global_position, -6.0, 1.6)

## Drag the green beam onto the player each tick, burning while it connects.
func _sweep_laser(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _laser == null or not is_instance_valid(_laser):
		_laser = ElectricBeam.new()
		var scene := get_tree().current_scene
		if scene == null:
			return
		scene.add_child(_laser)
		_laser.set_color(LASER_COLOR)
	var from: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 1.4
	var to: Vector3 = target.global_position + Vector3.UP * 0.9
	var clear := _can_see(target)
	_laser.update_beam(from, to, clear)
	_face_target(delta)
	if clear:
		_laser_tick -= delta
		if _laser_tick <= 0.0:
			_laser_tick = 0.25
			var d = target.get_node_or_null("Damageable")
			if d:
				d.apply_damage(laser_dps * 0.25, self)

func _stop_laser() -> void:
	_laser_t = 0.0
	if _laser and is_instance_valid(_laser):
		_laser.queue_free()
	_laser = null

func _exit_tree() -> void:
	_stop_laser()
