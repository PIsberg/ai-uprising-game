class_name EnemyBrute
extends EnemyBase
## A heavy, slow shielded brute. Its big frontal slab soaks ~90% of damage from
## the front, so you have to flank it — shoot its sides or back. Closes in and
## slams in melee. Reads its shield clearly so the counterplay is obvious.

@export var slam_damage: float = 30.0
@export var block_factor: float = 0.1 ## Fraction of frontal damage that gets through.
@export var front_cone_dot: float = 0.4 ## How wide the shielded front arc is.
@export var windup_time: float = 0.5 ## Telegraphed coil before the slam — your window to step aside.

## SHIELD RUSH: fire into the shield and the brute comes for you. RUSH_PROVOKE of
## damage blocked on the slab (it forgets RUSH_FORGET of it a second) makes it
## plant for RUSH_TELL, turning to face you at its own slow turn speed, then run
## the line it is facing at RUSH_SPEED for up to RUSH_TIME. Stand still and you
## are bashed. Step aside and it runs past: into a wall it is stunned for
## RUSH_STUN, onto open floor it stumbles for RUSH_MISS_OPEN, and either way the
## shield hangs open (no block at all) until it recovers. It keeps its footing:
## the run stops (as a miss) RUSH_LOOK short of a drop, of the navmesh's edge
## (how lava and water are carved) or of a hazard bed. Covered by
## tests/brute_rush_probe.
enum Rush { NONE, TELL, RUSH, OPEN }
const RUSH_PROVOKE := 45.0 ## blocked damage that sets it off
const RUSH_FORGET := 6.0 ## provocation lost per second
const RUSH_MIN := 5.0 ## metres: nearer than this it slams instead
const RUSH_MAX := 22.0
const RUSH_TELL := 0.7
const RUSH_SPEED := 11.0
const RUSH_TIME := 1.3
const RUSH_DAMAGE := 22.0
const RUSH_REACH := 1.9 ## metres from its centre the bash connects
const RUSH_STUN := 2.4 ## open after hitting a wall
const RUSH_MISS_OPEN := 1.1 ## open after running out of floor time
const RUSH_COOLDOWN := 7.0
const RUSH_OPEN_YAW := 1.2 ## rad the shield arm hangs aside while open
const RUSH_LOOK := 1.3 ## metres ahead its footing is checked while it runs
const RUSH_DROP := 0.7 ## a floor further below its feet than this is an edge
var rush: Rush = Rush.NONE
var _rush_t := 0.0 ## seconds left in the current phase
var _rush_cd := 0.0
var _rush_dir := Vector3.ZERO
var _provoked := 0.0

## True while a dodged rush has left the shield hanging aside: nothing is blocked.
func shield_open() -> bool:
	return rush == Rush.OPEN

var _shield_mat: Material
var _block_cd: float = 0.0
var _windup: float = 0.0

## Ridden (#343): a ground pound all round it, not the generic frontal slam:
## every loyal robot within PILOT_POUND_RADIUS takes the slam and is thrown back.
const PILOT_POUND_RADIUS := 6.0
func pilot_cooldown() -> float:
	return 1.1

func pilot_signature(_aim: Vector3) -> void:
	recoil = 1.0
	var dmg := PILOT_DPS * pilot_cooldown() * PILOT_SLAM_MULT
	for eb in pilot_foes():
		var to := eb.global_position - global_position
		to.y = 0.0
		var d := to.length()
		if d > PILOT_POUND_RADIUS:
			continue
		eb.hp.apply_damage(dmg * clampf(1.2 - d / PILOT_POUND_RADIUS, 0.4, 1.0), pilot_credit())
		eb.velocity += (to / maxf(d, 0.01)) * 8.0 + Vector3.UP * 4.0
	spawn_shockwave_ring(PILOT_POUND_RADIUS, Color(1.0, 0.55, 0.2), global_position, false)
	AudioBus.play_synth_at("explosion", global_position, 0.0, 0.5)

func _ready() -> void:
	add_to_group("shield_enemies")
	_build_shield()
	super._ready()
	max_health = 200.0 # the shield already soaks 90% frontal — raw HP stays modest so flanking pays off fast
	move_speed = 2.0 # lumbering — slow enough that you can circle out and flank it
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
	# A tower shield HELD IN THE RIGHT HAND (the brute's +X side), angled across the
	# front so it still covers the head-on arc — while the LEFT arm stays free to
	# slam. Offset + tilted so it reads as carried, not a centred barn-door wall.
	var shield := MeshInstance3D.new()
	shield.name = "ShieldSlab"
	var shm := BeveledBoxMesh.new()
	shm.size = Vector3(1.15, 1.6, 0.14)
	shm.bevel = 0.04
	shield.mesh = shm
	shield.position = Vector3(0.62, 1.2, -0.74)
	shield.rotation_degrees = Vector3(0, -15, -6) # canted like a shield braced on the forearm
	rig.add_child(shield)

	# Solid metal backing plate: always-visible physical shield behind the energy
	# face, so the carried shield reads even where the fancy shader washes out.
	var plate := MeshInstance3D.new()
	plate.name = "ShieldPlate"
	var pm := BeveledBoxMesh.new()
	pm.size = Vector3(1.15, 1.6, 0.06)
	pm.bevel = 0.03
	plate.mesh = pm
	plate.position = Vector3(0.60, 1.2, -0.68)
	plate.rotation_degrees = Vector3(0, -15, -6)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.18, 0.22)
	pmat.metallic = 0.85
	pmat.roughness = 0.35
	plate.material_override = pmat
	rig.add_child(plate)

	# Glowing shield rim so the protected face reads at a glance.
	var rim := MeshInstance3D.new()
	rim.name = "ShieldRim"
	var rm := BoxMesh.new()
	rm.size = Vector3(1.25, 1.7, 0.05)
	rim.mesh = rm
	rim.position = Vector3(0.65, 1.2, -0.79)
	rim.rotation_degrees = Vector3(0, -15, -6)
	rig.add_child(rim)
	
	_apply_shield_material()

func _apply_shield_material() -> void:
	var shield := get_node_or_null("ShieldRig/ShieldSlab") as MeshInstance3D
	var rim := get_node_or_null("ShieldRig/ShieldRim") as MeshInstance3D
	if shield == null or rim == null:
		return
	
	# The glowing energy sheet reads in BOTH paths — the fresnel hex face alone
	# was near-invisible head-on, which read as "the brute lost its shield".
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.3, 0.7, 1.0, 0.4)
	rmat.emission_enabled = true
	rmat.emission = Color(0.35, 0.75, 1.0)
	rmat.emission_energy_multiplier = 2.5
	rim.material_override = rmat
	rim.visible = true

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
	else:
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.18, 0.2, 0.24)
		smat.metallic = 0.8
		smat.roughness = 0.3
		shield.material_override = smat
		_shield_mat = rmat

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
func modify_incoming_damage(amount: float, source: Node, origin = null) -> float:
	# Judge the shield by where the damage actually came FROM. For splash that is
	# the blast centre (`origin`); for a bullet it is the shooter. Using `source`
	# for both meant a grenade landing behind this brute was still blocked 90%
	# because the thrower stood in front — which quietly deleted the entire point
	# of flanking a shield. See tests/blast_direction_probe.
	var from: Vector3
	if origin is Vector3:
		from = origin
	elif source is Node3D:
		from = (source as Node3D).global_position
	else:
		return amount
	var to := from - global_position
	to.y = 0.0
	if to.length() <= 0.1:
		return amount
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.normalized().dot(to.normalized()) > front_cone_dot:
		if shield_open():
			return amount # the slab hangs aside: the front is as soft as the back
		_provoked += amount
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
	_ease_shield_arm(delta)
	if state != State.DEAD and _tick_rush(delta):
		return
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

## True when nothing else has the body: an EMP, a hijack, a throw and the other
## takeovers in EnemyBase._physics_process all cancel a rush.
func _rush_free() -> bool:
	return _emp_t <= 0.0 and _launch_t <= 0.0 and not hijacked and not rogue 			and reward_hack == "" and courier_goal == null and state != State.STAGGER

## Drives the SHIELD RUSH. Returns true on a tick it moved the body itself.
func _tick_rush(delta: float) -> bool:
	_rush_cd = maxf(0.0, _rush_cd - delta)
	_provoked = maxf(0.0, _provoked - RUSH_FORGET * delta)
	if not _rush_free():
		if rush != Rush.NONE:
			_end_rush()
		return false
	match rush:
		Rush.NONE:
			if _provoked >= RUSH_PROVOKE and _rush_cd <= 0.0 and _windup <= 0.0 and is_instance_valid(target) 					and (state == State.CHASE or state == State.ATTACK):
				var d := global_position.distance_to(target.global_position)
				if d >= RUSH_MIN and d <= RUSH_MAX and _can_see(target):
					rush = Rush.TELL
					_rush_t = RUSH_TELL
					AudioBus.play_synth_at("mech_step", global_position, 3.0, 0.45) # a lower, longer growl than the slam's
			return false
		Rush.TELL:
			_rush_t -= delta
			_decelerate()
			if is_instance_valid(target):
				_face_target(delta)
			_apply_gravity(delta)
			move_and_slide()
			_set_shield_glow(1.0, 9.0)
			if _rush_t <= 0.0:
				# The line is where it faces NOW: it turns slowly, so a late step
				# aside is off the line.
				_rush_dir = -global_transform.basis.z
				_rush_dir.y = 0.0
				_rush_dir = _rush_dir.normalized()
				if not _rush_footing():
					_end_rush() # nowhere to run: it stays behind its shield
					return true
				rush = Rush.RUSH
				_rush_t = RUSH_TIME
				AudioBus.play_synth_at("mech_step", global_position, 4.0, 0.8)
			return true
		Rush.RUSH:
			_rush_t -= delta
			velocity.x = _rush_dir.x * RUSH_SPEED
			velocity.z = _rush_dir.z * RUSH_SPEED
			_apply_gravity(delta)
			move_and_slide()
			_set_shield_glow(1.0, 9.0)
			if is_instance_valid(target):
				var to := target.global_position - global_position
				to.y = 0.0
				if to.length() <= RUSH_REACH and to.normalized().dot(_rush_dir) > 0.2:
					_bash()
					_end_rush()
					return true
			if is_on_wall() and get_wall_normal().dot(_rush_dir) < -0.5:
				_hang_open(RUSH_STUN)
				spawn_shockwave_ring(2.2, Color(1.0, 0.6, 0.25), global_position, false)
				AudioBus.play_synth_at("impact_metal", global_position, 4.0, 0.5)
				AudioBus.play_synth_at("explosion", global_position, -6.0, 1.3)
			elif _rush_t <= 0.0 or not _rush_footing():
				_hang_open(RUSH_MISS_OPEN)
			return true
		Rush.OPEN:
			_rush_t -= delta
			_decelerate()
			_apply_gravity(delta)
			move_and_slide()
			_set_shield_glow(0.05, 0.4)
			if _rush_t <= 0.0:
				_end_rush()
			return true
	return false

## Is there ground to run on RUSH_LOOK metres along the rush line? A wall there
## counts as ground (it is about to hit it, which is the point). Otherwise the
## floor must be within RUSH_DROP below its feet, on the navmesh when the level
## has one, and outside every hazard bed.
func _rush_footing() -> bool:
	var space := get_world_3d().direct_space_state
	var chest := global_position + Vector3.UP * 0.9
	var ahead := PhysicsRayQueryParameters3D.create(chest, chest + _rush_dir * RUSH_LOOK, 1)
	ahead.exclude = [get_rid()]
	if not space.intersect_ray(ahead).is_empty():
		return true
	var p := global_position + _rush_dir * RUSH_LOOK
	var down := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.9, p + Vector3.DOWN * RUSH_DROP, 1)
	down.exclude = [get_rid()]
	var hit := space.intersect_ray(down)
	if hit.is_empty():
		return false
	var floor_at: Vector3 = hit.position
	var map := get_world_3d().navigation_map
	if map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty():
		var on_nav := NavigationServer3D.map_get_closest_point(map, floor_at)
		if Vector2(on_nav.x - floor_at.x, on_nav.z - floor_at.z).length() > 0.6:
			return false
	return not _pos_in_hazard(floor_at)

## The rush connected: the slab hits like a door.
func _bash() -> void:
	var d := target.get_node_or_null("Damageable")
	if d:
		d.apply_damage(RUSH_DAMAGE, self)
	if target is CharacterBody3D:
		(target as CharacterBody3D).velocity += _rush_dir * 11.0 + Vector3.UP * 3.0
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position + _rush_dir, 3.0, 0.6)
	AudioBus.play_synth_at("mech_step", global_position, 2.0, 0.6)

func _hang_open(seconds: float) -> void:
	rush = Rush.OPEN
	_rush_t = seconds
	velocity.x = 0.0
	velocity.z = 0.0
	var rig := get_node_or_null("ShieldRig") as Node3D
	if rig:
		rig.rotation.y = -RUSH_OPEN_YAW # thrown out to its right, off the front

func _end_rush() -> void:
	rush = Rush.NONE
	_rush_cd = RUSH_COOLDOWN
	_provoked = 0.0

## The shield arm swings back across the front once it is no longer open.
func _ease_shield_arm(delta: float) -> void:
	if rush == Rush.OPEN:
		return
	var rig := get_node_or_null("ShieldRig") as Node3D
	if rig and rig.rotation.y != 0.0:
		rig.rotation.y = move_toward(rig.rotation.y, 0.0, delta * 7.0)

func _set_shield_glow(grid: float, emission: float) -> void:
	if _shield_mat is ShaderMaterial:
		_shield_mat.set_shader_parameter("grid_intensity", grid)
	elif _shield_mat:
		_shield_mat.emission_energy_multiplier = emission
