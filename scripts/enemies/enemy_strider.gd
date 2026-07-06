class_name EnemyStrider
extends EnemyBase
## STRIDER — a chicken-walker sentry bot: a domed chassis with a single hostile
## red cyclops eye, raptor-stance legs and a chin gun. A mid-range trooper that
## strides in on its back-jointed legs and rakes the player with bursts of energy
## bolts, keeping its distance. Real model: a CC0 Quaternius robot (RobotModel on
## $Model drives the Run/Shoot/Idle clips).

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

@export var proj_speed: float = 38.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 3
@export var burst_interval: float = 0.09

## Leg STOMP — the chicken-walker's answer to being rushed. When the player
## crowds it, it plants its raptor legs and stamps the ground for a telegraphed
## AoE thump + knockback, instead of uselessly plinking at point-blank range.
@export_group("Stomp")
@export var stomp_damage: float = 18.0
@export var stomp_radius: float = 4.0
@export var stomp_range: float = 5.5   # rears up when the player closes inside this
@export var stomp_windup: float = 0.45 # a clear rear-back tell — your window to back off
@export var stomp_cooldown: float = 3.6

var _burst_left: int = 0
var _burst_t: float = 0.0
var _stomp_cd: float = 0.0
var _stomp_windup: float = 0.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 95.0
	move_speed = 5.0
	turn_speed = 8.0
	sight_range = 40.0
	sight_angle_deg = 220.0
	attack_range = 30.0
	preferred_range = 16.0
	attack_cooldown = 2.0
	telegraph_time = 0.0 # a strafing chin-gun fires on cadence — the generic wind-up + strafing left it barely landing a shot
	score_value = 140
	head_radius = 0.5
	combat_strafe = true # circle-strafe while shooting (and bank into it)
	hp.max_health = max_health
	hp.current_health = max_health

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		# Red eye throbs, spikes bright with each burst, flares when closing in.
		_eye_light.light_energy = 1.2 + sin(_state_timer * 3.0) * 0.4 + recoil * 3.0 \
			+ (2.0 if is_enraged() else 0.0)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_stomp_cd = maxf(0.0, _stomp_cd - delta)
	# Committing to a stomp: plant, face the target, rear back, then slam.
	if _stomp_windup > 0.0:
		_stomp_windup -= delta
		_decelerate()
		_face_target(delta)
		_apply_gravity(delta)
		move_and_slide()
		if _stomp_windup <= 0.0:
			_do_stomp()
		return
	super._physics_process(delta)
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = burst_interval
	# When the player crowds it, stamp instead of plinking.
	if target and _stomp_cd <= 0.0 and is_on_floor() and state in [State.CHASE, State.ATTACK] \
			and _can_see(target) and global_position.distance_to(target.global_position) <= stomp_range:
		_begin_stomp()

func _begin_stomp() -> void:
	_stomp_windup = stomp_windup
	_burst_left = 0 # abort any burst; it's committing to the stamp
	recoil = 0.6
	if _eye_light:
		_eye_light.light_energy = 5.0
	AudioBus.play_synth_at("overlord_glitch", global_position, -5.0, 0.8)

## Rear-and-slam: plants the legs and stamps, an AoE thump that knocks the
## crowding player back off their feet. Reads via an expanding shockwave ring.
func _do_stomp() -> void:
	_stomp_cd = stomp_cooldown
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -1.0, 0.6)
	_stomp_fx()
	if target and is_instance_valid(target) \
			and global_position.distance_to(target.global_position) <= stomp_radius:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(stomp_damage, self)
		if "velocity" in target and target is Node3D:
			var away: Vector3 = (target as Node3D).global_position - global_position
			away.y = 0.0
			if away.length() > 0.1:
				target.velocity += away.normalized() * 9.0 + Vector3.UP * 3.0

## Expanding emissive ground ring + a low dust kick — reads the stomp's reach so
## the AoE is fair. Detached to the scene so it outlives the strider moving on.
func _stomp_fx() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3; torus.outer_radius = 0.6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.5, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.15)
	mat.emission_energy_multiplier = 6.0
	torus.material = mat
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * (stomp_radius / 0.6), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(ring.queue_free)

## Kick off a burst — the actual bolts stream out in _physics_process.
func _perform_attack() -> void:
	if target == null:
		return
	_burst_left = burst_count
	_burst_t = 0.0
	recoil = 1.0 # plays the Shoot clip via RobotModel

func _fire_one() -> void:
	if target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 0.9
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.6 - origin).normalized()
	dir = scatter_aim(dir, 2.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", origin, -3.0, randf_range(0.92, 1.04))
