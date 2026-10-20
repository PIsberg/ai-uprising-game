class_name EnemyColossus
extends EnemyBase
## Gigantic suburban mega-boss — a ~10 m biped war-machine that towers over the
## houses. Multi-phase: it bombards with shoulder artillery, sweeps a chest beam
## once wounded, and ground-slams a shockwave when enraged or when you get close.
## Uses the HUD boss bar (GameState.announce_boss) and a cinematic entrance.
##
## Visuals are the imported "George" heavy mech (RobotModel on $Model drives the
## walk/idle clips; each attack plays its own: Shoot for the artillery, Shoot
## held through the beam sweep, a crouch-leap-land Jump for the slam). The
## pulsing Reactor weak-point sphere, the eye spotlight and the muzzles are scene
## markers that ride the rig's Body bone, and each seismic footfall fires as a
## foot plants (_follow_rig).

@export var boss_name: String = "GOLIATH-IX"   ## Shown on the HUD boss bar.
@export var boss_epithet: String = "WALKING SIEGE ENGINE" ## Under the name on the intro card (BossPresence).
@export var preview: bool = false ## Codex/briefing showcase: idle on the spot, skip the sky-drop entrance, thrusters, boss bar + AI.
@export var rocket_scene: PackedScene
@export var tracer_scene: PackedScene
@export var muzzle_flash_scene: PackedScene

@export_group("Artillery")
@export var rocket_speed: float = 30.0
@export var rocket_damage: float = 14.0   ## Per-rocket DIRECT hit (volleys of 3-5; the rocket now lands instead of relying on splash that excluded the player).
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

@export_group("Seismic footfall")
@export var footfall_radius: float = 8.5    ## Ground crushed under each step.
@export var footfall_damage: float = 10.0   ## Peak damage directly underfoot.
@export var footfall_knockback: float = 10.0

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
# Rig (see _setup_rig): markers ride the Body bone, footfalls land on the feet.
const FOOT_PLANTED := 0.3  ## A foot this close to the floor (m) is planted...
const FOOT_LIFTED := 0.45  ## ...once it has been lifted at least this high.
## Fraction of the George Jump clip where it lands (Body bone back to its
## crouch): the slam plays the clip so that landing falls on the impact.
const JUMP_LANDS_AT := 0.75
var _rig_tried := false
var _rig_sk: Skeleton3D
var _rig_body := -1
var _rig_feet: Array = []
var _rig_markers: Array = [] ## [node, position in the Body bone's frame at idle]
var _foot_up: Array = [false, false]

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
	max_health = 3000.0
	stagger_threshold = 100000.0 # a colossus shrugs off small-arms; never stunlocked
	move_speed = 2.2
	turn_speed = 1.6
	sight_range = 70.0
	sight_angle_deg = 300.0   # near-omniscient; it dominates the arena
	attack_range = 48.0
	preferred_range = 26.0
	attack_cooldown = artillery_cooldown
	score_value = 3000
	head_radius = 0.6
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
	# Codex/briefing: stand idle on the dais — no sky-drop, thrusters, boss bar or
	# AI (those spawn FX into the scene that would litter/stick in the viewer).
	if preview:
		hp.invulnerable = true
		set_physics_process(false)
		return
	_begin_entrance()

## The boss's arrival cinematic. Overridable so subclasses can arrive their own
## way (e.g. the titan folds space instead of making planetfall). Base = the
## GOLIATH sky-drop: hang high on retro-rockets, invulnerable, until it lands.
func _begin_entrance() -> void:
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
	for p in GameState.players():
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
	for p in GameState.players():
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
	return boss_phase()

func boss_phase_marks() -> Array:
	return [0.66, 0.33]

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
	# Footfall booms + SEISMIC SHOCKWAVE: this thing is so massive that each step
	# quakes the ground — the screen shakes as it lumbers, an expanding dust-ring
	# rips out from the foot, and anyone caught underfoot is flung and crushed. Its
	# movement itself is a weapon (matches the colossal siege chassis) — you never
	# want to be beneath it.
	if not _rig_tried:
		_setup_rig()
	if _rig_sk:
		_follow_rig(speed)
	elif speed > 0.1 and is_on_floor():
		# Rig-less (the titan): its procedural stride runs on _walk_phase.
		var fs := sin(_walk_phase)
		var last := sin(_walk_phase - delta * rate)
		if (fs > 0.0) != (last > 0.0):
			AudioBus.play_synth_at("mech_step", global_position, 1.0, randf_range(0.6, 0.75))
			_footfall_quake()

# ---------- rig: markers ride the body, quakes land under the feet ----------

## The George rig's Body bone bobs ~1.9 m through a walk cycle and leaps ~3.8 m
## in the Jump clip, so the scene's markers (reactor, head and eye, muzzles)
## follow its offset from the idle pose, and each seismic footfall fires when a
## foot actually plants, under that foot. Rig-less subclasses (the titan) keep
## the static markers and the _walk_phase footfall.
func _setup_rig() -> void:
	var model := get_node_or_null("Model") as RobotModel
	if model == null or not model.is_visible_in_tree():
		return
	var sks := model.find_children("*", "Skeleton3D", true, false)
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if sks.is_empty() or aps.is_empty():
		_rig_tried = true
		return
	var sk := sks[0] as Skeleton3D
	if (aps[0] as AnimationPlayer).current_animation != model.anim_idle:
		return # measure the idle pose
	_rig_tried = true
	_rig_body = sk.find_bone("Body")
	_rig_feet = [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
	if _rig_body < 0 or _rig_feet.has(-1):
		return
	_rig_sk = sk
	# Each marker's place in the Body bone's frame at idle, so it carries the
	# bone's bob, leap and RobotModel's lean alike.
	var to_bone := _rig_bone_xf().affine_inverse()
	for n in [_reactor, _head, _muzzle_l, _muzzle_r, _muzzle_core]:
		if n:
			_rig_markers.append([n, to_bone * (n as Node3D).position])
	# After the pose is final, so the markers never trail the animation a frame.
	sk.skeleton_updated.connect(_place_markers)

## A bone's position in the boss's own frame.
func _rig_point(bone: int) -> Vector3:
	return global_transform.affine_inverse() * (_rig_sk.global_transform * _rig_sk.get_bone_global_pose(bone).origin)

## The Body bone's transform in the boss's own frame.
func _rig_bone_xf() -> Transform3D:
	return global_transform.affine_inverse() * _rig_sk.global_transform * _rig_sk.get_bone_global_pose(_rig_body)

func _place_markers() -> void:
	if not is_instance_valid(_rig_sk):
		return
	var xf := _rig_bone_xf()
	for m in _rig_markers:
		(m[0] as Node3D).position = xf * (m[1] as Vector3)

func _follow_rig(speed: float) -> void:
	for i in _rig_feet.size():
		var foot := _rig_point(_rig_feet[i])
		if foot.y > FOOT_LIFTED:
			_foot_up[i] = true
		elif foot.y < FOOT_PLANTED and _foot_up[i]:
			_foot_up[i] = false
			if speed > 0.1 and is_on_floor():
				AudioBus.play_synth_at("mech_step", global_transform * foot, 1.0, randf_range(0.6, 0.75))
				_footfall_quake(global_transform * foot)

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
	# Phase change: its reactor flares (the roar, quake and banner are
	# EnemyBase._boss_phase_beat's).
	var ph := _phase()
	if ph != _last_phase:
		_last_phase = ph
		recoil = 1.0
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
	# Opening-seconds grace: still lumber into position, just don't start anything new.
	if GameState.attack_grace_active():
		return
	# Enraged or cornered -> ground slam.
	if _slam_cd <= 0.0 and (dist <= slam_trigger_range or (_phase() == 3 and dist <= slam_radius * 1.4)):
		_begin_slam()
		_bark_attack()
		return
	# Wounded -> sweeping beam.
	if _phase() >= 2 and _beam_cd <= 0.0:
		_begin_beam()
		_bark_attack()
		return
	# Default -> artillery barrage (volley grows with phase).
	if _artillery_cd <= 0.0:
		_fire_artillery()
		_bark_attack()

# ---------- seismic footfall ----------

## Every heavy step quakes the arena: a dust-ring rips outward, the camera jolts
## (scaled by how close you are), and anyone caught under the foot is crushed and
## flung clear. Distant steps are just an ominous rumble.
func _footfall_quake(at: Vector3 = Vector3.INF) -> void:
	if at == Vector3.INF:
		at = global_position
	_footfall_ring(at)
	for p in GameState.players():
		var to: Vector3 = (p as Node3D).global_position - at
		to.y = 0.0
		var d := to.length()
		if d <= footfall_radius:
			var prox := clampf(1.0 - d / footfall_radius, 0.0, 1.0)
			if p.has_method("shake"):
				p.shake(0.25 + prox * 0.55)
			# Grace period: shake but don't crush a fresh drop-in.
			if not GameState.attack_grace_active():
				var dm = p.get_node_or_null("Damageable")
				if dm:
					dm.apply_damage(footfall_damage * maxf(prox, 0.3), self)
				if d > 0.1 and "velocity" in p:
					p.velocity += to.normalized() * footfall_knockback + Vector3.UP * 4.0
		elif p.has_method("shake") and d < footfall_radius * 3.0:
			p.shake(0.12) # far-off tremor as the giant approaches

## An expanding shockwave dust-ring flung out from the foot on impact.
func _footfall_ring(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.05
	tm.rings = 24
	tm.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.62, 0.3, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.55, 0.25)
	m.emission_energy_multiplier = 2.2
	tm.material = m
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(0.6, 0.1, 0.6)
	scene.add_child(ring)
	ring.global_position = Vector3(at.x, 0.2, at.z)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(footfall_radius, 0.05, footfall_radius), 0.4) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "transparency", 1.0, 0.4)
	tw.chain().tween_callback(ring.queue_free)

# ---------- artillery ----------

func _fire_artillery() -> void:
	if target == null or rocket_scene == null:
		return
	_artillery_cd = maxf(0.9, artillery_cooldown - float(_phase() - 1) * 0.5)
	recoil = 1.0
	var volley := 2 + _phase()  # 3 / 4 / 5 rockets
	_play_clip("Shoot")
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
	_play_clip("Shoot", beam_duration) # braced, gun arm out, through the sweep
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

## Plays a George clip once and holds locomotion off it (over `seconds` if
## given). No-op on rig-less subclasses (the titan).
func _play_clip(clip: String, seconds: float = 0.0) -> void:
	var model := get_node_or_null("Model") as RobotModel
	if model == null:
		return
	if seconds > 0.0:
		model.play_oneshot_over(clip, seconds)
	else:
		model.play_oneshot(clip)

# ---------- ground slam ----------

func _begin_slam() -> void:
	_slam_windup = 0.5
	_slam_cd = slam_cooldown
	# A leaping stomp: crouch, leap, and land on the impact.
	_play_clip("Jump", _slam_windup / JUMP_LANDS_AT)
	recoil = 1.0
	AudioBus.play_synth_at("mech_step", global_position, 3.0, 0.45)
	# Paint the kill zone on the ground so the slam is dodgeable, not a surprise.
	spawn_ground_warning(global_position, slam_radius, _slam_windup)

func _do_slam() -> void:
	AudioBus.play_synth_at("explosion", global_position, 4.0, 0.55)
	var fx := EXPLOSION.instantiate()
	get_tree().current_scene.add_child(fx)
	(fx as Node3D).global_position = global_position
	for p in GameState.players():
		if (p as Node3D).global_position.distance_to(global_position) <= slam_radius:
			var d := p.get_node_or_null("Damageable")
			if d:
				d.apply_damage(slam_damage, self)
			if p.has_method("shake"):
				p.shake(1.0)

# ---------- death ----------

func _on_died(source: Node) -> void:
	# A boss this size goes out loud: a stagger of explosions + a long quake.
	for p in GameState.players():
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
