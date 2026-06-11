class_name EnemySniper
extends EnemyBase
## A long-range emplacement that plays completely differently from the rushers:
## it barely moves, sees far, and kills with a heavy hitscan beam — but only
## after a visible charge-up. Break line of sight during the charge and the shot
## misses, so it pressures the player to use cover and flank rather than peek.

@export var charge_time: float = 1.3
@export var beam_damage: float = 42.0

var _charging: bool = false
var _charge_t: float = 0.0
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D

func _ready() -> void:
	max_health = 90.0
	move_speed = 1.6
	turn_speed = 4.0
	sight_range = 60.0
	sight_angle_deg = 80.0
	attack_range = 55.0
	preferred_range = 34.0
	attack_cooldown = 3.6
	score_value = 220
	super._ready()

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_charge(delta)
	# The eye lamp glows brighter as the shot charges (the visible weakpoint tell).
	var lamp := get_node_or_null("Eye/EyeLight") as OmniLight3D
	if lamp:
		var goal := 1.5 + (5.0 * (_charge_t / charge_time) if _charging else 0.5 * sin(_state_timer * 3.0))
		lamp.light_energy = move_toward(lamp.light_energy, goal, delta * 25.0)

## A stagger interrupts the charge — the shot fizzles and the beam drops.
func _on_staggered() -> void:
	_charging = false
	_hide_beam()

## Begins a charged shot instead of firing instantly.
func _perform_attack() -> void:
	if _charging or target == null:
		return
	_charging = true
	_charge_t = 0.0
	_ensure_beam()
	# Crouch into the QuadShell's charge-up clip while the shot builds.
	var model := get_node_or_null("Model")
	if model and model.has_method("play_named"):
		model.play_named("Charge")
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("drone_hum", global_position, -4.0, 1.4)

## Advances a charging shot; aims the telegraph at the target and fires (or
## fizzles, if line of sight was lost) when the charge completes.
func _tick_charge(delta: float) -> void:
	if not _charging:
		return
	_charge_t += delta
	_aim_beam(false)
	if _charge_t >= charge_time:
		_charging = false
		_fire_beam()

func _ensure_beam() -> void:
	if _beam != null:
		return
	_beam = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, 1.0)
	_beam.mesh = bm
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = Color(1.0, 0.2, 0.15, 0.0)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(1.0, 0.25, 0.18)
	_beam_mat.emission_energy_multiplier = 6.0
	_beam.material_override = _beam_mat
	_beam.top_level = true # position in world space directly
	add_child(_beam)

## Stretches/aims the telegraph beam from the muzzle to the target. `hot` makes
## it the bright firing flash; otherwise it's the dim charging line.
func _aim_beam(hot: bool) -> void:
	if _beam == null or target == null or muzzle == null:
		return
	var from: Vector3 = muzzle.global_position
	var to: Vector3 = target.global_position + Vector3.UP * 0.4
	var mid := (from + to) * 0.5
	var dist := from.distance_to(to)
	_beam.global_position = mid
	if dist > 0.01:
		_beam.look_at(to, Vector3.UP)
	_beam.scale = Vector3(1.0, 1.0, dist)
	var charge_frac := clampf(_charge_t / charge_time, 0.0, 1.0)
	var width := (1.0 if hot else 0.25 + charge_frac * 0.5)
	_beam.scale.x = width
	_beam.scale.y = width
	_beam_mat.albedo_color.a = (0.9 if hot else 0.15 + charge_frac * 0.45)
	_beam_mat.emission_energy_multiplier = (12.0 if hot else 6.0)

func _fire_beam() -> void:
	if target == null or eye == null:
		_hide_beam()
		return
	var from: Vector3 = eye.global_position
	var to: Vector3 = target.global_position + Vector3.UP * 0.4
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	# Only connects if the ray actually reaches the player (LOS not broken).
	if hit and hit.get("collider") and (hit["collider"] as Node).is_in_group("player"):
		var d = (hit["collider"] as Node).get_node_or_null("Damageable")
		if d:
			d.apply_damage(beam_damage, self)
	_aim_beam(true)
	if has_node("/root/AudioBus"):
		var ab: Node = get_node("/root/AudioBus")
		if ab.has_method("play_synth_at"):
			ab.play_synth_at("rifle_fire", muzzle.global_position, 2.0, 0.7)
	recoil = 1.0
	# Flash fades out fast.
	var tw := _beam.create_tween()
	tw.tween_property(_beam_mat, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(_hide_beam)

func _hide_beam() -> void:
	if _beam_mat:
		_beam_mat.albedo_color.a = 0.0
