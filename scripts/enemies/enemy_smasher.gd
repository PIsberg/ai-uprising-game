class_name EnemySmasher
extends EnemyBase
## BEHEMOTH-X — a colossal humanoid war-mech (the poster machine): towering steel
## chassis, heavy pauldrons, a blazing red chest reactor and visor, and two
## oversized fists. Unlike the artillery colossus, this one is a pure MELEE
## SMASHER: it charges the player down, hammers with an overhead fist-smash, and
## ground-slams a shockwave when you crowd it. Bring the boss bar + an entrance.
##
## Visuals: the high-detail "rusty_claws_robot" — a battered, clawed humanoid
## hulk (RobotModel auto-fits it to 10 m on $Model; the model is rig-less, so it
## leans rather than playing clips). The pulsing Reactor weak-point and the red
## visor spotlight are scene markers layered on top.

@export var boss_name: String = "BEHEMOTH-X"   ## Shown on the HUD boss bar.
@export var preview: bool = false ## Codex/briefing showcase: idle on the spot, skip the wake-roar entrance, boss bar + AI.

@export_group("Smash")
@export var smash_damage: float = 40.0
@export var smash_range: float = 9.0      ## Reach of the overhead fist-smash.
@export var smash_arc_deg: float = 70.0   ## Frontal cone the smash sweeps.
@export var smash_cooldown: float = 2.4
@export var smash_windup: float = 0.5

@export_group("Slam")
@export var slam_damage: float = 52.0
@export var slam_radius: float = 10.0
@export var slam_trigger_range: float = 7.0
@export var slam_cooldown: float = 6.0
@export var slam_windup: float = 0.55

@export_group("Charge")
@export var charge_speed: float = 13.0    ## Lunge speed used to close on a distant target.

@onready var _reactor: MeshInstance3D = $Reactor
@onready var _eye_light: SpotLight3D = $Head/Eye/EyeLight
@onready var _head: Node3D = $Head

var _glow_mat: StandardMaterial3D
var _walk_phase: float = 0.0
var _last_phase: int = 1

var _smash_cd: float = 1.0
var _slam_cd: float = 3.0
var _smash_windup_t: float = 0.0
var _slam_windup_t: float = 0.0

# Brief invulnerable "wake" roar before it engages.
var _wake: float = 1.4

func _ready() -> void:
	super._ready()
	max_health = 3600.0
	stagger_threshold = 100000.0  # a behemoth is never stunlocked by small-arms
	move_speed = 3.0
	turn_speed = 2.2
	sight_range = 80.0
	sight_angle_deg = 300.0
	attack_range = 12.0
	preferred_range = 4.0          # it WANTS to be in your face
	attack_cooldown = smash_cooldown
	score_value = 3200
	head_radius = 1.3
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 8.0
	flinch_knockback = 0.0
	if eye == null:
		eye = get_node_or_null("Head/Eye")
	_glow_mat = preload("res://assets/materials/glow_red.tres").duplicate() as StandardMaterial3D
	if _reactor:
		_reactor.material_override = _glow_mat
	_relax_arms()
	# Codex/briefing: idle on the dais — skip the wake-roar entrance + AI.
	if preview:
		_wake = 0.0
		hp.invulnerable = true
		set_physics_process(false)
		return
	hp.invulnerable = true
	_do_entrance.call_deferred()

## Drop the George rig's baked "guard" arms to a natural heavy carry (same nudge
## the colossus uses) so the fists hang ready to swing.
func _relax_arms() -> void:
	var model := get_node_or_null("Model/Mesh")
	if model == null:
		return
	ModelPoser.relax_skeleton_arms(model, [
		{"bone": "UpperArm.L", "euler": Vector3(0, 0, -78)},
		{"bone": "UpperArm.R", "euler": Vector3(0, 0, 78)},
		{"bone": "LowerArm.L", "euler": Vector3(0, 0, 30)},
		{"bone": "LowerArm.R", "euler": Vector3(0, 0, -30)},
	])

func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	AudioBus.play_synth_at("mech_step", global_position, 6.0, 0.4)
	AudioBus.play_synth_at("explosion", global_position, 3.0, 0.5)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.2)

func _phase() -> int:
	var frac := hp.current_health / hp.max_health
	if frac <= 0.33:
		return 3
	elif frac <= 0.66:
		return 2
	return 1

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_walk_phase += delta * (2.0 + speed * 1.0)
	track_node_to_target(_head, delta, 60.0, 24.0, 3.0)
	var rage := 1.0 + float(_phase() - 1) * 0.8
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = (4.0 + sin(_walk_phase * 2.0) * 1.5 + recoil * 7.0 + damage_heat * 6.0 + (5.0 if is_enraged() else 0.0)) * rage
	if _eye_light:
		_eye_light.light_energy = (3.0 + sin(_walk_phase * 2.5) * 1.0 + _wake * 4.0) * rage
	if speed > 0.1 and is_on_floor():
		var fs := sin(_walk_phase)
		var last := sin(_walk_phase - delta * (2.0 + speed))
		if (fs > 0.0) != (last > 0.0):
			AudioBus.play_synth_at("mech_step", global_position, 1.0, randf_range(0.55, 0.7))

func _physics_process(delta: float) -> void:
	if _wake > 0.0:
		_wake -= delta
		velocity.x = move_toward(velocity.x, 0.0, 6.0)
		velocity.z = move_toward(velocity.z, 0.0, 6.0)
		_apply_gravity(delta)
		move_and_slide()
		if _wake <= 0.0:
			hp.invulnerable = false
		return
	# Phase-change punch.
	var ph := _phase()
	if ph != _last_phase:
		_last_phase = ph
		recoil = 1.0
		AudioBus.play_synth_ui("eas_alert", -10.0)
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("shake"):
			pl.shake(0.6)
	_smash_cd = maxf(0.0, _smash_cd - delta)
	_slam_cd = maxf(0.0, _slam_cd - delta)
	# Resolve in-flight windups.
	if _smash_windup_t > 0.0:
		_smash_windup_t -= delta
		_decelerate()
		_face_target(delta)
		if _smash_windup_t <= 0.0:
			_do_smash()
		_apply_gravity(delta)
		move_and_slide()
		return
	if _slam_windup_t > 0.0:
		_slam_windup_t -= delta
		_decelerate()
		if _slam_windup_t <= 0.0:
			_do_slam()
		_apply_gravity(delta)
		move_and_slide()
		return
	super._physics_process(delta)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	var dist := global_position.distance_to(target.global_position)
	# Crowded -> ground slam. In reach -> overhead smash. Otherwise charge in.
	if _slam_cd <= 0.0 and dist <= slam_trigger_range:
		_begin_slam()
		return
	if _smash_cd <= 0.0 and dist <= smash_range:
		_begin_smash()
		return
	if dist > smash_range * 0.85:
		_charge(delta)
	else:
		_decelerate()

## Barrel toward the target at charge speed to close melee distance fast.
func _charge(delta: float) -> void:
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	velocity.x = move_toward(velocity.x, dir.x * charge_speed, 18.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * charge_speed, 18.0 * delta)

# ---------- overhead fist-smash ----------

func _begin_smash() -> void:
	_smash_windup_t = smash_windup
	_smash_cd = smash_cooldown
	recoil = 1.0  # fires the Punch clip via RobotModel
	AudioBus.play_synth_at("charge", global_position, -4.0, 0.7)

func _do_smash() -> void:
	AudioBus.play_synth_at("explosion", global_position, 2.0, 0.7)
	AudioBus.play_synth_at("mech_step", global_position, 3.0, 0.5)
	var fx := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position - global_transform.basis.z * smash_range * 0.5 + Vector3.UP * 0.5
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		return
	# Frontal cone: the player must be ahead and within reach to eat the hammer.
	var to: Vector3 = (p as Node3D).global_position - global_position
	to.y = 0.0
	var fwd := -global_transform.basis.z
	if to.length() <= smash_range and rad_to_deg(fwd.angle_to(to)) <= smash_arc_deg * 0.5:
		var d := p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(smash_damage, self)
		if p.has_method("shake"):
			p.shake(0.9)
		if to.length() > 0.1 and "velocity" in p:
			p.velocity += to.normalized() * 9.0 + Vector3.UP * 3.0  # knock them back

# ---------- ground slam ----------

func _begin_slam() -> void:
	_slam_windup_t = slam_windup
	_slam_cd = slam_cooldown
	recoil = 1.0
	AudioBus.play_synth_at("mech_step", global_position, 3.0, 0.4)
	spawn_ground_warning(global_position, slam_radius, _slam_windup_t)

func _do_slam() -> void:
	AudioBus.play_synth_at("explosion", global_position, 4.0, 0.5)
	var fx := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		return
	if (p as Node3D).global_position.distance_to(global_position) <= slam_radius:
		var d := p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		if p.has_method("shake"):
			p.shake(1.1)

# ---------- death ----------

func _on_died(source: Node) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.5)
	GameState.hit_stop(0.25, 0.5)
	_spawn_death_explosions.call_deferred()
	super._on_died(source)

func _spawn_death_explosions() -> void:
	for i in 6:
		if not is_inside_tree():
			return
		var fx := EXPLOSION.instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(randf_range(-3, 3), randf_range(0.5, 9.0), randf_range(-3, 3))
		AudioBus.play_synth_at("explosion", global_position, 2.0, randf_range(0.5, 0.8))
		await get_tree().create_timer(0.18).timeout
