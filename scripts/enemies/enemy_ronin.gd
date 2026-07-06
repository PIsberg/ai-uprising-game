class_name EnemyRonin
extends EnemyBase
## RONIN — a hooded assassin frame (assets/models/robots/robot-killer_model.glb):
## tattered green cloak, one red eye, a katana across its back and revolvers on
## each hip. It STALKS: at range it snaps off single hard revolver slugs, then
## breaks into a flanking dash — a sudden sidestep burst that ruins your aim —
## and closes for a two-cut katana combo. Fast, precise, thinner armour than it
## looks. Kill it before it gets inside your guard.

const SLUG := preload("res://scenes/weapons/projectile_drone.tscn")

@export var slash_damage: float = 20.0     ## Each cut of the two-cut combo.
@export var slug_damage: float = 16.0
@export var slug_speed: float = 55.0
@export var slug_cooldown: float = 2.4
@export var dash_speed: float = 22.0
@export var dash_cooldown: float = 3.0

var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _slug_cd: float = 0.0

func _ready() -> void:
	super._ready()
	max_health = 240.0
	move_speed = 8.0
	turn_speed = 10.0
	sight_range = 42.0
	sight_angle_deg = 240.0
	attack_range = 2.8
	preferred_range = 1.6
	attack_cooldown = 1.1
	attack_lunge_speed = 17.0
	telegraph_time = 0.26
	score_value = 320
	stagger_threshold = 60.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 1.0

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		super._physics_process(delta)
		return
	_dash_cd = maxf(0.0, _dash_cd - delta)
	_slug_cd = maxf(0.0, _slug_cd - delta)
	# Mid-dash: ride the burst, ignore nav steering for its duration.
	if _dash_t > 0.0:
		_dash_t -= delta
		velocity.x = _dash_dir.x * dash_speed
		velocity.z = _dash_dir.z * dash_speed
		_apply_gravity(delta)
		_face_target(delta)
		move_and_slide()
		return
	super._physics_process(delta)
	if target == null or not is_instance_valid(target) or state not in [State.CHASE, State.ATTACK]:
		return
	var dist := global_position.distance_to(target.global_position)
	# Closing from mid range: a sudden angled dash — in and OFF your crosshair.
	if _dash_cd <= 0.0 and dist >= 7.0 and dist <= 18.0 and is_on_floor() and _can_see(target):
		var to := (target.global_position - global_position)
		to.y = 0.0
		_dash_dir = to.normalized().rotated(Vector3.UP, deg_to_rad(35.0 * (1.0 if randf() < 0.5 else -1.0)))
		_dash_t = 0.22
		_dash_cd = dash_cooldown
		AudioBus.play_synth_at("grenade_throw", global_position, -4.0, 1.4)
	# Too far to cut: a single hard revolver slug on a slow, deliberate cadence.
	elif _slug_cd <= 0.0 and dist > 9.0 and _can_see(target) and muzzle != null:
		_fire_slug()

func _fire_slug() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_slug_cd = slug_cooldown
	var proj := SLUG.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.6 - muzzle.global_position).normalized()
	dir = scatter_aim(dir, 1.5)  # an assassin barely misses
	if proj.has_method("launch"):
		proj.launch(dir * slug_speed, self, slug_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -3.0, 0.7)

## Two-cut katana combo: the first cut lands now, the follow-through a beat
## later if you're still inside its reach — dash out between the cuts.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	_attack_lunge()
	_cut()
	get_tree().create_timer(0.18).timeout.connect(_cut)

func _cut() -> void:
	if state == State.DEAD or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.4:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -5.0, 1.5)
	recoil = 1.0
