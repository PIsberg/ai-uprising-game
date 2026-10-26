class_name EnemyMender
extends EnemyBase
## MENDER — a support flyer that never shoots at you. It hangs back, finds the
## most-wounded robot on the field, and pours a green repair beam into it,
## undoing your damage in real time. While a MENDER is alive a pack heals faster
## than you can whittle it down, so it's a priority kill — which is exactly why
## it flees the moment you close in. Reuses the EyeDrone chassis, tinted teal.
##
## Eye rig (tests/mender_eye_probe). The chassis IS an eye (Enemy_EyeDrone:
## a sphere with a lidded lens on its Body bone, clips Idle/Look/Charging/
## BackFlip/Attack/Hit, no head chain). The beam used to leave a fixed node
## 0.36 m inside the sphere while the lens stared at the horizon, and the
## flee was a drift. Now the sphere pitches on its Body bone to look at
## what it is doing (the ally it mends, the player it runs from;
## BoneSweepModifier), the beam leaves the lens (the Muzzle node put on it each tick from the Body bone's swept pose),
## the iris narrows into the Charging clip's end pose and stays there
## while it mends (RobotModel.hold_pose), and when you close in it
## back-flips away (the BackFlip clip over a burst of speed).

const LENS_OFF := Vector3(0.0, 0.0, 0.8)  ## the lens, in the Body bone's frame (its +Z is the look)
const EYE_RATE := 6.0       ## rad/s the eye pitches onto a target
const EYE_MAX := 0.95       ## rad
const FLIP_CD := 3.5        ## s between back-flips
const FLIP_BURST := 1.6     ## flee speed through the flip

@export var hover_height: float = 3.2
@export var heal_range: float = 15.0
@export var heal_per_sec: float = 16.0
@export var flee_range: float = 9.0

var _hover_phase: float = 0.0
var _heal_target: EnemyBase = null
var _retarget: float = 0.0
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _beam_light: OmniLight3D
var _pulse: float = 0.0
var _repair_cd: float = 0.0
var _sweep: BoneSweepModifier = null
var _eye_pitch: float = 0.0
var _flip_t: float = 0.0
var _flip_cd: float = 0.0
var _focused: bool = false

@onready var _eye_light: OmniLight3D = $Eye/EyeLight

func _ready() -> void:
	speaks_own_death_line = true # staged on its fall, in _on_died
	super._ready()
	max_health = 70.0
	move_speed = 6.2
	sight_range = 64.0          # scans wide for the wounded
	sight_angle_deg = 360.0
	attack_range = heal_range
	preferred_range = heal_range * 0.6
	attack_cooldown = 0.1
	score_value = 170           # worth the bullets to silence it
	head_radius = 0.2
	flinch_knockback = 1.5
	hp.max_health = max_health
	hp.current_health = max_health
	_hover_phase = randf() * TAU
	_build_beam()
	_build_eye()

## The sphere's pitch rides a sweep on the Body bone; the muzzle (the beam's
## root) is put on the lens each tick from the bone's swept pose (the
## skeleton hands the clip's pose back once a frame is drawn, and this rig
## has no head chain for muzzle_on_bone's record to follow).
func _build_eye() -> void:
	var sk := find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null or sk.find_bone("Body") < 0:
		return
	_sweep = BoneSweepModifier.new()
	_sweep.name = "EyeSweep"
	_sweep.body = self
	sk.add_child(_sweep)
	_sweep.sweep("Body", Quaternion.IDENTITY)

## The lens, world space, on the Body bone as swept this frame.
func _lens_point() -> Vector3:
	if _sweep == null:
		return muzzle.global_position if muzzle else global_position
	var sk := _sweep.get_skeleton()
	var pose: Transform3D = sk.global_transform * _sweep.posed("Body")
	return pose.origin + pose.basis.orthonormalized() * LENS_OFF

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, 1.0)   # spans local -Z..+Z; we look_at the target
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = support_color()
	_beam_mat.emission_enabled = true
	_beam_mat.emission = support_color()
	_beam_mat.emission_energy_multiplier = 6.0
	bm.material = _beam_mat
	_beam.mesh = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_beam_light = OmniLight3D.new()
	_beam_light.light_color = support_color()
	_beam_light.light_energy = 0.0
	_beam_light.omni_range = 5.0
	_beam_light.shadow_enabled = false
	add_child(_beam_light)

func _apply_gravity(_delta: float) -> void:
	pass # it floats

## Custom flight + support AI, in place of the base attacker loop: keep distance
## from the player, close on the most-wounded ally, and beam-heal it.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	recoil = move_toward(recoil, 0.0, delta * 9.0)
	_hover_phase += delta * 3.0
	_repair_cd = maxf(0.0, _repair_cd - delta)
	_flip_t = maxf(0.0, _flip_t - delta)
	_flip_cd = maxf(0.0, _flip_cd - delta)
	_update_hit_react(delta)
	_poise = maxf(0.0, _poise - delta * 26.0)

	var player := _find_player()
	target = player

	# Refresh the support target periodically or when it is done with / gone.
	_retarget -= delta
	if _retarget <= 0.0 or _support_stale(_heal_target):
		_retarget = 0.5
		_heal_target = _pick_support_target()

	_fly(player, delta)

	# Beam-support (heal, for a MENDER) if the target is in range; not
	# through a back-flip.
	var healing := false
	var look_at: Variant = null
	if _flip_t <= 0.0 and _heal_target and is_instance_valid(_heal_target) and _heal_target.hp \
			and global_position.distance_to(_heal_target.global_position) <= heal_range + 1.0:
		healing = true
		look_at = _heal_target.global_position + Vector3.UP * 0.6
		_support(_heal_target, delta)
		_focus()
		_show_beam(_lens_point(), _heal_target.global_position + Vector3.UP * 0.6)
	if not healing:
		_hide_beam()
		_unfocus()
		_support_lost()
	if look_at == null and player and global_position.distance_to(player.global_position) < flee_range * 1.5:
		look_at = player.global_position + Vector3.UP * 1.5 # eyes on what it runs from
	_aim_eye(look_at, delta)

	move_and_slide()
	if muzzle:
		muzzle.global_position = _lens_point()

	# Eye throb in the support colour, hotter while actively supporting.
	if _eye_light:
		_eye_light.light_color = support_color()
		_eye_light.light_energy = 0.7 + sin(_hover_phase * 2.0) * 0.3 + (1.2 if healing else 0.0)

## Pitch the sphere on its Body bone to look at `at` (a world point, or null
## for level), the yaw being the body's (_face_dir).
func _aim_eye(at: Variant, delta: float) -> void:
	var want := 0.0
	if at is Vector3:
		var to: Vector3 = (at as Vector3) - global_position
		want = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -EYE_MAX, EYE_MAX)
	_eye_pitch = move_toward(_eye_pitch, want, EYE_RATE * delta)
	if _sweep:
		_sweep.sweep("Body", Quaternion(Vector3.RIGHT, _eye_pitch))

## The iris narrows into the Charging clip's end pose for the beam.
func _focus() -> void:
	if _focused:
		return
	_focused = true
	if _visual_root and _visual_root.has_method("hold_pose"):
		_visual_root.hold_pose("Charging", 0.15)

func _unfocus() -> void:
	if not _focused:
		return
	_focused = false
	if _visual_root and _visual_root.has_method("release_hold"):
		_visual_root.release_hold()

## A back-flip away from a player who has closed in: the clip over a burst
## of flee speed, the beam dropped for its length.
func _back_flip() -> void:
	if _flip_cd > 0.0 or _flip_t > 0.0 or _visual_root == null or not _visual_root.has_method("play_oneshot"):
		return
	_flip_cd = FLIP_CD
	_unfocus()
	_visual_root.play_oneshot("BackFlip", 0.1)
	var ap := find_child("AnimationPlayer", true, false) as AnimationPlayer
	_flip_t = ap.get_animation("BackFlip").length if ap and ap.has_animation("BackFlip") else 1.3
	AudioBus.play_synth_at("drone_hum", global_position, 0.0, 1.9)

# --- support hooks (EnemyAegis overrides these to shield instead of heal) ---

## The colour of the beam and the eye.
func support_color() -> Color:
	return Color(0.4, 1.0, 0.6)

## True when the current target needs replacing now: gone, dead, or (for a
## MENDER) back at full health.
func _support_stale(t: EnemyBase) -> bool:
	return t == null or not is_instance_valid(t) or t.state == State.DEAD or t.hp == null \
		or not t.hp.is_alive() or t.hp.current_health >= t.hp.max_health

func _pick_support_target() -> EnemyBase:
	return _find_wounded_ally()

## One tick of support on `t`, which is in beam range.
func _support(t: EnemyBase, delta: float) -> void:
	t.hp.heal(heal_per_sec * delta)
	if _repair_cd <= 0.0:
		_repair_cd = 0.9
		AudioBus.play_synth_at("pickup_health", t.global_position, -8.0, 1.4)

## Called on a tick with no target in beam range.
func _support_lost() -> void:
	pass

func _fly(player: Node3D, delta: float) -> void:
	var pos := global_position
	var move := Vector3.ZERO
	var look := Vector3.ZERO
	if _heal_target and is_instance_valid(_heal_target):
		var to: Vector3 = _heal_target.global_position - pos
		to.y = 0.0
		var d := to.length()
		look = to
		if d > heal_range * 0.8:
			move += to.normalized()              # close to repair range
		elif d < heal_range * 0.4:
			move -= to.normalized() * 0.6         # don't crowd it
	# Always peel away from the player — a healer that won't be cornered.
	if player:
		var fp: Vector3 = pos - player.global_position
		fp.y = 0.0
		var pd := fp.length()
		if pd < flee_range and pd > 0.01:
			move += fp.normalized() * 1.6
			_back_flip()
			if look.length_squared() < 0.01:
				look = -fp
	var dir := move.limit_length(1.0)
	var speed := move_speed * (FLIP_BURST if _flip_t > 0.0 else 1.0)
	velocity.x = move_toward(velocity.x, dir.x * speed, 14.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 14.0 * delta)
	var anchor_y := pos.y
	if _heal_target and is_instance_valid(_heal_target):
		anchor_y = _heal_target.global_position.y
	elif player:
		anchor_y = player.global_position.y
	var desired_y := anchor_y + hover_height + sin(_hover_phase) * 0.3
	velocity.y = move_toward(velocity.y, (desired_y - pos.y) * 4.0, 30.0 * delta)
	if look.length_squared() > 0.01:
		_face_dir(Vector3(look.x, 0.0, look.z).normalized(), delta * 0.9)

func _find_wounded_ally() -> EnemyBase:
	var best: EnemyBase = null
	var best_frac := 0.97
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self:
			continue
		var a := e as EnemyBase
		if a == null or a.state == State.DEAD or a is EnemyMender:
			continue
		if a.hp == null or not a.hp.is_alive() or a.hp.invulnerable:
			continue
		if a.hp.max_health <= 0.0:
			continue
		var frac := a.hp.current_health / a.hp.max_health
		if frac < best_frac:
			best_frac = frac
			best = a
	return best

func _show_beam(from: Vector3, to: Vector3) -> void:
	if _beam == null:
		return
	_beam.visible = true
	var len := from.distance_to(to)
	_beam.global_position = (from + to) * 0.5
	if len > 0.01:
		_beam.look_at(to, Vector3.UP)
		_beam.scale = Vector3(1.0, 1.0, len)
	_pulse += get_physics_process_delta_time() * 10.0
	_beam_mat.emission_energy_multiplier = 5.0 + sin(_pulse) * 2.5
	if _beam_light:
		_beam_light.global_position = to
		_beam_light.light_energy = 2.5 + sin(_pulse) * 1.0

func _hide_beam() -> void:
	if _beam:
		_beam.visible = false
	if _beam_light:
		_beam_light.light_energy = 0.0

func _on_died(_source: Node) -> void:
	set_state(State.DEAD)
	GameState.add_kill(score_value, _kill_label())
	_hide_beam()
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	_speak("die", 0.4)
	var style := _kill_style()
	if style != KillFx.NONE:
		_prep_kill_fx()
	if style == KillFx.DISINTEGRATE:
		KillFx.disintegrate(self)
	elif style == KillFx.ELECTROCUTE:
		KillFx.electrocute(self, _mender_death_fx)
	elif style == KillFx.SHRED:
		KillFx.spray(get_parent(), global_position, KillFx._flat(_shot_dir(_source), self))
		_mender_death_fx()
	else:
		_mender_death_fx()

## The classic mender death: a pop, then it drops out of the sky and winks out.
func _mender_death_fx() -> void:
	if get_parent() == null:
		return
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position
	AudioBus.play_synth_at("explosion", global_position, -2.0, 1.25)
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 2.2, 0.7).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", scale * 0.55, 0.7)
	tw.tween_callback(queue_free)
