class_name EnemyRaptor
extends EnemyBase
## RAPTOR — a flying heavy gunner (Quaternius "Robot Enemy Flying Gun"). It hovers
## at mid-range, strafes to stay a hard target, and rakes the player with bolt
## bursts. Tougher and higher-flying than the recon drone — shoot it out of the
## air. RobotModel on $Model drives its clips; killed, it tumbles and bursts.
##
## The model is the Blender fork quaternius_flyergun_strike.glb (swept wings, twin engine
## nacelles, V tail, beak, belly gun pod, talons; tools/blender/cfg_flyergun_strike.json),
## and it flies like what it now looks like: the nose follows the flight path, the
## thrusters vector from hover to run, and the strafing run is a bird of prey's stoop.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

@export var hover_height: float = 4.2
@export var strafe_speed: float = 4.2
@export var proj_speed: float = 40.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 4
@export var burst_interval: float = 0.12

## STRAFING RUN: on a cooldown the raptor stops hovering and commits — a fast,
## straight stoop through the point the player stood on when it committed. It dives
## from hover altitude raking belly-gun bolts ahead of itself, drags its talons through
## the low point, then pulls up and climbs out with its guns quiet. The committed line
## is also its weakness: mid-run it cannot adjust course, so stepping off the line
## dodges both the bolts and the talons.
@export var run_cooldown: float = 7.5
@export var run_speed: float = 16.0
@export var run_low: float = 1.6      ## Height over the aim point at the bottom of the stoop.
@export var rake_damage: float = 14.0
@export var rake_reach: float = 2.6   ## 3D distance at which the talons connect.

var _run_t: float = 0.0
var _run_dir: Vector3 = Vector3.ZERO
var _run_cd: float = 0.0
var _run_fire_t: float = 0.0
var _run_aim: Vector3 = Vector3.ZERO ## Where the player stood at commit; the stoop bottoms out here.
var _run_shots: int = 0              ## Bolts fired on the current/last run (probe hook).
var _raked: bool = false
var _rake_hits: int = 0              ## Talon hits landed, lifetime (probe hook).
var _pitch: float = 0.0
var _thrusters: Array[CPUParticles3D] = []
var _thrust: Vector3 = Vector3.DOWN

var _hover: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_t: float = 0.0
var _burst_left: int = 0
var _burst_t: float = 0.0
var _dying: bool = false
var _fall_time: float = 0.0

@onready var _eye_light: OmniLight3D = $EyeLight
@onready var _belly_muzzle: Node3D = get_node_or_null("BellyMuzzle")

func _ready() -> void:
	super._ready()
	max_health = 95.0
	move_speed = 7.0
	turn_speed = 8.0
	sight_range = 48.0
	sight_angle_deg = 300.0
	attack_range = 36.0
	preferred_range = 18.0
	attack_cooldown = 1.9
	score_value = 185
	head_radius = 0.3
	flinch_knockback = 1.0
	hp.max_health = max_health
	hp.current_health = max_health
	_hover = randf() * TAU
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_run_cd = randf_range(3.0, 6.0) # stagger a flight's first passes
	_make_thrusters()

## Twin glowing thruster jets at the engine nozzles — a streaming exhaust trail that
## sells the hover and reads as a live engine as it banks around. They vector: straight
## down to hold the hover, swung aft and run hard on a stoop (_update_thrusters).
func _make_thrusters() -> void:
	for sx in [-0.44, 0.44]:
		var p := CPUParticles3D.new()
		p.amount = 14
		p.lifetime = 0.45
		p.local_coords = false
		p.direction = Vector3(0, -1, 0)
		p.spread = 14.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.4
		p.gravity = Vector3.ZERO
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0)); curve.add_point(Vector2(1.0, 0.0))
		p.scale_amount_curve = curve
		p.scale_amount_min = 0.5; p.scale_amount_max = 1.0
		var mesh := SphereMesh.new()
		mesh.radius = 0.05; mesh.height = 0.1; mesh.radial_segments = 6; mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.7, 0.3, 0.55)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.55, 0.2)
		mat.emission_energy_multiplier = 4.0
		mesh.material = mat
		p.mesh = mesh
		add_child(p)
		p.position = Vector3(sx, 0.0, 1.1) # nozzle tips of the fork's nacelles
		_thrusters.append(p)

## Thrust direction in the raptor's own frame (probe hook: tests/raptor_stoop_probe).
func thrust_dir() -> Vector3:
	return _thrust

func _update_thrusters(delta: float) -> void:
	var running := _run_t > 0.0 and state != State.DEAD
	var want := Vector3(0.0, -0.2, 1.0).normalized() if running else Vector3.DOWN
	_thrust = _thrust.lerp(want, clampf(10.0 * delta, 0.0, 1.0)).normalized()
	for p in _thrusters:
		p.direction = _thrust
		p.initial_velocity_min = 3.5 if running else 0.6
		p.initial_velocity_max = 6.0 if running else 1.4
		p.scale_amount_max = 1.8 if running else 1.0

## Nose follows the flight path: down in the dive, up in the climb-out, level in the
## hover. Added on top of the hit-react rotation the base writes every tick.
func _update_pitch(delta: float) -> void:
	var want := 0.0
	var flat := Vector2(velocity.x, velocity.z).length()
	if flat > 4.0:
		want = clampf(atan2(velocity.y, flat), -0.6, 0.6)
	_pitch = lerpf(_pitch, want, clampf(9.0 * delta, 0.0, 1.0))
	if _visual_root:
		_visual_root.rotation.x += _pitch

func _apply_gravity(_delta: float) -> void:
	pass # it flies (until it dies)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		_eye_light.light_energy = 1.2 + recoil * 2.2 + (1.5 if is_enraged() else 0.0)
	_update_thrusters(delta)

func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	if _can_see(target) and global_position.distance_to(target.global_position) <= attack_range:
		set_state(State.ATTACK)
		return
	_fly_to(target.global_position, delta)

func _state_attack(delta: float) -> void:
	if target == null:
		set_state(State.CHASE)
		return
	# A committed run rides through LOS breaks — it's flying a straight pass,
	# not tracking, so a pillar flashing by must not abort it into CHASE.
	if _run_t > 0.0:
		_strafing_run(delta)
		return
	if not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	_run_cd -= delta
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(1.2, 2.6)
		_strafe_dir = -_strafe_dir
	var to := target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	var dirn := to.normalized() if to.length() > 0.01 else -global_transform.basis.z
	# Commit a strafing run: far enough out for a real pass, guns idle.
	if _run_cd <= 0.0 and dist > 10.0 and _burst_left <= 0 \
			and not GameState.attack_grace_active():
		_run_dir = dirn
		_run_aim = target.global_position
		_run_t = dist / run_speed + 0.9 # reach the aim point, then 0.9 s of climb-out
		_run_fire_t = 0.25 # first bolt lands as the pass crosses toward you
		_run_shots = 0
		_raked = false
		AudioBus.play_synth_at("charge", global_position, -8.0, 1.6) # dive whine
		return
	var fwd := 0.0
	if dist > preferred_range * 1.15:
		fwd = 1.0
	elif dist < preferred_range * 0.85:
		fwd = -1.0
	var right := dirn.cross(Vector3.UP)
	var mv := right * _strafe_dir * strafe_speed + dirn * fwd * move_speed * 0.8
	velocity.x = move_toward(velocity.x, mv.x, 14.0 * delta)
	velocity.z = move_toward(velocity.z, mv.z, 14.0 * delta)
	_hover += delta * 2.0
	var ty: float = target.global_position.y + hover_height + sin(_hover) * 0.3
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 4.0, 30.0 * delta)
	if _attack_timer <= 0.0 and _burst_left <= 0 and not GameState.attack_grace_active():
		_burst_left = burst_count
		_burst_t = 0.0
		_attack_timer = attack_interval()

## The committed pass, flown as a stoop along the locked line: dive from hover altitude
## to talon height over the aim point, raking angled-down belly-gun bolts ahead of it on
## a fixed cadence (the impacts paint a walking line — you dodge the LINE, not aimed
## fire), rake the talons through the bottom, then climb out with the guns quiet.
func _strafing_run(delta: float) -> void:
	_run_t -= delta
	velocity.x = _run_dir.x * run_speed
	velocity.z = _run_dir.z * run_speed
	# Signed distance still to fly to the aim point: > 0 approaching, < 0 climbing out.
	var ahead := (_run_aim - global_position).dot(_run_dir)
	var ease := smoothstep(0.0, 9.0 if ahead > 0.0 else 6.0, absf(ahead))
	var ty: float = _run_aim.y + lerpf(run_low, hover_height, ease)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 5.0, 40.0 * delta)
	_face_dir(_run_dir, delta)
	_run_fire_t -= delta
	var gun: Node3D = _belly_muzzle if _belly_muzzle else muzzle
	if _run_fire_t <= 0.0 and gun and ahead > 2.0:
		_run_fire_t = 0.11
		var scene := get_tree().current_scene
		if scene:
			var proj := PROJECTILE.instantiate()
			scene.add_child(proj)
			(proj as Node3D).global_position = gun.global_position
			var dir := scatter_aim((_run_dir + Vector3.DOWN * 0.85).normalized(), 4.0)
			if proj.has_method("launch"):
				proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
			recoil = 1.0
			_run_shots += 1
			gun.add_child(MUZZLE_FLASH.instantiate())
			AudioBus.play_synth_at("drone_shot", gun.global_position, -6.0, 1.15)
	_try_rake()
	if _run_t <= 0.0:
		_run_cd = run_cooldown # pass complete — peel back to the hover fight

## Talons: once per run, whoever is still standing on the line at the bottom gets raked.
func _try_rake() -> void:
	if _raked or target == null or not is_instance_valid(target) or GameState.attack_grace_active():
		return
	if global_position.distance_to(target.global_position) > rake_reach:
		return
	_raked = true
	var d = target.get_node_or_null("Damageable")
	if d:
		d.apply_damage(rake_damage, self)
		_rake_hits += 1
	var robot_model := _visual_root as RobotModel
	if robot_model:
		robot_model.play_named("CharacterArmature|Attack", 0.08)
	AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.35)

func _fly_to(dest: Vector3, delta: float) -> void:
	var ty: float = (target.global_position.y if target else dest.y) + hover_height
	var to := Vector3(dest.x, ty, dest.z) - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.05:
		var d := flat.normalized()
		var spd := chase_speed()
		velocity.x = move_toward(velocity.x, d.x * spd, 14.0 * delta)
		velocity.z = move_toward(velocity.z, d.z * spd, 14.0 * delta)
		_face_dir(d, delta)
	velocity.y = move_toward(velocity.y, (ty - global_position.y) * 4.0, 30.0 * delta)

func _physics_process(delta: float) -> void:
	if _dying:
		_fall_dead(delta)
		return
	super._physics_process(delta)
	_update_pitch(delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = burst_interval

func _fire_one() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	_bark_attack()
	var scene := get_tree().current_scene
	if scene == null:
		return
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.5 - muzzle.global_position).normalized()
	dir = scatter_aim(dir, 3.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -4.0, randf_range(0.95, 1.08))

## Killed: lose lift, tumble down, and burst on impact.
func _on_died(_source: Node) -> void:
	if _dying:
		return
	_dying = true
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	collision_layer = 0
	collision_mask = 1
	## Disintegrated: burns away in the air, no fall. Electrocuted: hangs and
	## spasms, then loses lift as usual. Otherwise it tumbles down and bursts.
	var style := _kill_style()
	if style == KillFx.NONE or style == KillFx.DECAPITATE: # all head: nothing to sever
		_start_fall()
		return
	_prep_kill_fx()
	if style == KillFx.SHRED: # knocked out of the air along the shot
		_start_fall()
		_shred_kick(_source)
		return
	_dying = false # hold position: no fall while the style plays
	set_physics_process(false)
	if style == KillFx.DISINTEGRATE:
		collision_mask = 0
		if _damaged_emitter and is_instance_valid(_damaged_emitter):
			_damaged_emitter.queue_free()
		KillFx.disintegrate(self)
	else:
		KillFx.electrocute(self, _start_fall)

func _start_fall() -> void:
	_dying = true
	set_physics_process(true)
	velocity += Vector3(randf_range(-2, 2), 1.5, randf_range(-2, 2))
	if _damaged_emitter == null or not is_instance_valid(_damaged_emitter):
		_damaged_emitter = DAMAGED_FX.instantiate()
		add_child(_damaged_emitter)

func _fall_dead(delta: float) -> void:
	velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta
	velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
	rotation.x += delta * 4.0
	rotation.z += delta * 5.5
	move_and_slide()
	_fall_time += delta
	if is_on_floor() or _fall_time > 4.0:
		var fx := EXPLOSION.instantiate()
		get_parent().add_child(fx)
		(fx as Node3D).global_position = global_position
		AudioBus.play_synth_at("explosion", global_position, 0.0, 1.1)
		queue_free()
