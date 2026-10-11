class_name EnemyMech
extends EnemyBase
## Stilt mech (Quaternius "Stan": a lean frame on two spike stilts, an open
## right hand, no launcher anywhere). It fights the way it is built:
## - lopes on the Run clip and circle-strafes at range, light on its feet;
## - fires short bolt bursts from its raised right palm (the Shoot clip's hand);
## - inside LEAP_RANGE it plants, marks where it will land (a ground warning
##   just short of the player) and springs off its stilts, coming down
##   spike-first: KICK_RADIUS damage + knockback. Dash out of the ring.
## Visuals/animation come from the imported model on $Model (RobotModel blends
## idle<->run and fires the Shoot clip off the recoil spike).

@export var projectile_scene: PackedScene ## Palm bolt (projectile_drone).
@export var projectile_speed: float = 34.0
@export var bolt_damage: float = 10.0
@export var burst_count: int = 3
@export var stomp_damage: float = 25.0 ## The spike landing.

const PALM_BONE := "PalmI.R"
const LEAP_RANGE := 10.0     ## leaps at a target this close (when the leap is ready)
const LEAP_MIN := 2.0        ## lands this far short of the player (on them = under them)
const LEAP_WINDUP := 0.5     ## planted, Jump clip crouching, ring on the floor
const LEAP_TIME := 0.75      ## flight time; apex g*t^2/8, 1.7 m at the project's gravity of 24
const LEAP_RECOVER := 0.45   ## stilts dug in after landing
const LEAP_COOLDOWN := 3.4
const KICK_RADIUS := 2.8

enum Leap { NONE, WINDUP, AIR, RECOVER }
var _leap: int = Leap.NONE
var _leap_t: float = 0.0
var _leap_cd: float = 0.0
var _leap_to: Vector3 = Vector3.ZERO
var _burst_left: int = 0
var _burst_t: float = 0.0
var _dust: CPUParticles3D


func _ready() -> void:
	super._ready()
	max_health = 260.0
	move_speed = 5.4
	turn_speed = 6.0
	sight_range = 30.0
	attack_range = 24.0
	preferred_range = 14.0
	attack_cooldown = 1.9
	score_value = 250
	combat_strafe = true
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 2.0
	flinch_knockback = 2.0 # lean frame: a hit rocks it more than the old heavy chassis
	# The gun is the right palm: bolts (and the muzzle flash) leave the hand
	# the Shoot clip raises.
	muzzle_on_bone(PALM_BONE)
	_make_dust()


## Dust burst where the stilts come down.
func _make_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.amount = 22
	_dust.lifetime = 0.7
	_dust.local_coords = false
	_dust.direction = Vector3(0, 1, 0)
	_dust.spread = 80.0
	_dust.initial_velocity_min = 1.2
	_dust.initial_velocity_max = 3.4
	_dust.gravity = Vector3(0, -3.0, 0)
	var ramp := Curve.new()
	ramp.add_point(Vector2(0.0, 0.5)); ramp.add_point(Vector2(1.0, 1.6))
	_dust.scale_amount_curve = ramp
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	grad.colors = PackedColorArray([Color(0.4, 0.36, 0.3, 0.0), Color(0.42, 0.38, 0.32, 0.45), Color(0.4, 0.36, 0.3, 0.0)])
	_dust.color_ramp = grad
	var sm := SphereMesh.new()
	sm.radius = 0.14; sm.height = 0.28; sm.radial_segments = 6; sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	_dust.mesh = sm
	add_child(_dust)
	_dust.position = Vector3(0, 0.1, 0)


func is_leaping() -> bool:
	return _leap != Leap.NONE


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD:
		return
	_leap_cd = maxf(0.0, _leap_cd - delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_bolt()
			_burst_left -= 1
			_burst_t = 0.13


## A leap in progress owns the body until it has landed and recovered.
func _run_state(delta: float) -> void:
	if _leap == Leap.NONE:
		super._run_state(delta)
	else:
		_leap_tick(delta)


func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	var dist := global_position.distance_to(target.global_position)
	if dist > attack_range * 1.1:
		set_state(State.CHASE)
		return
	if GameState.attack_grace_active():
		_combat_strafe(delta)
		return
	if dist <= LEAP_RANGE and _leap_cd <= 0.0 and is_on_floor():
		_begin_leap()
		return
	if dist > preferred_range * 1.3:
		_move_toward(target.global_position, delta)
	else:
		_combat_strafe(delta)
	if _attack_timer <= 0.0 and _burst_left == 0:
		_burst_left = burst_count
		_burst_t = 0.0
		_attack_timer = attack_interval()
		_bark_attack()


func _begin_leap() -> void:
	_leap = Leap.WINDUP
	_leap_t = 0.0
	_burst_left = 0
	var to := target.global_position - global_position
	to.y = 0.0
	var reach := maxf(0.0, to.length() - LEAP_MIN)
	_leap_to = global_position + to.normalized() * reach
	spawn_ground_warning(_leap_to, KICK_RADIUS, LEAP_WINDUP + LEAP_TIME)
	if _visual_root and _visual_root.has_method("play_oneshot_over"):
		# The clip crouches, springs and lands: stretch it over the whole leap.
		_visual_root.play_oneshot_over("Jump", LEAP_WINDUP + LEAP_TIME + 0.2, 0.1)
	AudioBus.play_synth_at("mech_step", global_position, 1.0, 1.25)


func _leap_tick(delta: float) -> void:
	_leap_t += delta
	match _leap:
		Leap.WINDUP:
			_decelerate()
			if target and is_instance_valid(target):
				_face_target(delta)
			if _leap_t >= LEAP_WINDUP:
				_leap = Leap.AIR
				_leap_t = 0.0
				var g: float = ProjectSettings.get_setting("physics/3d/default_gravity")
				var flat := (_leap_to - global_position) / LEAP_TIME
				velocity = Vector3(flat.x, g * LEAP_TIME * 0.5, flat.z)
		Leap.AIR:
			if _leap_t > 0.12 and is_on_floor():
				_spike_landing()
				_leap = Leap.RECOVER
				_leap_t = 0.0
			elif _leap_t > LEAP_TIME * 3.0: # fell off a ledge; call it a landing
				_leap = Leap.RECOVER
				_leap_t = 0.0
		Leap.RECOVER:
			velocity.x = 0.0
			velocity.z = 0.0
			if _leap_t >= LEAP_RECOVER:
				_leap = Leap.NONE
				_leap_cd = LEAP_COOLDOWN
				_attack_timer = maxf(_attack_timer, 0.6)


## Spikes into the floor: AoE damage + knockback, a hard shake, dust and an
## expanding ring so the landing hits with weight.
func _spike_landing() -> void:
	velocity = Vector3.ZERO
	recoil = 1.0
	AudioBus.play_synth_at("mech_step", global_position, 5.0, 0.55)
	AudioBus.play_synth_at("impact_metal", global_position, 2.0, 0.7)
	if _dust:
		_dust.restart()
	var p := get_tree().get_first_node_in_group("player")
	if p is CharacterBody3D and (p as Node3D).global_position.distance_to(global_position) <= KICK_RADIUS:
		var d := p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(stomp_damage, self)
		if p.has_method("shake"):
			p.shake(0.8)
		var away: Vector3 = (p as Node3D).global_position - global_position
		away.y = 0.0
		if away.length() < 0.1:
			away = -global_transform.basis.z
		p.velocity += away.normalized() * 12.0 + Vector3.UP * 4.0
	spawn_shockwave_ring(KICK_RADIUS, Color(1.0, 0.5, 0.2))


func _fire_bolt() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null or projectile_scene == null:
		return
	recoil = 1.0
	_muzzle_flash()
	var proj := projectile_scene.instantiate()
	get_tree().current_scene.add_child(proj)
	proj.global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.6 - muzzle.global_position).normalized()
	dir = scatter_aim(dir) # difficulty-driven inaccuracy
	if proj.has_method("launch"):
		proj.launch(dir * projectile_speed, self, bolt_damage, 0.0, 0.0)
	AudioBus.play_synth_at("plasma_fire", muzzle.global_position, -1.0, randf_range(1.05, 1.2))
