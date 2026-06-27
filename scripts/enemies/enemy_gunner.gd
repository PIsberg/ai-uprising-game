class_name EnemyGunner
extends EnemyBase
## GUNNER — a heavy weapons robot (Quaternius "Robot Enemy Large Gun"): slow,
## armored, twin red eyes over a chunky chaingun. It plants itself at range and,
## after a telegraphed spin-up (eyes flare, barrel whine), unloads a long
## suppressive burst that forces you into cover. Tanky and high-value: a priority
## kill you have to flank or wait out. RobotModel on $Model drives Walk/Shoot.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

@export var proj_speed: float = 42.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 12
@export var burst_interval: float = 0.11
@export var windup: float = 0.6

var _burst_left: int = 0
var _burst_t: float = 0.0
var _windup_t: float = 0.0
var _winding: bool = false

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 230.0
	move_speed = 3.4              # heavy and slow
	turn_speed = 5.0
	sight_range = 44.0
	sight_angle_deg = 210.0
	attack_range = 36.0
	preferred_range = 22.0       # holds at range and suppresses
	attack_cooldown = 3.2        # long reset between bursts
	score_value = 260
	head_radius = 0.7
	stagger_threshold = 220.0    # shrugs off small-arms; flank or burst it down
	flinch_knockback = 0.0
	combat_strafe = true         # reposition between bursts (plants while firing)
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 4.0

func _process(delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		# Eyes idle-glow, flare hot during spin-up, spike with each round.
		_eye_light.light_energy = 1.4 + recoil * 2.0 + (3.5 if _winding else 0.0) \
			+ (1.5 if is_enraged() else 0.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _winding:
		_windup_t -= delta
		if _windup_t <= 0.0:
			_winding = false
			_burst_left = burst_count
			_burst_t = 0.0
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = burst_interval

## Plant while spinning up or firing — a suppressing gunner doesn't strafe.
func _move_toward(dest: Vector3, delta: float) -> void:
	if _winding or _burst_left > 0:
		_decelerate()
		_face_target(delta)
		return
	super._move_toward(dest, delta)

## Strafe to reposition between bursts, but plant the moment it commits to firing.
func _combat_strafe(delta: float) -> void:
	if _winding or _burst_left > 0:
		_decelerate()
		_face_target(delta)
		return
	super._combat_strafe(delta)

## Telegraphed spin-up; the burst itself streams out in _physics_process.
func _perform_attack() -> void:
	if target == null or _winding or _burst_left > 0:
		return
	_winding = true
	_windup_t = windup
	AudioBus.play_synth_at("drone_hum", global_position, -1.0, 0.7) # barrel spin-up whine
	_speak("atk", 0.4)

func _fire_one() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.5 - muzzle.global_position).normalized()
	dir = scatter_aim(dir, 3.0) # suppressive fire: a spread cone, not a laser (tightened so the chaingun actually connects)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -5.0, randf_range(0.88, 1.0))
