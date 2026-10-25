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
##
## It walks on its legs (tests/enforcer_gait_probe): the GLB keeps both
## trouser legs in one mesh and the boots in the chest-plate mesh, so
## `_setup_gait` cuts both by side (PartRig) and `_tick_gait` swings each leg
## with its boot about the hip, the two in opposition, at a cadence that
## follows ground speed; they come back under it when it stands.

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
var _rifle: AimedPart

const LEGS := "Object_8"     ## both trouser legs, one mesh
const BOOTS := "Object_13"   ## the chest plate and both boots, one mesh
const BOOT_TOP := 0.5        ## body-frame y below which that mesh is boot and ankle (its faces sit at 0-0.4 and 1.4-1.6)
const STRIDE := 1.3          ## m of ground per gait cycle
const SWING := 0.42          ## rad each leg swings either side at full speed
var _legs: Array = []        ## {entries, pivot, offset}
var _gait_tried := false
var _gait_phase := 0.0
var _gait_amp := 0.0

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
		_tick_gait(delta)
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
	var parts: Array = []
	for n in RIFLE_PARTS:
		var mi := find_child(n, true, false) as MeshInstance3D
		if mi:
			parts.append(PartRig.entry(self, mi))
	var g := PartRig.mean(PartRig.body_points(self, grip))
	_rifle = AimedPart.new(parts, g, AimedPart.far_mean(PartRig.body_points(self, tube), g, 0.03), AIM_RATE)

## Shoulder the rifle onto the target while engaged (port arms otherwise);
## the muzzle rides the barrel's tip.
func _tick_rifle(delta: float) -> void:
	if _rifle == null:
		_setup_rifle()
		return
	var live := target != null and is_instance_valid(target)
	var engaged := live and state in [State.CHASE, State.ATTACK]
	var at: Variant = target.global_position + Vector3.UP * 0.6 if live else null
	var tip := _rifle.tick(self, at, engaged, delta)
	if muzzle:
		muzzle.global_position = tip

## Cut the legs and the boots by side and find each hip (the top band of the
## trouser leg), once RobotModel's fit has landed.
func _setup_gait() -> void:
	var legs := find_child(LEGS, true, false) as MeshInstance3D
	var boots := find_child(BOOTS, true, false) as MeshInstance3D
	if legs == null or boots == null or not legs.is_visible_in_tree():
		return
	_gait_tried = true # one attempt: a failed cut keeps the legs as they are
	var halves := PartRig.split_x(self, legs, 0.0)
	if halves[0] == null:
		return
	var boot_parts := PartRig.split_groups(self, boots,
		func(c: Vector3) -> int: return 2 if c.y > BOOT_TOP else (1 if c.x > 0.0 else 0),
		["_BootL", "_BootR", "_Plate"])
	for side in 2:
		var hip := AimedPart.band_mean(PartRig.body_points(self, halves[side][0]), Vector3.UP, 0.06)
		var entries: Array = [halves[side]]
		if boot_parts[side] != null:
			entries.append(boot_parts[side])
		_legs.append({"entries": entries, "pivot": hip, "offset": 0.0 if side == 0 else PI})

## Swing each leg about its hip: cadence from ground speed, the two legs in
## opposition, back under it at rest.
func _tick_gait(delta: float) -> void:
	if not _gait_tried:
		_setup_gait()
		return
	if _legs.is_empty():
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_gait_phase = fposmod(_gait_phase + delta * speed / STRIDE * TAU, TAU)
	# A deadband under the creep a nav agent or a shove leaves on a standing
	# unit (about 0.05 m/s), or the legs twitch while it holds its ground.
	_gait_amp = move_toward(_gait_amp, SWING * clampf((speed - 0.25) / maxf(move_speed - 0.25, 0.1), 0.0, 1.0), delta * 3.0)
	for leg in _legs:
		var lay := PartRig.turn(leg["pivot"], Vector3.RIGHT, sin(_gait_phase + float(leg["offset"])) * _gait_amp)
		for e in leg["entries"]:
			PartRig.pose(e, lay)
