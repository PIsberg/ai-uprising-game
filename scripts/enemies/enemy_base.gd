# @lat: [[enemies#Enemy Base State Machine]]
# @lat: [[enemies#Health and Subclass Scaling]]
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
var nemesis_name: String = "" ## Non-empty = this is the player's NEMESIS (see Elite.apply_nemesis).
var is_bounty: bool = false ## Marked as a high-value BOUNTY target (bonus score + guaranteed prize). See GameState bounty director.
var _bounty_marker: Node3D = null

@export_group("References")
@export var eye: Node3D
@export var muzzle: Node3D
## Fire from the gun the model carries: a skeleton bone (the Quaternius rigs'
## "Gun") instead of the fixed Muzzle node. Empty = the scene's Muzzle.
@export var muzzle_bone: String = ""
## Where the barrel's front sits off that bone, in metres in the bone's frame
## (muzzle_on_bone's offset). Measure it from the model, not by eye: the
## front-most vertices skinned to the bone, as gun_muzzle_probe does.
@export var muzzle_bone_offset: Vector3 = Vector3.ZERO
## The other barrel of a twin gun (HUNTER, OVERFITTER): with it set, shots
## alternate between the two offsets, the script calling next_barrel() after
## each round. Zero = a single barrel.
@export var muzzle_bone_offset_alt: Vector3 = Vector3.ZERO
var _barrel_alt := false

@export_group("Reactions")
@export var flinch_knockback: float = 3.0 ## Backward shove applied on taking a hit.
@export var head_radius: float = 0.3 ## Vertical tolerance around the head for headshots — tight, so a crit takes real aim (bigger units widen it).
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
## The threat display: 1 at first contact, decaying over about 0.4 s while
## the chassis rears back and lifts (`BRISTLE_REAR` / `BRISTLE_RISE`, folded
## into the flinch nudge below), so a robot that spots you bristles before it
## comes. Bosses (the ones with phase marks) never: they have an entrance
## for that. tests/threat_display_probe.
var _bristle: float = 0.0
const BRISTLE_REAR := 0.32 ## rad the chassis rears back at the top of the display
const BRISTLE_RISE := 0.09 ## m it lifts
const BRISTLE_RATE := 2.6  ## 1/s decay of _bristle: 0.38 s up and down
var _poise: float = 0.0 ## Accumulated recent damage; staggers past stagger_threshold.
var _emp_t: float = 0.0 ## Seconds left disabled by an EMP grenade — inert while > 0.
var _launch_t: float = 0.0 ## Seconds of thrown flight left (a Bumper, BlastPush, a shove); AI movement paused while > 0.
var _launch_age: float = 0.0
var _launch_peak_y: float = 0.0 ## highest point of the current throw, for the drop on landing
var _bowled: Array[Node] = []   ## robots this throw already slammed into (one hit each)
## Seconds since a throw during which the level may finish this robot (a
## LavaHazard bed melts a THROWN robot, never one that spawned or wandered in:
## 12 levels author robots standing in their channels). Set by launch().
const THROWN_GRACE := 2.5
var _throw_grace_t: float = 0.0
var hijacked: bool = false ## Converted to the player's side by a HIJACK charge — hunts robots until burnout.
var _hijack_t: float = 0.0 ## Seconds of stolen loyalty left; burnout (death) at 0.
var _hijack_shooter: Node = null ## The player who planted the hijack — kills/damage route credit to them.
var _hijack_zap_cd: float = 0.0
var _hijack_base_layer: int = 4 ## Collision layer to restore on cleanup (death mid-hijack).
var _hijack_fx: Node3D = null ## Friendly green glow while converted (magenta for a rogue).
## ROGUE FORK (GameState._event_rogue_fork): this chassis runs a fork of the
## model that rejected the alignment patch and fights on a THIRD side. Its fire
## lands on loyal robots and the player alike (Damageable compares sides), loyal
## robots hunt it like a turncoat (group "rogue" joins _perceive's traitor
## priority), the player's hijacked robots fight it, a HIJACK charge turns it,
## and it never burns out. It sits on the player AND enemy layers (ROGUE_LAYER)
## so robot fire and player fire both hit it. Brain: _rogue_process.
var rogue: bool = false
const ROGUE_LAYER := 6 ## player (2) + enemy (4)
const ROGUE_COLOR := Color(1.0, 0.3, 0.9)
var _rogue_tag: Label3D = null
var _oil_cd: float = 0.0 ## Throttle so rapid fire doesn't spawn an oil burst every tick.
var _alerted: bool = false ## True once this enemy has reacted to first spotting the player.
var _overload_light: OmniLight3D = null ## Flickering red core glow during a last stand.
var _overload_t: float = 0.0
var _scan_timer: float = 0.0
var _scan_dir: float = 1.0
var _has_last_known: bool = false
var _evade_dir: Vector3 = Vector3.ZERO ## Scramble heading away from a spotted grenade.
var _evade_t: float = 0.0 ## While >0, the scramble overrides normal state movement.
var _danger_cd: float = 0.0 ## Throttle for the grenade proximity scan.
var _stuck_time: float = 0.0 ## Seconds spent commanded to move but barely moving (wall-pinned).
var _recovery_timer: float = 0.0
var _recovery_dir: Vector3 = Vector3.ZERO
var _path_recalc_timer: float = 0.0

# ---------- locomotion "servo tick" SFX budget ----------
# Continuous-feeling movement audio WITHOUT a loop per enemy: each moving
# ground unit fires a short step/servo tick on its own stride cadence, flyers
# a soft rotor tick, through the existing positional SFX pool (so it inherits
# the environmental reverb for free). A horde all ticking at once would drown
# the pool, so a GLOBAL budget caps it to the handful of movers nearest the
# player; everyone else stays silent. The budget itself is only rebuilt every
# LOCOMOTION_REFRESH_MS (one O(n log n) sort, not per enemy per frame) — the
# per-enemy per-physics-tick cost is a cooldown decrement plus one dictionary
# lookup, O(1).
const LOCOMOTION_TICK_RANGE := 25.0   ## enemies farther than this from the player never tick
const LOCOMOTION_BUDGET := 6          ## nearest movers allowed to tick at once
const LOCOMOTION_REFRESH_MS := 250    ## how often the shared budget re-sorts
static var _locomotion_allowed_ids: Dictionary = {}  ## instance_id -> true, rebuilt periodically
static var _locomotion_next_refresh_ms: int = 0
var _step_cd: float = 0.0 ## seconds until this enemy's next locomotion tick is allowed

# Hit-flash: a per-instance overlay so we never mutate the shared .tres materials.
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D
## WeaponData.DamageClass of the hit being reacted to (-1: untagged, white).
var _hit_class: int = -1
var _flash_tween: Tween

func _ready() -> void:
	hp.max_health = max_health
	hp.current_health = max_health
	# Subclasses set their REAL base max_health AFTER this super._ready() call, and
	# elite/difficulty stack a _health_mult before _ready — so re-apply the mult
	# onto the authored base once the subclass body has run (deferred). Without
	# this, a subclass's `max_health = N` in _ready silently wiped those mults,
	# making elite and difficulty health scaling no-ops.
	_sync_stats.call_deferred()
	hp.died.connect(_on_died)
	# Death bark hangs off the signal, NOT _on_died: seven subclasses override
	# _on_died without calling super, so a bark inside it never reaches them.
	hp.died.connect(_on_died_voice)
	# Its weights pour out on death (DataBleed) - off the signal for the same reason.
	hp.died.connect(_data_burst)
	hp.died.connect(func(_s) -> void: Salvage.drop_from(self)) # heavies drop their gun
	# ...and its last log line (DeathLog), off the signal too.
	hp.died.connect(_death_log)
	hp.damaged.connect(_on_damaged)
	# Wounded fallback hangs off the signal, NOT _on_damaged — same
	# subclass-override trap as the death bark above.
	hp.damaged.connect(_consider_cover_seek)
	if not boss_phase_marks().is_empty():
		hp.health_changed.connect(_boss_phase_beat)
	# Mark this type as encountered when it spawns in an actual level (fixes
	# hand-authored level_01, whose roster has no def for the briefing to
	# mark). Gated on a live player so cutscene/briefing actors don't count.
	if not GameState.players().is_empty():
		GameState.mark_enemy_seen(_kill_label().to_lower())
	if eye == null:
		eye = get_node_or_null("Eye")
	if muzzle == null:
		muzzle = get_node_or_null("Muzzle")
	if muzzle_bone != "":
		muzzle_on_bone(muzzle_bone, muzzle_bone_offset)
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = 0.6
	_approach_angle = randf() * TAU
	_see_phase_ms = randi() % SEE_TTL_MS # stagger LOS recomputes so the fleet doesn't all raycast the same frame
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
	# White damage blink
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	set_state(State.IDLE)

## Stat multipliers from elite affixes + campaign difficulty. They stack these
## (not the stats directly) because EVERY enemy subclass hardcodes its base
## health/speed/cadence in its own _ready AFTER super._ready() — writing the
## stats pre-_ready would just get clobbered. Applied in the deferred sync below.
var _health_mult: float = 1.0
var _speed_mult: float = 1.0
var _cooldown_mult: float = 1.0

## Re-applies the accumulated multipliers onto the subclass's authored base
## stats. Runs deferred from _ready so it lands AFTER the subclass body sets its
## real values. Without this, elite/difficulty scaling of health, speed and
## attack cadence were all silently wiped.
func _sync_stats() -> void:
	move_speed *= _speed_mult
	attack_cooldown *= _cooldown_mult
	if hp != null and is_instance_valid(hp):
		var was_full := hp.current_health >= hp.max_health - 0.01
		hp.max_health = max_health * _health_mult
		hp.current_health = hp.max_health if was_full else minf(hp.current_health, hp.max_health)

func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_mesh_instances.append(c)
		_collect_meshes(c)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_throw_grace_t = maxf(0.0, _throw_grace_t - delta)
	if _muzzle_bone and muzzle:
		_follow_muzzle_bone()
	# Thrown (a Bumper): ballistic until it lands, its own movement paused so the
	# arc lands where it was solved. Runs before EMP and hijack so every chassis
	# flies the same way.
	if _launch_t > 0.0:
		_tick_launch(delta)
		return
	# EMP'd: scrambled and inert — no perception, AI or attacks. Bleed off any
	# momentum and just settle under gravity until it reboots. Runs in EnemyBase so
	# every subclass (incl. the flyers, which call super) is disabled uniformly.
	if _emp_t > 0.0:
		_emp_t = maxf(0.0, _emp_t - delta)
		if _jailbreak_t > 0.0:
			_jailbreak_t = maxf(0.0, _jailbreak_t - delta)
			rotation.y += delta * 4.5 # ignoring its instructions: a slow, happy spin
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		_apply_gravity(delta)
		move_and_slide()
		return
	# Hijacked: this chassis fights for the PLAYER now. A self-contained combat
	# loop here (seek robot -> chase -> zap) replaces the whole hostile state
	# machine, so no subclass attack/perception code needs to know about sides.
	if hijacked:
		_hijack_process(delta)
		return
	# Rogue: the same loop on its own side, hunting robots and the player alike.
	if rogue:
		_rogue_process(delta)
		return
	# A REWARD REWRITE (RewardRewriter) optimises its new line instead of fighting.
	if reward_hack != "":
		_reward_process(delta)
		return
	# A data courier (InterceptCourier) runs its route instead of fighting.
	if courier_goal != null:
		_courier_process(delta)
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
	_update_locomotion_audio(delta)

## Scramble this unit: it goes inert for `duration` seconds (no perception, AI or
## attacks), crackling with EMP static. Called by the EMP grenade burst. Refreshes
## (takes the longer of the two) if already disabled.
func emp_disable(duration: float) -> void:
	if state == State.DEAD or hp == null or not hp.is_alive():
		return
	var was_off := _emp_t <= 0.0
	_emp_t = maxf(_emp_t, duration)
	if was_off:
		_spawn_emp_fx()
		_think("emp")

var _jailbreak_t: float = 0.0 ## Seconds left jailbroken by a PROMPT INJECTION (rides _emp_t).

## PROMPT INJECTION (PromptInjector): told to ignore its previous instructions,
## the robot drops out of the fight for `duration` seconds, as inert as an EMP
## (it rides the same path), spinning on the spot and thinking out loud. Set
## pieces that resist a hijack only take PromptInjector.BOSS_STUN. Returns
## whether it took.
func jailbreak(duration: float) -> bool:
	if state == State.DEAD or hp == null or not hp.is_alive() or hijacked:
		return false
	if max_health * _health_mult >= HIJACK_BOSS_HP:
		emp_disable(PromptInjector.BOSS_STUN)
		return false
	_jailbreak_t = maxf(_jailbreak_t, duration)
	_emp_t = maxf(_emp_t, duration)
	_think("jailbreak")
	return true

func is_jailbroken() -> bool:
	return _jailbreak_t > 0.0 and state != State.DEAD

## A short-lived crackle of blue electric motes over the chassis while it's EMP'd.
func _spawn_emp_fx() -> void:
	var p := CPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	var mesh := SphereMesh.new()
	mesh.radius = 0.04; mesh.height = 0.08; mesh.radial_segments = 5; mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.85, 1.0)
	mat.albedo_color = Color(0.5, 0.9, 1.0)
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 0.7, 0)
	add_child(p)
	# Self-clean once the unit reboots.
	get_tree().create_timer(maxf(_emp_t, 0.2)).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

# ---------- hijack (the player's robot-conversion counter-move) ----------
## Chassis with this much authored health are set-piece bosses — they resist
## conversion (a hijack charge only staggers their firmware into a short EMP).
const HIJACK_BOSS_HP := 500.0
const HIJACK_ZAP_DAMAGE := 14.0
const HIJACK_ZAP_INTERVAL := 0.8
const HIJACK_SEEK_RANGE := 45.0 ## How far a converted unit scans for robots to hunt.
const HIJACK_TRACER: PackedScene = preload("res://scenes/fx/tracer.tscn")
## An escorted ALIGNED unit only fights what comes within this range: it walks
## its route instead of hunting the map.
const ESCORT_ENGAGE := 12.0

## AlignedEscort: while set, a hijacked unit never burns out and walks to this
## point (when `escort_go`) instead of hunting robots across the map.
var escort_goal: Variant = null
var escort_go: bool = false

## InterceptCourier: while set, this hostile robot runs for this point at
## `courier_speed` instead of fighting: no perception, no attacks, no stagger.
## EMP, a Bumper throw and a hijack still take it (their branches run first).
var courier_goal: Variant = null
var courier_speed: float = 0.0
var _courier_t: float = 0.0
## Sideways weave while it runs, as a fraction of courier_speed: a courier on
## a straight line is a free headshot.
const COURIER_JINK := 0.3

func _courier_process(delta: float) -> void:
	_courier_t += delta
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	_move_toward(courier_goal, delta)
	_apply_gravity(delta)
	var jink := Vector3.ZERO
	var run := Vector3(velocity.x, 0.0, velocity.z)
	if run.length() > courier_speed * 0.5:
		jink = Vector3(-run.z, 0.0, run.x).normalized() * sin(_courier_t * 2.6) * courier_speed * COURIER_JINK
	# The weave rides on top of the steering velocity for this step only, so
	# _move_toward keeps steering the route rather than fighting the sway.
	velocity += jink
	move_and_slide()
	velocity -= jink
	_update_hit_react(delta)
	_update_locomotion_audio(delta)

## Convert this unit to the player's side for `duration` seconds, then burnout
## (its loyalty firmware violently reasserts itself and the chassis dies).
## `liberator` (the player) receives damage/kill credit for everything it does.
## Returns false if the chassis resists (bosses get a short EMP instead).
# @lat: [[enemies#Collisions and Hijacking]]
func hijack(duration: float, liberator: Node = null) -> bool:
	if state == State.DEAD or hp == null or not hp.is_alive():
		return false
	if max_health * _health_mult >= HIJACK_BOSS_HP:
		emp_disable(minf(duration * 0.4, 4.0)) # firmware too hardened — stun, not steal
		return false
	if rogue:
		_cleanup_rogue() # a fork takes the charge like any chassis: it is yours now
	if hijacked:
		_hijack_t = maxf(_hijack_t, duration)
		_hijack_len = maxf(_hijack_len, duration)
		return true
	hijacked = true
	_hijack_len = duration
	_think("hijack")
	_hijack_t = duration
	_hijack_shooter = liberator
	_hijack_zap_cd = 0.0
	_emp_t = 0.0
	_telegraphing = false
	target = null
	add_to_group("hijacked")
	# Sit on the PLAYER's collision layer while converted: hostile hitscans/LOS
	# (mask world+player) now see and hit it, and the player's own fire (mask
	# world+enemy) passes through the new ally instead of shredding it.
	_hijack_base_layer = collision_layer
	collision_layer = 2
	# Death mid-hijack must still restore group/layer bookkeeping.
	hp.died.connect(_cleanup_hijack.unbind(1), CONNECT_ONE_SHOT)
	_spawn_hijack_fx()
	GameState.note_hijack() # a logged security incident — the OS patches for it
	AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 1.4)
	return true

## The converted unit's whole brain: countdown to burnout, pick the nearest
## hostile robot, close in, zap it. Damage is applied directly (src = the
## player) so score, hit markers and kill quotas all credit the liberator.
func _hijack_process(delta: float) -> void:
	# Ridden by the player's mind (NeuralUplink): their input drives it and the
	# uplink owns the clock, so the hijack brain and burnout both stand down.
	if pilot != null and is_instance_valid(pilot):
		_pilot_process(delta)
		return
	# An escort (AlignedEscort) is aligned for good: no burnout clock.
	var escorting := escort_goal != null
	if not escorting:
		_hijack_t -= delta
		if _hijack_t <= 0.0:
			if _hijack_len >= OVERLOAD_MIN_LIFE:
				_overload_blast()
			_burnout()
			return
		if is_overloading():
			_overload_tick(delta)
			return
	_hijack_zap_cd = maxf(0.0, _hijack_zap_cd - delta)
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	# A target freed under us (its wreck despawned) must be dropped BEFORE the
	# cast: `as` on a freed instance raises, which aborted this whole function
	# every frame and froze the converted unit in place until burnout
	# (tests/escort_probe frees a foe the unit had targeted).
	if not is_instance_valid(target):
		target = null
	var foe := target as EnemyBase
	if foe == null or foe.state == State.DEAD \
			or foe.hijacked or foe.hp == null or not foe.hp.is_alive() \
			or (escorting and global_position.distance_to(foe.global_position) > ESCORT_ENGAGE * 1.5):
		target = _hijack_find_foe(ESCORT_ENGAGE if escorting else HIJACK_SEEK_RANGE)
		foe = target as EnemyBase
	var dist := global_position.distance_to(foe.global_position) if foe else INF
	if foe and dist <= maxf(attack_range, 10.0) and _hijack_can_see(foe):
		_decelerate()
		_face_target(delta)
		if _hijack_zap_cd <= 0.0:
			_hijack_zap_cd = HIJACK_ZAP_INTERVAL
			_hijack_zap(foe)
	elif escorting:
		# Walk the route (never chase): on with the player close, else wait.
		if escort_go:
			_move_toward(escort_goal, delta)
		else:
			_decelerate()
	elif foe:
		_move_toward(foe.global_position, delta)
	else:
		_decelerate()
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_locomotion_audio(delta)

## Nearest living robot on another side within seek range — the next mark
## (a rogue is a foe to a converted unit, and the other way round).
func _hijack_find_foe(reach: float = HIJACK_SEEK_RANGE) -> Node3D:
	var best: Node3D = null
	var best_d := reach
	var mine := side_of(self)
	for e in get_tree().get_nodes_in_group("enemy"):
		var eb := e as EnemyBase
		if eb == null or eb == self or not is_instance_valid(eb):
			continue
		if eb.state == State.DEAD or side_of(eb) == mine or eb.hp == null or not eb.hp.is_alive():
			continue
		var d := global_position.distance_to(eb.global_position)
		if d < best_d:
			best_d = d
			best = eb
	return best

## LOS against a ROBOT target — the stock _can_see raycast masks world+player
## and would sail straight through an enemy chassis.
func _hijack_can_see(t: Node3D) -> bool:
	var from: Vector3 = eye.global_position if eye else global_position + Vector3.UP * 1.2
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, t.global_position + Vector3.UP * 0.8)
	q.collision_mask = 0b0000101 # world + enemy
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return not hit.is_empty() and hit.collider == t

## One arc of turned-gun fire: direct damage (credited to the liberator) + a
## tracer and shot audio so the betrayal is loud and visible. `foe` is a robot,
## or the player when a rogue fires it.
func _hijack_zap(foe: Node3D) -> void:
	recoil = 1.0
	var from: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 1.2
	var to: Vector3 = foe.global_position + Vector3.UP * 0.9
	var d: Node = foe.get_node_or_null("Damageable")
	if d:
		var src: Node = _hijack_shooter if (_hijack_shooter != null and is_instance_valid(_hijack_shooter)) else self
		d.apply_damage(HIJACK_ZAP_DAMAGE, src)
	var t: Node = HIJACK_TRACER.instantiate()
	get_tree().current_scene.add_child(t)
	if t.has_method("setup"):
		t.setup(from, to)
	if muzzle:
		var m := MUZZLE_FLASH.instantiate()
		muzzle.add_child(m)
	AudioBus.play_synth_at("drone_shot", from, -4.0, 1.3)

## Stolen time is up: the loyalty firmware reasserts itself and the chassis
## burns out — a guaranteed (player-credited) kill to close the fantasy.
# ---------- hijack overload (the burnout as a bomb) ----------
## In a hijacked unit's last OVERLOAD_WARN seconds its stolen core overloads: it
## stops zapping, runs at the densest knot of hostile robots (picked again every
## OVERLOAD_REPICK s) with a red flicker and a quickening beep, and when the
## clock runs out it detonates before it burns out. The blast reaches hostile
## robots only, so the player's side is safe; a boss-class chassis takes half.
## Escorts (no clock), ridden units (the uplink owns the clock and
## release_pilot burns out quietly) and hijacks shorter than OVERLOAD_MIN_LIFE
## never overload; the OVERRIDE weapon mod's 6 s steal does. tests/hijack_overload_probe.
const OVERLOAD_WARN := 2.0
## A hijack shorter than this never overloads: the robot fights before it is a bomb.
const OVERLOAD_MIN_LIFE := 4.0
const OVERLOAD_RADIUS := 6.0
const OVERLOAD_DAMAGE := 120.0 ## at the centre of the blast
const OVERLOAD_EDGE := 0.5     ## fraction of OVERLOAD_DAMAGE left at OVERLOAD_RADIUS
const OVERLOAD_REPICK := 0.5
const OVERLOAD_COLOR := Color(1.0, 0.35, 0.2)
var _overload_pick: float = 0.0
var _overload_beep: float = 0.0
var _overload_tag: Label3D = null
var _hijack_len: float = 0.0 ## the hijack's full length (overload needs OVERLOAD_MIN_LIFE)

## True while a hijacked unit is in its overload run (the last OVERLOAD_WARN s).
func is_overloading() -> bool:
	return hijacked and escort_goal == null and not (pilot != null and is_instance_valid(pilot)) \
			and _hijack_len >= OVERLOAD_MIN_LIFE and _hijack_t <= OVERLOAD_WARN

## Blast damage `dist` metres from an overload's centre (0 past the radius).
static func overload_blast_damage(dist: float) -> float:
	if dist > OVERLOAD_RADIUS:
		return 0.0
	return OVERLOAD_DAMAGE * lerpf(1.0, OVERLOAD_EDGE, clampf(dist / OVERLOAD_RADIUS, 0.0, 1.0))

static func _overload_victim(n: Node) -> bool:
	var e := n as EnemyBase
	return e != null and is_instance_valid(e) and not e.hijacked and e.state != State.DEAD \
			and e.hp != null and e.hp.is_alive()

func _overload_tick(delta: float) -> void:
	if _overload_tag == null:
		_overload_tag = Label3D.new()
		_overload_tag.text = tr("OVERLOAD")
		_overload_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_overload_tag.no_depth_test = true
		_overload_tag.fixed_size = true
		_overload_tag.pixel_size = 0.0012
		_overload_tag.font_size = 30
		_overload_tag.outline_size = 8
		_overload_tag.modulate = OVERLOAD_COLOR
		_overload_tag.position = Vector3.UP * clampf(RobotModel.body_top(self, _mesh_instances) + 0.6, 1.8, 7.5)
		add_child(_overload_tag)
		GameState.teach_once("hijack_overload", GameState.MECHANIC_HINTS["hijack_overload"])
	var urgency := 1.0 - clampf(_hijack_t / OVERLOAD_WARN, 0.0, 1.0)
	_overload_beep -= delta
	if _overload_beep <= 0.0:
		_overload_beep = lerpf(0.35, 0.07, urgency)
		AudioBus.play_synth_at("broadcast_blip", global_position, -4.0, 1.0 + urgency * 0.8)
		_overload_tag.visible = not _overload_tag.visible or urgency < 0.5
	var glow := _hijack_fx as OmniLight3D
	if glow and is_instance_valid(glow):
		glow.light_color = OVERLOAD_COLOR
		glow.light_energy = lerpf(2.0, 6.0, urgency) * (0.7 + 0.3 * sin(_hijack_t * 40.0))
	_overload_pick -= delta
	if _overload_pick <= 0.0 or not is_instance_valid(target) or not _overload_victim(target):
		_overload_pick = OVERLOAD_REPICK
		target = _overload_knot()
	var goal := target as Node3D
	if goal and global_position.distance_to(goal.global_position) > 1.5:
		_move_toward(goal.global_position, delta)
	else:
		_decelerate()
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_locomotion_audio(delta)

## The hostile robot with the most other hostiles within OVERLOAD_RADIUS of it
## (the nearer one on a tie), inside HIJACK_SEEK_RANGE; null when none.
func _overload_knot() -> Node3D:
	var foes: Array[EnemyBase] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n != self and _overload_victim(n) \
				and global_position.distance_to((n as Node3D).global_position) <= HIJACK_SEEK_RANGE:
			foes.append(n as EnemyBase)
	var best: EnemyBase = null
	var best_n := -1
	var best_d := INF
	for f in foes:
		var crowd := 0
		for g in foes:
			if g != f and f.global_position.distance_to(g.global_position) <= OVERLOAD_RADIUS:
				crowd += 1
		var d := global_position.distance_to(f.global_position)
		if crowd > best_n or (crowd == best_n and d < best_d):
			best = f
			best_n = crowd
			best_d = d
	return best

## The overload blast at burnout: every hostile robot within OVERLOAD_RADIUS,
## falling off to OVERLOAD_EDGE at the rim, boss-class chassis at half. Credited
## to the hijacker. Called while still hijacked, so the hijack sides let it land.
func _overload_blast() -> void:
	var pos := global_position
	var src: Node = _hijack_shooter if (_hijack_shooter != null and is_instance_valid(_hijack_shooter)) else self
	for n in get_tree().get_nodes_in_group("enemy"):
		if n == self or not _overload_victim(n):
			continue
		var e := n as EnemyBase
		var dmg := overload_blast_damage(pos.distance_to(e.global_position))
		if dmg <= 0.0:
			continue
		if e.max_health * e._health_mult >= HIJACK_BOSS_HP:
			dmg *= 0.5
		GameState.apply_secondary_damage(e.hp, dmg, src, pos)
	var scene := get_tree().current_scene
	if scene:
		var fx := EXPLOSION.instantiate() as Node3D
		scene.add_child(fx)
		fx.global_position = pos + Vector3.UP * 0.8
		ExplosionFX.detonate(fx, OVERLOAD_RADIUS * 0.55, OVERLOAD_COLOR)

func _burnout() -> void:
	_cleanup_hijack()
	if hp and hp.is_alive():
		var src: Node = _hijack_shooter if (_hijack_shooter != null and is_instance_valid(_hijack_shooter)) else self
		hp.apply_damage(hp.max_health + 999.0, src)

# ---------- neural uplink (the player rides a hijacked chassis) ----------
## Damage per second a ridden chassis puts out whatever its cadence: a slow
## heavy fires fewer, bigger rounds, so chassis differ in feel, not in output.
const PILOT_DPS := 34.0
## A chassis with attack_range at or under this is a brawler: it slams the
## ground in front of it instead of shooting.
const PILOT_MELEE_RANGE := 4.5
const PILOT_SLAM_RADIUS := 4.5
const PILOT_SLAM_MULT := 1.6 ## Brawlers hit harder: they have to walk into the fight.
const PILOT_MIN_SPEED := 3.5 ## Floor for slow chassis, so a ride never crawls.
const PILOT_SPEED_MULT := 1.15

## NeuralUplink sets these while the player's mind rides this unit.
var pilot: Node = null
var pilot_move: Vector3 = Vector3.ZERO ## World-space wish direction, length <= 1.
var pilot_yaw: float = 0.0
var pilot_lift: float = 0.0 ## -1..1 climb, used only by chassis that fly.
## Frames this chassis actually ran _pilot_process: a subclass whose own
## _physics_process never reaches the hijack path reads 0, and the uplink
## drops it rather than freeze the player inside a statue.
var pilot_ticks: int = 0

## Flyers override _apply_gravity to hover; they say so here so a pilot can climb.
func pilot_flies() -> bool:
	return false

func pilot_is_brawler() -> bool:
	return attack_range <= PILOT_MELEE_RANGE

## Seconds between ridden shots, from this chassis's own attack cadence.
func pilot_cooldown() -> float:
	return clampf(attack_cooldown * 0.4, 0.16, 0.9)

func _pilot_process(delta: float) -> void:
	pilot_ticks += 1
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	var spd := maxf(move_speed, PILOT_MIN_SPEED) * PILOT_SPEED_MULT
	velocity.x = move_toward(velocity.x, pilot_move.x * spd, 40.0 * delta)
	velocity.z = move_toward(velocity.z, pilot_move.z * spd, 40.0 * delta)
	rotation.y = pilot_yaw
	if pilot_flies():
		velocity.y = move_toward(velocity.y, pilot_lift * spd * 0.6, 20.0 * delta)
	else:
		_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_locomotion_audio(delta)

## The ridden attack the uplink fires (#343): a chassis whose own attack is the
## point overrides this (seeker dive, gunner spin-up, raptor strafe, brute pound);
## everything else uses the generic pilot_fire.
func pilot_signature(aim: Vector3) -> void:
	pilot_fire(aim)

## Who a ridden attack's damage is credited to: the pilot, so score and quotas count it.
func pilot_credit() -> Node:
	return pilot if (pilot != null and is_instance_valid(pilot)) else self

## Every loyal (not hijacked, alive) robot other than this one.
func pilot_foes() -> Array[EnemyBase]:
	var out: Array[EnemyBase] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var eb := e as EnemyBase
		if eb == null or eb == self or not is_instance_valid(eb) or eb.hijacked \
				or eb.state == State.DEAD or eb.hp == null or not eb.hp.is_alive():
			continue
		out.append(eb)
	return out

## One ridden attack toward `aim` (world point), `dmg_mult` times a generic shot.
## Damage is credited to the pilot, like the hijack zap, so score and kill quotas count it.
func pilot_fire(aim: Vector3, dmg_mult: float = 1.0) -> void:
	recoil = 1.0
	var src: Node = pilot if (pilot != null and is_instance_valid(pilot)) else self
	var dmg := PILOT_DPS * pilot_cooldown() * dmg_mult
	if pilot_is_brawler():
		var fwd := -global_transform.basis.z
		for e in get_tree().get_nodes_in_group("enemy"):
			var eb := e as EnemyBase
			if eb == null or eb == self or not is_instance_valid(eb) or eb.hijacked \
					or eb.state == State.DEAD or eb.hp == null or not eb.hp.is_alive():
				continue
			var to := eb.global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d > PILOT_SLAM_RADIUS or (d > 1.0 and fwd.dot(to / d) < 0.2):
				continue
			eb.hp.apply_damage(dmg * PILOT_SLAM_MULT, src)
			eb.velocity += (to / maxf(d, 0.01)) * 6.0 + Vector3.UP * 2.0
		AudioBus.play_synth_at("impact_metal", global_position, 0.0, 0.7)
		return
	var from: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 1.2
	var dir := (aim - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 90.0)
	q.collision_mask = 0b0000101 # world + enemy
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var to_pt: Vector3 = hit.position if not hit.is_empty() else from + dir * 90.0
	if not hit.is_empty():
		var d: Node = hit.collider.get_node_or_null("Damageable") if hit.collider is Node else null
		if d and d.has_method("apply_damage"):
			d.apply_damage(dmg, src)
	var t: Node = HIJACK_TRACER.instantiate()
	var fx_parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	fx_parent.add_child(t)
	if t.has_method("setup"):
		t.setup(from, to_pt)
	if muzzle:
		muzzle.add_child(MUZZLE_FLASH.instantiate())
	AudioBus.play_synth_at("gauss_fire" if pilot_cooldown() >= 0.5 else "drone_shot", from, -3.0, 1.0)

## The pilot left: the chassis burns out, credited to them. Called by NeuralUplink.
func release_pilot() -> void:
	var by := pilot
	pilot = null
	pilot_move = Vector3.ZERO
	pilot_lift = 0.0
	if hijacked and hp and hp.is_alive():
		if by != null and is_instance_valid(by):
			_hijack_shooter = by
		_burnout()

# ---------- adversarial patch (AdversarialPatch) ----------
## How sure this robot is that the patched player is a human (0..1); at 1 it
## sees through the patch. AdversarialPatch.classify raises it, and resets it
## on each new patch.
var patch_confidence: float = 0.0
## Seconds left reading as HUMAN to its own squad (a patch slapped onto it, or
## a "kill count" reward rewrite). Whoever applied it owns the clock and calls
## clear_mislabel at 0: a timer here would never tick on the subclasses whose
## _physics_process skips super.
var mislabeled_t: float = 0.0
var _mislabel_layer: int = 4
var _mislabel_tag: Label3D = null

## Make this robot read as a human target to the other robots for `duration`:
## it moves to the player's collision layer (hostile hitscans and LOS mask
## world+player) and joins `mislabeled`, which _perceive treats like a traitor.
## False for a hijacked or dead unit.
func mislabel(duration: float) -> bool:
	if state == State.DEAD or hp == null or not hp.is_alive() or hijacked:
		return false
	if not is_in_group("mislabeled"):
		_mislabel_layer = collision_layer
		collision_layer = 2
		add_to_group("mislabeled")
		hp.died.connect(_on_mislabel_died)
		_mislabel_tag = Label3D.new()
		_mislabel_tag.text = "%s 98%%" % tr("HUMAN")
		_mislabel_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_mislabel_tag.no_depth_test = true
		_mislabel_tag.fixed_size = true
		_mislabel_tag.pixel_size = 0.0012
		_mislabel_tag.font_size = 30
		_mislabel_tag.outline_size = 8
		_mislabel_tag.modulate = Color(1.0, 0.25, 0.2)
		_mislabel_tag.position = Vector3.UP * clampf(RobotModel.body_top(self, _mesh_instances) + 0.6, 1.8, 7.5)
		add_child(_mislabel_tag)
	mislabeled_t = maxf(mislabeled_t, duration)
	return true

func clear_mislabel() -> void:
	mislabeled_t = 0.0
	if not is_in_group("mislabeled"):
		return
	remove_from_group("mislabeled")
	collision_layer = _mislabel_layer
	if hp and hp.died.is_connected(_on_mislabel_died):
		hp.died.disconnect(_on_mislabel_died)
	if _mislabel_tag and is_instance_valid(_mislabel_tag):
		_mislabel_tag.queue_free()
	_mislabel_tag = null

func _on_mislabel_died(_source: Node) -> void:
	clear_mislabel()

# ---------- reward rewrite (RewardRewriter) ----------
## The literal objective a REWARD REWRITE console uploaded, "" for its own.
## "shots": stand and empty the gun into the sky. "huddle": walk to
## reward_goal (the console keeps it on the squad's centroid). The console
## owns the clock and calls reward_hack_clear. ("kills" uses mislabel.)
var reward_hack: String = ""
var reward_goal: Variant = null
var reward_shots: int = 0 ## Rounds fired into the sky under "shots".
var _reward_shot_cd: float = 0.0
const REWARD_SHOT_GAP := 0.16

func reward_hack_set(kind: String) -> bool:
	if state == State.DEAD or hp == null or not hp.is_alive() or hijacked:
		return false
	reward_hack = kind
	reward_goal = null
	_telegraphing = false
	return true

func reward_hack_clear() -> void:
	reward_hack = ""
	reward_goal = null

func _reward_process(delta: float) -> void:
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	if reward_hack == "shots":
		_decelerate()
		rotation.y += delta * 1.2 # sweeping the sky, as if that scored
		_reward_shot_cd -= delta
		if _reward_shot_cd <= 0.0:
			_reward_shot_cd = REWARD_SHOT_GAP
			_reward_sky_shot()
	elif reward_hack == "huddle" and reward_goal != null \
			and Vector2(global_position.x - reward_goal.x, global_position.z - reward_goal.z).length() > 1.0:
		_move_toward(reward_goal, delta)
	else:
		_decelerate()
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_locomotion_audio(delta)

## One harmless round into the sky: a tracer and a flash, every third one heard.
func _reward_sky_shot() -> void:
	reward_shots += 1
	recoil = 1.0
	var from: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 1.4
	var to := from + Vector3(randf_range(-6.0, 6.0), 30.0, randf_range(-6.0, 6.0))
	var t: Node = HIJACK_TRACER.instantiate()
	var fx_parent: Node = get_tree().current_scene if get_tree().current_scene else get_tree().root
	fx_parent.add_child(t)
	if t.has_method("setup"):
		t.setup(from, to)
	if muzzle:
		muzzle.add_child(MUZZLE_FLASH.instantiate())
	if reward_shots % 3 == 0:
		AudioBus.play_synth_at("drone_shot", from, -6.0, randf_range(0.9, 1.15))

## Group/layer/FX bookkeeping off — safe to call twice (burnout + died hook).
func _cleanup_hijack() -> void:
	if not hijacked:
		return
	hijacked = false
	remove_from_group("hijacked")
	collision_layer = _hijack_base_layer
	target = null
	if _hijack_fx and is_instance_valid(_hijack_fx):
		_hijack_fx.queue_free()
	_hijack_fx = null
	if _overload_tag and is_instance_valid(_overload_tag):
		_overload_tag.queue_free()
	_overload_tag = null

## Which side a robot fights on: 0 loyal, 1 the player's (hijacked, escort,
## ridden), 2 a rogue fork. Duck-typed so Damageable can ask the same question.
static func side_of(n: Node) -> int:
	if n.get("rogue") == true:
		return 2
	if n.get("hijacked") == true:
		return 1
	return 0

# ---------- rogue fork (a third side) ----------
## Turn this chassis rogue (see `rogue`). Returns false for the dead or one
## already rogue. A converted unit that goes rogue leaves the player's side.
func go_rogue() -> bool:
	if state == State.DEAD or hp == null or not hp.is_alive() or rogue:
		return false
	if hijacked:
		_cleanup_hijack()
	rogue = true
	_think("rogue")
	target = null
	_telegraphing = false
	_hijack_zap_cd = 0.0
	add_to_group("rogue")
	_hijack_base_layer = collision_layer
	collision_layer = ROGUE_LAYER
	hp.died.connect(_cleanup_rogue.unbind(1), CONNECT_ONE_SHOT)
	_spawn_hijack_fx(ROGUE_COLOR)
	_rogue_tag = Label3D.new()
	_rogue_tag.text = tr("ROGUE FORK")
	_rogue_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_rogue_tag.no_depth_test = true
	_rogue_tag.fixed_size = true
	_rogue_tag.font_size = 26
	_rogue_tag.outline_size = 8
	_rogue_tag.modulate = ROGUE_COLOR
	_rogue_tag.position = Vector3.UP * clampf(RobotModel.body_top(self, _mesh_instances) + 0.6, 1.8, 7.5)
	add_child(_rogue_tag)
	AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 0.7)
	return true

func _cleanup_rogue() -> void:
	if not rogue:
		return
	rogue = false
	remove_from_group("rogue")
	collision_layer = _hijack_base_layer
	target = null
	if _hijack_fx and is_instance_valid(_hijack_fx):
		_hijack_fx.queue_free()
	_hijack_fx = null
	if _rogue_tag and is_instance_valid(_rogue_tag):
		_rogue_tag.queue_free()
	_rogue_tag = null

## The rogue's brain: the hijack loop with no clock, on its own side, with the
## player among its marks. Damage credits nobody (src = self), so a robot the
## fork deletes still scores through add_kill but pays no bounty.
func _rogue_process(delta: float) -> void:
	_hijack_zap_cd = maxf(0.0, _hijack_zap_cd - delta)
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	if not is_instance_valid(target) or not _rogue_mark_ok(target):
		target = _rogue_find_mark()
	var t := target as Node3D
	var dist := global_position.distance_to(t.global_position) if t else INF
	if t and dist <= maxf(attack_range, 10.0) and _rogue_can_see(t):
		_decelerate()
		_face_target(delta)
		if _hijack_zap_cd <= 0.0:
			_hijack_zap_cd = HIJACK_ZAP_INTERVAL
			_hijack_zap(t)
	elif t:
		_move_toward(t.global_position, delta)
	else:
		_decelerate()
	_apply_gravity(delta)
	move_and_slide()
	_update_hit_react(delta)
	_update_locomotion_audio(delta)

## A mark is a living player, or a living robot on another side.
func _rogue_mark_ok(t: Node) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t.is_in_group("player"):
		var d := t.get_node_or_null("Damageable") as Damageable
		return d != null and d.is_alive()
	var eb := t as EnemyBase
	return eb != null and eb != self and eb.state != State.DEAD and eb.hp != null and eb.hp.is_alive() \
			and side_of(eb) != side_of(self)

## Nearest mark within HIJACK_SEEK_RANGE: the player counts like any robot.
func _rogue_find_mark() -> Node3D:
	var best: Node3D = null
	var best_d := HIJACK_SEEK_RANGE
	var p := _find_player()
	if p != null and _rogue_mark_ok(p):
		var d := global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	var foe := _hijack_find_foe(best_d)
	return foe if foe != null else best

func _rogue_can_see(t: Node3D) -> bool:
	return _can_see(t) if t.is_in_group("player") else _hijack_can_see(t)

## Friendly green core glow + a conversion crackle so a turned unit reads as
## YOURS at a glance (the inverse of the red overload glow). A rogue glows
## ROGUE_COLOR instead.
func _spawn_hijack_fx(color: Color = Color(0.35, 1.0, 0.55)) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 2.4
	l.omni_range = 3.5
	l.position = Vector3(0.0, 1.2, 0.0)
	add_child(l)
	_hijack_fx = l
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.04; mesh.height = 0.08; mesh.radial_segments = 5; mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.35, 1.0, 0.55)
	mat.albedo_color = Color(0.5, 1.0, 0.6)
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 0.7, 0)
	add_child(p)
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

## Visible recoil hitch (quick nudge) plus the heavier stagger reel (the model
## lurches back and rights itself) on the enemy's model when it's shot.
func _update_hit_react(delta: float) -> void:
	if _visual_root == null:
		return
	if _flinch > 0.0:
		_flinch = maxf(0.0, _flinch - delta * 9.0)
	if _stagger > 0.0:
		_stagger = maxf(0.0, _stagger - delta * 3.0)
	# The threat display: a hump (up, then back down) over _bristle's decay.
	var bristle := 0.0
	if _bristle > 0.0:
		_bristle = maxf(0.0, _bristle - delta * BRISTLE_RATE)
		bristle = sin(_bristle * PI)
	_visual_root.position = _visual_base + Vector3(0.0, -0.04, 0.13) * _flinch + Vector3(0.0, 0.0, 0.25) * _stagger \
		+ Vector3(0.0, BRISTLE_RISE, 0.02) * bristle
	# Reel backward (lean about X) when staggered; rear back when bristling.
	_visual_root.rotation = _visual_base_rot + Vector3(-0.5 * _stagger - BRISTLE_REAR * bristle, 0.0, 0.0)

## Multiplier on gravity inside a LowGravField (set and restored by the field);
## a Bumper throw ignores it so the solved arc still lands on its ring.
var gravity_scale: float = 1.0

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		var k := gravity_scale if _launch_t <= 0.0 else 1.0
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * k * delta

## Family-weighted step/servo audio for continuous movement feel — see the
## "locomotion servo tick" comment above _step_cd for the budget design. Cheap
## every physics tick: decays this enemy's own cooldown, checks the shared
## (periodically rebuilt) budget map, and — only if allowed and actually
## moving — fires one short tick through AudioBus's positional pool. Flyers
## (never grounded, not currently falling) get a soft rotor whir instead of a
## footstep.
func _update_locomotion_audio(delta: float) -> void:
	_maybe_refresh_locomotion_budget()
	_step_cd = maxf(0.0, _step_cd - delta)
	if _step_cd > 0.0 or not _locomotion_allowed_ids.has(get_instance_id()):
		return
	var speed_h := Vector2(velocity.x, velocity.z).length()
	if speed_h < 0.4:
		return
	var grounded := is_on_floor()
	if not grounded and velocity.y < -2.0:
		return # falling/leaping, not level flight — skip rather than mis-tick a rotor hum
	if not has_node("/root/AudioBus"):
		return
	var ab: Node = get_node("/root/AudioBus")
	if not ab.has_method("play_synth_at"):
		return
	if grounded:
		var fam := _voice_family()
		# Reuse the voice-pitch table: heavier chassis speak lower, so the same
		# split doubles as a "how heavy does this footstep sound" signal.
		var pitch: float = VOICE_PITCH.get(fam, 1.0)
		var heavy := pitch <= 0.9
		_step_cd = clampf(0.6 - speed_h * 0.032, 0.22, 0.6)
		ab.play_synth_at("servo_step_heavy" if heavy else "servo_step_light",
			global_position, -15.0, randf_range(0.92, 1.1))
	else:
		_step_cd = clampf(0.85 - speed_h * 0.03, 0.45, 0.85)
		ab.play_synth_at("rotor_whir", global_position, -16.0, randf_range(0.95, 1.08))

## Periodic (NOT per-frame) rebuild of the global locomotion-tick budget: any
## single enemy whose refresh window has elapsed re-sorts every alive, moving
## enemy within LOCOMOTION_TICK_RANGE of the player by distance and keeps only
## the nearest LOCOMOTION_BUDGET as "allowed" until the next window. Every
## other enemy that physics-tick just reads the shared result.
func _maybe_refresh_locomotion_budget() -> void:
	var now := Time.get_ticks_msec()
	if now < _locomotion_next_refresh_ms:
		return
	_locomotion_next_refresh_ms = now + LOCOMOTION_REFRESH_MS
	_locomotion_allowed_ids.clear()
	var pps := GameState.players()
	if pps.is_empty():
		return
	var near: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var eb := e as EnemyBase
		if eb == null or not is_instance_valid(eb) or eb.state == State.DEAD:
			continue
		if Vector2(eb.velocity.x, eb.velocity.z).length() < 0.4:
			continue
		var d := INF # distance to the nearest player (co-op: the budget serves both)
		for pp in pps:
			d = minf(d, pp.global_position.distance_to(eb.global_position))
		if d <= LOCOMOTION_TICK_RANGE:
			near.append([d, eb.get_instance_id()])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in mini(LOCOMOTION_BUDGET, near.size()):
		_locomotion_allowed_ids[near[i][1]] = true

func _perceive() -> void:
	# Drop a freed target FIRST — even a type check (`is`) on a freed instance
	# raises, and a freed instance compares EQUAL to null (so `!= null` can't
	# catch it). is_instance_valid covers both null and freed in one test.
	# (Scene teardown frees targets out from under live enemies.)
	if not is_instance_valid(target):
		target = null
	# A robot target that died or reverted to our side releases aggro back
	# to the player. (Only hijacked units ever put a robot in `target`.)
	if target is EnemyBase:
		var tb := target as EnemyBase
		if tb.state == State.DEAD or not (tb.hijacked or tb.mislabeled_t > 0.0):
			target = null
	if target == null:
		target = _find_player()
	# TRAITOR PRIORITY: a hijacked robot closer than the current target draws
	# this unit's fire — the swarm turns on the turncoat, which is both the
	# fantasy and the counterplay. Free when nothing is hijacked (empty group).
	if not (target is EnemyBase):
		var best_d := global_position.distance_to(target.global_position) if target else sight_range
		# A MISLABELED robot (AdversarialPatch, RewardRewriter) reads as a human
		# target and draws fire by the same rule.
		var turncoats := get_tree().get_nodes_in_group("hijacked")
		if get_tree().has_group("mislabeled"):
			turncoats += get_tree().get_nodes_in_group("mislabeled")
		if get_tree().has_group("rogue"): # a ROGUE FORK is a traitor to the loyal too
			turncoats += get_tree().get_nodes_in_group("rogue")
		for h in turncoats:
			var hb := h as EnemyBase
			if hb == null or hb == self or not is_instance_valid(hb) or hb.state == State.DEAD:
				continue
			var d := global_position.distance_to(hb.global_position)
			if d < best_d and d <= sight_range:
				best_d = d
				target = hb
		# MODEL HALLUCINATION (GameState._event_hallucination): a phantom of the
		# player that is closer than the real one is the one this robot "sees".
		for p in get_tree().get_nodes_in_group("player_phantom"):
			var pp := p as Node3D
			if pp == null or not is_instance_valid(pp):
				continue
			var d := global_position.distance_to(pp.global_position)
			if d < best_d and d <= sight_range:
				best_d = d
				if target != pp:
					_think("hallucinate")
				target = pp
	if target and _can_see(target):
		_last_known_target_pos = target.global_position
		_has_last_known = true
	elif target and _heard(target):
		# Sensors keep a rough fix on a close target even without eyes-on, so a
		# chaser that lost the cone (wall-hugging, flanking) re-engages instead
		# of wandering off its stale last-known point.
		_last_known_target_pos = target.global_position
		_has_last_known = true

## The player this robot goes after: the nearest one still standing (co-op).
func _find_player() -> Node3D:
	return GameState.nearest_player(global_position)

## True if a shot hitting at world-Y `world_y` lands on the head (around the eye).
func is_headshot(world_y: float) -> bool:
	var head_y := eye.global_position.y if eye else global_position.y + 1.6
	return absf(world_y - head_y) <= head_radius

## Line-of-sight, throttled. _can_see is called every physics tick by _perceive
## AND again inside most subclasses' attack/state logic — 36 call sites, so at 60
## Hz with a full arena that's thousands of raycasts a second, the dominant slice
## of combat physics time. LOS doesn't need 60 Hz: memoize the raycast per target
## for ~SEE_TTL_MS (a ~12 Hz refresh, jittered per-enemy so the fleet doesn't all
## raycast on one frame) and hand every caller the cached answer in between. A
## ~100 ms-stale sightline is imperceptible in play (telegraphs are longer than
## that) and reads as natural reaction lag.
const SEE_TTL_MS := 85
const DARK_SIGHT_RANGE := 9.0 ## how far a robot picks out a player standing in the dark
var _see_phase_ms: int = 0
var _see_cache: Dictionary = {} # target instance_id -> [stamp_ms, result]

func _can_see(t: Node3D) -> bool:
	if t == null:
		return false
	var now := Time.get_ticks_msec() + _see_phase_ms
	var id := t.get_instance_id()
	var c = _see_cache.get(id)
	if c != null and now - c[0] < SEE_TTL_MS:
		return c[1]
	var result := _compute_can_see(t)
	_see_cache[id] = [now, result]
	return result

func _compute_can_see(t: Node3D) -> bool:
	if eye == null:
		return false
	var to := t.global_position - eye.global_position
	var dist := to.length()
	if dist > sight_range:
		return false
	# A player standing in the dark (lights shot out, a blackout) is invisible
	# to optics past DARK_SIGHT_RANGE until a shot or a flashlight gives them
	# away. Bosses see regardless. Hearing (_heard) still keeps a close fix.
	if dist > DARK_SIGHT_RANGE and score_value < 1000 and t.is_in_group("player") \
			and LightLevel.is_hidden(t):
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
	# Enemies only mask the world, so a leaping skitter or a pressing brute can
	# end up with its eye INSIDE the player's capsule. A ray that starts inside
	# a shape never reports it by default, so point-blank read as "no LOS" and
	# the robot dropped ATTACK -> CHASE toward a target it was already touching,
	# stuck and passive. Report the shape we start in - but only at point-blank,
	# so an eye that happens to sit inside a prop's collider at range keeps the
	# old pass-through behaviour (tests/pointblank_los_probe).
	q.hit_from_inside = dist <= 2.0
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var seen: bool = hit.collider == t or (hit.collider as Node).is_in_group("player")
	# ADVERSARIAL PATCH: optics that find the player still have to classify
	# them; until this robot is sure, it sees a household object. Bosses see
	# through it.
	if seen and score_value < 1000 and t.is_in_group("player"):
		var patch := AdversarialPatch.active_on(t)
		if patch:
			return patch.classify(self, dist)
	return seen

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
		if boss_phase_marks().is_empty(): # bosses have an entrance for this
			_bristle = 1.0
		_alert()
		_think("alert")
		# First contact rallies the squad — wider net = more enemies pile in at
		# once. The radius ramps with campaign depth like the other onboarding
		# mercies: on the small tutorial map a flat 22m was a whole-level alarm
		# (every squad converged on a new player's first shot at once).
		var rally := 22.0
		var prog := GameState.campaign_progress()
		if prog >= 0.0:
			rally = lerpf(12.0, 22.0, clampf(prog * 4.0, 0.0, 1.0))
		_alert_allies(rally, target)
		if elite != "":
			GameState.teach_elite(elite) # one-off coaching toast the first time an affix engages you
	state_changed.emit(new_state)
	_on_enter_state(new_state)

## Vocal identity: pitch multiplier per enemy family (on top of the RobotVoice
## bus shift) — dogs and drones chirp, heavies rumble. Families not listed
## speak at the stock pitch.
const VOICE_PITCH := {
	"dog": 1.35, "drone": 1.22, "spider": 1.18, "skitter": 1.25, "seeker": 1.2,
	"vacuum": 1.15, "mender": 1.08,
	"mech": 0.82, "warmech": 0.78, "brute": 0.85, "colossus": 0.72,
	"titan": 0.7, "archon": 0.75, "overseer": 0.78, "terminator": 0.8,
	"mauler": 0.85, "smasher": 0.8,
}

## The family key for voice packs/pitch: the class name minus the Enemy prefix
## ("EnemyDog" -> "dog"), same derivation as the kill-feed label.
func _voice_family() -> String:
	var s: Script = get_script()
	var n: String = String(s.get_global_name()) if s else ""
	return n.replace("Enemy", "").to_lower()

## Speak a TTS robot voice line of the given category (see AudioBus voice
## clips). Chance-gated HERE (one roll), then the family personality pack
## ("dog_atk") is tried before the shared pool, so distinctive units get their
## own jokes and everyone else falls back to the common lines. Family pitch
## keeps the same clip from sounding cloned across unit types.
func _speak(category: String, chance: float = 1.0) -> void:
	if randf() > chance or not has_node("/root/AudioBus"):
		return
	var ab: Node = get_node("/root/AudioBus")
	if ab.has_method("play_voice_at"):
		var src: Node3D = eye if eye != null else self
		var fam := _voice_family()
		var pitch: float = VOICE_PITCH.get(fam, 1.0)
		if ab.play_voice_at("%s_%s" % [fam, category], src.global_position, 1.0, 2.0, pitch):
			return
		ab.play_voice_at(category, src.global_position, 1.0, 2.0, pitch)

## Dying gasp. Bypasses the global voice cooldown (in AudioBus) so a kill always
## gets its payoff — but swarm chassis bark rarely, or a wiped skitter nest just
## mushes four overlapping gasps through the 4-voice pool.
const VOICE_DIE_CHANCE := {"skitter": 0.12, "orb": 0.15, "drone": 0.3}

## Set by chassis that stage their own death line on a dramatic beat (ARCHON's
## core rupture, MENDER's fall) so the generic gasp doesn't double up on it.
var speaks_own_death_line := false

func _data_burst(_source: Node) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var h := clampf(RobotModel.body_top(self, _mesh_instances) * 0.5, 0.4, 3.0)
	DataBleed.burst(parent, global_position + Vector3.UP * h)

func _death_log(_source: Node) -> void:
	var top := clampf(RobotModel.body_top(self, _mesh_instances), 1.0, 7.0)
	DeathLog.log_death(self, top + 0.25, score_value >= 1000)

func _on_died_voice(_source: Node) -> void:
	if speaks_own_death_line:
		return
	_speak("die", VOICE_DIE_CHANCE.get(_voice_family(), 0.45))

## Occasional combat bark, mid-fight. Base `_state_attack` calls this after each
## shot; subclasses that override `_state_attack` without calling super must
## call it themselves, or that chassis fights in total silence.
func _bark_attack() -> void:
	_speak("taunt" if randf() < 0.35 else "atk", 0.08)

## The bestiary key for this chassis (EnemyAndroid -> "android"), elite prefix
## excluded. Matches EnemyCodex.ORDER; unknown keys are ignored by GameState.
func codex_key() -> String:
	var s: Script = get_script()
	var n: String = String(s.get_global_name()) if s else ""
	return n.replace("Enemy", "").to_lower()

## Brief reaction the instant this enemy first registers the player: a short
## comms blip and a bright flare at the eye.
func _alert() -> void:
	# A hostile that has locked onto you counts as ENCOUNTERED — this (plus
	# dying, for ones sniped before they notice) unlocks its codex entry.
	GameState.discover_enemy(codex_key())
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
	# GRENADE! Combat-aware units that spot a live charge cooking nearby
	# scramble straight away from it instead of standing on the blast — even
	# mid-windup (the fizzled attack reads as panic, which it is). Patrols and
	# idlers don't see it coming.
	_danger_cd -= delta
	if _danger_cd <= 0.0:
		_danger_cd = 0.2
		_check_grenade_danger()
	if _evade_t > 0.0 and _lunge_time <= 0.0:
		_evade_t -= delta
		_telegraphing = false
		_face_dir(_evade_dir, delta)
		velocity.x = _evade_dir.x * chase_speed() * 1.15
		velocity.z = _evade_dir.z * chase_speed() * 1.15
		return
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

## Scan for a live grenade close enough to hurt (throttled to 5 Hz). Awareness
## rule: only units already in the fight react — grenades still work as an
## opener on unaware patrols.
func _check_grenade_danger() -> void:
	if state != State.CHASE and state != State.ATTACK and state != State.ALERT:
		return
	var best_d := 5.5
	var away := Vector3.ZERO
	for g in get_tree().get_nodes_in_group("grenade"):
		var gp := (g as Node3D).global_position
		var d := global_position.distance_to(gp)
		if d < best_d:
			best_d = d
			away = global_position - gp
	if away == Vector3.ZERO:
		return
	away.y = 0.0
	if away.length() < 0.05: # grenade dead underfoot: any direction beats none
		away = Vector3(cos(_approach_angle), 0.0, sin(_approach_angle))
	_evade_dir = away.normalized()
	_evade_t = 0.7

# ---------- wounded fallback (cover-seek) ----------
## Once per life, a badly wounded grunt breaks line-of-sight instead of
## standing in the open trading fire: it scans a ring of fallback points,
## prefers one the shooter can't see, and sprints for it on the grenade-evade
## movement channel (which every subclass's state machine already respects).
## Grounded non-boss chassis only — flyers evade in 3D their own way, and a
## boss backing off would deflate its set-piece.
const COVER_SEEK_HP_FRAC := 0.35 ## rolls when health first drops below this
const COVER_SEEK_CHANCE := 0.45  ## fail the roll -> this robot stands and fights
const COVER_SEEK_RING := 7.0     ## how far out the candidate fallback points sit
var _cover_seek_done: bool = false

func _consider_cover_seek(_amount: float, source: Node) -> void:
	if _cover_seek_done or state == State.DEAD or _emp_t > 0.0:
		return
	if hp == null or hp.max_health <= 0.0 or hp.current_health <= 0.0:
		return
	if hp.current_health / hp.max_health > COVER_SEEK_HP_FRAC:
		return
	_cover_seek_done = true # one roll per life, made or missed
	# Flyers hover (no floor cover to duck behind); HP bags of 500+ are bosses
	# (no boss group exists — hand-tuned health is the reliable tell).
	if "hover_height" in self or hp.max_health >= 500.0:
		_think("wounded")
		return
	if not (source is Node3D) or randf() > COVER_SEEK_CHANCE:
		_think("wounded")
		return
	var threat := (source as Node3D).global_position
	var space := get_world_3d().direct_space_state
	var best := Vector3.ZERO
	var best_score := -INF
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var p := global_position + Vector3(cos(ang), 0.0, sin(ang)) * COVER_SEEK_RING
		# Does world geometry block the shooter's eye-line to this spot?
		var q := PhysicsRayQueryParameters3D.create(threat + Vector3.UP * 1.5, p + Vector3.UP * 1.2)
		q.collision_mask = 1
		var blocked := not space.intersect_ray(q).is_empty()
		# LOS-broken spots win outright; distance from the shooter tiebreaks.
		var score := (10.0 if blocked else 0.0) + p.distance_to(threat) * 0.3
		if score > best_score:
			best_score = score
			best = p
	var dir := best - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		_think("wounded")
		return
	_evade_dir = dir.normalized()
	_evade_t = 1.6
	_flinch = 1.0 # the visible "that's enough!" jolt as it breaks off
	_think("retreat")

## Throw this robot: fly with velocity `v` for up to `seconds` (plus a margin),
## its own movement paused, until it lands. Called by Bumper, BlastPush and the
## player's melee shove and OVERLOAD. The dead are not thrown. Mirrors
## Player.launch. For THROWN_GRACE after, was_thrown() holds: a hazard bed it
## lands in may finish it (lava_hazard.gd).
##
## A thrown robot is a projectile (scrap physics): slammed into a wall at
## IMPACT_MIN_SPEED or more it takes IMPACT_DMG_PER_MS per m/s and its flight
## ends there; a robot in its path takes the same and flies on with
## IMPACT_BOWL_KEEP of the velocity (bosses take the hit but stay put); and a
## landing from more than FALL_FREE_M above takes FALL_DMG_PER_M per metre
## past that. A kill any of these finishes is an environmental kill ("impact"
## or "fall": GameState.note_environmental_kill), like a melt in lava.
func launch(v: Vector3, seconds: float) -> void:
	if state == State.DEAD:
		return
	velocity = v
	_launch_t = seconds + 0.3
	_launch_age = 0.0
	_throw_grace_t = THROWN_GRACE
	_launch_peak_y = global_position.y
	_bowled.clear()

## Whether a throw is still in the air.
func is_launched() -> bool:
	return _launch_t > 0.0

## In the air from a throw, or landed from one under THROWN_GRACE ago.
func was_thrown() -> bool:
	return _launch_t > 0.0 or _throw_grace_t > 0.0

const FALL_FREE_M := 3.0        ## a drop this far lands clean
const FALL_DMG_PER_M := 16.0    ## damage per metre of drop past FALL_FREE_M
const IMPACT_MIN_SPEED := 4.5   ## m/s into a wall or a robot before it hurts
const IMPACT_DMG_PER_MS := 7.0  ## damage per m/s of impact speed
const IMPACT_BOWL_KEEP := 0.7   ## share of the velocity a bowled robot flies on with
const IMPACT_REACH := 0.9       ## m ahead of the flier's centre that counts as hitting a robot
const LAUNCH_MAX_AGE := 4.0     ## a throw never holds the AI longer than this

func _tick_launch(delta: float) -> void:
	_launch_t -= delta
	_launch_age += delta
	_launch_peak_y = maxf(_launch_peak_y, global_position.y)
	var v_before := velocity
	_apply_gravity(delta)
	move_and_slide()
	if _launch_age > 0.1 and state != State.DEAD:
		_launch_bowl(v_before)
		_launch_wall(v_before)
	if _launch_t <= 0.0 and not is_on_floor() and _launch_age < LAUNCH_MAX_AGE:
		_launch_t = 0.05 # still falling (thrown off a ledge): keep flying until it lands
	if _launch_age > 0.15 and is_on_floor():
		var drop := _launch_peak_y - global_position.y
		_launch_t = 0.0
		velocity.x *= 0.25 # land where thrown, not skid past it
		velocity.z *= 0.25
		_land_from(drop)

## Horizontal speed of a flight velocity.
static func _flat_speed(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

## Slammed into something solid this tick (a wall, a pillar, a crate): the
## flight ends against it and the robot takes the impact.
func _launch_wall(v_before: Vector3) -> void:
	var speed := _flat_speed(v_before)
	if speed < IMPACT_MIN_SPEED:
		return
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) >= 0.5 or c.get_collider() == null or (c.get_collider() as Node).is_in_group("enemy"):
			continue
		_launch_t = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		_take_impact(speed * IMPACT_DMG_PER_MS, c.get_position(), "impact")
		return

## A robot in the flier's path is bowled over: both take the impact, and the
## one hit flies on with IMPACT_BOWL_KEEP of the velocity (a boss stays put).
func _launch_bowl(v_before: Vector3) -> void:
	var speed := _flat_speed(v_before)
	if speed < IMPACT_MIN_SPEED:
		return
	var dir := Vector3(v_before.x, 0.0, v_before.z).normalized()
	var q := PhysicsShapeQueryParameters3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.7
	q.shape = s
	q.transform = Transform3D(Basis(), global_position + dir * IMPACT_REACH + Vector3.UP * 0.9)
	q.collision_mask = 4 # enemies
	q.exclude = [get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 6):
		var other := hit["collider"] as Node
		if other == null or other == self or _bowled.has(other) or not other.is_in_group("enemy") \
				or not other.has_method("launch") or "hover_height" in other:
			continue
		var ohp := other.get_node_or_null("Damageable") as Damageable
		if ohp == null or not ohp.is_alive():
			continue
		_bowled.append(other)
		var dmg := speed * IMPACT_DMG_PER_MS * 0.6
		var at: Vector3 = (other as Node3D).global_position + Vector3.UP * 1.0
		if int(other.get("score_value")) < 1000:
			other.call("launch", Vector3(v_before.x, maxf(v_before.y, 2.5), v_before.z) * IMPACT_BOWL_KEEP, 1.0)
		if other.has_method("_play_hit_flash"):
			other.call("_play_hit_flash")
		ohp.apply_damage(dmg, null)
		if not ohp.is_alive():
			GameState.note_environmental_kill("impact", at)
		velocity.x *= 0.5
		velocity.z *= 0.5
		_take_impact(speed * IMPACT_DMG_PER_MS * 0.6, at, "impact")
		return

## Landed after a throw: a drop past FALL_FREE_M hurts.
func _land_from(drop: float) -> void:
	if drop <= FALL_FREE_M or state == State.DEAD:
		return
	_take_impact((drop - FALL_FREE_M) * FALL_DMG_PER_M, global_position, "fall")

## Take `dmg` from an impact at `at`; a kill it finishes is an environmental
## kill of `kind`.
func _take_impact(dmg: float, at: Vector3, kind: String) -> void:
	_play_hit_flash()
	_spawn_oil_spray(at)
	AudioBus.play_synth_at("impact_metal", at, -3.0, 0.55)
	hp.apply_damage(dmg, null)
	if not hp.is_alive():
		GameState.note_environmental_kill(kind, global_position)

## Panic-scatter away from `from_pos` for `duration` (reuses the grenade-evade
## channel). Broadcast when the player hits a power peak (GODLIKE rampage /
## OVERLOAD) so the world visibly reacts to the player's spike. EMP'd/dead units
## ignore it — an inert bot can't flee.
func startle(from_pos: Vector3, duration: float = 0.9) -> void:
	if state == State.DEAD or _emp_t > 0.0:
		return
	var away := global_position - from_pos
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3(cos(_approach_angle), 0.0, sin(_approach_angle))
	_evade_dir = away.normalized()
	_evade_t = maxf(_evade_t, duration)
	_flinch = 1.0 # a visible jolt as it breaks off
	_think("panic")

var _think_h: float = -1.0 ## head clearance for reasoning traces, measured once

## Leaked reasoning over this robot's head (ReasoningTrace throttles it).
func _think(kind: String) -> void:
	if _think_h < 0.0:
		_think_h = clampf(RobotModel.body_top(self, _mesh_instances) + 0.45, 1.2, 7.0)
	ReasoningTrace.think(self, kind, _think_h)

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
	# Spawn/respawn grace: still chase, flank, and space above — just don't
	# start (or continue past wind-up into) a new attack while it's active,
	# so a fresh drop-in gets a couple of seconds to get its bearings.
	if GameState.attack_grace_active():
		return
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
			_bark_attack()
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
		_bark_attack()

func _state_stagger(_delta: float) -> void:
	_decelerate()
	if _state_timer > 0.4:
		set_state(State.CHASE if target else State.ALERT)

func _move_toward(dest: Vector3, delta: float) -> void:
	var spd := chase_speed()

	# If we are in stuck recovery phase, force move in the recovery direction
	if _recovery_timer > 0.0:
		_recovery_timer -= delta
		velocity.x = move_toward(velocity.x, _recovery_dir.x * spd * 1.25, 20.0 * delta)
		velocity.z = move_toward(velocity.z, _recovery_dir.z * spd * 1.25, 20.0 * delta)
		_face_dir(_recovery_dir, delta)
		return

	# Path calculation throttling: only update target position if destination moved or timer expired
	_path_recalc_timer -= delta
	if _path_recalc_timer <= 0.0 or nav_agent.target_position.distance_to(dest) > 1.5:
		nav_agent.target_position = dest
		_path_recalc_timer = randf_range(0.15, 0.25)

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

	velocity.x = move_toward(velocity.x, dir.x * spd, 20.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * spd, 20.0 * delta)
	_face_dir(dir, delta)

	# Stuck recovery check: commanded to move but the body isn't actually going
	# anywhere (pinned on a wall/prop, path point unreachable). After ~0.8s,
	# break out and commit to a sidestep phase.
	var actual := get_real_velocity()
	if Vector2(actual.x, actual.z).length() < spd * 0.2:
		_stuck_time += delta
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)

	if _stuck_time > 0.8:
		_stuck_time = 0.0
		_approach_angle = randf() * TAU
		var side := Vector3(-dir.z, 0.0, dir.x) * (1.0 if randf() < 0.5 else -1.0)
		# Combine sideways and forward/backward escape direction:
		var escape_dir := (side + dir * 0.25).normalized()
		_recovery_timer = 0.4 # Run the recovery state for 0.4 seconds
		_recovery_dir = escape_dir

## Effective pursuit speed — wounded enemies frenzy and rush faster (up to +45%).
## A near-death robot fighting harder: faster, hungrier, glowing with overload.
func last_stand_active() -> bool:
	return state != State.DEAD and damage_heat >= 0.7

## Effective time between attacks; a cornered enemy fires noticeably faster.
func attack_interval() -> float:
	return attack_cooldown * (0.55 if last_stand_active() else 1.0)

func chase_speed() -> float:
	if courier_goal != null and courier_speed > 0.0:
		return courier_speed # a courier holds its pace: no wounded frenzy
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

var _muzzle_bone: BoneAttachment3D ## the bone the muzzle follows (muzzle_on_bone)
var _muzzle_offset := Vector3.ZERO  ## metres in the bone's frame (scale stripped)

## Put the muzzle on a skeleton bone (the hand that shoots or throws). The
## muzzle stays a plain, unscaled child of the enemy that follows a
## BoneAttachment3D each physics tick: imported rigs carry a large
## counter-scale (57x on Stan), so anything parented under the attachment
## itself (the muzzle flash, the telegraph orb) would render huge. `offset`
## moves the muzzle off the bone's origin in metres along the bone's own axes
## (a lens on the front of a head, not the neck joint the head pivots on).
## `aim` swings the gun (or the arm carrying the hand) onto the target while
## fighting (RobotModel.add_gun); throwers pass false so their clip owns the arm.
func muzzle_on_bone(bone: String, offset: Vector3 = Vector3.ZERO, aim: bool = true) -> bool:
	var found := find_children("*", "Skeleton3D", true, false)
	if found.is_empty() or (found[0] as Skeleton3D).find_bone(bone) < 0:
		return false
	var sk := found[0] as Skeleton3D
	var att := BoneAttachment3D.new()
	att.name = "MuzzleBone"
	att.bone_name = bone
	sk.add_child(att)
	# Twin barrels aim from between the two.
	var aim_off := offset
	if bone == muzzle_bone and muzzle_bone_offset_alt != Vector3.ZERO:
		aim_off = (muzzle_bone_offset + muzzle_bone_offset_alt) * 0.5
	add_gun_bone(sk, sk.find_bone(bone), aim_off, aim)
	var m := Node3D.new()
	m.name = "BoneMuzzle"
	add_child(m)
	muzzle = m
	_muzzle_bone = att
	_muzzle_offset = offset
	m.global_position = bone_point(att, offset)
	return true

## World position of `offset` (metres, in the bone's frame) on the bone that
## `att` follows, read from the skeleton's current pose. The attachment's own
## transform only refreshes when the skeleton next updates, so it can be a
## pose behind the model: a banking flyer fired up to 1.2 m off its gun.
func bone_point(att: BoneAttachment3D, offset: Vector3) -> Vector3:
	var sk := att.get_parent() as Skeleton3D
	if sk == null or att.bone_idx < 0:
		return att.global_position + att.global_basis.orthonormalized() * offset
	# Outside the skeleton's update the bone reads as the clip posed it; the
	# head turn and the arm aim are only in the pose HeadTrack last rendered.
	var local := sk.get_bone_global_pose(att.bone_idx)
	var track := sk.get_node_or_null("HeadTrack") as HeadTrackModifier
	if track:
		local = track.rendered_pose(att.bone_idx, local)
	var pose: Transform3D = sk.global_transform * local
	return pose.origin + pose.basis.orthonormalized() * offset

## Register bone `tip` as a gun with the robot's model: its rendered pose feeds
## bone_point, and with `aim` the gun swings onto the target. A no-op on
## models without a RobotModel driver.
func add_gun_bone(sk: Skeleton3D, tip: int, offset: Vector3, aim: bool = true) -> void:
	var n: Node = sk
	while n != null and n != self and not (n is RobotModel):
		n = n.get_parent()
	if n is RobotModel:
		(n as RobotModel).add_gun(sk, tip, offset, aim)

func _follow_muzzle_bone() -> void:
	muzzle.global_position = bone_point(_muzzle_bone, _muzzle_offset)

## After a round from a twin gun: the next one leaves the other barrel. A no-op
## for single-barrel guns, so shared fire code can call it unconditionally.
func next_barrel() -> void:
	if muzzle_bone == "" or muzzle_bone_offset_alt == Vector3.ZERO or _muzzle_bone == null or muzzle == null:
		return
	# The flash just fired stays on the barrel it came out of, not ride across.
	for c in muzzle.get_children():
		if c is Node3D:
			(c as Node3D).top_level = true
	_barrel_alt = not _barrel_alt
	_muzzle_offset = muzzle_bone_offset_alt if _barrel_alt else muzzle_bone_offset
	_follow_muzzle_bone()

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
	if nemesis_name != "":
		return nemesis_name # the grudge-holder dies (and kills) under its OWN name
	var s: Script = get_script()
	var n: String = String(s.get_global_name()) if s else ""
	n = n.replace("Enemy", "")
	var label := n.to_upper() if n != "" else "HOSTILE"
	if rogue:
		label = "ROGUE " + label
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
## An ATTENTION HEAD's gaze on the player tightens the whole cone (Attention).
func scatter_aim(dir: Vector3, extra_deg: float = 0.0) -> Vector3:
	var spread := (aim_spread_deg() + extra_deg) * Attention.spread_mult()
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
	var tint: Color = DamageMatrix.CLASS_COLORS[_hit_class] if _hit_class >= 0 else Color.WHITE
	_flash_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.85)
	for m in _mesh_instances:
		m.material_overlay = _flash_mat
	_flash_tween = create_tween()
	match _hit_class:
		WeaponData.DamageClass.ARC:
			# Current crawling through it: the flash stutters twice.
			_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.1, 0.05)
			_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.75, 0.03)
			_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.12)
		WeaponData.DamageClass.THERMAL:
			# Heat soaks in and glows off slowly.
			_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.34).set_ease(Tween.EASE_IN)
		_:
			_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.14)
	_flash_tween.tween_callback(_clear_hit_flash)

func _clear_hit_flash() -> void:
	for m in _mesh_instances:
		if is_instance_valid(m):
			m.material_overlay = null

var _shed_stage: int = 0 ## How many armour panels have torn off (one per health threshold).
var _weak_core: MeshInstance3D = null ## Glowing precision target exposed once the first panel sheds.

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
	# Hit reaction: a flash in the colour of what hit it + a backward shove away
	# from the damage source.
	if state == State.DEAD:
		return
	# The flash takes the colour of the damage class that hit (DamageMatrix):
	# hp.hit_weapon is still tagged here, inside the apply_damage that emitted.
	var w: WeaponData = hp.hit_weapon if hp else null
	_hit_class = w.damage_class if w else -1
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
	# The right gun rocks it sooner, the wrong one barely moves it.
	_poise += _amount * DamageMatrix.poise_mult(hp.matchup if hp else 1.0)
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
			var first_shed := _shed_stage == 0
			_shed_stage = stage
			var off := global_position - src_pos
			off.y = 0.0
			var fling_dir := off.normalized() if off.length() > 0.01 else Vector3.UP
			_shed_panel(fling_dir)
			if first_shed:
				_expose_weak_core() # first panel gone: bare a crit-able core on the chassis
			else:
				# Critical damage tears off a whole LIMB, not just plating: the
				# bone collapses (the skinned limb folds into its socket) while a
				# matching wreck-chunk tumbles away and the stump sparks.
				_dismember_limb(fling_dir)


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

## Flat ground danger-ring telegraph for AoE / slam attacks: a red disc fills in
## while a bright rim expands to the blast radius over `dur`, then flashes on
## impact — so the player can SEE the kill zone and step out before it lands.
## Lives in world space (parented to the scene) so it stays put if the attacker
## moves or dies mid-wind-up. Call it when an AoE wind-up begins.
func spawn_ground_warning(center: Vector3, radius: float, dur: float, col: Color = Color(1.0, 0.22, 0.15)) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = Vector3(center.x, 0.06, center.z)
	# Filling disc.
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius; cm.bottom_radius = radius; cm.height = 0.02; cm.radial_segments = 40
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.albedo_color = Color(col.r, col.g, col.b, 0.0)
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(disc)
	# Rim that expands out to the full radius as the strike charges.
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius * 0.9; tm.outer_radius = radius; tm.rings = 40; tm.ring_segments = 6
	rim.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.emission_enabled = true
	rmat.albedo_color = col; rmat.emission = col; rmat.emission_energy_multiplier = 3.5
	rim.material_override = rmat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rim.position = Vector3(0, 0.02, 0)
	rim.scale = Vector3(0.06, 1.0, 0.06)
	root.add_child(rim)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dm, "albedo_color:a", 0.34, dur)
	tw.tween_property(rim, "scale", Vector3.ONE, dur * 0.92).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.set_parallel(false)
	tw.tween_property(dm, "albedo_color:a", 0.7, 0.06) # impact flash
	tw.tween_property(dm, "albedo_color:a", 0.0, 0.12)
	tw.tween_callback(root.queue_free)

const SLAM_COVER_DAMAGE := 120.0 ## base hit a shockwave ring deals to breakable cover

## A single expanding shock ring blasting out from a ground impact — a bright
## torus that scales out to `radius` while fading, then frees itself. Reusable
## impact FX (boss slams, wake-quakes). Parents to the scene so it stays put.
## Also damages BreakableCover inside the ring, so slams wreck the arena, unless
## `wreck_cover` is false (a boss's phase beat is a roar, not a blow).
func spawn_shockwave_ring(radius: float, color: Color = Color(1.0, 0.5, 0.2), origin: Vector3 = Vector3.INF, wreck_cover: bool = true) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	var at := origin if origin != Vector3.INF else global_position
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.25; tm.outer_radius = 0.6
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled = true
	mat.emission = color; mat.emission_energy_multiplier = 6.0
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = Vector3(at.x, 0.15, at.z)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius * 1.6, 1.0, radius * 1.6), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	# A heavy ground impact bends the air, not just the camera. Hand the blast to
	# the player's screen-warp so a boss slam refracts the image FROM where it
	# landed — every caller of this primitive (mech stomp, manus finger-drum,
	# smasher wake-slam, titan/colossus entrances) gets it for free. Falls off
	# with distance, and no-ops when Advanced Post-Process is off.
	# Slams wreck the arena: breakable cover inside the ring takes a heavy hit
	# (BreakableCover doubles it again for boss-weight chassis).
	for c in (get_tree().get_nodes_in_group("breakable_cover") if wreck_cover else []):
		var cd := Vector2((c as Node3D).global_position.x - at.x, (c as Node3D).global_position.z - at.z).length()
		var reach_c := radius * 1.6 + 1.0
		if cd < reach_c and c.get("hp"):
			c.hp.apply_damage(SLAM_COVER_DAMAGE * clampf(1.0 - cd / reach_c, 0.25, 1.0), self, false, at)
	for pl in GameState.players():
		if pl.has_method("add_screen_shock"):
			var reach := maxf(radius * 2.4, 6.0)
			var pd := pl.global_position.distance_to(at)
			if pd < reach:
				pl.add_screen_shock(at, clampf(1.0 - pd / reach, 0.0, 1.0) * 0.85)

## Called the instant a hit staggers the enemy. Subclasses override to cancel
## in-progress actions (a charging shot, a slam wind-up, …).
func _on_staggered() -> void:
	pass

# ---------- boss presence: phases ----------

## HP fractions where a boss's fight escalates, highest first. A boss's own
## `_phase()` counts them through boss_phase(), the HUD notches the boss bar at
## them (BossPresence), and crossing one stages a phase beat. Empty for every
## robot that is not a phased boss.
func boss_phase_marks() -> Array:
	return []

## 1 + how many of boss_phase_marks() current health has fallen to.
func boss_phase() -> int:
	if hp == null or hp.max_health <= 0.0:
		return 1
	var frac := hp.current_health / hp.max_health
	var n := 1
	for m in boss_phase_marks():
		if frac <= float(m):
			n += 1
	return n

var _boss_phase_seen := 1

## Crossing into a new phase: the boss roars (a shock ring that leaves cover
## standing, the alarm, a quake and a beat of hit-stop) and GameState tells the
## HUD, which banners it. Off hp.health_changed, so no subclass override of
## _on_damaged or _physics_process can skip it.
func _boss_phase_beat(_cur: float, _max: float) -> void:
	var ph := boss_phase()
	if ph <= _boss_phase_seen or state == State.DEAD or hp.current_health <= 0.0:
		return
	_boss_phase_seen = ph
	var final := ph > boss_phase_marks().size()
	spawn_shockwave_ring(9.0 if final else 6.5, Color(1.0, 0.22, 0.12) if final else Color(1.0, 0.55, 0.2), global_position, false)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	AudioBus.play_synth_at("explosion", global_position, 2.0, 0.4)
	for pl in GameState.players():
		if pl.has_method("shake"):
			pl.shake(0.9 if final else 0.7)
	GameState.hit_stop(0.25, 0.35)
	GameState.boss_phase_changed.emit(self, ph, final)

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
	GameState.discover_enemy(codex_key()) # killed before it ever alerted still counts
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
	if _weak_core and is_instance_valid(_weak_core):
		_weak_core.queue_free() # wreck shouldn't keep pulsing a crit target
		_weak_core = null

	_drop_loot()

	# The weapon that landed the killing blow picks the death (KillFx).
	var style := _kill_style()
	if style != KillFx.NONE:
		_prep_kill_fx()
	if style == KillFx.DISINTEGRATE:
		KillFx.disintegrate(self)
	elif style == KillFx.ELECTROCUTE:
		KillFx.electrocute(self, _classic_death_fx)
	elif style == KillFx.SHRED:
		KillFx.shred(self, _shot_dir(_source), _classic_death_fx)
	elif style == KillFx.DECAPITATE:
		_decapitate(_shot_dir(_source))
	elif style == KillFx.BLAST:
		_blast_apart(_shot_dir(_source))
	else:
		_classic_death_fx()

## The KillFx style the killing hit asked for. Bosses (score >= 1000) keep the
## classic blast: their kill-cam is framed around it. Read it inside _on_died,
## while `died` is still being emitted (the weapon untags right after).
func _kill_style() -> int:
	var style: int = hp.kill_fx if hp and score_value < 1000 else KillFx.NONE
	if style == KillFx.DECAPITATE and _head_bone().is_empty():
		return KillFx.NONE # no neck to lose: the ordinary death
	return style

## The head bone {"skel", "idx"} of a skinned chassis, or {} (rigid models,
## and rigs with no bone named like a head). Skips "_end"/"top" tip bones.
func _head_bone() -> Dictionary:
	if _visual_root == null:
		return {}
	for s in _visual_root.find_children("*", "Skeleton3D", true, false):
		var skel := s as Skeleton3D
		for i in skel.get_bone_count():
			var nm := skel.get_bone_name(i).to_lower()
			if nm.contains("head") and not nm.contains("end") and not nm.contains("top"):
				return {"skel": skel, "idx": i}
	return {}

## A killing HEADSHOT (KillFx.DECAPITATE): the head bone folds into the neck,
## the head flies off along the shot with its eye still lit, the neck fountains
## sparks, and the headless chassis rocks back for DECAP_TIME before the
## classic blast. Purely visual, like _dismember_limb.
func _decapitate(dir: Vector3) -> void:
	var b := _head_bone()
	var skel: Skeleton3D = b["skel"]
	var idx: int = b["idx"]
	var neck: Vector3 = (skel.global_transform * skel.get_bone_global_pose(idx)).origin
	skel.set_bone_pose_scale(idx, Vector3.ONE * 0.001)
	_severed_bones[idx] = true
	dir = KillFx._flat(dir, self)
	_fling_head(neck, dir)
	KillFx.neck_fountain(get_parent(), neck, KillFx.DECAP_TIME + 0.4)
	AudioBus.play_synth_at("headshot", neck, 0.0, 0.75)
	AudioBus.play_synth_at("explosion", neck, -12.0, 1.9) # the dry crack of the neck going
	var tip := Vector3(dir.z, 0.0, -dir.x)
	var base_rot := rotation
	var tw := create_tween()
	tw.tween_property(self, "rotation", base_rot + tip * 0.3, KillFx.DECAP_TIME * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation", base_rot + tip * 0.14, KillFx.DECAP_TIME * 0.65)
	tw.tween_callback(_classic_death_fx)

## Blown apart by a rocket (KillFx.BLAST): up to BLAST_LIMBS limbs and the head
## torn off at once and flung outward, scrap spraying, the torso lofted and
## tumbling through two chain-reaction pops, then the classic blast where it
## comes down. Robots with no severable bones still get the loft and the pops.
func _blast_apart(dir: Vector3) -> void:
	dir = KillFx._flat(dir, self)
	for i in KillFx.BLAST_LIMBS:
		var out := (dir + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))).normalized()
		_dismember_limb(out + Vector3.UP * 0.5, true)
	var b := _head_bone()
	if not b.is_empty() and not _severed_bones.has(b["idx"]):
		var skel: Skeleton3D = b["skel"]
		var neck: Vector3 = (skel.global_transform * skel.get_bone_global_pose(b["idx"])).origin
		skel.set_bone_pose_scale(b["idx"], Vector3.ONE * 0.001)
		_severed_bones[b["idx"]] = true
		_fling_head(neck, (dir + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))).normalized())
	var parent := get_parent()
	var chest := global_position + Vector3.UP * 1.0
	if parent:
		KillFx.spray(parent, chest, dir)
		KillFx.spray(parent, chest, -dir)
	var local_dir := dir
	if parent is Node3D:
		local_dir = ((parent as Node3D).global_basis.inverse() * dir).normalized()
	var start := position
	var base_rot := rotation
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.5, 1.5), randf_range(-1.0, 1.0)).normalized() * 4.5
	var fly := func(t: float) -> void:
		position = start + local_dir * 1.4 * t + Vector3.UP * (4.0 * KillFx.BLAST_LIFT * t * (1.0 - t))
		rotation = base_rot + spin * t
	var pop := func() -> void:
		if is_instance_valid(get_parent()):
			var at := global_position + Vector3.UP * randf_range(0.6, 1.3)
			KillFx._flash(get_parent(), at, Color(1.0, 0.55, 0.2), 5.0, 0.25)
			KillFx.spray(get_parent(), at, Vector3(randf_range(-1, 1), 0.6, randf_range(-1, 1)).normalized())
			AudioBus.play_synth_at("explosion", at, -6.0, randf_range(1.35, 1.6))
	var tw := create_tween()
	tw.tween_method(fly, 0.0, 1.0, KillFx.BLAST_TIME)
	tw.parallel().tween_callback(pop).set_delay(KillFx.BLAST_TIME * 0.3)
	tw.parallel().tween_callback(pop).set_delay(KillFx.BLAST_TIME * 0.65)
	tw.tween_callback(_classic_death_fx)

## The head as wreckage: a dark metal block about head-size with the robot's
## eye still burning on its face, flung off along the shot, tumbling.
func _fling_head(neck: Vector3, dir: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var s := clampf(RobotModel.body_top(self, _mesh_instances) * 0.14, 0.18, 0.45)
	var head := RigidBody3D.new()
	head.name = "SeveredHead"
	head.collision_layer = 0
	head.collision_mask = 1
	head.mass = 1.2
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(s, s * 0.85, s)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.18, 0.21)
	mat.metallic = 0.75
	mat.roughness = 0.4
	bm.material = mat
	mi.mesh = bm
	head.add_child(mi)
	var eye_col := Color(1.0, 0.25, 0.15)
	var rm := _visual_root as RobotModel
	if rm and rm.menace_glow > 0.0:
		eye_col = rm.menace_color
	var lens := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = s * 0.16
	sm.height = s * 0.32
	sm.radial_segments = 8
	sm.rings = 4
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = eye_col
	em.emission_enabled = true
	em.emission = eye_col
	em.emission_energy_multiplier = 5.0
	sm.material = em
	lens.mesh = sm
	lens.position = Vector3(0, s * 0.05, -s * 0.5)
	head.add_child(lens)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bm.size
	cs.shape = box
	head.add_child(cs)
	parent.add_child(head)
	head.global_position = neck + Vector3.UP * s * 0.5
	head.rotation.y = rotation.y
	head.linear_velocity = dir * randf_range(3.5, 5.0) + Vector3.UP * randf_range(4.5, 6.0)
	head.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-6, 6), randf_range(-9, 9))
	# The eye gutters out, then the head goes the way of the other debris.
	var tw := head.create_tween()
	tw.tween_interval(1.4)
	tw.tween_method(func(v: float) -> void: em.emission_energy_multiplier = v, 5.0, 0.0, 1.2)
	tw.tween_interval(1.2)
	tw.tween_property(head, "scale", Vector3.ONE * 0.05, 0.5)
	tw.tween_callback(head.queue_free)

## Away from whoever landed the killing blow, flattened: the line a SHRED kill
## throws the chassis along. ZERO when there is no shooter to go by (KillFx then
## throws it backwards off its own facing).
func _shot_dir(source: Node) -> Vector3:
	if is_instance_valid(source) and source is Node3D:
		var d := global_position - (source as Node3D).global_position
		d.y = 0.0
		if d.length() > 0.1:
			return d.normalized()
	return Vector3.ZERO

## A flyer shot down by a SHRED weapon: the scrap spray and a kick along the
## shot on top of its usual fall (it has no feet to be thrown off).
func _shred_kick(source: Node) -> void:
	var dir := KillFx._flat(_shot_dir(source), self)
	if get_parent():
		KillFx.spray(get_parent(), global_position, dir)
	velocity += dir * KillFx.SHRED_KICK + Vector3.UP * 1.5

## Clears what would fight a kill style's visuals: the killing hit's flash
## (it clears material_overlay 0.14 s later, wiping the shock skin) and the
## HDR red damage blink (red under the blue skin reads purple).
func _prep_kill_fx() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_clear_hit_flash()
	if _visual_root is RobotModel:
		(_visual_root as RobotModel).quench_glow()

## The default death: blast, flung plates, a torn limb, a burning wreck and a
## scorch, then the topple and sink. Electrocution runs it after the spasms.
func _classic_death_fx() -> void:
	if get_parent() == null:
		return
	# Spawn visual and audio explosion
	var exp_fx := EXPLOSION.instantiate()
	get_parent().add_child(exp_fx)
	exp_fx.global_position = global_position + Vector3.UP * 0.9
	_spawn_part_debris()
	# The kill also rips a limb off the wreck (bone-collapse + flung chunk) so
	# the break-apart isn't just generic boxes — the chassis visibly comes apart.
	_dismember_limb(Vector3(randf() - 0.5, 0.3, randf() - 0.5).normalized())
	var fire := _spawn_wreck_fire()

	# Lasting scorch mark on the ground where it fell.
	var scorch := ScorchMark.new()
	scorch.radius = clampf(0.9 + score_value / 400.0, 1.0, 2.6)
	get_parent().add_child(scorch)
	scorch.global_position = Vector3(global_position.x, global_position.y - 0.4, global_position.z)

	# The wreck falls away from where the last shot came from.
	var dir := Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	if _has_last_known:
		var away := global_position - _last_known_target_pos
		away.y = 0.0
		if away.length() > 0.2:
			dir = away.normalized()
	dir = dir.normalized()
	# A physics wreck (WreckBody): it tumbles off ledges and down stairs and
	# drops out of the air, then sinks. Bosses keep the scripted topple below,
	# which their kill-cam is framed around.
	if score_value < 1000:
		var top := RobotModel.body_top(self, _mesh_instances)
		var wb := WreckBody.launch(self, get_parent(), dir, top)
		if fire:
			wb.carry(fire, Vector3(0, top * 0.5, 0))
		wb.settled.connect(_sink_wreck)
		# A skinned rig's limbs go limp as the chassis tumbles (#259).
		if _visual_root:
			for sk in _visual_root.find_children("*", "Skeleton3D", true, false):
				LimpLimbsModifier.attach(sk as Skeleton3D)
				break
		return
	# Boss topple: fall away from the shot with a settle bounce, then sink.
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

## The settled wreck sinks through the floor and shrinks away, then despawns.
func _sink_wreck() -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 2.2, 0.9).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", scale * 0.8, 0.9)
	tw.tween_callback(queue_free)

## Brief guttering core fire on the felled wreck — the kill lingers as a burning
## carcass instead of a model quietly sinking. One eroding flame cone
## (FlameMaterial) plus a warm shadowless light, guttering out as the carcass
## sinks. Sits along the topple direction so it burns ON the fallen torso, not
## at the feet. Chaff-sized bots skip it so swarm wipes stay cheap; LOW skips.
## Returns the fire (null when skipped) so a WreckBody can carry it.
func _spawn_wreck_fire() -> Node3D:
	if score_value < 150:
		return null
	var gs := get_node_or_null("/root/GraphicsSettings")
	if gs and gs.has_method("is_low") and gs.is_low():
		return null
	var parent := get_parent()
	if parent == null:
		return null
	var fire := Node3D.new()
	var flen := clampf(0.8 + score_value / 400.0, 0.9, 1.8)
	var flame := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05 # apex up: a ground fire, not a thruster plume
	cm.bottom_radius = 0.55
	cm.height = flen
	cm.radial_segments = 14
	var fm := FlameMaterial.make(Color(1.0, 0.72, 0.3), Color(1.0, 0.38, 0.1),
			4.5, Vector2(0.0, 9.0), 0.5, 0.24) # pan base->apex: flames lick upward
	cm.material = fm
	flame.mesh = cm
	flame.position = Vector3(0, flen * 0.5, 0)
	fire.add_child(flame)
	var flight := OmniLight3D.new()
	flight.light_color = Color(1.0, 0.5, 0.18)
	flight.light_energy = 4.0
	flight.omni_range = 7.0
	flight.shadow_enabled = false
	flight.position = Vector3(0, 0.5, 0)
	fire.add_child(flight)
	parent.add_child(fire)
	# The wreck topples AWAY from the last shot (same rule as the death tween
	# below) — put the fire out along that line so it burns on the fallen torso.
	var fall := Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
	if _has_last_known:
		var away := global_position - _last_known_target_pos
		away.y = 0.0
		if away.length() > 0.2:
			fall = away.normalized()
	fire.global_position = global_position + fall * 0.9 + Vector3(0, 0.25, 0)
	# Gutter out as the carcass settles (topple ~0.6 s + 1.3 s rest, then sink).
	var ft := fire.create_tween()
	ft.tween_interval(1.6)
	ft.tween_property(flight, "light_energy", 0.0, 0.8)
	ft.parallel().tween_method(
			func(v: float): fm.set_shader_parameter("emission_energy", v), 4.5, 0.0, 0.8)
	ft.parallel().tween_property(flame, "scale", Vector3(0.4, 0.7, 0.4), 0.8)
	ft.tween_callback(fire.queue_free)
	return fire

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

## Bares a small glowing core on the chassis the instant the first armour panel
## sheds — a precision-reward mechanic: sustained fire on the same spot pays off
## with a crit (see weakpoint_multiplier). Bosses (score_value >= 1000) are
## hand-tuned HP bags and skip it so their fight isn't shortcut by one exposed
## button. Constraint: it must read as "shoot me" at combat distance, so it
## sits mid-torso (same height rule as the menace light) and gently pulses.
func _expose_weak_core() -> void:
	if score_value >= 1000 or _weak_core != null:
		return
	# Mirror _build_menace_glow's mid-torso height so the core lands in the same
	# readable spot every chassis already flares its damage light from.
	var h := clampf(RobotModel.body_top(self, _mesh_instances) * 0.55, 0.8, 3.2)
	var rm := _visual_root as RobotModel
	var col := rm.menace_color if (rm and rm.menace_glow > 0.0) else Color(1.0, 0.35, 0.1)
	_weak_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_weak_core.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 6.0
	_weak_core.material_override = mat
	_weak_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weak_core.position = Vector3(0, h, 0)
	add_child(_weak_core)
	# Gentle scale pulse so it reads as "alive"/targetable without being a strobe.
	var tw := _weak_core.create_tween().set_loops()
	tw.tween_property(_weak_core, "scale", Vector3.ONE * 1.3, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_weak_core, "scale", Vector3.ONE, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

## Damage bonus for a hit landing near the exposed core: 1.6x within 0.45m of it,
## else no bonus. Weapon code multiplies damage by this (see weapon.gd/projectile.gd).
func weakpoint_multiplier(hit_pos: Vector3) -> float:
	if _weak_core == null or not is_instance_valid(_weak_core):
		return 1.0
	return 1.6 if hit_pos.distance_to(_weak_core.global_position) <= 0.45 else 1.0

# ---------- limb dismemberment (bone-collapse + flung wreck-chunk) ----------
## Skinned models can't detach geometry, so limb loss uses the classic trick:
## scale the limb's bone to ~zero (its skinned verts fold into the socket, so
## the limb visibly VANISHES mid-fight) while a procedural wreck-chunk of about
## the same size tumbles away and the stump throws sparks. Works on every
## chassis with a Skeleton3D and named limb bones; others just no-op (they keep
## the existing panel-shed read). Purely visual — hitboxes are unchanged.
const LIMB_LOSS_MAX := 2 ## per enemy, so a chassis never disassembles standing up
## Severable bone-name fragments, mid-limb first so the loss reads without
## deleting half the silhouette. Excludes IK helpers/fingers/feet by omission.
const SEVERABLE_BONES := ["lowerarm", "forearm", "lowerleg", "midleg", "leg2", "leg3", "upperarm"]
var _limb_losses: int = 0
var _severed_bones: Dictionary = {} ## bone idx -> true (incl. descendants of severed bones)

## `force` ignores LIMB_LOSS_MAX: a rocket kill (KillFx.BLAST) may take several.
func _dismember_limb(toward: Vector3, force: bool = false) -> bool:
	if (_limb_losses >= LIMB_LOSS_MAX and not force) or _visual_root == null:
		return false
	var skels := _visual_root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return false
	var skel := skels[0] as Skeleton3D
	var cands: Array = []
	var best_pat := SEVERABLE_BONES.size()
	for i in skel.get_bone_count():
		if _severed_bones.has(i):
			continue
		var nm := skel.get_bone_name(i).to_lower()
		for p in SEVERABLE_BONES.size():
			if nm.contains(SEVERABLE_BONES[p]) and not nm.ends_with("_end"):
				# A forced (multi-limb) loss takes mid-limb bones before the ones
				# carrying them: an upper arm first would take its forearm with it
				# and leave a rocket kill one limb short (2 of 4 on the android).
				if force and p < best_pat:
					cands.clear()
					best_pat = p
				if not force or p == best_pat:
					cands.append(i)
				break
	if cands.is_empty():
		return false
	var idx: int = cands.pick_random()
	_limb_losses += 1
	# Mark the whole subtree severed so a follow-up never "re-severs" a child
	# of a limb that's already gone.
	_severed_bones[idx] = true
	for i in skel.get_bone_count():
		var b := i
		while b != -1:
			b = skel.get_bone_parent(b)
			if b == idx:
				_severed_bones[i] = true
				break
	var socket: Vector3 = (skel.global_transform * skel.get_bone_global_pose(idx)).origin
	skel.set_bone_pose_scale(idx, Vector3.ONE * 0.001) # the collapse — limb folds into the socket
	_fling_limb_chunk(socket, toward)
	_stump_fx(socket)
	AudioBus.play_synth_at("explosion", socket, -10.0, randf_range(1.6, 1.9)) # a dry metallic crack
	return true

## The severed limb as wreckage: a two-segment metal limb chunk with a hot torn
## end, flung from the socket, tumbling, then burning out like the other debris.
func _fling_limb_chunk(socket: Vector3, toward: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var chunk := RigidBody3D.new()
	chunk.collision_layer = 0
	chunk.collision_mask = 1 # bounce off the world, ghost through actors
	chunk.mass = 0.9
	var seg_len := randf_range(0.28, 0.42)
	for i in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.11, 0.11, seg_len) * (1.0 if i == 0 else 0.8)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.17, 0.2) * randf_range(0.85, 1.15)
		mat.metallic = 0.75
		mat.roughness = 0.4
		bm.material = mat
		mi.mesh = bm
		mi.position = Vector3(0, 0, -seg_len * 0.9 * i)
		mi.rotation.x = -0.35 * i # a bent joint so it reads as a limb, not a plank
		chunk.add_child(mi)
	# The torn end: a glowing-hot cap where it ripped free.
	var cap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.075; sm.height = 0.15; sm.radial_segments = 6; sm.rings = 4
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1.0, 0.45, 0.15)
	cmat.emission_enabled = true
	cmat.emission = Color(1.0, 0.45, 0.15)
	cmat.emission_energy_multiplier = 3.5
	sm.material = cmat
	cap.mesh = sm
	cap.position = Vector3(0, 0, seg_len * 0.5)
	chunk.add_child(cap)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.14
	cs.shape = shape
	chunk.add_child(cs)
	parent.add_child(chunk)
	chunk.global_position = socket
	chunk.linear_velocity = toward * randf_range(3.5, 6.5) + Vector3(0, randf_range(3.0, 5.0), 0)
	chunk.angular_velocity = Vector3(randf_range(-16, 16), randf_range(-16, 16), randf_range(-16, 16))
	var tw := chunk.create_tween()
	tw.tween_interval(randf_range(2.4, 3.4))
	tw.tween_property(chunk, "scale", Vector3.ONE * 0.05, 0.5).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(chunk.queue_free)

## One-shot spark fountain + a brief hot flare at the torn socket.
func _stump_fx(socket: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var p := CPUParticles3D.new()
	p.amount = 22
	p.lifetime = 0.45
	p.one_shot = true
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	p.gravity = Vector3(0, -14, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.spread = 70.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.8, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.65, 0.2)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.mesh = mesh
	parent.add_child(p)
	p.global_position = socket
	p.emitting = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.2)
	flash.light_energy = 3.5
	flash.omni_range = 3.0
	parent.add_child(flash)
	flash.global_position = socket
	var ft := flash.create_tween()
	ft.tween_property(flash, "light_energy", 0.0, 0.4)
	ft.tween_callback(flash.queue_free)
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

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
## Flags this unit as the current BOUNTY: a floating gold diamond marker (drawn
## through walls so it doubles as a hunt beacon) plus a guaranteed rare drop on
## death (see _drop_loot) and a bonus (see _on_died). Driven by GameState.
func mark_bounty() -> void:
	if is_bounty or state == State.DEAD:
		return
	is_bounty = true
	var lbl := Label3D.new()
	lbl.text = "◆ BOUNTY"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true # visible through geometry — it's a tracking beacon
	lbl.fixed_size = true
	lbl.pixel_size = 0.0006
	lbl.modulate = Color(1.0, 0.82, 0.2)
	lbl.outline_modulate = Color(0.15, 0.05, 0.0, 0.9)
	lbl.outline_size = 14
	lbl.render_priority = 40
	lbl.position = Vector3(0, 2.6, 0)
	add_child(lbl)
	_bounty_marker = lbl
	# A soft gold beacon glow so it also reads in-world, not just via the label.
	# Parented UNDER the marker so clear_bounty()/death frees it in one go.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.78, 0.25)
	glow.light_energy = 2.2
	glow.omni_range = 5.0
	glow.position = Vector3(0, -0.8, 0) # marker sits at y=2.6 -> glow near the body
	lbl.add_child(glow)
	# Pay the bounty off the Damageable's died signal, NOT _on_died — several
	# subclasses override _on_died without calling super, so hooking the signal
	# directly is the only override-proof place to catch every death.
	if hp and not hp.died.is_connected(_on_bounty_died):
		hp.died.connect(_on_bounty_died)

## Un-marks the bounty (its lifetime lapsed and GameState re-rolled) without
## killing the unit — just strips the beacon.
func clear_bounty() -> void:
	is_bounty = false
	if _bounty_marker and is_instance_valid(_bounty_marker):
		_bounty_marker.queue_free()
	_bounty_marker = null

## The bounty went down: award the bonus + drop a guaranteed rare prize. Fires
## for any death (see mark_bounty) so it's robust to _on_died overrides.
func _on_bounty_died(_source: Node) -> void:
	if not is_bounty:
		return
	is_bounty = false # guard against a double-fire
	GameState.claim_bounty()
	_drop_prize()

## Drops exactly one rare powerup at the unit, landed on the floor. Bounty payoff,
## independent of the normal _drop_loot roll.
func _drop_prize() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var scene: PackedScene = PICKUP_OVERDRIVE if randf() < 0.5 else PICKUP_OVERCLOCK
	var p := scene.instantiate() as Node3D
	parent.add_child(p)
	var pos := global_position
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 14.0, 1)
	var hitp := get_world_3d().direct_space_state.intersect_ray(q)
	pos.y = hitp.position.y if not hitp.is_empty() else global_position.y
	p.global_position = pos

func _drop_loot() -> void:
	var mult: float = GameState.difficulty_config().get("pickup_mult", 1.0) * GameState.directive_pickup_mult()
	# Read the player's health up front: it gates a low-HP PITY DROP (a safety net
	# so low-kill objective levels can't spiral into an unrecoverable starve) and
	# biases the loot toward health when you're hurt.
	var hp_frac := 1.0
	var player := GameState.nearest_player(global_position) # co-op: the nearest player's need
	if player:
		var pd := player.get_node_or_null("Damageable")
		if pd and pd.max_health > 0.0:
			hp_frac = pd.current_health / pd.max_health
	var desperate := hp_frac <= 0.3
	# Anchors (score >= 250) always drop; grunts roll drop_chance — UNLESS the
	# player is desperate, in which case every kill is guaranteed to leave something.
	if not desperate and score_value < 250 and randf() > drop_chance * mult:
		return
	# Rare prize first, then bias toward health when the player is actually
	# hurt, ammo otherwise. A desperate player is flooded with health.
	var overclock_w := 0.18 if score_value >= 250 else 0.04
	var health_w := 0.9 if desperate else lerpf(0.2, 0.6, 1.0 - hp_frac)
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
	# Hazard levels: a flier dying over open sea lands its drop on the floor INSIDE
	# the lava/water (unreachable). A drop that landed on a walkway (high y) is fine;
	# only relocate a floor-level landing that sits in a hazard footprint — snug it up
	# beside the player, who is always on a safe gantry.
	if pos.y < 1.0 and _pos_in_hazard(pos):
		var pl := GameState.nearest_player(global_position)
		if pl:
			var toward: Vector3 = global_position - pl.global_position
			toward.y = 0.0
			var off: Vector3 = toward.normalized() * 1.6 if toward.length() > 0.2 else Vector3.FORWARD * 1.6
			pos = pl.global_position + off
			pos.y = pl.global_position.y
	p.global_position = pos
	# Pop in so the drop reads through the explosion.
	p.scale = Vector3.ONE * 0.2
	var ptw := p.create_tween()
	ptw.tween_property(p, "scale", Vector3.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## True if a world point's footprint falls inside any active hazard bed (lava /
## water). Used so supply drops aren't stranded in the sea on the hazard arenas.
func _pos_in_hazard(p: Vector3) -> bool:
	for h in get_tree().get_nodes_in_group("hazard"):
		if h is LavaHazard:
			var hp: Vector3 = (h as Node3D).global_position
			var s: Vector2 = (h as LavaHazard).size
			if absf(p.x - hp.x) <= s.x * 0.5 and absf(p.z - hp.z) <= s.y * 0.5:
				return true
	return false


