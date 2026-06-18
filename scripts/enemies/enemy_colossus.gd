class_name EnemyColossus
extends EnemyBase
## Gigantic suburban mega-boss — a ~10 m biped war-machine that towers over the
## houses. Multi-phase: it bombards with shoulder artillery, sweeps a chest beam
## once wounded, and ground-slams a shockwave when enraged or when you get close.
## Uses the HUD boss bar (GameState.announce_boss) and a cinematic entrance.
##
## Visuals are the imported "George" heavy mech (RobotModel on $Model drives the
## walk/shoot clips); the pulsing Reactor weak-point sphere and the eye spotlight
## are scene markers layered on top.

@export var boss_name: String = "GOLIATH-IX"   ## Shown on the HUD boss bar.
@export var rocket_scene: PackedScene
@export var tracer_scene: PackedScene
@export var muzzle_flash_scene: PackedScene

@export_group("Artillery")
@export var rocket_speed: float = 30.0
@export var rocket_damage: float = 20.0
@export var rocket_splash_radius: float = 5.0
@export var rocket_splash_damage: float = 16.0
@export var artillery_cooldown: float = 2.6

@export_group("Beam")
@export var beam_damage_per_tick: float = 15.0
@export var beam_cooldown: float = 6.0
@export var beam_duration: float = 1.5
@export var beam_sweep_deg: float = 28.0

@export_group("Slam")
@export var slam_radius: float = 11.0
@export var slam_damage: float = 38.0
@export var slam_trigger_range: float = 10.0
@export var slam_cooldown: float = 5.5

@onready var _muzzle_l: Node3D = $MuzzleL
@onready var _muzzle_r: Node3D = $MuzzleR
@onready var _muzzle_core: Node3D = $MuzzleCore
@onready var _reactor: MeshInstance3D = $Reactor
@onready var _eye_light: SpotLight3D = $Head/Eye/EyeLight
@onready var _head: Node3D = $Head

## Sky-drop entrance: how far above its mark GOLIATH-IX ignites and falls in on
## retro-rockets before slamming down.
const DROP_HEIGHT := 44.0

var _walk_phase: float = 0.0
var _entrance: float = 0.0
var _descending: bool = false
var _drop_target_y: float = 0.0
var _thrusters: Array[RocketExhaust] = []
var _glow_mat: StandardMaterial3D
var _last_phase: int = 1

# Attack timers.
var _artillery_cd: float = 1.5
var _beam_cd: float = 4.0
var _slam_cd: float = 3.0
var _fire_left_next: bool = false

# Beam sweep state.
var _beam_time: float = 0.0
var _beam_tick: float = 0.0
var _beam_dir0: float = 0.0  # base yaw toward player when the sweep began

# Slam windup state.
var _slam_windup: float = 0.0

func _ready() -> void:
	super._ready()
	max_health = 3200.0
	stagger_threshold = 100000.0 # a colossus shrugs off small-arms; never stunlocked
	move_speed = 2.2
	turn_speed = 1.6
	sight_range = 70.0
	sight_angle_deg = 300.0   # near-omniscient; it dominates the arena
	attack_range = 48.0
	preferred_range = 26.0
	attack_cooldown = artillery_cooldown
	score_value = 3000
	head_radius = 1.2
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 8.0
	flinch_knockback = 0.0     # immovable
	if eye == null:
		eye = get_node_or_null("Head/Eye")
	_glow_mat = preload("res://assets/materials/glow_red.tres").duplicate() as StandardMaterial3D
	if _reactor:
		_reactor.material_override = _glow_mat
	# The George rig bakes the arms into a raised "guard" across every clip; drop
	# the upper arms to a natural carry (no-op on rigless models like the titan).
	_relax_arms()
	# Cinematic sky-drop: GOLIATH-IX makes planetfall on its foot retro-rockets,
	# then slams down. It hangs high and invulnerable until it lands.
	_drop_target_y = global_position.y
	global_position.y += DROP_HEIGHT
	velocity = Vector3.ZERO
	_descending = true
	hp.invulnerable = true
	_spawn_thrusters()
	_do_entrance.call_deferred()

## Drop the George rig's raised "guard" arms to a natural carry. The pose is
## baked into every clip, so an ArmRelaxModifier nudges the upper-arm bones down
## (and slightly straightens the elbows) after each frame's animation. No-op on
## rigless chassis like the titan's, which re-pose their loose parts instead.
func _relax_arms() -> void:
	var model := get_node_or_null("Model/Mesh")
	if model == null:
		return
	ModelPoser.relax_skeleton_arms(model, [
		{"bone": "UpperArm.L", "euler": Vector3(0, 0, -85)},
		{"bone": "UpperArm.R", "euler": Vector3(0, 0, 85)},
		{"bone": "LowerArm.L", "euler": Vector3(0, 0, 25)},
		{"bone": "LowerArm.R", "euler": Vector3(0, 0, -25)},
	])

func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	# A distant boom + dread shake as it ignites and begins its descent.
	AudioBus.play_synth_at("explosion", global_position, 4.0, 0.7)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(0.7)

## Two foot thrusters plus a central booster, blazing straight down.
func _spawn_thrusters() -> void:
	for foot in [Vector3(1.05, 0.6, 0.3), Vector3(-1.05, 0.6, 0.3)]:
		var th := RocketExhaust.new()
		th.flame_length = 6.5
		th.flame_radius = 0.95
		th.position = foot
		add_child(th)
		_thrusters.append(th)
	var core := RocketExhaust.new()
	core.flame_length = 8.0
	core.flame_radius = 1.3
	core.position = Vector3(0, 0.7, -0.2)
	add_child(core)
	_thrusters.append(core)

## Retro-rocket descent: plummet from high up, brake hard over the last metres.
func _process_descent(delta: float) -> void:
	var h := global_position.y - _drop_target_y
	# A controlled retro-burn, not a plummet: steady fall, braking over the deck.
	var desired := -clampf(h * 0.7, 7.0, 22.0)
	if h < 8.0:
		desired = -clampf(h * 1.4 + 1.0, 2.5, 12.0) # flare the burn, settle in
	velocity.y = move_toward(velocity.y, desired, 30.0 * delta)
	velocity.x = 0.0
	velocity.z = 0.0
	recoil = maxf(recoil, 0.35)
	move_and_slide()
	if global_position.y <= _drop_target_y + 0.08 or is_on_floor():
		global_position.y = _drop_target_y
		_land()

## Touchdown: a ground-shaking impact ring, then a brief planted beat before the
## boss engages.
func _land() -> void:
	_descending = false
	velocity = Vector3.ZERO
	_entrance = 0.6
	AudioBus.play_synth_at("explosion", global_position, 8.0, 0.32)
	AudioBus.play_synth_at("mech_step", global_position, 6.0, 0.45)
	GameState.hit_stop(0.12, 0.45)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(2.0)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var fx := EXPLOSION.instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(cos(ang) * 5.0, 0.3, sin(ang) * 5.0)
	for th in _thrusters:
		if is_instance_valid(th):
			th.shut_down()
	_thrusters.clear()

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
	var rate := 2.0 + speed * 1.2
	_walk_phase += delta * rate
	# The stride itself is driven by RobotModel on $Model (idle<->walk clips).
	# The head/eye slowly tracks the player — it watches you across the arena.
	track_node_to_target(_head, delta, 50.0, 22.0, 2.5)
	# Reactor weak-point throbs; brighter as it loses health (overloading).
	var rage := 1.0 + float(_phase() - 1) * 0.8
	if _glow_mat:
		_glow_mat.emission_energy_multiplier = (4.0 + sin(_walk_phase * 2.0) * 1.5 + recoil * 6.0 + damage_heat * 6.0 + (4.0 if is_enraged() else 0.0)) * rage
	if _eye_light:
		_eye_light.light_energy = (3.0 + sin(_walk_phase * 2.5) * 1.0 + _entrance * 5.0) * rage
	# Footfall booms.
	if speed > 0.1 and is_on_floor():
		var fs := sin(_walk_phase)
		var last := sin(_walk_phase - delta * rate)
		if (fs > 0.0) != (last > 0.0):
			AudioBus.play_synth_at("mech_step", global_position, 1.0, randf_range(0.6, 0.75))

func _physics_process(delta: float) -> void:
	if _descending:
		_process_descent(delta)
		return
	if _entrance > 0.0:
		_entrance -= delta
		velocity.x = move_toward(velocity.x, 0.0, 4.0)
		velocity.z = move_toward(velocity.z, 0.0, 4.0)
		_apply_gravity(delta)
		move_and_slide()
		if _entrance <= 0.0:
			hp.invulnerable = false
		return
	super._physics_process(delta)
	# Phase-change punch: brief quake + alarm when crossing a threshold.
	var ph := _phase()
	if ph != _last_phase:
		_last_phase = ph
		recoil = 1.0
		AudioBus.play_synth_ui("eas_alert", -10.0)
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("shake"):
			pl.shake(0.6)
	# Tick cooldowns.
	_artillery_cd = maxf(0.0, _artillery_cd - delta)
	_beam_cd = maxf(0.0, _beam_cd - delta)
	_slam_cd = maxf(0.0, _slam_cd - delta)
	if _beam_time > 0.0:
		_tick_beam(delta)
	if _slam_windup > 0.0:
		_slam_windup -= delta
		if _slam_windup <= 0.0:
			_do_slam()

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	var dist := global_position.distance_to(target.global_position)
	# Lumber to keep the player in its preferred bombardment band.
	if dist > preferred_range * 1.3:
		_move_toward(target.global_position, delta)
	else:
		_decelerate()
	_choose_attack(dist)

func _choose_attack(dist: float) -> void:
	# Mid-action (beam/slam) locks out new attacks.
	if _beam_time > 0.0 or _slam_windup > 0.0:
		return
	# Enraged or cornered -> ground slam.
	if _slam_cd <= 0.0 and (dist <= slam_trigger_range or (_phase() == 3 and dist <= slam_radius * 1.4)):
		_begin_slam()
		return
	# Wounded -> sweeping beam.
	if _phase() >= 2 and _beam_cd <= 0.0:
		_begin_beam()
		return
	# Default -> artillery barrage (volley grows with phase).
	if _artillery_cd <= 0.0:
		_fire_artillery()

# ---------- artillery ----------

func _fire_artillery() -> void:
	if target == null or rocket_scene == null:
		return
	_artillery_cd = maxf(0.9, artillery_cooldown - float(_phase() - 1) * 0.5)
	recoil = 1.0
	var volley := 2 + _phase()  # 3 / 4 / 5 rockets
	var muzzle := _muzzle_l if _fire_left_next else _muzzle_r
	_fire_left_next = not _fire_left_next
	if muzzle == null:
		return
	if muzzle_flash_scene:
		muzzle.add_child(muzzle_flash_scene.instantiate())
	AudioBus.play_synth_at("plasma_fire", muzzle.global_position, 2.0, randf_range(0.55, 0.65))
	var origin := muzzle.global_position
	var aim := target.global_position + Vector3.UP * 0.6
	for i in volley:
		var proj := rocket_scene.instantiate()
		get_tree().current_scene.add_child(proj)
		proj.global_position = origin
		var dir := (aim - origin).normalized()
		dir = scatter_aim(dir, 3.0 + i * 2.0)  # fan the volley + difficulty spread
		if proj.has_method("launch"):
			proj.launch(dir * rocket_speed, self, rocket_damage, rocket_splash_radius, rocket_splash_damage)

# ---------- sweeping beam ----------

func _begin_beam() -> void:
	if target == null:
		return
	_beam_time = beam_duration
	_beam_tick = 0.0
	var to := target.global_position - global_position
	_beam_dir0 = atan2(to.x, to.z)
	AudioBus.play_synth_at("plasma_fire", global_position, 3.0, 0.4)

func _tick_beam(delta: float) -> void:
	_beam_time -= delta
	_beam_cd = beam_cooldown
	recoil = 1.0
	if _muzzle_core == null:
		return
	# Sweep the aim yaw across the arc over the beam's duration.
	var t := 1.0 - clampf(_beam_time / beam_duration, 0.0, 1.0)
	var off := lerpf(-beam_sweep_deg, beam_sweep_deg, t)
	var yaw := _beam_dir0 + deg_to_rad(off)
	var dir := Vector3(sin(yaw), 0.0, cos(yaw))
	if target:
		dir.y = (target.global_position.y + 0.6 - _muzzle_core.global_position.y) / 20.0
	dir = dir.normalized()
	var origin := _muzzle_core.global_position
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 70.0)
	q.collision_mask = 0b0000011
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 70.0
	_beam_tick -= delta
	if not hit.is_empty():
		end_point = hit.position
		if _beam_tick <= 0.0:
			var col: Node = hit.collider
			var d: Node = col.get_node_or_null("Damageable") if col else null
			if d:
				d.apply_damage(beam_damage_per_tick, self)
	if _beam_tick <= 0.0:
		_beam_tick = 0.1
		if tracer_scene:
			var tr := tracer_scene.instantiate()
			get_tree().current_scene.add_child(tr)
			if tr.has_method("setup"):
				tr.setup(origin, end_point)

# ---------- ground slam ----------

func _begin_slam() -> void:
	_slam_windup = 0.5
	_slam_cd = slam_cooldown
	recoil = 1.0
	AudioBus.play_synth_at("mech_step", global_position, 3.0, 0.45)

func _do_slam() -> void:
	AudioBus.play_synth_at("explosion", global_position, 4.0, 0.55)
	var fx := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if (p as Node3D).global_position.distance_to(global_position) <= slam_radius:
		var d := p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		if p.has_method("shake"):
			p.shake(1.0)

# ---------- death ----------

func _on_died(source: Node) -> void:
	# A boss this size goes out loud: a stagger of explosions + a long quake.
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.5)
	GameState.hit_stop(0.25, 0.5) # cinematic slow-mo on the mega-boss kill
	_spawn_death_explosions.call_deferred()
	super._on_died(source)

func _spawn_death_explosions() -> void:
	for i in 6:
		if not is_inside_tree():
			return
		var fx := EXPLOSION.instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = global_position + Vector3(randf_range(-3, 3), randf_range(0.5, 8.0), randf_range(-3, 3))
		AudioBus.play_synth_at("explosion", global_position, 2.0, randf_range(0.5, 0.8))
		await get_tree().create_timer(0.18).timeout
