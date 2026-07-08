class_name EnemyTitan
extends EnemyColossus
## Second campaign mega-boss. Mechanically a Colossus (artillery / chest beam /
## ground-slam, HUD boss bar, cinematic entrance) but a distinct fighter: a
## taller, lankier warframe — the "Giant Robot" model (CC-BY, Dann Beeson) —
## tuned faster and a touch less armored, so it strides and repositions where
## GOLIATH lumbers. The model has no rig, so RobotModel drives no clips; its
## advance is velocity + the procedural sway already on the chassis. The raw GLB
## ships frozen in a stiff "hands raised, reaching forward" stance, so we swing
## the loose arm parts down at load time (see ModelPoser) into a natural ready
## stance.

func _ready() -> void:
	super._ready()
	# Re-skin identity + a faster, glassier tuning (changed synchronously here,
	# before the deferred boss announcement reads them).
	boss_name = "PROMETHEUS-0"
	max_health = 2600.0
	move_speed = 3.4   # a strider, not a siege engine
	turn_speed = 2.2
	score_value = 3200
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0
	# The GLB has no rig, so build a procedural gait from its loose parts: pose the
	# arms into a natural stance, then bucket arms + legs into pivot nodes we swing
	# each frame (see _drive_gait). Without this PROMETHEUS-0 just slides forward
	# statue-stiff; with it, it strides — legs swinging, arms counter-pumping.
	var mesh := get_node_or_null("Model/Mesh") as Node3D
	if mesh:
		var arms := ModelPoser.pose_giant_robot_arms(mesh)
		var legs := ModelPoser.rig_giant_robot_legs(mesh)
		_arm_r = arms.get("R") as Node3D
		_arm_l = arms.get("L") as Node3D
		_leg_r = legs.get("R") as Node3D
		_leg_l = legs.get("L") as Node3D
		if _arm_r: _arm_r_base = _arm_r.rotation
		if _arm_l: _arm_l_base = _arm_l.rotation

# ---------------------------------------------------------------------------
# Signature ENTRANCE — SPATIAL FOLD (overrides the Colossus sky-drop)
#
# GOLIATH-IX makes planetfall. PROMETHEUS-0 doesn't arrive — it *un-folds into
# being*. A violet rift tears open over the dais, reality glitches, and the titan
# de-rezzes into the arena on a spatial shockwave: the exact trick it uses to
# blink around you mid-fight, now weaponised as its introduction. Held frozen +
# invulnerable through the materialise, then it drops into the fight.
# ---------------------------------------------------------------------------

## Override: no sky-drop. Freeze + hide, then run the fold-in cinematic.
func _begin_entrance() -> void:
	hp.invulnerable = true
	visible = false
	set_physics_process(false)
	_do_entrance.call_deferred()

func _do_entrance() -> void:
	GameState.announce_boss(self)
	AudioBus.play_synth_ui("eas_alert", -6.0)
	var here := global_position
	var p := get_tree().get_first_node_in_group("player")
	var scene := get_tree().current_scene
	if scene == null:
		_finish_fold_in()
		return

	# 1) Reality tears: a violet spatial rift irises open above the dais.
	var rift := BossPortal.new()
	rift.radius = 5.0
	rift.color = Color(0.58, 0.5, 1.0)
	scene.add_child(rift)
	rift.global_position = here + Vector3(0, 4.0, 0)
	if p and p is Node3D:
		rift.face((p as Node3D).global_position)
	AudioBus.play_synth_at("overlord_glitch", here, 3.0, 0.95)
	if p and p.has_method("shake"):
		p.shake(0.7)
	rift.open(0.5)
	await get_tree().create_timer(0.5).timeout

	# 2) It de-rezzes in: a glitch crack at the dais, then the chassis snaps into
	#    existence with a fold shockwave — hit-stop + a hard shake sell the arrival.
	_blink_flash(here)
	AudioBus.play_synth_at("overlord_glitch", here, 2.0, 0.7)
	AudioBus.play_synth_at("explosion", here, 4.0, 0.55)
	visible = true
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.scale = Vector3(1.18, 0.72, 1.18) # a squashed "phasing-in" pop...
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(model, "scale", Vector3.ONE, 0.45) # ...settling to solid
	GameState.hit_stop(0.09, 0.55)
	if p and p.has_method("shake"):
		p.shake(1.2)
	_entrance = 6.0   # eye-blaze surge (drives the inherited eye-glow spike)
	await get_tree().create_timer(0.4).timeout

	# 3) Echo cracks around it as the rift collapses — the fold "settles".
	_blink_flash(here + Vector3(3.2, 0, -2.4))
	_blink_flash(here + Vector3(-3.0, 0, 2.6))
	rift.close(0.45)
	await get_tree().create_timer(0.2).timeout
	_finish_fold_in()

## Release the freeze/invuln and hand control to the normal fight.
func _finish_fold_in() -> void:
	hp.invulnerable = false
	visible = true
	set_physics_process(true)

# ---------------------------------------------------------------------------
# Signature mechanic — PHASE-BLINK HIT-AND-RUN
#
# GOLIATH-IX lumbers; PROMETHEUS-0 *strides*. Where the Colossus closes the
# distance on foot, the Titan folds space: once wounded (phase 2+) and whenever
# the player has opened up the range, it de-rezzes and re-materialises on a
# flank just inside bombardment range, then immediately opens with a sweeping
# beam. This is the one thing the Colossus kit can't do — it turns the second
# mega-boss from a re-skin into a distinct, mobile fight.
# ---------------------------------------------------------------------------

@export var blink_cooldown: float = 7.0  ## Base seconds between phase-blinks (shortens as it loses health).
var _blink_cd: float = 4.0

# Procedural gait: pivots (built in _ready) holding the rigless model's limb
# parts, swung each frame off the inherited _walk_phase. The legs stride about
# the hip; the arms counter-pump on top of their posed resting rotation.
var _arm_r: Node3D
var _arm_l: Node3D
var _leg_r: Node3D
var _leg_l: Node3D
var _arm_r_base: Vector3
var _arm_l_base: Vector3
const STRIDE_MAX := 0.42   ## peak hip swing (radians) at full speed
const ARM_SWING := 0.5     ## arm counter-swing as a fraction of the leg stride
## After a blink the beam doesn't fire INSTANTLY — it charges for this long first
## (a readable tell at the new angle) so the reposition is a threat you can react
## to, not a free hit. Without it the blink-onto-flank + immediate on-target beam
## was effectively undodgeable.
const BLINK_BEAM_TELL := 0.55
var _blink_beam_delay: float = 0.0

func _process(delta: float) -> void:
	super._process(delta)
	_drive_gait()
	if _blink_cd > 0.0:
		_blink_cd -= delta
	if _blink_beam_delay > 0.0:
		_blink_beam_delay -= delta
		if _blink_beam_delay <= 0.0:
			_begin_beam() # tell finished — now the sweep fires

## Swing the rigless model's limbs into a stride. Driven by the inherited
## _walk_phase (which advances faster the quicker it moves), scaled by how fast
## it's actually travelling so the gait blends from an idle sway to a full stride.
func _drive_gait() -> void:
	if _leg_r == null and _arm_r == null:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := clampf(speed / maxf(move_speed, 0.1), 0.0, 1.0)
	var stride := sin(_walk_phase) * STRIDE_MAX * moving
	# A faint idle breath keeps the arms alive when it's planted and bombarding.
	var idle := sin(_walk_phase) * 0.03 * (1.0 - moving)
	if _leg_r:
		_leg_r.rotation.x = stride
	if _leg_l:
		_leg_l.rotation.x = -stride
	# Arms counter-pump the legs (opposite phase), layered on their posed base.
	if _arm_r:
		_arm_r.rotation = _arm_r_base + Vector3(-stride * ARM_SWING + idle, 0.0, 0.0)
	if _arm_l:
		_arm_l.rotation = _arm_l_base + Vector3(stride * ARM_SWING + idle, 0.0, 0.0)

## Inject the blink ahead of the inherited artillery/beam/slam decision.
func _choose_attack(dist: float) -> void:
	# A blink/beam/slam (or a charging post-blink beam) already in flight locks out
	# new actions (mirrors Colossus).
	if _beam_time > 0.0 or _slam_windup > 0.0 or _blink_beam_delay > 0.0:
		return
	if _try_blink(dist):
		return
	super._choose_attack(dist)

## Returns true if it blinked this frame (and thus consumed the attack slot).
func _try_blink(dist: float) -> bool:
	if _blink_cd > 0.0 or _phase() < 2 or target == null:
		return false
	# Only worth folding space when the player has slipped out of the kill band;
	# up close it stays and brawls with the inherited kit.
	if dist < preferred_range * 0.8:
		return false
	# More aggressive the more wounded it is: phase 2 -> 7s, phase 3 -> 5.5s.
	_blink_cd = maxf(3.5, blink_cooldown - float(_phase() - 2) * 1.5)
	var here := global_position
	# Re-materialise on a flank of the player, just inside bombardment range.
	var to_player := target.global_position - here
	var flat := Vector3(to_player.x, 0.0, to_player.z)
	if flat.length() < 0.1:
		flat = Vector3.FORWARD
	flat = flat.normalized()
	var side := flat.cross(Vector3.UP)
	if randf() < 0.5:
		side = -side
	var dest := target.global_position - flat * preferred_range + side * (preferred_range * 0.5)
	dest.y = here.y
	# De-rez here, re-rez there, with a glitch crack at both ends.
	_blink_flash(here)
	global_position = dest
	velocity = Vector3.ZERO
	_face_target(0.0)
	_blink_flash(dest)
	AudioBus.play_synth_at("overlord_glitch", dest, 2.0, 0.85)
	GameState.hit_stop(0.05, 0.6)
	# Punish the reposition with a sweeping beam from its new angle — but charge it
	# for BLINK_BEAM_TELL first so the blink-onto-flank is a readable threat you can
	# react to, not a free on-target hit (see the const's note). The _process handler
	# fires _begin_beam() when this delay elapses; the lockout in _choose_attack holds
	# other actions until then.
	_blink_beam_delay = BLINK_BEAM_TELL
	return true

func _blink_flash(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx := EXPLOSION.instantiate()
	scene.add_child(fx)
	(fx as Node3D).global_position = at + Vector3.UP * 2.0
