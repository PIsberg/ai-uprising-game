class_name EnemyWarmech
extends EnemyBase
## WARMECH — a fierce bipedal siege walker (Quaternius Mech, twin shoulder
## cannons). Enormously tanky and slow; it plants at long range and, after a
## telegraphed charge (cannons glow, body rears into its Shoot_Big pose), lobs a
## SALVO of heavy plasma shells that you have to dodge. The late-game area-denial
## anchor: you can't tank it, you have to break line-of-sight or flank and burn it
## down. RobotModel on $Model drives Walk/Shoot_Big/HitRecieve.

const SHELL := preload("res://scenes/weapons/projectile_warmech.tscn")

@export var shell_speed: float = 26.0
@export var shell_damage: float = 15.0
@export var salvo_count: int = 3
@export var salvo_interval: float = 0.22
@export var windup: float = 0.7

var _salvo_left: int = 0
var _salvo_t: float = 0.0
var _windup_t: float = 0.0
var _winding: bool = false
var _charge: MeshInstance3D = null

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 420.0           # a wall — priority kill, not a tank-and-spank
	move_speed = 2.8             # siege crawl
	turn_speed = 4.5
	sight_range = 50.0
	sight_angle_deg = 200.0
	attack_range = 44.0
	preferred_range = 26.0       # holds at long range and shells you
	attack_cooldown = 3.8
	score_value = 360
	head_radius = 0.8
	stagger_threshold = 320.0    # only a heavy hit rocks it (plays HitRecieve)
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0

func _process(_delta: float) -> void:
	if state == State.DEAD:
		return
	if _eye_light:
		_eye_light.light_energy = 1.4 + recoil * 2.0 + (4.0 if _winding else 0.0) \
			+ (1.5 if is_enraged() else 0.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _winding:
		_windup_t -= delta
		# Charge orb swells + brightens at the muzzle as the cannons spin up.
		if is_instance_valid(_charge):
			var prog := clampf(1.0 - _windup_t / maxf(windup, 0.01), 0.0, 1.0)
			_charge.scale = Vector3.ONE * lerpf(0.15, 1.1, prog)
			var cm := _charge.material_override as StandardMaterial3D
			if cm:
				cm.emission_energy_multiplier = lerpf(2.0, 13.0, prog)
		if _windup_t <= 0.0:
			_winding = false
			_salvo_left = salvo_count
			_salvo_t = 0.0
			if is_instance_valid(_charge):
				_charge.queue_free()
				_charge = null
	if _salvo_left > 0:
		_salvo_t -= delta
		if _salvo_t <= 0.0:
			_fire_shell()
			_salvo_left -= 1
			_salvo_t = salvo_interval

## Plant while charging or firing — a siege mech doesn't shoot on the move.
func _move_toward(dest: Vector3, delta: float) -> void:
	if _winding or _salvo_left > 0:
		_decelerate()
		_face_target(delta)
		return
	super._move_toward(dest, delta)

## Telegraphed charge; the salvo streams out in _physics_process.
func _perform_attack() -> void:
	if target == null or _winding or _salvo_left > 0:
		return
	_winding = true
	_windup_t = windup
	recoil = 1.0   # snaps the model into its Shoot_Big pose during the charge
	AudioBus.play_synth_at("overlord_glitch", global_position, -2.0, 0.6)
	_begin_charge_fx()

## A growing emissive orb at the muzzle while the cannons spin up — the fair,
## readable "it's about to fire" tell, and a menacing one.
func _begin_charge_fx() -> void:
	if muzzle == null:
		return
	if is_instance_valid(_charge):
		_charge.queue_free()
	_charge = MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 0.32; s.height = 0.64; s.radial_segments = 10; s.rings = 6
	_charge.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.5, 0.18, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.16)
	mat.emission_energy_multiplier = 2.0
	_charge.material_override = mat
	_charge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge.scale = Vector3.ONE * 0.15
	muzzle.add_child(_charge)

func _fire_shell() -> void:
	if target == null or not is_instance_valid(target) or muzzle == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var proj := SHELL.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = muzzle.global_position
	var dir := (target.global_position + Vector3.UP * 0.6 - muzzle.global_position).normalized()
	dir = scatter_aim(dir, 3.0)   # heavy ordnance walks a little — gives you room to juke
	if proj.has_method("launch"):
		proj.launch(dir * shell_speed, self, shell_damage, 0.0, 0.0)
	recoil = 1.0
	if _eye_light:
		_eye_light.light_energy = 7.0
	AudioBus.play_synth_at("impact_metal", muzzle.global_position, -3.0, 0.7)
