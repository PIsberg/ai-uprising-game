class_name EnemyHowitzer
extends EnemyBase
## HOWITZER — a four-legged artillery walker (assets/models/robots/
## walking_robot_gun.glb): a long-barrelled cannon slung over four bladed
## crab-legs, antennae whipping. It stalks the long sightlines, PLANTS, charges
## with a rising whine, and sends a heavy ballistic shell arcing at you —
## the impact throws splash you have to respect even behind thin cover. Slow,
## armoured, and blind up close: get under its barrel and stay there.
## The barrel is its own node in the model (Gun), so it moves like artillery:
## it lays to the ballistic solve while the walker aims (dipping at a close
## target, lofting at a far one), slides back on the shot and runs out again,
## and the shell leaves from its front end as drawn. tests/howitzer_barrel_probe.
## It walks on its four crab legs: the GLB has them in one mesh (Legs), so
## `_setup_gait` cuts it into four (PartRig, left/right then front/back) and
## each leg swings about its hip in a slow trot, diagonal pairs together, the
## swinging leg lifted a little outward. tests/howitzer_gait_probe.

const SHELL := preload("res://scenes/weapons/projectile_howitzer.tscn")

@export var shell_damage: float = 40.0
@export var splash_radius: float = 4.5
@export var splash_damage: float = 26.0
@export var shell_speed: float = 32.0
@export var windup: float = 0.9

var _winding: bool = false
var _windup_t: float = 0.0

# Barrel laying. Measured off walking_robot_gun.glb at fit_height 4.3: the
# barrel runs z -1.92 (muzzle) to +1.65 (breech) at y 2.87, nose 1.1 deg down,
# over a body spanning z -0.27..1.56; the trunnion sits over the body.
const GUN_PIVOT := Vector3(0.0, 2.87, 0.4)  ## body frame
const GUN_REST_PITCH := -0.019              ## rad, the barrel's own droop
const ELEV_MIN := -0.21                     ## rad (-12 deg)
const ELEV_MAX := 0.35                      ## rad (+20 deg): steeper buries the breech
const ELEV_RATE := 0.4                      ## rad/s: a heavy gun lays slowly
const KICK := 0.5                           ## m the barrel slides back on the shot
const RUN_OUT := 0.9                        ## s to run back out
static var _shell_gs: float = -1.0          ## the shell's gravity_scale, read once
var _gun: Node3D
var _gun_rest: Transform3D                  ## Gun's own transform as imported
var _to_parent: Transform3D                 ## body frame -> Gun's parent frame
var _muzzle_on_gun: Vector3                 ## Muzzle in Gun's frame
var elevation: float = 0.0                  ## rad above the barrel's rest lay

# Walking. The legs mesh and the gap between its front and back pairs (body
# frame z, at fit_height 4.3: front legs end at 0.26, back ones start at 0.44).
const LEGS := "Legs_Legs_0"
const LEGS_SPLIT_Z := 0.35
const STRIDE := 1.6     ## m of ground per gait cycle
const SWING := 0.22     ## rad each leg swings either side at a walk
const LIFT := 0.1       ## rad a swinging leg rolls outward (lifts)
var _legs: Array = []   ## {entries, hip, offset, side}
var _gait_ready := false
var _gait_phase := 0.0
var _gait_amp := 0.0
var _kick: float = 0.0                      ## m of recoil still to run out

func _ready() -> void:
	super._ready()
	max_health = 640.0
	move_speed = 2.6
	turn_speed = 2.2
	sight_range = 60.0
	sight_angle_deg = 200.0
	attack_range = 55.0
	preferred_range = 32.0     # artillery keeps its distance
	attack_cooldown = 5.0
	telegraph_time = 0.0       # the audible spin-up IS the telegraph
	score_value = 500
	head_radius = 0.45
	stagger_threshold = 400.0  # a gun carriage doesn't flinch
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0
	# The GLB's Cell_Cell_0 / _001 are a dark full-size duplicate of the whole
	# model (76k vertices, drawn coincident with it, barely visible). Hidden:
	# they hold a copy of the barrel that stays put when the real one lays.
	for n in ["Cell_Cell_0", "Cell_Cell_0_001"]:
		var dup := find_child(n, true, false) as MeshInstance3D
		if dup:
			dup.visible = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_lay_gun(delta)
	_tick_gait(delta)
	if _winding:
		_windup_t -= delta
		if _windup_t <= 0.0:
			_winding = false
			_fire_shell()

## A committed gun carriage: plants dead-still through the charge and the shot.
func _move_toward(dest: Vector3, delta: float) -> void:
	if _winding:
		_decelerate()
		_face_target(delta)
		return
	super._move_toward(dest, delta)

func _perform_attack() -> void:
	if target == null or _winding:
		return
	_winding = true
	_windup_t = windup
	AudioBus.play_synth_at("charge", global_position, 0.0, 0.55)  # deep breech whine
	_speak("atk", 0.4)

func _fire_shell() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var proj := SHELL.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	# Ballistic solve: lead the runner, then hold the barrel high enough that
	# the shell's gravity drop lands the arc on them. Must use the PROJECT's
	# actual gravity (24.0, see project.godot), not a bare 9.8 — the shell
	# itself falls under ProjectSettings physics/3d/default_gravity *
	# gravity_scale (projectile.gd _physics_process), and a stale 9.8 here
	# under-lofts the shot by 2.45x, so every shell undershot and hit the
	# floor well short of the target instead of reaching it.
	var dir := _ballistic_dir()
	if proj.has_method("launch"):
		proj.launch(dir * shell_speed, self, shell_damage, splash_radius, splash_damage)
	recoil = 1.0
	_kick = KICK
	_muzzle_flash()
	AudioBus.play_synth_at("explosion", muzzle.global_position, -4.0, 1.6)  # sharp muzzle report
	AudioBus.play_synth_at("mech_step", global_position, 0.0, 0.45)         # carriage rocks back

## Launch direction that lands the shell on the target: lead the runner, then
## loft the aim by the shell's gravity drop over its flight time.
func _ballistic_dir() -> Vector3:
	var aim: Vector3 = target.global_position + Vector3.UP * 0.4
	if "velocity" in target:
		aim += (target.velocity as Vector3) * 0.35
	var t := muzzle.global_position.distance_to(aim) / shell_speed
	if _shell_gs < 0.0:
		var probe := SHELL.instantiate()
		_shell_gs = float(probe.get("gravity_scale")) if probe.get("gravity_scale") != null else 0.3
		probe.free()
	var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	aim += Vector3.UP * (0.5 * g * _shell_gs * t * t)
	return (aim - muzzle.global_position).normalized()

## Lay the barrel on the solve while there is a target to shoot, back to rest
## otherwise, and run out the recoil; the muzzle rides the barrel's front.
func _lay_gun(delta: float) -> void:
	if state == State.DEAD or muzzle == null:
		return
	if _gun == null:
		var gun := find_child("Gun", true, false) as Node3D
		# RobotModel fits the mesh deferred and hides it until then: measure the
		# frames below only once the fit has landed.
		if gun == null or not gun.is_visible_in_tree():
			return
		_gun = gun
		_gun_rest = _gun.transform
		_to_parent = _gun.get_parent().global_transform.affine_inverse() * global_transform
		_muzzle_on_gun = _gun.global_transform.affine_inverse() * muzzle.global_position
	var want := 0.0
	if target != null and is_instance_valid(target) and (state == State.ATTACK or _winding):
		want = clampf(asin(clampf(_ballistic_dir().y, -1.0, 1.0)) - GUN_REST_PITCH, ELEV_MIN, ELEV_MAX)
	elevation = move_toward(elevation, want, ELEV_RATE * delta)
	_kick = move_toward(_kick, 0.0, KICK / RUN_OUT * delta)
	# Pitch about the trunnion (+X raises the muzzle, forward is -Z), then slide
	# back along the laid barrel; built in the body frame, applied in the Gun's.
	var r := Basis(Vector3.RIGHT, elevation)
	var lay := Transform3D(r, GUN_PIVOT - r * GUN_PIVOT + r * Vector3(0.0, 0.0, _kick))
	_gun.transform = _to_parent * lay * _to_parent.affine_inverse() * _gun_rest
	muzzle.global_position = _gun.global_transform * _muzzle_on_gun

## Cut the legs mesh into four and find each hip (its top band), once the fit
## has landed.
func _setup_gait() -> void:
	var mi := find_child(LEGS, true, false) as MeshInstance3D
	if mi == null or not mi.is_visible_in_tree():
		return
	_gait_ready = true # one attempt: a failed split keeps the legs as they are
	# Four legs in one pass: left/right of x = 0, front/back of LEGS_SPLIT_Z.
	var quarters := PartRig.split_groups(self, mi,
		func(c: Vector3) -> int: return (1 if c.x > 0.0 else 0) * 2 + (1 if c.z > LEGS_SPLIT_Z else 0),
		["_L_F", "_L_B", "_R_F", "_R_B"])
	for g in 4:
		if quarters[g] == null:
			return
		var side := g / 2
		var end := g % 2
		var pts := PartRig.body_points(self, quarters[g][0])
		var hip := AimedPart.band_mean(pts, Vector3.UP, 0.08)
		# Trot: front-left with back-right, front-right with back-left.
		var offset := 0.0 if (side == 0) == (end == 0) else PI
		_legs.append({"entries": [quarters[g]], "hip": hip, "offset": offset, "side": -1.0 if side == 0 else 1.0})

## A slow trot whose cadence follows ground speed; the legs come back under the
## body when it stops (and while it plants to fire).
func _tick_gait(delta: float) -> void:
	if not _gait_ready:
		_setup_gait()
		return
	if _legs.is_empty() or state == State.DEAD:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_gait_phase = fposmod(_gait_phase + delta * speed / STRIDE * TAU, TAU)
	_gait_amp = move_toward(_gait_amp, clampf(speed / 2.0, 0.0, 1.0), delta * 2.0)
	for leg in _legs:
		var ph := _gait_phase + float(leg["offset"])
		var swing := sin(ph) * SWING * _gait_amp
		var lift := maxf(cos(ph), 0.0) * LIFT * _gait_amp * float(leg["side"])
		var r := Basis(Vector3.RIGHT, swing) * Basis(Vector3.BACK, lift)
		var hip: Vector3 = leg["hip"]
		var lay := Transform3D(r, hip - r * hip)
		for e in leg["entries"]:
			PartRig.pose(e, lay)
