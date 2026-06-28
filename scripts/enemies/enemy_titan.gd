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
	# Lower the model's raised arms into a natural stance (the GLB has no rig).
	var mesh := get_node_or_null("Model/Mesh") as Node3D
	if mesh:
		ModelPoser.pose_giant_robot_arms(mesh)

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

func _process(delta: float) -> void:
	super._process(delta)
	if _blink_cd > 0.0:
		_blink_cd -= delta

## Inject the blink ahead of the inherited artillery/beam/slam decision.
func _choose_attack(dist: float) -> void:
	# A blink/beam/slam already in flight locks out new actions (mirrors Colossus).
	if _beam_time > 0.0 or _slam_windup > 0.0:
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
	# Punish the reposition with an immediate sweeping beam from its new angle.
	_begin_beam()
	return true

func _blink_flash(at: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var fx := EXPLOSION.instantiate()
	scene.add_child(fx)
	(fx as Node3D).global_position = at + Vector3.UP * 2.0
