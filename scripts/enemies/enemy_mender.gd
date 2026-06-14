class_name EnemyMender
extends EnemyBase
## MENDER — a support flyer that never shoots at you. It hangs back, finds the
## most-wounded robot on the field, and pours a green repair beam into it,
## undoing your damage in real time. While a MENDER is alive a pack heals faster
## than you can whittle it down, so it's a priority kill — which is exactly why
## it flees the moment you close in. Reuses the EyeDrone chassis, tinted teal.

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

@onready var _eye_light: OmniLight3D = $Eye/EyeLight

func _ready() -> void:
	super._ready()
	max_health = 70.0
	move_speed = 6.2
	sight_range = 64.0          # scans wide for the wounded
	sight_angle_deg = 360.0
	attack_range = heal_range
	preferred_range = heal_range * 0.6
	attack_cooldown = 0.1
	score_value = 170           # worth the bullets to silence it
	head_radius = 0.4
	flinch_knockback = 1.5
	hp.max_health = max_health
	hp.current_health = max_health
	_hover_phase = randf() * TAU
	_build_beam()

func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, 1.0)   # spans local -Z..+Z; we look_at the target
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.albedo_color = Color(0.4, 1.0, 0.6)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(0.4, 1.0, 0.6)
	_beam_mat.emission_energy_multiplier = 6.0
	bm.material = _beam_mat
	_beam.mesh = bm
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)
	_beam_light = OmniLight3D.new()
	_beam_light.light_color = Color(0.4, 1.0, 0.6)
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
	_update_hit_react(delta)
	_poise = maxf(0.0, _poise - delta * 26.0)

	var player := _find_player()
	target = player

	# Refresh the heal target periodically or when it's full / gone.
	_retarget -= delta
	var stale := _heal_target == null or not is_instance_valid(_heal_target) \
		or _heal_target.state == State.DEAD or _heal_target.hp == null \
		or not _heal_target.hp.is_alive() \
		or _heal_target.hp.current_health >= _heal_target.hp.max_health
	if _retarget <= 0.0 or stale:
		_retarget = 0.5
		_heal_target = _find_wounded_ally()

	_fly(player, delta)

	# Beam-heal if a wounded ally is in range.
	var healing := false
	if _heal_target and is_instance_valid(_heal_target) and _heal_target.hp \
			and global_position.distance_to(_heal_target.global_position) <= heal_range + 1.0:
		healing = true
		_heal_target.hp.heal(heal_per_sec * delta)
		_show_beam(_eye_light.global_position if _eye_light else global_position,
			_heal_target.global_position + Vector3.UP * 0.6)
		if _repair_cd <= 0.0:
			_repair_cd = 0.9
			AudioBus.play_synth_at("pickup_health", _heal_target.global_position, -8.0, 1.4)
			var rm := _heal_target.get_node_or_null("Model") as RobotModel
			if rm and rm.has_method("damage_blink"):
				pass # the green beam already reads as repair
	if not healing:
		_hide_beam()

	move_and_slide()

	# Teal eye throb, hotter while actively mending.
	if _eye_light:
		_eye_light.light_color = Color(0.4, 1.0, 0.6)
		_eye_light.light_energy = 0.7 + sin(_hover_phase * 2.0) * 0.3 + (1.2 if healing else 0.0)

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
			if look.length_squared() < 0.01:
				look = -fp
	var dir := move.limit_length(1.0)
	velocity.x = move_toward(velocity.x, dir.x * move_speed, 14.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * move_speed, 14.0 * delta)
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
	var fx := EXPLOSION.instantiate()
	get_parent().add_child(fx)
	(fx as Node3D).global_position = global_position
	AudioBus.play_synth_at("explosion", global_position, -2.0, 1.25)
	_speak("die", 0.4)
	# Drops out of the sky and winks out.
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 2.2, 0.7).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "scale", scale * 0.55, 0.7)
	tw.tween_callback(queue_free)
