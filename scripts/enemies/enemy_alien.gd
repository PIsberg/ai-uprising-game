class_name EnemyAlien
extends EnemyBase
## An organic flying alien — the machines' off-world allies. It no longer rams:
## it swoops to mid-range and strafes, rears back with a glowing throat, then
## VOMITS a fan of corrosive bio-plasma orbs at the player — and every few
## seconds screams into a close dive for a wider burst before peeling off. A
## ranged aerial threat you have to juke, not just back-pedal from. Visuals are
## an imported animated creature (RobotModel on $Model: Idle/Run/Attack clips);
## the throat-sac glow telegraphs each spit.

@export var intercept_height: float = 2.2 ## Hovers about the player's head height.
@export var strafe_speed: float = 3.4
@export var spit_damage: float = 11.0
@export var spit_speed: float = 30.0
@export var spit_orbs: int = 3
@export var charge_time: float = 0.45 ## Throat windup before a volley (the dodge tell).

const BIO_SPIT := preload("res://scenes/weapons/bio_spit.tscn")

var _peel: float = 0.0          ## While >0, peeling up-and-back after a dive pass.
var _charge: float = 0.0
var _charging: bool = false
var _dive: bool = false
var _dive_t: float = 0.0
var _dive_cd: float = 4.0
var _strafe_dir: float = 1.0
var _strafe_t: float = 0.0
var _hover: float = 0.0

var _mouth: Node3D
var _throat: MeshInstance3D
var _throat_mat: StandardMaterial3D
var _throat_light: OmniLight3D

func _ready() -> void:
	max_health = 80.0
	move_speed = 8.5
	turn_speed = 9.0
	sight_range = 46.0
	sight_angle_deg = 300.0
	attack_range = 30.0
	preferred_range = 14.0
	attack_cooldown = 2.0
	score_value = 160
	stagger_threshold = 60.0
	super._ready()
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_hover = randf() * TAU
	_dive_cd = randf_range(3.0, 5.0)
	_build_throat()

## A bio-luminescent throat sac at the mouth that swells and flares green as the
## alien charges a spit — the player's cue to start dodging.
func _build_throat() -> void:
	_mouth = Node3D.new()
	_mouth.position = Vector3(0, 0.2, -0.6) # model faces -Z
	add_child(_mouth)
	_throat = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	_throat_mat = StandardMaterial3D.new()
	_throat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_throat_mat.emission_enabled = true
	_throat_mat.albedo_color = Color(0.6, 1.0, 0.4)
	_throat_mat.emission = Color(0.5, 1.0, 0.3)
	_throat_mat.emission_energy_multiplier = 2.0
	sm.material = _throat_mat
	_throat.mesh = sm
	_throat.scale = Vector3.ONE * 0.3
	_throat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mouth.add_child(_throat)
	_throat_light = OmniLight3D.new()
	_throat_light.light_color = Color(0.5, 1.0, 0.4)
	_throat_light.light_energy = 0.0
	_throat_light.omni_range = 4.0
	_throat_light.shadow_enabled = false
	_mouth.add_child(_throat_light)

func _apply_gravity(_delta: float) -> void:
	pass # it flies

func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	if _can_see(target) and global_position.distance_to(target.global_position) <= attack_range:
		set_state(State.ATTACK)
		return
	_fly_to(target.global_position, delta, 1.0)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.0, 2.4)
		_strafe_dir = -_strafe_dir
	_update_dive(delta)

	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dirn := to.normalized() if to.length() > 0.01 else -global_transform.basis.z
	var fwd := 0.0
	if dist > preferred_range * 1.15:
		fwd = 1.0
	elif dist < preferred_range * 0.8:
		fwd = -1.0
	var strafe := strafe_speed
	var fly_h := intercept_height
	if _dive:
		fwd = 1.6          # commit to the screaming dive
		strafe *= 0.3
		fly_h = 1.2
	if _peel > 0.0:
		fwd = -1.3         # break off, up and away
		fly_h = intercept_height + 2.2
	var right := dirn.cross(Vector3.UP)
	var rush := move_speed * (1.5 if _dive else 0.8)
	var mv := right * _strafe_dir * strafe + dirn * fwd * rush
	velocity.x = move_toward(velocity.x, mv.x, 16.0 * delta)
	velocity.z = move_toward(velocity.z, mv.z, 16.0 * delta)
	_hover += delta * 2.2
	var ty: float = target.global_position.y + fly_h + sin(_hover) * 0.25
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 30.0 * delta)

	if _attack_timer <= 0.0 and _peel <= 0.0 and not _charging:
		_begin_spit()
		_attack_timer = attack_interval()

func _fly_to(dest: Vector3, delta: float, spd_mult: float) -> void:
	var ty: float = (target.global_position.y if target else dest.y) + intercept_height
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		var d := flat.normalized()
		var spd := chase_speed() * spd_mult
		velocity.x = move_toward(velocity.x, d.x * spd, 16.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * spd, 16.0 * delta)
		_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 30.0 * delta)

## Periodic screaming dive: rush the player, spit a wider burst point-blank, peel.
func _update_dive(delta: float) -> void:
	_dive_cd -= delta
	if not _dive and _dive_cd <= 0.0 and _peel <= 0.0:
		_dive = true
		_dive_t = 0.85
		AudioBus.play_synth_at("drone_hum", global_position, 2.0, 0.55) # shriek
		_speak("atk", 0.3)
	if _dive:
		_dive_t -= delta
		if _dive_t <= 0.0:
			_dive = false
			_dive_cd = randf_range(4.0, 7.0)
			_peel = 0.6

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_peel = maxf(0.0, _peel - delta)
	super._physics_process(delta)
	# Throat telegraph swells through the windup, then fires the volley.
	if _charging:
		_charge -= delta
		var k := clampf(1.0 - _charge / charge_time, 0.0, 1.0)
		if _throat:
			_throat.scale = Vector3.ONE * (0.3 + k * 1.2)
		if _throat_mat:
			_throat_mat.emission_energy_multiplier = 2.0 + k * 9.0
		if _throat_light:
			_throat_light.light_energy = k * 4.5
		if _charge <= 0.0:
			_charging = false
			_spit()
	else:
		if _throat:
			_throat.scale = _throat.scale.move_toward(Vector3.ONE * 0.3, delta * 3.0)
		if _throat_mat:
			_throat_mat.emission_energy_multiplier = move_toward(_throat_mat.emission_energy_multiplier, 2.0, delta * 24.0)
		if _throat_light:
			_throat_light.light_energy = move_toward(_throat_light.light_energy, 0.0, delta * 14.0)

func _begin_spit() -> void:
	_charging = true
	_charge = charge_time
	recoil = 1.0 # plays the Attack clip via RobotModel
	AudioBus.play_synth_at("drone_hum", global_position, -5.0, 1.6) # rising throat hiss

## Vomit a fanned volley of corrosive orbs at the player (wider on a dive pass).
func _spit() -> void:
	if target == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = _mouth.global_position if _mouth else global_position
	var n := spit_orbs + (2 if _dive else 0)
	var base := target.global_position + Vector3.UP * 0.5 - origin
	if base.length() < 0.01:
		base = -global_transform.basis.z
	base = base.normalized()
	for i in n:
		var orb := BIO_SPIT.instantiate()
		scene.add_child(orb)
		(orb as Node3D).global_position = origin
		var spread := deg_to_rad((float(i) - float(n - 1) * 0.5) * 7.0)
		var dir := base.rotated(Vector3.UP, spread)
		dir = scatter_aim(dir, 2.0)
		if orb.has_method("launch"):
			orb.launch(dir * spit_speed, self, spit_damage, 0.0, 0.0)
	AudioBus.play_synth_at("acid_spit", origin, -1.0, randf_range(0.95, 1.08))
	if _dive:
		_peel = 0.6
