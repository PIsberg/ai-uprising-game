class_name EnemyWarmech
extends EnemyBase
## WARMECH — a fierce bipedal siege walker (Quaternius Mech, twin shoulder
## cannons). Enormously tanky and slow; it plants at long range and, after a
## telegraphed charge (cannons glow, body rears into its Shoot_Big pose), lobs a
## SALVO of heavy plasma shells that you have to dodge. The late-game area-denial
## anchor: you can't tank it, you have to break line-of-sight or flank and burn it
## down. RobotModel on $Model drives Walk/Shoot_Big/HitRecieve.

const SHELL := preload("res://scenes/weapons/projectile_warmech.tscn")
## The two shoulder cannons' muzzles, body frame at rest (the front vertices
## of each cannon on the posed mesh). Both cannons are skinned to the Torso,
## so the shells follow the body as Shoot_Big rears it back.
const CANNON_BONE := "Torso"
const CANNON_TIPS := [Vector3(-1.05, 2.52, -1.08), Vector3(1.05, 2.52, -1.08)]

@export var shell_speed: float = 26.0
@export var shell_damage: float = 34.0
@export var salvo_count: int = 3
@export var salvo_interval: float = 0.22
@export var windup: float = 0.7

var _salvo_left: int = 0
var _salvo_t: float = 0.0
var _windup_t: float = 0.0
var _winding: bool = false
var _charges: Array = []    ## one charge orb per cannon while winding up
var _cannon_off: Array = [] ## each cannon's muzzle in the Torso bone's frame
var _cannon_i: int = 0

@onready var _eye_light: OmniLight3D = $EyeLight

func _ready() -> void:
	super._ready()
	max_health = 380.0           # a wall — priority kill, not a tank-and-spank
	move_speed = 2.8             # siege crawl
	turn_speed = 4.5
	sight_range = 50.0
	sight_angle_deg = 200.0
	attack_range = 44.0
	preferred_range = 26.0       # holds at long range and shells you
	attack_cooldown = 3.2
	score_value = 360
	head_radius = 0.4
	stagger_threshold = 320.0    # only a heavy hit rocks it (plays HitRecieve)
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 6.0
	_rig_cannons()

## One unscaled muzzle on the Torso bone that switches between the two cannons
## shell by shell (the base follows `_muzzle_bone` plus `_muzzle_offset`).
func _rig_cannons() -> void:
	if not muzzle_on_bone(CANNON_BONE):
		return
	var sk := _muzzle_bone.get_parent() as Skeleton3D
	var pose: Transform3D = sk.global_transform * sk.get_bone_global_pose(sk.find_bone(CANNON_BONE))
	var inv := pose.basis.orthonormalized().inverse()
	for tip: Vector3 in CANNON_TIPS:
		_cannon_off.append(inv * (global_transform * tip - pose.origin))
	_use_cannon(0)

func _use_cannon(i: int) -> void:
	if _cannon_off.is_empty():
		return
	_cannon_i = i
	_muzzle_offset = _cannon_off[i]
	muzzle.global_position = _cannon_tip(i)

func _cannon_tip(i: int) -> Vector3:
	if _cannon_off.is_empty() or _muzzle_bone == null:
		return muzzle.global_position if muzzle else global_position
	return _muzzle_bone.global_position + _muzzle_bone.global_basis.orthonormalized() * (_cannon_off[i] as Vector3)

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
		# A charge orb swells + brightens in each cannon as they spin up.
		var prog := clampf(1.0 - _windup_t / maxf(windup, 0.01), 0.0, 1.0)
		for i in _charges.size():
			var orb: MeshInstance3D = _charges[i]
			if not is_instance_valid(orb):
				continue
			orb.global_position = _cannon_tip(i)
			orb.scale = Vector3.ONE * lerpf(0.15, 1.1, prog)
			var cm := orb.material_override as StandardMaterial3D
			if cm:
				cm.emission_energy_multiplier = lerpf(2.0, 13.0, prog)
		if _windup_t <= 0.0:
			_winding = false
			_salvo_left = salvo_count
			_salvo_t = 0.0
			_clear_charges()
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

## A growing emissive orb in each cannon while they spin up — the fair,
## readable "it's about to fire" tell, and a menacing one.
func _begin_charge_fx() -> void:
	if muzzle == null:
		return
	_clear_charges()
	var s := SphereMesh.new(); s.radius = 0.32; s.height = 0.64; s.radial_segments = 10; s.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.5, 0.18, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.16)
	mat.emission_energy_multiplier = 2.0
	for i in maxi(_cannon_off.size(), 1):
		var orb := MeshInstance3D.new()
		orb.mesh = s
		orb.material_override = mat
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		orb.scale = Vector3.ONE * 0.15
		add_child(orb) # an unscaled child of the body, placed on its cannon each tick
		orb.global_position = _cannon_tip(i)
		_charges.append(orb)

func _clear_charges() -> void:
	for orb: Variant in _charges:
		if is_instance_valid(orb):
			(orb as Node).queue_free()
	_charges.clear()

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
	_use_cannon((_cannon_i + 1) % 2) # the next shell comes from the other shoulder
