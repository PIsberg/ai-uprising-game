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
##
## The model carries its rifle at port arms, across its chest with the barrel
## to its left. Engaged, it swings the rifle about its grip onto you (the rifle
## parts move as one, PartRig), and rounds and the laser leave from the
## barrel's tip; it brings the rifle back across its chest when it loses you.
## tests/enforcer_rifle_probe.

const LASER_COLOR := Color(0.35, 1.0, 0.4)

@export var laser_dps: float = 22.0
@export var laser_duration: float = 1.1
@export var laser_cooldown: float = 6.0

var _laser: ElectricBeam
var _laser_t: float = 0.0
var _laser_cd: float = 3.0 # first sweep comes a few seconds into the fight
var _laser_tick: float = 0.0

# The rifle, as named in mech_police.glb: tube (barrel), the two receiver
# halves, small parts, trigger (the grip) and the sight's glass.
const RIFLE_PARTS := ["Object_11", "Object_3", "Object_4", "Object_17", "Object_10", "Object_5"]
const RIFLE_GRIP := "Object_10"
const RIFLE_BARREL := "Object_11"
const AIM_RATE := 5.0 ## 1/s: port arms to shouldered in about 0.2 s
var _rifle: Array = []
var _rifle_ready := false
var _grip := Vector3.ZERO ## body frame, at port arms
var _tip := Vector3.ZERO
var _aim_w := 0.0
var _aim_q := Quaternion.IDENTITY ## rest barrel -> the last aim, body frame

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
	if state != State.DEAD:
		_tick_rifle(delta) # before the shot this tick may fire
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

## Measure the rifle at port arms once RobotModel's fit has landed.
func _setup_rifle() -> void:
	var grip := find_child(RIFLE_GRIP, true, false) as MeshInstance3D
	var tube := find_child(RIFLE_BARREL, true, false) as MeshInstance3D
	if grip == null or tube == null or not grip.is_visible_in_tree():
		return
	for n in RIFLE_PARTS:
		var mi := find_child(n, true, false) as MeshInstance3D
		if mi:
			_rifle.append(PartRig.entry(self, mi))
	_grip = PartRig.mean(PartRig.body_points(self, grip))
	var pts := PartRig.body_points(self, tube)
	var far := 0.0
	for q in pts:
		far = maxf(far, q.distance_to(_grip))
	var tip := PackedVector3Array()
	for q in pts:
		if q.distance_to(_grip) > far - 0.03:
			tip.append(q)
	_tip = PartRig.mean(tip)
	_rifle_ready = true

## Shoulder the rifle onto the target while engaged (port arms otherwise);
## the muzzle rides the barrel's tip.
func _tick_rifle(delta: float) -> void:
	if not _rifle_ready:
		_setup_rifle()
		return
	var live := target != null and is_instance_valid(target)
	var engaged := live and state in [State.CHASE, State.ATTACK]
	_aim_w = move_toward(_aim_w, 1.0 if engaged else 0.0, AIM_RATE * delta)
	if live:
		var aim := global_transform.basis.inverse() * (target.global_position + Vector3.UP * 0.6 - global_transform * _grip)
		if aim.length() > 0.01:
			_aim_q = Quaternion((_tip - _grip).normalized(), aim.normalized())
	# Eases out of the last aim when the target is gone.
	var r := Basis(Quaternion.IDENTITY.slerp(_aim_q, smoothstep(0.0, 1.0, _aim_w)))
	var lay := Transform3D(r, _grip - r * _grip)
	for e in _rifle:
		PartRig.pose(e, lay)
	if muzzle:
		muzzle.global_position = global_transform * (_grip + r * (_tip - _grip))
