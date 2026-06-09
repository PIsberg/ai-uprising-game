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
var _scope_mat: StandardMaterial3D

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
	_build_model()
	super._ready()

func _build_model() -> void:
	var model := Node3D.new()
	model.name = "Model"
	add_child(model)

	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.17, 0.2)
	steel.metallic = 0.7
	steel.roughness = 0.4

	# Tripod legs.
	for a in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
		var leg := MeshInstance3D.new()
		var lm := BeveledBoxMesh.new()
		lm.size = Vector3(0.11, 1.1, 0.11)
		lm.bevel = 0.012
		leg.mesh = lm
		leg.material_override = steel
		leg.position = Vector3(sin(a) * 0.5, 0.55, cos(a) * 0.5)
		leg.rotation = Vector3(deg_to_rad(12) * cos(a), a, deg_to_rad(12) * sin(a))
		model.add_child(leg)

	# Body / housing.
	var body := MeshInstance3D.new()
	var bm := BeveledBoxMesh.new()
	bm.size = Vector3(0.62, 0.45, 0.85)
	bm.bevel = 0.035
	body.mesh = bm
	body.material_override = steel
	body.position = Vector3(0, 1.25, 0)
	model.add_child(body)

	# Barrel.
	var barrel := MeshInstance3D.new()
	var barm := CylinderMesh.new()
	barm.top_radius = 0.07
	barm.bottom_radius = 0.07
	barm.height = 1.2
	barrel.mesh = barm
	barrel.material_override = steel
	barrel.rotation = Vector3(deg_to_rad(90), 0, 0)
	barrel.position = Vector3(0, 1.3, -0.7)
	model.add_child(barrel)

	# Glowing scope/eye (a bright weakpoint that reads at a distance).
	var scope := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	scope.mesh = sm
	_scope_mat = StandardMaterial3D.new()
	_scope_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_scope_mat.albedo_color = Color(1.0, 0.2, 0.15)
	_scope_mat.emission_enabled = true
	_scope_mat.emission = Color(1.0, 0.25, 0.18)
	_scope_mat.emission_energy_multiplier = 4.0
	scope.material_override = _scope_mat
	scope.position = Vector3(0, 1.45, 0.1)
	model.add_child(scope)

	var eye_node := Node3D.new()
	eye_node.name = "Eye"
	eye_node.position = Vector3(0, 1.45, -0.2)
	add_child(eye_node)
	eye = eye_node

	var muzzle_node := Node3D.new()
	muzzle_node.name = "Muzzle"
	muzzle_node.position = Vector3(0, 1.3, -1.3)
	add_child(muzzle_node)
	muzzle = muzzle_node

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_tick_charge(delta)
	# Pulse the scope; glow brighter as the shot charges.
	if _scope_mat:
		var e := 4.0 + (6.0 * (_charge_t / charge_time) if _charging else sin(_state_timer * 3.0))
		_scope_mat.emission_energy_multiplier = e

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
