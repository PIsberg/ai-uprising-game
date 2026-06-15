class_name EnemyBrute
extends EnemyBase
## A heavy, slow shielded brute. Its big frontal slab soaks ~90% of damage from
## the front, so you have to flank it — shoot its sides or back. Closes in and
## slams in melee. Reads its shield clearly so the counterplay is obvious.

@export var slam_damage: float = 30.0
@export var block_factor: float = 0.1 ## Fraction of frontal damage that gets through.
@export var front_cone_dot: float = 0.4 ## How wide the shielded front arc is.
@export var windup_time: float = 0.5 ## Telegraphed coil before the slam — your window to step aside.

var _shield_mat: Material
var _block_cd: float = 0.0
var _windup: float = 0.0

func _ready() -> void:
	add_to_group("shield_enemies")
	_build_shield()
	super._ready()
	max_health = 280.0
	move_speed = 2.5
	turn_speed = 1.8 # turns slowly — circle to its unshielded sides/back to flank it
	sight_range = 40.0
	sight_angle_deg = 200.0
	attack_range = 3.2
	preferred_range = 2.2
	attack_cooldown = 1.7
	attack_lunge_speed = 9.0 # heaves its bulk forward into the slam
	score_value = 320
	stagger_threshold = 100000.0 # immovable
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 3.0

## The chassis itself is the imported "Mike" heavy mech ($Model in the scene);
## only the gameplay-critical frontal shield slab + glowing rim are code-built,
## bolted to the body so the protected arc reads at a glance.
func _build_shield() -> void:
	var rig := Node3D.new()
	rig.name = "ShieldRig"
	add_child(rig)
	# The big frontal shield slab (faces local -Z, the enemy's front).
	var shield := MeshInstance3D.new()
	shield.name = "ShieldSlab"
	var shm := BeveledBoxMesh.new()
	shm.size = Vector3(1.6, 1.8, 0.16)
	shm.bevel = 0.04
	shield.mesh = shm
	shield.position = Vector3(0, 1.3, -0.8)
	rig.add_child(shield)
	
	# Glowing shield rim so the protected face reads at a glance.
	var rim := MeshInstance3D.new()
	rim.name = "ShieldRim"
	var rm := BoxMesh.new()
	rm.size = Vector3(1.72, 1.92, 0.06)
	rim.mesh = rm
	rim.position = Vector3(0, 1.3, -0.86)
	rig.add_child(rim)
	
	_apply_shield_material()

func _apply_shield_material() -> void:
	var shield := get_node_or_null("ShieldRig/ShieldSlab") as MeshInstance3D
	var rim := get_node_or_null("ShieldRig/ShieldRim") as MeshInstance3D
	if shield == null or rim == null:
		return
	
	var use_shader := bool(GraphicsSettings.get("robot_triplanar_enabled"))
	if use_shader:
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://shaders/shield.gdshader")
		sm.set_shader_parameter("shield_color", Color(0.3, 0.7, 1.0))
		sm.set_shader_parameter("pattern_scale", 6.0)
		sm.set_shader_parameter("fresnel_power", 3.5)
		sm.set_shader_parameter("grid_intensity", 0.45)
		_shield_mat = sm
		shield.material_override = sm
		rim.visible = false
	else:
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.18, 0.2, 0.24)
		smat.metallic = 0.8
		smat.roughness = 0.3
		shield.material_override = smat
		
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.albedo_color = Color(0.3, 0.7, 1.0, 0.5)
		rmat.emission_enabled = true
		rmat.emission = Color(0.35, 0.75, 1.0)
		rmat.emission_energy_multiplier = 2.5
		_shield_mat = rmat
		rim.material_override = rmat
		rim.visible = true

func update_shield_settings() -> void:
	_apply_shield_material()

var _next_ripple_idx := 0

func notify_shield_hit(source: Node) -> void:
	if not (_shield_mat is ShaderMaterial):
		return
	if source is Node3D:
		var shield := get_node_or_null("ShieldRig/ShieldSlab") as MeshInstance3D
		if shield:
			var local_pos: Vector3 = shield.global_transform.affine_inverse() * (source as Node3D).global_position
			var param_pos := "hit_pos_" + str(_next_ripple_idx)
			var param_time := "hit_time_" + str(_next_ripple_idx)
			_shield_mat.set_shader_parameter(param_pos, local_pos)
			_shield_mat.set_shader_parameter(param_time, Time.get_ticks_msec() / 1000.0)
			_next_ripple_idx = (_next_ripple_idx + 1) % 3

## Frontal shield: damage hitting the front arc is mostly absorbed. Flank it.
func modify_incoming_damage(amount: float, source: Node) -> float:
	if source is Node3D:
		var to: Vector3 = (source as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() > 0.1:
			var fwd := -global_transform.basis.z
			fwd.y = 0.0
			if fwd.normalized().dot(to.normalized()) > front_cone_dot:
				_shield_spark()
				notify_shield_hit(source)
				return amount * block_factor
	return amount

func _shield_spark() -> void:
	if _block_cd > 0.0:
		return
	_block_cd = 0.08
	if _shield_mat:
		if _shield_mat is ShaderMaterial:
			_shield_mat.set_shader_parameter("grid_intensity", 1.0)
		else:
			_shield_mat.emission_energy_multiplier = 9.0
	if has_node("/root/AudioBus"):
		AudioBus.play_synth_at("impact_metal", global_position - global_transform.basis.z * 0.7, -2.0, 0.7)

func _physics_process(delta: float) -> void:
	# Mid-windup: the brute is committed to the coil — hold ground with the
	# shield flared bright as the tell, then slam when it expires. It does NOT
	# track you during this window, so a sidestep beats it.
	if _windup > 0.0 and state != State.DEAD:
		_windup -= delta
		_decelerate()
		_apply_gravity(delta)
		move_and_slide()
		if _shield_mat:
			if _shield_mat is ShaderMaterial:
				_shield_mat.set_shader_parameter("grid_intensity", 0.9)
			else:
				_shield_mat.emission_energy_multiplier = 7.0
		if _windup <= 0.0:
			_slam()
		return
	super._physics_process(delta)
	if _block_cd > 0.0:
		_block_cd = maxf(0.0, _block_cd - delta)
	elif _shield_mat:
		if _shield_mat is ShaderMaterial:
			var cur: float = _shield_mat.get_shader_parameter("grid_intensity")
			_shield_mat.set_shader_parameter("grid_intensity", move_toward(cur, 0.45, delta * 3.0))
		else:
			_shield_mat.emission_energy_multiplier = move_toward(_shield_mat.emission_energy_multiplier, 2.5, delta * 18.0)

## The base calls this when in range and off cooldown — but the brute doesn't
## hit instantly: it coils first (the tell) and the slam lands when the windup
## expires. A small backward lean + a growl sells the wind-up.
func _perform_attack() -> void:
	if target == null or _windup > 0.0:
		return
	if global_position.distance_to(target.global_position) <= attack_range:
		_windup = windup_time
		AudioBus.play_synth_at("mech_step", global_position, 0.0, 0.55) # low growl tell
		# Rock back onto its heels — the coil before the spring.
		var back := (global_position - target.global_position)
		back.y = 0.0
		if back.length() > 0.05:
			velocity += back.normalized() * 2.5

## The committed strike: fires even if you've stepped out of range (that's the
## dodge payoff). Heaves forward, slams, and knocks the player back.
func _slam() -> void:
	if target == null:
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage, self)
		if target is CharacterBody3D:
			var away := (target.global_position - global_position)
			away.y = 0.0
			(target as CharacterBody3D).velocity += away.normalized() * 8.0 + Vector3.UP * 2.0
	_attack_lunge() # heave forward into the slam (sets recoil -> slam clip)
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.6)
