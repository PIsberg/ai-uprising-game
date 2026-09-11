class_name EnemyManus
extends EnemyBase
## MANUS — a colossal severed robot arm (assets/models/robots/robot_arm_wip_2.glb),
## the assembly plant's master manipulator, torn free and feral — but ROOTED:
## its wrist trunk is fused through the deck into the plant's drive machinery,
## so it holds its ground and fights with reach instead of pursuit. In close it
## has a backhand SWEEP and a raised-palm SLAM; its signature GRAB is now a
## floor-shaking YANK — a finger-spread tell, then the player is reeled across
## the arena into the palm, squeezed, and hurled. Beyond arm's reach it strikes
## THROUGH the floor: servo fingers erupt from the deck under your feet.
##
## ARMOURED EVERYWHERE BUT ONE SPOT: the exposed reactor coupling on its wrist
## (the glowing core). Every hit anywhere else sparks off harmlessly — only the
## core takes damage, and it takes it AMPLIFIED. Fighting MANUS is aiming.
##
## WOUNDED, IT GETS FASTER: three health-keyed phases like the other bosses
## (see _phase). Every attack cooldown shrinks per phase, and from phase 3 the
## finger eruption strikes TWICE — the second burst leads where you're running.

@export var boss_name: String = "MANUS"   ## Shown on the HUD boss bar.
@export var preview: bool = false ## Codex/briefing showcase: idle, skip entrance/boss bar.
@export_group("Weak spot")
@export var core_radius: float = 1.1      ## Hit tolerance around the wrist core.
@export var core_multiplier: float = 2.2  ## Crit bonus for rounds on the core.
@export_group("Sweep")
@export var sweep_damage: float = 30.0
@export var sweep_range: float = 9.5
@export var sweep_arc_deg: float = 170.0
@export var sweep_cooldown: float = 3.4
@export var sweep_windup: float = 0.45
@export_group("Slam")
@export var slam_damage: float = 42.0
@export var slam_radius: float = 5.5
@export var slam_cooldown: float = 6.5
@export var slam_windup: float = 0.6
@export_group("Grab")
@export var grab_reach: float = 14.0           ## The yank connects out to this range.
@export var grab_squeeze_damage: float = 10.0  ## Per squeeze tick (x3).
@export var grab_cooldown: float = 9.0
@export_group("Finger eruption")
@export var spike_damage: float = 26.0
@export var spike_radius: float = 3.2
@export var spike_cooldown: float = 4.5
@export var spike_windup: float = 0.75

var _sweep_cd: float = 1.5
var _slam_cd: float = 4.0
var _grab_cd: float = 6.0
var _spike_cd: float = 2.5
var _sweep_windup_t: float = 0.0
var _slam_windup_t: float = 0.0
var _slam_point: Vector3
var _grabbed: Node3D = null
var _squeeze_t: float = 0.0
var _squeeze_tick: float = 0.0
var _crawl_phase: float = 0.0
var _core_mat: StandardMaterial3D
var _armored_fx_cd: float = 0.0
# Weak-spot gating: weapons call weakpoint_multiplier(hit_pos) right before
# applying damage; we remember whether that hit found the core, then
# modify_incoming_damage (which has no position) consumes the answer. Damage
# with NO fresh position report (splash, shoves) never reaches the core.
var _core_hit_fresh: bool = false
var _wake: float = 1.2
var _last_phase: int = 1

## Cooldown scale per phase (index = phase - 1): a wounded arm lashes out sooner.
const PHASE_CD_MULT := [1.0, 0.8, 0.62]
## Phase-3 eruption pair: the second burst lands this far ahead along the
## player's velocity, this long after the first — punishes running straight.
const SPIKE_LEAD_SEC := 0.7
const SPIKE_SECOND_DELAY := 0.35

@onready var _core: MeshInstance3D = $WeakSpot/Core
@onready var _core_light: OmniLight3D = $WeakSpot/CoreLight
@onready var _palm: Node3D = $Palm

func _ready() -> void:
	super._ready()
	max_health = 2800.0
	stagger_threshold = 100000.0
	move_speed = 0.0 # ROOTED — the trunk is fused through the deck; zero also kills evade/frenzy drift
	turn_speed = 2.6
	sight_range = 70.0
	sight_angle_deg = 360.0   # a hand has no face to blindside
	close_sense_range = 20.0
	attack_range = 13.0
	preferred_range = 5.0
	attack_cooldown = 2.6
	reaction_time = 0.3
	score_value = 3000
	head_radius = 0.0         # no head, no headshots — there's only the core
	flinch_knockback = 0.0
	drop_chance = 1.0
	hp.max_health = max_health
	hp.current_health = max_health
	_core_mat = _core.material_override as StandardMaterial3D
	if preview:
		_wake = 0.0
		hp.invulnerable = true
		set_physics_process(false)
		return
	hp.invulnerable = true
	_do_entrance.call_deferred()

## FINGER-DRUM WAKE entrance: the severed master-arm boots up — its knuckles rap
## the deck one by one (each rap kicks a shock ring and pulses the core brighter),
## then it REARS and drives the whole fist down in a floor-quaking slam. Unique to
## the hand: it doesn't walk in, it drums itself awake.
func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	var p := get_tree().get_first_node_in_group("player")
	# Knuckles rap the deck one by one — each strike a shock ring at a fingertip,
	# the core throbbing louder with every rap.
	var knuckles := [Vector3(2.4, 0, 1.4), Vector3(1.0, 0, 2.7), Vector3(-1.1, 0, 2.5), Vector3(-2.5, 0, 1.1)]
	for i in 4:
		AudioBus.play_synth_at("servo_step_heavy", global_position, 4.0, 0.5 + i * 0.12)
		spawn_shockwave_ring(2.2 + i * 0.5, Color(0.72, 0.95, 1.0), global_position + knuckles[i])
		recoil = 0.85 # pulse the core glow with each rap (see _process driver)
		if p and p.has_method("shake"):
			p.shake(0.35)
		await get_tree().create_timer(0.16).timeout
		if state == State.DEAD:
			return
	# Then it REARS and drives the whole fist down — a floor-quaking slam ring.
	AudioBus.play_synth_at("mech_step", global_position, 5.0, 0.3)
	AudioBus.play_synth_at("explosion", global_position, 6.0, 0.9)
	spawn_shockwave_ring(8.5, Color(0.6, 0.9, 1.0))
	recoil = 1.0
	GameState.hit_stop(0.09, 0.5)
	if p and p.has_method("shake"):
		p.shake(1.4)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Finger-drag scuttle: the chassis rocks with each pull; the core throbs —
	# brighter the harder it's hurt, so the target you must hit gets LOUDER.
	var speed := Vector2(velocity.x, velocity.z).length()
	_crawl_phase += delta * (1.6 + speed * 1.4)
	if _visual_root:
		_visual_root.rotation.x = _visual_base_rot.x + sin(_crawl_phase) * 0.05
	var hurt := 1.0 - hp.current_health / hp.max_health
	if _core_mat:
		_core_mat.emission_energy_multiplier = 4.0 + sin(_crawl_phase * 2.4) * 1.8 + hurt * 5.0 + recoil * 6.0
	if _core_light:
		_core_light.light_energy = 2.5 + sin(_crawl_phase * 2.4) * 1.0 + hurt * 3.0
	if speed > 0.15 and is_on_floor():
		var fs := sin(_crawl_phase * 2.0)
		var last := sin((_crawl_phase - delta * (1.6 + speed * 1.4)) * 2.0)
		if (fs > 0.0) != (last > 0.0):
			AudioBus.play_synth_at("servo_step_heavy", global_position, 2.0, randf_range(0.45, 0.6))

func _physics_process(delta: float) -> void:
	_armored_fx_cd = maxf(0.0, _armored_fx_cd - delta)
	if _wake > 0.0:
		_wake -= delta
		_decelerate()
		_apply_gravity(delta)
		move_and_slide()
		if _wake <= 0.0:
			hp.invulnerable = false
		return
	# Phase-change punch: the arm rears, the alarm sounds, the floor shakes —
	# the tell that the fight just got faster (same read as SMASHER/COLOSSUS).
	var ph := _phase()
	if ph != _last_phase:
		_last_phase = ph
		recoil = 1.0
		AudioBus.play_synth_ui("eas_alert", -10.0)
		var pl := get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("shake"):
			pl.shake(0.6)
		spawn_shockwave_ring(sweep_range * 0.6, Color(0.5, 0.85, 1.0), global_position)
	_sweep_cd = maxf(0.0, _sweep_cd - delta)
	_slam_cd = maxf(0.0, _slam_cd - delta)
	_grab_cd = maxf(0.0, _grab_cd - delta)
	_spike_cd = maxf(0.0, _spike_cd - delta)
	# Squeeze in progress: crush the catch, then hurl them.
	if _grabbed != null:
		_update_squeeze(delta)
		_decelerate()
		_apply_gravity(delta)
		move_and_slide()
		return
	if _sweep_windup_t > 0.0:
		_sweep_windup_t -= delta
		_face_target(delta)
		if _sweep_windup_t <= 0.0:
			_do_sweep()
		_apply_gravity(delta)
		move_and_slide()
		return
	if _slam_windup_t > 0.0:
		_slam_windup_t -= delta
		# Rear up on the wrist for the slam.
		if _visual_root:
			_visual_root.rotation.x = _visual_base_rot.x - 0.5 * minf(1.0, (slam_windup - _slam_windup_t) * 3.0)
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
	var dist := global_position.distance_to(target.global_position)
	if not GameState.attack_grace_active():
		if _grab_cd <= 0.0 and dist >= 5.0 and dist <= grab_reach:
			_begin_grab()
			_bark_attack()
			return
		if _slam_cd <= 0.0 and dist <= 11.0:
			_begin_slam()
			_bark_attack()
			return
		if _sweep_cd <= 0.0 and dist <= sweep_range:
			_begin_sweep()
			_bark_attack()
			return
		# Beyond arm's reach: strike THROUGH the deck it's rooted into —
		# servo fingers erupt under the player's feet, anywhere in the arena.
		if _spike_cd <= 0.0 and dist > sweep_range:
			_begin_spike()
			_bark_attack()
			return
	# Rooted: the trunk never leaves its spot — it plants, tracks, and reaches.
	_decelerate()
	_face_target(delta)

## Rooted: there is no pursuit. Anything it can see is already "in range" —
## close targets meet the arm, far ones meet the deck eruption — so seeing the
## player IS engaging. Without this the base chase state would idle forever
## against a player camped beyond attack_range (move_speed is 0).
func _state_chase(delta: float) -> void:
	if target and _can_see(target):
		set_state(State.ATTACK)
		return
	_decelerate()
	if target and _has_last_known:
		_face_dir((_last_known_target_pos - global_position) * Vector3(1, 0, 1), delta)

## Health-keyed phase, 1..3 (same thresholds as the other bosses): the core
## reads hotter and every attack cycles faster the more damage it has taken.
func _phase() -> int:
	var frac := hp.current_health / maxf(hp.max_health, 1.0)
	if frac <= 0.33:
		return 3
	elif frac <= 0.66:
		return 2
	return 1

func _cd_mult() -> float:
	return float(PHASE_CD_MULT[_phase() - 1])

## FINGER ERUPTION — the rooted arm's ranged answer: it drives power through
## the deck it's fused into and servo fingers burst from the floor under the
## player. Telegraphed with a ground ring (same read as every AoE), so at range
## the fight is "keep moving and keep shooting the core".
func _begin_spike() -> void:
	_spike_cd = spike_cooldown * _cd_mult()
	recoil = 1.0
	var at: Vector3 = target.global_position
	_erupt_at(at, 0.0)
	# Wounded (phase 3): a second eruption leads the player's run — standing
	# still eats the first, sprinting straight eats the second.
	if _phase() >= 3:
		var lead := Vector3.ZERO
		if "velocity" in target:
			lead = Vector3(target.velocity.x, 0.0, target.velocity.z) * SPIKE_LEAD_SEC
		_erupt_at(at + lead, SPIKE_SECOND_DELAY)

## One telegraphed finger eruption at `at`, `delay` seconds from now: warning
## ring for the windup, then the spears, shock ring, and the hit check.
func _erupt_at(at: Vector3, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
		if state == State.DEAD or not is_inside_tree():
			return
	spawn_ground_warning(at, spike_radius, spike_windup, Color(0.72, 0.95, 1.0))
	AudioBus.play_synth_at("charge", at, -6.0, 0.7)
	await get_tree().create_timer(spike_windup).timeout
	if state == State.DEAD or not is_inside_tree():
		return
	AudioBus.play_synth_at("mech_step", at, 2.0, 0.4)
	spawn_shockwave_ring(spike_radius, Color(0.72, 0.95, 1.0), at)
	_spawn_spike_fingers(at)
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		return
	if (p as Node3D).global_position.distance_to(at) <= spike_radius:
		var d = p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(spike_damage, self)
		if "velocity" in p:
			p.velocity += Vector3.UP * 6.0 # knocked off your feet, not just ticked
		if p.has_method("shake"):
			p.shake(0.9)

## The eruption made visible: dark servo-finger spears punch up out of the deck
## in a ring, hold a beat, then withdraw back into the floor.
func _spawn_spike_fingers(at: Vector3) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	for i in 5:
		var ang := TAU * float(i) / 5.0 + randf_range(-0.2, 0.2)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * spike_radius * randf_range(0.25, 0.8)
		var spear := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.22
		cm.height = 2.6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.13, 0.15, 0.18)
		mat.metallic = 0.8
		mat.roughness = 0.35
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.85, 1.0)
		mat.emission_energy_multiplier = 1.2
		cm.material = mat
		spear.mesh = cm
		spear.rotation = Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
		parent.add_child(spear)
		spear.global_position = at + off + Vector3.DOWN * 2.6 # start buried
		var tw := spear.create_tween()
		tw.tween_property(spear, "global_position:y", at.y + 1.1, 0.09) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(float(i) * 0.03)
		tw.tween_interval(0.5)
		tw.tween_property(spear, "global_position:y", at.y - 2.8, 0.3).set_ease(Tween.EASE_IN)
		tw.tween_callback(spear.queue_free)

func _begin_sweep() -> void:
	_sweep_windup_t = sweep_windup
	_sweep_cd = sweep_cooldown * _cd_mult()
	recoil = 1.0
	AudioBus.play_synth_at("charge", global_position, -4.0, 0.6)

func _do_sweep() -> void:
	if _visual_root:
		_visual_root.rotation.x = _visual_base_rot.x
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.5)
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		return
	var to: Vector3 = (p as Node3D).global_position - global_position
	to.y = 0.0
	var fwd := -global_transform.basis.z
	if to.length() <= sweep_range and rad_to_deg(fwd.angle_to(to)) <= sweep_arc_deg * 0.5:
		var d = p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(sweep_damage, self)
		if "velocity" in p and to.length() > 0.1:
			p.velocity += to.normalized() * 11.0 + Vector3.UP * 4.0  # backhanded across the floor
		if p.has_method("shake"):
			p.shake(0.8)

func _begin_slam() -> void:
	_slam_windup_t = slam_windup
	_slam_cd = slam_cooldown * _cd_mult()
	recoil = 1.0
	_slam_point = target.global_position if target else global_position - global_transform.basis.z * 6.0
	spawn_ground_warning(_slam_point, slam_radius, _slam_windup_t)
	AudioBus.play_synth_at("charge", global_position, -3.0, 0.5)

func _do_slam() -> void:
	if _visual_root:
		_visual_root.rotation.x = _visual_base_rot.x
	AudioBus.play_synth_at("explosion", _slam_point, 2.0, 0.5)
	var fx := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = _slam_point
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node3D):
		return
	if (p as Node3D).global_position.distance_to(_slam_point) <= slam_radius:
		var d = p.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		if p.has_method("shake"):
			p.shake(1.0)

func _begin_grab() -> void:
	_grab_cd = grab_cooldown * _cd_mult()
	recoil = 1.0
	AudioBus.play_synth_at("charge", global_position, -2.0, 0.42)
	AudioBus.play_synth_ui("overlord_glitch", -8.0)
	# Finger-spread tell, then the YANK: the rooted arm doesn't lunge — if the
	# tell lands and you're still inside its reach, it snatches and REELS you
	# across the floor into the palm (the squeeze pull does the dragging).
	spawn_ground_warning(target.global_position, 2.4, 0.55, Color(1.0, 0.5, 0.1))
	await get_tree().create_timer(0.55).timeout
	if state == State.DEAD or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= grab_reach + 2.0:
		_connect_grab()

func _connect_grab() -> void:
	velocity = Vector3.ZERO
	_grabbed = target
	_squeeze_t = 1.1
	_squeeze_tick = 0.0
	AudioBus.play_synth_at("impact_metal", _palm.global_position, 0.0, 0.5)
	if _grabbed.has_method("shake"):
		_grabbed.shake(1.0)

## Caught: dragged to the palm and crushed in three squeezes — the core on the
## wrist is right in your face the whole time. Empty a mag into it. Then the
## hand THROWS you.
func _update_squeeze(delta: float) -> void:
	if _grabbed == null or not is_instance_valid(_grabbed):
		_grabbed = null
		return
	_squeeze_t -= delta
	_squeeze_tick -= delta
	# Reel the catch into the palm (velocity pull, not a teleport, so the
	# player's own physics stays in charge).
	if "velocity" in _grabbed:
		_grabbed.velocity = (_palm.global_position - _grabbed.global_position) * 9.0
	if _squeeze_tick <= 0.0:
		_squeeze_tick = 0.34
		var d = _grabbed.get_node_or_null("Damageable")
		if d:
			d.apply_damage(grab_squeeze_damage, self)
		AudioBus.play_synth_at("impact_metal", _palm.global_position, -3.0, 0.6)
		if _grabbed.has_method("shake"):
			_grabbed.shake(0.5)
	if _squeeze_t <= 0.0:
		_hurl()

func _hurl() -> void:
	if _grabbed and is_instance_valid(_grabbed) and "velocity" in _grabbed:
		var away := -global_transform.basis.z
		away = away.rotated(Vector3.UP, randf_range(-0.5, 0.5))
		_grabbed.velocity = away * 14.0 + Vector3.UP * 9.0
		if _grabbed.has_method("shake"):
			_grabbed.shake(1.0)
	AudioBus.play_synth_at("grenade_throw", global_position, 2.0, 0.5)
	_grabbed = null

## ---- The one weak spot ----------------------------------------------------
func weakpoint_multiplier(hit_pos: Vector3) -> float:
	var near := hit_pos.distance_to(_core.global_position) <= core_radius
	_core_hit_fresh = near
	return core_multiplier if near else 1.0

func modify_incoming_damage(amount: float, src, _origin = null) -> float:
	if src == self:
		return amount
	var on_core := _core_hit_fresh
	_core_hit_fresh = false
	if on_core:
		return amount
	# Everything else — plating hits, splash, shoves — sparks off harmlessly.
	if _armored_fx_cd <= 0.0:
		_armored_fx_cd = 0.45
		AudioBus.play_synth_at("impact_metal", global_position + Vector3.UP * 2.0, -6.0, 1.7)
		# Flash the core: the game TEACHING you where to shoot.
		if _core_mat:
			_core_mat.emission_energy_multiplier = 14.0
	return 0.0

func _on_died(src: Node) -> void:
	if _grabbed != null:
		_hurl()  # never take the player down with the wreck
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.5)
	GameState.hit_stop(0.25, 0.5)
	_spawn_death_explosions.call_deferred()
	super._on_died(src)

func _spawn_death_explosions() -> void:
	for i in 5:
		if not is_inside_tree():
			return
		var fx := EXPLOSION.instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = global_position \
			+ Vector3(randf_range(-4, 4), randf_range(0.5, 3.5), randf_range(-4, 4))
		AudioBus.play_synth_at("explosion", global_position, 2.0, randf_range(0.5, 0.8))
		await get_tree().create_timer(0.18).timeout
