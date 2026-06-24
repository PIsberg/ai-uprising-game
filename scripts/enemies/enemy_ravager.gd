class_name EnemyRavager
extends EnemyBase
## RAVAGER — the fierce alpha of the swarm. A heavy, armoured brute that lumbers
## between long, telegraphed leaps, crashing down into a ground-slam that hammers
## everything around the impact. Where a skitter nips at your feet, a Ravager
## bounds the length of the arena and lands on your head — the late-game threat
## that punishes standing still. Tanky and hard to stagger; the windup before
## each leap is your window. Real model: the bladed fierce chassis, scaled up.

@export var slam_damage: float = 20.0
@export var slam_radius: float = 4.2 ## Landing shockwave — clips you even if the leap overshoots.

@export_group("Leap")
@export var leap_windup: float = 0.5 ## It rears back and coils — a clear tell before it springs.
@export var leap_cooldown: float = 2.0
@export var leap_min: float = 4.0
@export var leap_max: float = 18.0
@export var leap_h_speed: float = 14.0
@export var leap_up: float = 7.5

var _leaping: bool = false
var _leap_time: float = 0.0
var _windup: float = 0.0
var _leap_cd: float = 0.0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	max_health = 220.0
	move_speed = 4.6
	turn_speed = 7.0
	sight_range = 40.0
	sight_angle_deg = 240.0
	attack_range = 3.6
	preferred_range = 2.0
	attack_cooldown = 1.6
	score_value = 320
	stagger_threshold = 90.0   # an armoured bruiser — won't be stunlocked
	flinch_knockback = 0.3
	super._ready()
	hp.max_health = max_health
	hp.current_health = max_health

## Lumber-then-bound: closes on the player, then telegraphs and springs in a high
## ballistic arc, ground-slamming on landing. Falls back to the base ground AI.
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_leap_cd = maxf(0.0, _leap_cd - delta)
	if _leaping:
		_apply_gravity(delta)
		move_and_slide()
		_leap_time += delta
		if (is_on_floor() and _leap_time > 0.18) or _leap_time > 2.2:
			_leaping = false
			_leap_cd = leap_cooldown
			_slam()
		return
	if _windup > 0.0:
		_windup -= delta
		_decelerate()
		_face_target(delta)
		_apply_gravity(delta)
		move_and_slide()
		if _windup <= 0.0:
			_launch_leap()
		return
	super._physics_process(delta)
	if target and _leap_cd <= 0.0 and is_on_floor() \
			and state in [State.CHASE, State.ATTACK]:
		var dist := global_position.distance_to(target.global_position)
		if dist >= leap_min and dist <= leap_max and _can_see(target):
			_begin_windup()

func _begin_windup() -> void:
	_windup = leap_windup
	recoil = 0.6
	AudioBus.play_synth_at("overlord_glitch", global_position, -5.0, 1.2)

func _launch_leap() -> void:
	if target == null:
		return
	_leaping = true
	_leap_time = 0.0
	var dir := target.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	velocity.x = dir.x * leap_h_speed
	velocity.z = dir.z * leap_h_speed
	velocity.y = leap_up
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -3.0, 0.8)

## Ground-slam: a heavy AoE thump on landing — hits the player if they're inside
## the shockwave, so leaping into a crowd is the Ravager's whole game.
func _slam() -> void:
	AudioBus.play_synth_at("impact_metal", global_position, -1.0, 0.6)
	if _eye_light:
		_eye_light.light_energy = 5.0
	_slam_fx()
	if target and is_instance_valid(target):
		if global_position.distance_to(target.global_position) <= slam_radius:
			var d = target.get_node_or_null("Damageable")
			if d:
				d.apply_damage(slam_damage, self)

## Landing shockwave: an expanding emissive ground ring + dust kick that reads the
## slam's reach at a glance (so the AoE is fair) and lands with weight. Detached
## into the scene so it outlives the Ravager moving on.
func _slam_fx() -> void:
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
	mat.albedo_color = Color(1.0, 0.45, 0.2, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.15)
	mat.emission_energy_multiplier = 7.0
	torus.material = mat
	ring.mesh = torus
	ring.rotation_degrees = Vector3(90, 0, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.15, 0)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * (slam_radius / 0.6), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.32)
	tw.tween_callback(ring.queue_free)
	# A low dust kick around the impact.
	var dust := CPUParticles3D.new()
	dust.one_shot = true; dust.emitting = true
	dust.amount = 20; dust.lifetime = 0.5; dust.explosiveness = 0.9
	dust.direction = Vector3.UP; dust.spread = 75.0
	dust.initial_velocity_min = 2.0; dust.initial_velocity_max = 5.0
	dust.gravity = Vector3(0, -9.0, 0)
	dust.scale_amount_min = 0.4; dust.scale_amount_max = 0.9
	var puff := SphereMesh.new(); puff.radius = 0.18; puff.height = 0.36; puff.radial_segments = 6; puff.rings = 3
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.5, 0.35, 0.3, 0.5)
	puff.material = dmat
	dust.mesh = puff
	scene.add_child(dust)
	dust.global_position = global_position
	scene.get_tree().create_timer(1.2).timeout.connect(dust.queue_free)

func _process(_delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		var tell := 3.5 if _windup > 0.0 else 0.0
		_eye_light.light_energy = lerpf(_eye_light.light_energy, 1.7 + recoil * 2.0 + tell, 0.2)

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slam_damage * 0.6, self)  # a swipe between leaps
		recoil = 1.0
		AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.1)
