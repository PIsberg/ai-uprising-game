class_name EnemyBase
extends CharacterBody3D

signal state_changed(new_state: int)

enum State { IDLE, PATROL, ALERT, CHASE, ATTACK, STAGGER, DEAD }

@export_group("Stats")
@export var max_health: float = 100.0
@export var move_speed: float = 4.0
@export var turn_speed: float = 8.0
@export var sight_range: float = 30.0
@export var sight_angle_deg: float = 110.0
@export var hearing_range: float = 14.0
@export var close_sense_range: float = 5.0 ## Within this, sensors ignore the sight cone (LOS ray still applies).
@export var attack_range: float = 14.0
@export var preferred_range: float = 10.0
@export var attack_cooldown: float = 1.4
@export var reaction_time: float = 0.45 ## Delay between first spotting the player and the first attack. Difficulty scales this (reaction_mult) so easy robots are slow on the trigger, hard ones snap to.
@export var attack_lunge_speed: float = 0.0 ## >0: a melee striker that LEAPS at the target on attack instead of standing and tapping it.
@export var telegraph_time: float = 0.35 ## Wind-up before each attack: the unit charges (eye flare + charge whine) for this long so the player can read the shot and dodge it. 0 = no tell (units that telegraph their own way, e.g. the sniper's charged beam).
@export var score_value: int = 100
var elite: String = "" ## Elite affix id ("shielded"/"volatile"/"swift"), set by Elite.apply.

@export_group("References")
@export var eye: Node3D
@export var muzzle: Node3D

@export_group("Reactions")
@export var flinch_knockback: float = 3.0 ## Backward shove applied on taking a hit.
@export var head_radius: float = 0.45 ## Vertical tolerance around the head for headshots.
@export var stagger_threshold: float = 38.0 ## Poise: damage absorbed before a hit staggers it (bosses set this high).

@export_group("Loot")
@export var drop_chance: float = 0.45 ## Chance to leave a supply drop on death (anchors with score >= 250 always drop). Kills are the ONLY supply source in campaign levels; difficulty scales this via pickup_mult.

const MUZZLE_FLASH: PackedScene = preload("res://scenes/fx/muzzle_flash.tscn")
const EXPLOSION: PackedScene = preload("res://scenes/fx/enemy_explosion.tscn")
const DAMAGED_FX: PackedScene = preload("res://scenes/fx/damaged_fx.tscn")
const PICKUP_AMMO: PackedScene = preload("res://scenes/pickups/ammo_box.tscn")
const PICKUP_HEALTH: PackedScene = preload("res://scenes/pickups/health_pack.tscn")
const PICKUP_OVERCLOCK: PackedScene = preload("res://scenes/pickups/overclock.tscn")
const PICKUP_OVERDRIVE: PackedScene = preload("res://scenes/pickups/overdrive.tscn")


@onready var hp: Damageable = $Damageable
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var _damaged_emitter: Node3D = null
var _spark_emitter: Node3D = null
## 0..1 battle-damage heat; rises as health falls. Subclasses add it to glow.
var damage_heat: float = 0.0


var state: State = State.IDLE
var target: Node3D
var recoil: float = 0.0 ## 0..1, spikes to 1 on firing; subclasses read it for weapon kick.
var _attack_timer: float = 0.0
var _telegraphing: bool = false ## True during an attack wind-up (see telegraph_time).
var _tele_timer: float = 0.0
var _lunge_time: float = 0.0 ## While >0, a melee leap is in flight; movement logic lets the surge ride.
var _state_timer: float = 0.0
var _last_known_target_pos: Vector3
var _approach_angle: float = 0.0 ## Stable angle each enemy circles to, so they flank instead of stacking.
var combat_strafe: bool = false ## Ranged enemies opt in: circle-strafe at preferred range instead of standing still.
var _strafe_sign: float = 1.0
var _strafe_cd: float = 0.0
var _visual_root: Node3D ## Rig/Model node nudged for the hit-flinch.
var _visual_base: Vector3
var _visual_base_rot: Vector3
var _flinch: float = 0.0
var _stagger: float = 0.0 ## 0..1 visual reel from a staggering hit.
var _poise: float = 0.0 ## Accumulated recent damage; staggers past stagger_threshold.
var _oil_cd: float = 0.0 ## Throttle so rapid fire doesn't spawn an oil burst every tick.
var _alerted: bool = false ## True once this enemy has reacted to first spotting the player.
var _overload_light: OmniLight3D = null ## Flickering red core glow during a last stand.
var _overload_t: float = 0.0
var _scan_timer: float = 0.0
var _scan_dir: float = 1.0
var _has_last_known: bool = false
var _stuck_time: float = 0.0 ## Seconds spent commanded to move but barely moving (wall-pinned).

# Hit-flash: a per-instance overlay so we never mutate the shared .tres materials.
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween

func _ready() -> void:
	hp.max_health = max_health
	hp.current_health = max_health
	hp.died.connect(_on_died)
	hp.damaged.connect(_on_damaged)
	# Mark this type as encountered when it spawns in an actual level (fixes
	# hand-authored level_01, whose roster has no def for the briefing to
	# mark). Gated on a live player so cutscene/briefing actors don't count.
	if get_tree().get_first_node_in_group("player") != null:
		GameState.mark_enemy_seen(_kill_label().to_lower())
	if eye == null:
		eye = get_node_or_null("Eye")
	if muzzle == null:
		muzzle = get_node_or_null("Muzzle")
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 0.6
	_approach_angle = randf() * TAU
	_visual_root = get_node_or_null("Rig")
	if _visual_root == null:
		_visual_root = get_node_or_null("Model")
	if _visual_root:
		_visual_base = _visual_root.position
		_visual_base_rot = _visual_root.rotation
	_collect_meshes(self)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Red damage blink (robots are neutral-toned until hit).
	_flash_mat.albedo_color = Color(1, 0.18, 0.1, 0)
	set_state(State.IDLE)

func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_mesh_instances.append(c)
		_collect_meshes(c)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_state_timer += delta
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	_perceive()
	_run_state(delta)
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_overload(delta)
	_oil_cd = maxf(0.0, _oil_cd - delta)
	_poise = maxf(0.0, _poise - delta * 26.0) # poise regenerates between hits

## Visible recoil hitch (quick nudge) plus the heavier stagger reel (the model
## lurches back and rights itself) on the enemy's model when it's shot.
func _update_hit_react(delta: float) -> void:
	if _visual_root == null:
		return
	if _flinch > 0.0:
		_flinch = maxf(0.0, _flinch - delta * 9.0)
	if _stagger > 0.0:
		_stagger = maxf(0.0, _stagger - delta * 3.0)
	_visual_root.position = _visual_base + Vector3(0.0, -0.04, 0.13) * _flinch + Vector3(0.0, 0.0, 0.25) * _stagger
	# Reel backward (lean about X) when staggered.
	_visual_root.rotation = _visual_base_rot + Vector3(-0.5 * _stagger, 0.0, 0.0)

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta

func _perceive() -> void:
	if target == null or not is_instance_valid(target):
		target = _find_player()
	if target and _can_see(target):
		_last_known_target_pos = target.global_position
		_has_last_known = true
	elif target and _heard(target):
		# Sensors keep a rough fix on a close target even without eyes-on, so a
		# chaser that lost the cone (wall-hugging, flanking) re-engages instead
		# of wandering off its stale last-known point.
		_last_known_target_pos = target.global_position
		_has_last_known = true

func _find_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]

## True if a shot hitting at world-Y `world_y` lands on the head (around the eye).
func is_headshot(world_y: float) -> bool:
	var head_y := eye.global_position.y if eye else global_position.y + 1.6
	return absf(world_y - head_y) <= head_radius

func _can_see(t: Node3D) -> bool:
	if eye == null:
		return false
	var to := t.global_position - eye.global_position
	var dist := to.length()
	if dist > sight_range:
		return false
	# Point-blank, the cone doesn't apply: a robot doesn't ignore a target at
	# its shoulder just because its nav heading faces a wall. LOS still must
	# be clear (the raycast below), so this never sees through geometry.
	if dist > close_sense_range:
		var forward := -eye.global_transform.basis.z
		var angle := rad_to_deg(forward.angle_to(to.normalized()))
		if angle > sight_angle_deg * 0.5:
			return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye.global_position, t.global_position + Vector3.UP * 0.8)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	return hit.collider == t or (hit.collider as Node).is_in_group("player")

func set_state(new_state: State) -> void:
	if state == new_state:
		return
	# Leaving the attack state (staggered, lost sight, died) cancels any wind-up
	# in progress so the next attack re-telegraphs cleanly.
	if state == State.ATTACK and new_state != State.ATTACK:
		_telegraphing = false
	state = new_state
	_state_timer = 0.0
	# First contact: announce it with an alert blip + an eye-flare so engagements
	# kick off with punch. Re-arms once the enemy fully disengages to IDLE.
	if new_state == State.IDLE:
		_alerted = false
	elif not _alerted and (new_state == State.CHASE or new_state == State.ALERT or new_state == State.ATTACK):
		_alerted = true
		# Reaction delay before it can open fire on first contact — the window
		# scales with difficulty (easy = slow on the trigger, hard = near-instant).
		_attack_timer = maxf(_attack_timer, reaction_time)
		_alert()
		_alert_allies(22.0, target) # first contact rallies the squad — wider net = more enemies pile in at once
	state_changed.emit(new_state)
	_on_enter_state(new_state)

## Speak a TTS robot voice line of the given category (see AudioBus voice
## clips). Chance-gated here, globally cooldown-gated in AudioBus.
func _speak(category: String, chance: float = 1.0) -> void:
	if not has_node("/root/AudioBus"):
		return
	var ab: Node = get_node("/root/AudioBus")
	if ab.has_method("play_voice_at"):
		var src: Node3D = eye if eye != null else self
		ab.play_voice_at(category, src.global_position, chance)

## Brief reaction the instant this enemy first registers the player: a short
## comms blip and a bright flare at the eye.
func _alert() -> void:
	var src: Node3D = eye if eye != null else self
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("broadcast_blip", src.global_position, -1.0, 1.35)
	# Call the contact out loud — mostly a spotting line, sometimes a taunt.
	_speak("taunt" if randf() < 0.25 else "spot", 0.9)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.18)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.2)
	mat.emission_energy_multiplier = 8.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orb.material_override = mat
	src.add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.35, 0.25)
	light.light_energy = 4.5
	light.omni_range = 5.0
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * 2.4, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.35)
	tw.chain().tween_callback(orb.queue_free)

func _on_enter_state(_s: State) -> void:
	pass

func _run_state(delta: float) -> void:
	match state:
		State.IDLE:
			_state_idle(delta)
		State.PATROL:
			_state_patrol(delta)
		State.ALERT:
			_state_alert(delta)
		State.CHASE:
			_state_chase(delta)
		State.ATTACK:
			_state_attack(delta)
		State.STAGGER:
			_state_stagger(delta)

func _state_idle(delta: float) -> void:
	_decelerate()
	if target == null:
		target = _find_player()
	if target:
		if _can_see(target):
			set_state(State.CHASE)
			return
		if _heard(target):
			# Sensed something close (even from behind) — go investigate.
			set_state(State.ALERT)
			return
	# Slowly sweep its gaze so a stationary guard actually scans for intruders
	# instead of staring blankly in one direction.
	rotation.y += delta * 0.6 * _scan_dir
	_scan_timer += delta
	if _scan_timer > 2.5:
		_scan_timer = 0.0
		_scan_dir = -_scan_dir

func _state_patrol(_delta: float) -> void:
	_state_idle(_delta) # default: same as idle unless overridden

func _state_alert(delta: float) -> void:
	# Turn to face the threat and step toward where it was last sensed, so the
	# enemy closes in / investigates instead of freezing.
	if target:
		if _can_see(target):
			set_state(State.CHASE)
			return
		_face_dir((_last_known_target_pos - global_position) * Vector3(1, 0, 1), delta)
		if _has_last_known and global_position.distance_to(_last_known_target_pos) > 2.0:
			_move_toward(_last_known_target_pos, delta)
		else:
			_decelerate()
	if _state_timer > 6.0:
		set_state(State.IDLE)

## Picks up a nearby target by "sound" — within hearing range, ignoring the
## sight cone — so robots aren't blind to a player flanking or behind them.
func _heard(t: Node3D) -> bool:
	return global_position.distance_to(t.global_position) <= hearing_range

## Rally nearby allies onto a threat so a group engages together instead of one
## at a time. Only wakes idle/unaware robots; already-engaged ones are left be,
## which also keeps the alert from echoing forever.
func _alert_allies(radius: float, threat: Node3D) -> void:
	if threat == null:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self:
			continue
		var ally: EnemyBase = e as EnemyBase
		if ally == null or ally.state == State.DEAD:
			continue
		# Only rouse the unaware; already-engaged robots are left alone, which also
		# stops the alarm from echoing endlessly through the group.
		if ally.state != State.IDLE and ally.state != State.PATROL:
			continue
		if global_position.distance_to(ally.global_position) > radius:
			continue
		ally.target = threat
		ally._last_known_target_pos = threat.global_position
		ally._has_last_known = true
		ally.set_state(State.ALERT)

func _state_chase(delta: float) -> void:
	if target == null:
		set_state(State.IDLE)
		return
	var dist_to_target := global_position.distance_to(target.global_position)
	if _can_see(target) and dist_to_target <= attack_range:
		set_state(State.ATTACK)
		return
	if not _has_last_known and not _can_see(target):
		set_state(State.IDLE)
		return
	# Flank: aim for a point offset around the target by this enemy's angle, so a
	# pack spreads out and pressures from several sides instead of single-file.
	var dest := _last_known_target_pos
	if _can_see(target):
		var ring := maxf(preferred_range * 0.9, 1.0)
		dest = target.global_position + Vector3(cos(_approach_angle), 0.0, sin(_approach_angle)) * ring
	_move_toward(dest, delta)

func _state_attack(delta: float) -> void:
	if target == null or not _can_see(target):
		set_state(State.CHASE)
		return
	_face_target(delta)
	# A melee leap in flight: let the surge carry (don't fight it with the
	# normal spacing logic) so the pounce reads as one committed motion.
	if _lunge_time > 0.0:
		_lunge_time -= delta
		return
	var dist := global_position.distance_to(target.global_position)
	if dist > attack_range * 1.1:
		set_state(State.CHASE)
		return
	if dist < preferred_range * 0.7:
		_move_toward(global_position + (global_position - target.global_position).normalized() * 2.0, delta)
	elif dist > preferred_range * 1.3:
		_move_toward(target.global_position, delta)
	elif combat_strafe:
		_combat_strafe(delta) # circle-strafe at range instead of standing still
	else:
		_decelerate()
	# Wind-up telegraph: charge for telegraph_time (eye flare + whine) so the shot
	# is readable and dodgeable, THEN fire. Units with telegraph_time 0 fire
	# instantly (or telegraph their own way, like the sniper's charged beam).
	if _telegraphing:
		_tele_timer -= delta
		_decelerate() # plant and charge
		if _tele_timer <= 0.0:
			_telegraphing = false
			_perform_attack()
			_attack_timer = attack_cooldown
			_speak("taunt" if randf() < 0.35 else "atk", 0.08)
		return
	if _attack_timer <= 0.0:
		if telegraph_time > 0.0:
			_telegraphing = true
			_tele_timer = telegraph_time
			_begin_telegraph(telegraph_time)
			return
		_perform_attack()
		_attack_timer = attack_cooldown
		# Occasional combat bark mid-fight (cooldown-gated globally).
		_speak("taunt" if randf() < 0.35 else "atk", 0.08)

func _state_stagger(_delta: float) -> void:
	_decelerate()
	if _state_timer > 0.4:
		set_state(State.CHASE if target else State.ALERT)

func _move_toward(dest: Vector3, delta: float) -> void:
	nav_agent.target_position = dest
	var dir: Vector3
	if nav_agent.is_navigation_finished():
		# Either we've genuinely arrived, or no nav path exists yet (navmesh
		# still baking / unreachable point). Distinguish by actual distance and
		# fall back to a straight line so the enemy keeps closing in.
		var flat := dest - global_position
		flat.y = 0.0
		if flat.length() <= nav_agent.target_desired_distance + 0.15:
			_decelerate()
			return
		dir = flat.normalized()
	else:
		var next := nav_agent.get_next_path_position()
		dir = next - global_position
		dir.y = 0.0
		dir = dir.normalized()
	var spd := chase_speed()
	velocity.x = move_toward(velocity.x, dir.x * spd, 20.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, 20.0 * delta)
	_face_dir(dir, delta)
	# Stuck recovery: commanded to move but the body isn't actually going
	# anywhere (pinned on a wall/prop, path point unreachable). After ~0.9s,
	# break out: pick a fresh flank lane, sidestep hard, and force a replan —
	# instead of grinding the wall forever.
	var actual := get_real_velocity()
	if Vector2(actual.x, actual.z).length() < spd * 0.2:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)
	if _stuck_time > 0.9:
		_stuck_time = 0.0
		_approach_angle = randf() * TAU
		var side := Vector3(-dir.z, 0.0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
		velocity += side * spd * 1.3
		if target:
			nav_agent.target_position = target.global_position

## Effective pursuit speed — wounded enemies frenzy and rush faster (up to +45%).
## A near-death robot fighting harder: faster, hungrier, glowing with overload.
func last_stand_active() -> bool:
	return state != State.DEAD and damage_heat >= 0.7

## Effective time between attacks; a cornered enemy fires noticeably faster.
func attack_interval() -> float:
	return attack_cooldown * (0.55 if last_stand_active() else 1.0)

func chase_speed() -> float:
	# Wounded frenzy, with an extra surge once it's making its last stand.
	var frenzy := 1.0 + damage_heat * 0.45
	if last_stand_active():
		frenzy += 0.25
	return move_speed * frenzy

## Pulsing red overload glow that builds while an enemy is in its last stand,
## flickering harder as it nears destruction.
func _update_overload(delta: float) -> void:
	if not last_stand_active():
		if _overload_light != null:
			_overload_light.light_energy = move_toward(_overload_light.light_energy, 0.0, delta * 12.0)
		return
	if _overload_light == null:
		_overload_light = OmniLight3D.new()
		_overload_light.light_color = Color(1.0, 0.2, 0.12)
		_overload_light.omni_range = 4.5
		_overload_light.position = Vector3(0.0, 1.1, 0.0)
		add_child(_overload_light)
	_overload_t += delta
	# Intensity ramps with how close to death it is; flicker quickens late.
	var sev := clampf((damage_heat - 0.7) / 0.3, 0.0, 1.0)
	var flick := 0.6 + 0.4 * sin(_overload_t * (24.0 + sev * 36.0))
	_overload_light.light_energy = (1.5 + sev * 3.5) * flick

## Circle-strafe the target at range: slide sideways while keeping the gun on the
## player, flipping direction now and then. Velocity is set directly (not via
## _move_toward) so the body keeps facing the target while it sidesteps — and the
## RobotModel banks into it. Ranged enemies set `combat_strafe = true`.
func _combat_strafe(delta: float) -> void:
	if target == null:
		_decelerate()
		return
	_strafe_cd -= delta
	if _strafe_cd <= 0.0:
		_strafe_cd = randf_range(1.1, 2.3)
		_strafe_sign = -_strafe_sign
	var to := target.global_position - global_position
	to.y = 0.0
	if to.length() < 0.2:
		_decelerate()
		return
	var right := to.normalized().cross(Vector3.UP)
	var spd := chase_speed() * 0.55
	velocity.x = move_toward(velocity.x, right.x * _strafe_sign * spd, 14.0 * delta)
	velocity.z = move_toward(velocity.z, right.z * _strafe_sign * spd, 14.0 * delta)
	_face_target(delta)

func _decelerate() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 0.8)
	velocity.z = move_toward(velocity.z, 0.0, 0.8)

func _face_target(delta: float) -> void:
	if target == null:
		return
	var dir := target.global_position - global_position
	dir.y = 0
	_face_dir(dir.normalized(), delta)

func _face_dir(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.001:
		return
	var desired_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(turn_speed * delta, 0.0, 1.0))

## Smoothly aim a rig node's local -Z at the current target (head/gun tracking).
## Layered on top of the AnimationPlayer for "alive" enemies that follow you even
## while strafing. Clamped to a cone so it never snaps unnaturally far.
func track_node_to_target(node: Node3D, delta: float, max_yaw_deg: float = 55.0, max_pitch_deg: float = 32.0, speed: float = 7.0) -> void:
	if node == null or target == null or not is_instance_valid(target):
		return
	var parent := node.get_parent() as Node3D
	if parent == null:
		return
	var to: Vector3 = (target.global_position + Vector3.UP * 0.4) - node.global_position
	if to.length_squared() < 0.0009:
		return
	var local := parent.global_transform.basis.inverse() * to
	var yaw := clampf(atan2(-local.x, -local.z), -deg_to_rad(max_yaw_deg), deg_to_rad(max_yaw_deg))
	var flat := Vector2(local.x, local.z).length()
	var pitch := clampf(atan2(local.y, flat), -deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))
	var goal := Quaternion.from_euler(Vector3(pitch, yaw, 0.0))
	node.quaternion = node.quaternion.slerp(goal, clampf(speed * delta, 0.0, 1.0))

# Override in subclasses
func _perform_attack() -> void:
	pass

## An aggressive committed melee strike: an explosive forward-and-up leap at the
## target, synced to the attack animation, with the surge held alive briefly so
## it reads as a pounce instead of a step. Melee subclasses call this from
## _perform_attack (needs attack_lunge_speed > 0).
func _attack_lunge() -> void:
	if target == null or attack_lunge_speed <= 0.0:
		return
	var dir := target.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	velocity.x = dir.x * attack_lunge_speed
	velocity.z = dir.z * attack_lunge_speed
	velocity.y = maxf(velocity.y, 3.0) # a little air — a lunge, not a shuffle
	recoil = 1.0                        # fire the attack/slam clip
	_lunge_time = 0.22                  # let the surge ride past the spacing logic

## True when the enemy has closed to short range on its target — drives a
## visual "enrage" flare (brighter eyes/core) so the aggression reads.
func is_enraged() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if state not in [State.CHASE, State.ATTACK]:
		return false
	return global_position.distance_to(target.global_position) <= preferred_range * 1.4

## Readable enemy name for the kill feed, derived from the script's class_name
## (EnemyAndroid -> "ANDROID").
func _kill_label() -> String:
	var s: Script = get_script()
	var n: String = String(s.get_global_name()) if s else ""
	n = n.replace("Enemy", "")
	var label := n.to_upper() if n != "" else "HOSTILE"
	return ("%s %s" % [elite.to_upper(), label]) if elite != "" else label

## Difficulty-driven inaccuracy cone in degrees (0 = perfectly accurate).
## Lower difficulty widens it so robots aim worse; HARD is dead-on.
func aim_spread_deg() -> float:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.has_method("difficulty_config"):
		return gs.difficulty_config().get("aim_spread_deg", 0.0)
	return 0.0

## Rotate an aim direction by a random angle within the difficulty spread cone,
## plus any per-enemy base scatter (degrees). Ranged enemies call this on fire.
func scatter_aim(dir: Vector3, extra_deg: float = 0.0) -> Vector3:
	var spread := aim_spread_deg() + extra_deg
	if spread <= 0.0:
		return dir
	var axis := Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5)
	if axis.length_squared() < 0.0001:
		axis = Vector3.UP
	return dir.rotated(axis.normalized(), randf() * deg_to_rad(spread)).normalized()

## Spawn the shared muzzle-flash FX at the muzzle. Subclasses call this on fire.
func _muzzle_flash() -> void:
	if muzzle:
		muzzle.add_child(MUZZLE_FLASH.instantiate())

func _play_hit_flash() -> void:
	if _mesh_instances.is_empty() or _flash_mat == null:
		return
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_mat.albedo_color.a = 0.85
	for m in _mesh_instances:
		m.material_overlay = _flash_mat
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.14)
	_flash_tween.tween_callback(_clear_hit_flash)

func _clear_hit_flash() -> void:
	for m in _mesh_instances:
		if is_instance_valid(m):
			m.material_overlay = null

var _shed_stage: int = 0 ## How many armour panels have torn off (one per health threshold).

func _on_damaged(_amount: float, source: Node) -> void:
	if source and source is Node3D:
		_last_known_target_pos = (source as Node3D).global_position
		_has_last_known = true
	if target == null and source and source.is_in_group("player"):
		target = source
	if state in [State.IDLE, State.PATROL, State.ALERT]:
		set_state(State.CHASE)
	# Taking fire from off-screen rallies nearby allies to the shooter too.
	if source and source.is_in_group("player") and source is Node3D:
		_alert_allies(16.0, source as Node3D)
	# Hit reaction: white flash + a backward shove away from the damage source.
	if state == State.DEAD:
		return
	_play_hit_flash()
	# Matching red flare on the model's emission channel + core light.
	var rm := _visual_root as RobotModel
	if rm:
		rm.damage_blink()
	_flinch = 1.0
	_speak("hurt", 0.07)
	var src_pos := global_position
	if source and source is Node3D:
		src_pos = (source as Node3D).global_position
		var away := global_position - src_pos
		away.y = 0.0
		if away.length() > 0.01:
			velocity += away.normalized() * flinch_knockback
	# Oil + spark spray bursting from the wound (throttled for rapid fire).
	if _oil_cd <= 0.0:
		_oil_cd = 0.07
		_spawn_oil_spray(src_pos)
	# Poise: enough damage in quick succession staggers it — interrupting its
	# attack, reeling the body back, and briefly stunning it.
	_poise += _amount
	if _poise >= stagger_threshold and state != State.STAGGER:
		_poise = 0.0
		_stagger = 1.0
		_on_staggered()
		set_state(State.STAGGER)

	# Escalating battle damage: smoke when wounded, sparks when critical, and a
	# rising `damage_heat` (0..1) that subclasses fold into their core/eye glow
	# so the robot visibly overheats as it dies.
	_update_damage_state()

	# Visible dismemberment: each time it drops past a health threshold an armour
	# panel tears off toward the impact, so the chassis degrades as you shoot it
	# (the bigger break-apart happens on death via _spawn_part_debris).
	if hp.max_health > 0.0:
		var frac := hp.current_health / hp.max_health
		var stage := 0
		for thr in [0.66, 0.33]:
			if frac <= thr:
				stage += 1
		if stage > _shed_stage:
			_shed_stage = stage
			var off := global_position - src_pos
			off.y = 0.0
			_shed_panel(off.normalized() if off.length() > 0.01 else Vector3.UP)


## The attack wind-up made visible + audible: a charging energy orb that swells
## at the muzzle/eye over `dur` then pops as the shot releases, plus a rising
## whine. This is the player's cue to dodge (pairs with the dash).
func _begin_telegraph(dur: float) -> void:
	var src: Node3D = muzzle if muzzle != null else (eye if eye != null else self)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("charge", src.global_position, -7.0, randf_range(0.95, 1.08))
	var col := Color(1.0, 0.32, 0.18)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1; sm.height = 0.2; sm.radial_segments = 8; sm.rings = 5
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.9)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	src.add_child(orb)
	orb.scale = Vector3.ONE * 0.3
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.0
	light.omni_range = 3.5
	orb.add_child(light)
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * 1.5, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(light, "light_energy", 4.5, dur)
	tw.tween_property(mat, "emission_energy_multiplier", 9.0, dur)
	tw.set_parallel(false)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(orb.queue_free)

## Called the instant a hit staggers the enemy. Subclasses override to cancel
## in-progress actions (a charging shot, a slam wind-up, …).
func _on_staggered() -> void:
	pass

## A burst of dark oil globules + bright sparks thrown from the wound, arcing
## away from the shooter. Lives on the scene so it trails as the robot moves.
func _spawn_oil_spray(source_pos: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var body_h := 0.9
	if eye:
		body_h = maxf(0.4, (eye.global_position.y - global_position.y) * 0.6)
	var dir := global_position - source_pos
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.BACK
	dir.y = 0.5 # bias upward so it fountains

	# Oil: dark, heavy, gravity-pulled droplets.
	var omesh := SphereMesh.new()
	omesh.radius = 0.05
	omesh.height = 0.1
	omesh.radial_segments = 5
	omesh.rings = 3
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.04, 0.04, 0.05)
	omat.metallic = 0.3
	omat.roughness = 0.5
	omesh.material = omat
	
	var oil_amount := 10
	if GraphicsSettings.gpu_particles_enabled:
		oil_amount = 30
		
	var oil := GraphicsSettings.create_particles(
		oil_amount,
		0.7,
		1.0,
		dir,
		42.0,
		Vector3(0, -14.0, 0),
		2.0,
		5.0,
		0.4,
		1.0,
		omesh
	)
	parent.add_child(oil)
	oil.global_position = global_position + Vector3(0, body_h, 0)

	# Sparks: bright, fast, emissive, short-lived.
	var smesh := BoxMesh.new()
	smesh.size = Vector3(0.025, 0.025, 0.1)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.85, 0.4)
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.7, 0.25)
	smat.emission_energy_multiplier = 5.0
	smesh.material = smat
	
	var sparks_amount := 8
	if GraphicsSettings.gpu_particles_enabled:
		sparks_amount = 24
		
	var sparks := GraphicsSettings.create_particles(
		sparks_amount,
		0.3,
		1.0,
		dir,
		55.0,
		Vector3(0, -18.0, 0),
		4.0,
		9.0,
		0.3,
		0.8,
		smesh
	)
	parent.add_child(sparks)
	sparks.global_position = global_position + Vector3(0, body_h, 0)

	var tree := get_tree()
	if tree:
		var t := tree.create_timer(1.0)
		t.timeout.connect(oil.queue_free)
		t.timeout.connect(sparks.queue_free)

## Progressive damage visuals driven by current health fraction.
func _update_damage_state() -> void:
	if hp.max_health <= 0.0:
		return
	var frac := hp.current_health / hp.max_health
	damage_heat = clampf(1.0 - frac, 0.0, 1.0)
	# Place FX around mid-body using the real (world) eye height, not local.
	var body_h := 0.9
	if eye:
		body_h = maxf(0.4, eye.global_position.y - global_position.y) * 0.6
	# Stage 1 — smoke once wounded.
	if frac <= 0.66 and (_damaged_emitter == null or not is_instance_valid(_damaged_emitter)):
		_damaged_emitter = DAMAGED_FX.instantiate()
		add_child(_damaged_emitter)
		_damaged_emitter.position = Vector3(0, body_h, 0)
	# Stage 2 — sparks when critical.
	if frac <= 0.33 and (_spark_emitter == null or not is_instance_valid(_spark_emitter)):
		_spark_emitter = _make_damage_sparks()
		add_child(_spark_emitter)
		_spark_emitter.position = Vector3(0, body_h * 1.05, 0)


## A small continuous shower of orange sparks for a critically damaged robot.
func _make_damage_sparks() -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.7, 0.25)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	
	var amount := 10
	if GraphicsSettings.gpu_particles_enabled:
		amount = 30
		
	var p := GraphicsSettings.create_particles(
		amount,
		0.5,
		0.0,
		Vector3(0, 1, 0),
		70.0,
		Vector3(0, -16, 0),
		1.5,
		3.5,
		0.15,
		0.4,
		mesh
	)
	if p is CPUParticles3D:
		p.one_shot = false
	elif p is GPUParticles3D:
		p.one_shot = false
	return p


func _on_died(_source: Node) -> void:
	set_state(State.DEAD)
	# Dying gasp — bypasses the global voice cooldown so kills get their payoff.
	_speak("die", 0.45)
	GameState.add_kill(score_value, _kill_label())
	# Satisfying slow-mo crunch on heftier player kills (bosses do their own,
	# bigger one; regular drones/androids stay snappy so swarms don't stutter).
	if _source and _source.is_in_group("player") and score_value >= 200 and score_value < 1000:
		GameState.hit_stop(0.6, 0.1)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	
	# Clean up damage trail
	if _damaged_emitter and is_instance_valid(_damaged_emitter):
		_damaged_emitter.queue_free()
		_damaged_emitter = null
	if _spark_emitter and is_instance_valid(_spark_emitter):
		_spark_emitter.queue_free()
		_spark_emitter = null
	
	# Spawn visual and audio explosion
	var exp_fx := EXPLOSION.instantiate()
	get_parent().add_child(exp_fx)
	exp_fx.global_position = global_position + Vector3.UP * 0.9
	_spawn_part_debris()

	_drop_loot()

	# Lasting scorch mark on the ground where it fell.
	var scorch := ScorchMark.new()
	scorch.radius = clampf(0.9 + score_value / 400.0, 1.0, 2.6)
	get_parent().add_child(scorch)
	scorch.global_position = Vector3(global_position.x, global_position.y - 0.4, global_position.z)

	# Death topple: fall toward where the last shot came from, with a settle bounce,
	# then sink into the ground and shrink away — reads as a felled wreck.
	var dir := Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	if _has_last_known:
		var away := global_position - _last_known_target_pos
		away.y = 0.0
		if away.length() > 0.2:
			dir = away.normalized()
	dir = dir.normalized()
	var pitch: float = dir.z * deg_to_rad(96.0)
	var roll: float = -dir.x * deg_to_rad(96.0)
	var fallen := Vector3(rotation.x + pitch, rotation.y + randf_range(-0.35, 0.35), rotation.z + roll)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation", fallen, 0.45)
	tw.parallel().tween_property(self, "position:y", position.y - 0.1, 0.45)
	# Small settle bounce as it hits the deck.
	tw.tween_property(self, "rotation", fallen - Vector3(pitch, 0, roll) * 0.04, 0.12)
	tw.tween_interval(1.3)
	# Sink through the floor and shrink, then despawn.
	tw.tween_property(self, "position:y", position.y - 2.2, 0.9).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", scale * 0.8, 0.9)
	tw.tween_callback(queue_free)

## Physical wreckage: a handful of armor-plate chunks blasted off the chassis,
## tumbling with real physics and bouncing off the floor before burning out.
## One chunk stays ember-hot so the debris reads in the dark. Bigger robots
## shed more, capped so swarm deaths can't flood the physics server.
func _spawn_part_debris() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var count := clampi(3 + score_value / 120, 3, 8)
	for i in count:
		var chunk := RigidBody3D.new()
		chunk.collision_layer = 0
		chunk.collision_mask = 1 # bounce off the world, ghost through actors
		chunk.mass = 0.4
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := randf_range(0.08, 0.2)
		bm.size = Vector3(s, s * randf_range(0.3, 0.7), s * randf_range(0.8, 1.6))
		var mat := StandardMaterial3D.new()
		if i == 0:
			# The hot piece: a glowing ember chunk straight from the core.
			mat.albedo_color = Color(1.0, 0.4, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.45, 0.15)
			mat.emission_energy_multiplier = 3.0
		else:
			mat.albedo_color = Color(0.18, 0.19, 0.22) * randf_range(0.8, 1.3)
			mat.metallic = 0.7
			mat.roughness = 0.45
		bm.material = mat
		mi.mesh = bm
		chunk.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = bm.size
		cs.shape = shape
		chunk.add_child(cs)
		parent.add_child(chunk)
		chunk.global_position = global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.6, 1.3), randf_range(-0.3, 0.3))
		chunk.linear_velocity = Vector3(randf_range(-4.0, 4.0), randf_range(3.0, 7.0), randf_range(-4.0, 4.0))
		chunk.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
		# Burn out: shrink the visual (never the physics body) after the
		# bounce settles, then free the whole chunk.
		var tw := chunk.create_tween()
		tw.tween_interval(randf_range(1.6, 2.4))
		tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.5).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(chunk.queue_free)

## A single armour panel torn off the chassis at a damage threshold: a flat
## metal plate with a faintly-hot torn edge, flung off toward the impact and
## tumbling to the floor. The running fight's "losing parts" read; the full
## break-apart is _spawn_part_debris on death.
func _shed_panel(toward: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var chunk := RigidBody3D.new()
	chunk.collision_layer = 0
	chunk.collision_mask = 1 # bounce off the world, ghost through actors
	chunk.mass = 0.6
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(randf_range(0.22, 0.34), randf_range(0.04, 0.07), randf_range(0.24, 0.4))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.21, 0.24) * randf_range(0.8, 1.2)
	mat.metallic = 0.75
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.15)
	mat.emission_energy_multiplier = 0.7 # glowing torn edge
	bm.material = mat
	mi.mesh = bm
	chunk.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bm.size
	cs.shape = shape
	chunk.add_child(cs)
	parent.add_child(chunk)
	chunk.global_position = global_position + Vector3(0, randf_range(0.7, 1.2), 0) + toward * 0.3
	chunk.linear_velocity = toward * randf_range(3.0, 6.0) + Vector3(0, randf_range(2.5, 4.5), 0)
	chunk.angular_velocity = Vector3(randf_range(-14, 14), randf_range(-14, 14), randf_range(-14, 14))
	var tw := chunk.create_tween()
	tw.tween_interval(randf_range(2.2, 3.2))
	tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(chunk.queue_free)

## Kills feed the push: supplies ONLY come from enemies — they sometimes leave
## a drop where they fell, anchors (score >= 250) always do — chasing resupply
## into the fight beats retreating for it. Difficulty's pickup_mult scales the
## odds (easy drops more, hard less). Overclock rides the pool as a rare prize,
## mostly off anchors. Weapons and keycards are deliberately NOT in the loot
## pool: those stay where the level placed them.
func _drop_loot() -> void:
	var mult: float = GameState.difficulty_config().get("pickup_mult", 1.0)
	if score_value < 250 and randf() > drop_chance * mult:
		return
	# Rare prize first, then bias toward health when the player is actually
	# hurt, ammo otherwise.
	var overclock_w := 0.18 if score_value >= 250 else 0.04
	var health_w := 0.2
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var d := player.get_node_or_null("Damageable")
		if d and d.max_health > 0.0:
			health_w = lerpf(0.2, 0.6, 1.0 - d.current_health / d.max_health)
	# The rare prize is a coin-flip between OVERCLOCK (damage) and OVERDRIVE
	# (rapid-fire + speed) so both powerups show up across a run.
	var prize: PackedScene = PICKUP_OVERDRIVE if randf() < 0.5 else PICKUP_OVERCLOCK
	var scene := prize if randf() < overclock_w \
			else (PICKUP_HEALTH if randf() < health_w else PICKUP_AMMO)
	var p := scene.instantiate() as Node3D
	get_parent().add_child(p)
	var pos := global_position + Vector3(randf_range(-0.7, 0.7), 0.0, randf_range(-0.7, 0.7))
	# Land it on the floor — fliers die in the air.
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 14.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	pos.y = hit.position.y if not hit.is_empty() else 0.0
	p.global_position = pos
	# Pop in so the drop reads through the explosion.
	p.scale = Vector3.ONE * 0.2
	var ptw := p.create_tween()
	ptw.tween_property(p, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


