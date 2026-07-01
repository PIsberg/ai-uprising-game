class_name EnemyTerminator
extends EnemyBase
## Boss android built around an imported glTF model (CC0, Quaternius "Animated
## Robot" — see CREDITS.md). Heavily armored and fast, fires alternating
## dual-muzzle red beams. The model is rigged, so its idle/walk clips drive the
## limbs while the script layers a heavy whole-body stomp bob + lean + recoil on
## the wrapper and a pulsing red eye light. The model is auto-fit at runtime:
## scaled to `target_height` and stood on the floor regardless of its authored
## scale/pivot.

const ANIM_IDLE := "RobotArmature|Robot_Idle"
const ANIM_WALK := "RobotArmature|Robot_Walking"

@export var hitscan_damage: float = 9.0
@export var burst_count: int = 6
@export var burst_interval: float = 0.08
@export var burst_spread_deg: float = 1.4
@export var tracer_scene: PackedScene
@export var muzzle_flash_scene: PackedScene
@export var target_height: float = 2.2   ## The model is scaled to this height (metres).
@export var model_yaw_deg: float = 180.0 ## Flip (0/180) if the model faces the wrong way.
@export var boss_name: String = "APEX ENDOFRAME" ## Shown on the HUD boss bar.
@export var preview: bool = false ## Codex/briefing showcase: idle on the spot, skip the eruption entrance (telegraph ring), boss bar + AI.

const ENTRANCE_FX := preload("res://scenes/fx/enemy_explosion.tscn")

# Eruption entrance: it starts buried this far under the deck, rumbles a beat
# (telegraph), then bursts up through the breaking floor and settles.
const RISE_DEPTH := 4.2
const TELEGRAPH_TIME := 0.75
const RISE_TIME := 0.9

# --- Optic Lance: a tracking green death-ray fired from the eye. It charges,
# then sweeps toward the player at a capped turn rate so you watch it close in;
# standing in it burns fast, but you can outrun it by strafing.
const BEAM_WINDUP := 0.6        ## eye charges green before firing
const BEAM_DURATION := 2.6      ## seconds the beam stays live
const BEAM_RANGE := 60.0
const BEAM_TICK := 0.18         ## damage cadence while it's on you
const BEAM_DAMAGE := 10.0
const BEAM_TURN := 1.5          ## rad/s sweep speed (ramps up when wounded)
const BEAM_COOLDOWN := 7.5
const BEAM_COLOR := Color(0.3, 1.0, 0.35)

@onready var _model: Node3D = $Model
@onready var _muzzle_l: Node3D = $MuzzleL
@onready var _muzzle_r: Node3D = $MuzzleR
@onready var _eye_glow: SpotLight3D = $EyeGlow
@onready var _eye: Node3D = $Eye

var _burst_remaining: int = 0
var _burst_timer: float = 0.0
var _fire_left_next: bool = false
var _walk_phase: float = 0.0
var _model_base_y: float = 0.0
var _entrance: float = 0.0          ## eye-blaze / power-up intensity, decays after the rise
var _anim: AnimationPlayer = null
# Eruption entrance state.
var _rising: bool = false
var _rise_t: float = 0.0
var _rise_target_y: float = 0.0     ## the floor height its feet settle at
var _breached: bool = false
var _telegraph: Node3D = null
# Optic Lance state.
var _beam: ElectricBeam = null
var _beam_windup: float = 0.0
var _beam_time: float = 0.0
var _beam_cd: float = BEAM_COOLDOWN * 0.5   ## first lance comes a few seconds in
var _beam_dir: Vector3 = Vector3.FORWARD
var _beam_tick_t: float = 0.0
var _beam_charge: float = 0.0               ## 0..1, drives the eye turning green

func _ready() -> void:
	super._ready()
	# Was 560 (toned down from 700 for FEEL — it hit too hard). But that left it
	# the weakest boss by ~3x, dying in ~5s — it read as an elite, not a boss.
	# Raise only the HP for a proper boss-length fight; its (already-toned) low
	# damage is unchanged, so it lasts longer without hitting harder.
	max_health = 900.0
	stagger_threshold = 200.0 # heavy boss: only big/sustained hits stagger it
	move_speed = 6.8
	turn_speed = 9.0
	sight_range = 40.0
	sight_angle_deg = 280.0 # relentless — sees you almost anywhere
	attack_range = 26.0
	preferred_range = 16.0
	attack_cooldown = 2.1  # slower burst cadence
	score_value = 1000
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0
	flinch_knockback = 0.4 # near-immune to stagger
	# Deferred so the rig's bones have posed — the model is many bone-driven parts,
	# so the fit needs their posed world bounds, not rest-frame node transforms.
	# Hide it for that one frame so an unscaled flash never shows.
	if _model:
		_model.visible = false
	_fit_model.call_deferred()
	# Drive the rig's looping locomotion clips (idle <-> walk in _process).
	if _model:
		_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in [ANIM_IDLE, ANIM_WALK]:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if _anim.has_animation(ANIM_IDLE):
			_anim.play(ANIM_IDLE)
	# Codex/briefing: stand idle on the dais — skip the eruption entrance (which
	# spawns a warning ring into the scene that would litter/stick in the viewer).
	# _fit_model (queued above) still runs to size + reveal the model.
	if preview:
		hp.invulnerable = true
		set_physics_process(false)
		return
	# Eruption entrance: bury it under the deck, then it bursts up through the
	# breaking floor. Invulnerable + held until it settles.
	_rise_target_y = global_position.y
	global_position.y -= RISE_DEPTH
	velocity = Vector3.ZERO
	_rising = true
	_rise_t = 0.0
	_breached = false
	_entrance = 1.0
	hp.invulnerable = true
	_do_entrance.call_deferred()

func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -8.0)
	# A subterranean rumble building under the deck before it erupts.
	AudioBus.play_synth_at("mech_step", _breach_point(), 1.0, 0.5)
	_spawn_telegraph()

## Where the floor will break — directly above the buried boss, at deck level.
func _breach_point() -> Vector3:
	return Vector3(global_position.x, _rise_target_y, global_position.z)

## A pulsing fracture warning on the deck during the telegraph beat.
func _spawn_telegraph() -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.7
	tm.outer_radius = 2.7
	tm.rings = 24
	tm.ring_segments = 10
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.emission_enabled = true
	m.emission = Color(1.0, 0.32, 0.12)
	m.albedo_color = Color(1.0, 0.32, 0.12)
	tm.material = m
	ring.mesh = tm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(ring)
	ring.global_position = _breach_point() + Vector3(0, 0.06, 0)
	_telegraph = ring

## Telegraph rumble, then erupt up through the floor and settle.
func _process_rise(delta: float) -> void:
	_rise_t += delta
	velocity = Vector3.ZERO
	var buried_y := _rise_target_y - RISE_DEPTH
	if not _breached:
		# Buried: tremor in place, the warning ring pulses and tightens, dust ticks.
		global_position.y = buried_y + sin(_rise_t * 38.0) * 0.06
		var grow := clampf(_rise_t / TELEGRAPH_TIME, 0.0, 1.0)
		if _telegraph and is_instance_valid(_telegraph):
			var pulse := 0.6 + 0.4 * sin(_rise_t * 22.0)
			_telegraph.scale = Vector3.ONE * (1.0 - 0.25 * grow)
			var m := (_telegraph as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
			if m:
				m.emission_energy_multiplier = 1.5 + 5.0 * grow * pulse
		# Building tremor handed to the player.
		var p := get_tree().get_first_node_in_group("player")
		if p and p.has_method("shake"):
			p.shake(0.08 + 0.18 * grow)
		if _rise_t >= TELEGRAPH_TIME:
			_breach()
		return
	# Rising: punch up fast, easing into the settle.
	var t := clampf((_rise_t - TELEGRAPH_TIME) / RISE_TIME, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 3.0)
	global_position.y = buried_y + eased * RISE_DEPTH
	if t >= 1.0:
		_land_settle()

## The floor shatters and the boss erupts: debris, dust, crater, quake, hit-stop.
func _breach() -> void:
	_breached = true
	if _telegraph and is_instance_valid(_telegraph):
		_telegraph.queue_free()
	_telegraph = null
	var bp := _breach_point()
	var breach := FloorBreach.new()
	breach.radius = 2.9
	get_tree().current_scene.add_child(breach)
	breach.global_position = bp
	# Extra blast at the breach + a couple of scattered bursts.
	for i in 3:
		var fx := ENTRANCE_FX.instantiate()
		get_tree().current_scene.add_child(fx)
		(fx as Node3D).global_position = bp + Vector3(randf_range(-1.6, 1.6), 0.4, randf_range(-1.6, 1.6))
	AudioBus.play_synth_ui("eas_alert", -6.0)
	AudioBus.play_synth_at("explosion", bp, 6.0, 0.55)
	AudioBus.play_synth_at("mech_step", bp, 3.0, 0.7)
	GameState.hit_stop(0.12, 0.45)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(2.2)

## Touchdown at deck level: a planted thud, then control returns.
func _land_settle() -> void:
	_rising = false
	global_position.y = _rise_target_y
	velocity = Vector3.ZERO
	hp.invulnerable = false
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.85)
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(0.7)

## Scale the model to target_height and stand its feet at y=0, centred. The
## model is many bone-driven parts, so we merge every part's POSED world AABB
## (via global_transform, which reflects the skeleton) — a single part's local
## bounds would give a bogus fit. Run deferred so the rig has posed.
func _fit_model() -> void:
	if _model == null:
		return
	_model.scale = Vector3.ONE
	_model.rotation = Vector3.ZERO
	_model.position = Vector3.ZERO
	var meshes: Array = []
	_collect_model_meshes(_model, meshes)
	if meshes.is_empty():
		return
	var inv := _model.global_transform.affine_inverse()
	# Some imported mechs ship welded to a flat display slab. Measure each mesh in
	# MODEL space (post-transform) and hide any wide, flat, low-sitting slab so the
	# unit isn't standing on a floating grid in the level.
	var parts := {}
	var lowest := 1e9
	for mi in meshes:
		if mi.mesh == null:
			continue
		var p: AABB = inv * (mi.global_transform * mi.mesh.get_aabb())
		parts[mi] = p
		lowest = minf(lowest, p.position.y)
	for mi in parts:
		var p: AABB = parts[mi]
		var foot: float = maxf(p.size.x, p.size.z)
		var flat := p.size.y < foot * 0.16
		var low := p.position.y < lowest + maxf(0.2, p.size.y)
		if foot > 1.5 and flat and low:
			(mi as MeshInstance3D).visible = false
	var ab := AABB()
	var first := true
	for mi in parts:
		if not (mi as MeshInstance3D).visible:
			continue
		var part: AABB = parts[mi]
		if first:
			ab = part
			first = false
		else:
			ab = ab.merge(part)
	var h := ab.size.y
	if h > 0.001:
		var s := target_height / h
		_model.scale = Vector3(s, s, s)
		var c := ab.get_center()
		_model.position = Vector3(-c.x * s, -ab.position.y * s, -c.z * s)
	_model.rotation.y = deg_to_rad(model_yaw_deg)
	_model_base_y = _model.position.y
	_model.visible = true

func _collect_model_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_collect_model_meshes(c, out)

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	# Eyes blaze through the eruption, then cool to their combat baseline.
	if not _rising and _entrance > 0.0:
		_entrance = maxf(0.0, _entrance - delta * 0.6)
	var speed := Vector2(velocity.x, velocity.z).length()
	var rate := 4.5 + speed * 1.8
	_walk_phase += delta * rate
	var amp := clampf(speed / move_speed, 0.0, 1.0)
	# Blend the rig's locomotion: walk while moving (clip speed tracks ground
	# speed), idle when planted.
	if _anim:
		if amp > 0.12 and _anim.has_animation(ANIM_WALK):
			if _anim.current_animation != ANIM_WALK:
				_anim.play(ANIM_WALK, 0.2)
			_anim.speed_scale = lerpf(0.9, 1.7, amp)
		elif _anim.has_animation(ANIM_IDLE):
			if _anim.current_animation != ANIM_IDLE:
				_anim.play(ANIM_IDLE, 0.3)
			_anim.speed_scale = 1.0
	# A subtler whole-body sway layered on the rig: lean into movement, recoil
	# rocks it back. The rig now does the leg stomp, so the wrapper bob is light.
	if _model:
		_model.position.y = _model_base_y - absf(sin(_walk_phase)) * amp * 0.03
		_model.rotation.x = amp * 0.05 - recoil * 0.12
		_model.rotation.y = deg_to_rad(model_yaw_deg)
	if _eye_glow:
		var flare := _entrance * 6.0 # eyes blaze brighter while powering up
		_eye_glow.light_energy = 4.0 + sin(_walk_phase * 2.5) * 1.5 + recoil * 6.0 + flare + _beam_charge * 10.0
		# The optic shifts from its combat red to a hot green as the lance charges.
		_eye_glow.light_color = Color(1, 0.1, 0.1).lerp(BEAM_COLOR, _beam_charge)
	# Footstep booms on each footfall.
	if speed > 0.1 and is_on_floor():
		var fs := sin(_walk_phase)
		var last := sin(_walk_phase - delta * rate)
		if (fs > 0.0) != (last > 0.0):
			AudioBus.play_synth_at("mech_step", global_position, -2.0, randf_range(1.15, 1.3))

func _physics_process(delta: float) -> void:
	if _rising:
		_process_rise(delta)
		return
	_beam_cd = maxf(0.0, _beam_cd - delta)
	# The lance owns the boss while it's charging/firing — planted, no bursts.
	if _beaming():
		_process_beam(delta)
		return
	super._physics_process(delta)
	if _burst_remaining > 0:
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_fire_one_shot()
			_burst_remaining -= 1
			_burst_timer = burst_interval

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	_decelerate()
	var dist := global_position.distance_to(target.global_position)
	# Optic Lance when it's off cooldown and you're at a beam-able distance;
	# otherwise the dual-cannon burst.
	if _beam_cd <= 0.0 and dist >= 6.0 and dist <= BEAM_RANGE:
		_begin_beam()
		return
	if _attack_timer <= 0.0:
		_start_burst()
		_attack_timer = attack_interval()

func _beaming() -> bool:
	return _beam_windup > 0.0 or _beam_time > 0.0

## Fire up the optic lance: a green charge, then a sweeping death-ray.
func _begin_beam() -> void:
	_beam_windup = BEAM_WINDUP
	_beam_time = 0.0
	_beam_tick_t = 0.0
	if target:
		_beam_dir = (target.global_position + Vector3.UP * 0.7 - _beam_origin()).normalized()
	if _beam == null:
		_beam = ElectricBeam.new()
		_beam.set_color(BEAM_COLOR)
		get_tree().current_scene.add_child(_beam)
	AudioBus.play_synth_at("plasma_fire", _beam_origin(), 2.0, 0.45)

func _beam_origin() -> Vector3:
	return _eye.global_position if _eye else global_position + Vector3.UP * 2.0

## Drive the charge + the tracking, damaging beam.
func _process_beam(delta: float) -> void:
	# Plant and keep turning the body toward the player so the sweep starts aimed.
	_decelerate()
	if not is_on_floor():
		_apply_gravity(delta)
	move_and_slide()
	if target and _can_see(target):
		_face_target(delta)

	var origin := _beam_origin()
	var aim_pt := (target.global_position + Vector3.UP * 0.7) if target else origin + _beam_dir
	var desired := (aim_pt - origin).normalized()

	# Charge phase: eye spins up green, beam not yet lethal.
	if _beam_windup > 0.0:
		_beam_windup -= delta
		_beam_charge = clampf(1.0 - _beam_windup / BEAM_WINDUP, 0.0, 1.0)
		_beam_dir = desired   # lock straight onto the player at ignition
		if _beam_windup <= 0.0:
			_beam_time = BEAM_DURATION
			AudioBus.play_synth_at("plasma_fire", origin, 4.0, 0.3)
		return

	# Firing: sweep the beam toward the player at a capped rate (faster when hurt).
	_beam_charge = 1.0
	_beam_time -= delta
	var ramp := 1.0 + (1.0 - hp.current_health / maxf(hp.max_health, 1.0)) * 1.2
	var max_step := BEAM_TURN * ramp * delta
	var ang := _beam_dir.angle_to(desired)
	if ang > 0.0001:
		_beam_dir = _beam_dir.slerp(desired, clampf(max_step / ang, 0.0, 1.0))

	# Trace the beam: world + player. Damage only when it actually lands on you.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + _beam_dir * BEAM_RANGE)
	q.collision_mask = 0b0000011
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + _beam_dir * BEAM_RANGE
	var on_player := false
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		on_player = col != null and col.is_in_group("player")
		_beam_tick_t -= delta
		if on_player and _beam_tick_t <= 0.0:
			var d: Node = col.get_node_or_null("Damageable")
			if d:
				d.apply_damage(BEAM_DAMAGE, self)
			_beam_tick_t = BEAM_TICK
	if _beam:
		_beam.update_beam(origin, end_point, true)
	if _beam_time <= 0.0:
		_end_beam()

func _end_beam() -> void:
	_beam_windup = 0.0
	_beam_time = 0.0
	_beam_charge = 0.0
	_beam_cd = BEAM_COOLDOWN
	if _beam:
		_beam.deactivate()

func _start_burst() -> void:
	_burst_remaining = burst_count
	_burst_timer = 0.0

func _fire_one_shot() -> void:
	if target == null or _muzzle_l == null or _muzzle_r == null:
		return
	recoil = 1.0
	var active := _muzzle_l if _fire_left_next else _muzzle_r
	_fire_left_next = not _fire_left_next
	if muzzle_flash_scene:
		active.add_child(muzzle_flash_scene.instantiate())
	AudioBus.play_synth_at("drone_shot", active.global_position, -2.0, randf_range(0.85, 0.95))
	var origin := active.global_position
	var dir := (target.global_position + Vector3.UP * 0.7 - origin).normalized()
	# Inherent burst scatter + difficulty-driven inaccuracy.
	dir = scatter_aim(dir, burst_spread_deg)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 90.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 90.0
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		var d: Node = col.get_node_or_null("Damageable") if col else null
		if d:
			d.apply_damage(hitscan_damage, self)
	if tracer_scene:
		var tr := tracer_scene.instantiate()
		get_tree().current_scene.add_child(tr)
		if tr.has_method("setup"):
			tr.setup(origin, end_point)

func _perform_attack() -> void:
	_start_burst()

func _on_died(source: Node) -> void:
	# Boss kill payoff: a camera kick + brief slow-mo before the base death.
	_beam_windup = 0.0
	_beam_time = 0.0
	_beam_charge = 0.0
	if is_instance_valid(_beam):
		_beam.queue_free()
		_beam = null
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("shake"):
		p.shake(1.0)
	GameState.hit_stop(0.3, 0.45)
	super._on_died(source)
