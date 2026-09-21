class_name EnemyGunner
extends EnemyBase
## GUNNER — a heavy weapons robot (Quaternius "Robot Enemy Large Gun"): slow,
## armored, twin red eyes over a chunky chaingun. It plants itself at range and,
## after a telegraphed spin-up (eyes flare, barrel whine), unloads a long
## suppressive burst that forces you into cover. Tanky and high-value: a priority
## kill you have to flank or wait out. RobotModel on $Model drives Walk/Shoot.
##
## The model is the Blender fork quaternius_gunner_siege.glb (recoil spades, gun shield,
## ammo drum, rotary mount; tools/blender/cfg_gunner_siege.json). The barrels have to
## turn, so they are built here on the Gun bone instead of skinned into the mesh: they
## spin up through the windup (the visible telegraph) and glow hotter with each round.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

## Barrel-cluster centre in the GLB's own space: Blender (0, -1.25, 1.13) as (x, z, -y).
const ROTOR_POS := Vector3(0.0, 1.13, 1.25)
const ROTOR_BARRELS := 6
const ROTOR_LEN := 0.34          # model units; the Mesh node's 2.1 scale makes it ~0.7 m
const ROTOR_SPIN_MAX := 30.0     # rad/s at full burst
const HEAT_COLD := Color(0.9, 0.12, 0.02)
const HEAT_HOT := Color(1.0, 0.42, 0.08)

@export var proj_speed: float = 42.0
@export var proj_damage: float = 9.0
@export var burst_count: int = 12
@export var burst_interval: float = 0.11
@export var windup: float = 0.6

var _burst_left: int = 0
var _burst_t: float = 0.0
var _windup_t: float = 0.0
var _winding: bool = false
var _rotor: Node3D
var _rotor_mat: StandardMaterial3D
var _rotor_spin: float = 0.0
var _barrel_heat: float = 0.0

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
	head_radius = 0.35
	stagger_threshold = 220.0    # shrugs off small-arms; flank or burst it down
	flinch_knockback = 0.0
	combat_strafe = true         # reposition between bursts (plants while firing)
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 4.0
	_build_rotor()

func _process(delta: float) -> void:
	_update_rotor(delta)
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

## Six barrels + clamp rings on the Gun bone. Built in the GLB's own units and placed in
## the Mesh node's frame, so it takes the model's scale and facing like the skinned parts
## do; going through the bone's REST frame keeps that independent of the spawn pose and
## cancels the rig's internal 100x scale (see EnemyHive._build_uplink).
func _build_rotor() -> void:
	var mesh_root := get_node_or_null("Model/Mesh") as Node3D
	if mesh_root == null:
		return
	var skel := mesh_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var bone := skel.find_bone("Gun") if skel else -1
	if bone < 0:
		return
	var att := BoneAttachment3D.new()
	att.name = "RotorAttach"
	skel.add_child(att)
	att.bone_name = "Gun"
	_rotor = Node3D.new()
	_rotor.name = "BarrelRotor"
	att.add_child(_rotor)
	var rest_global := skel.global_transform * skel.get_bone_global_rest(bone)
	_rotor.transform = rest_global.affine_inverse() * (mesh_root.global_transform * Transform3D(Basis.IDENTITY, ROTOR_POS))
	_rotor_mat = StandardMaterial3D.new()
	_rotor_mat.albedo_color = Color(0.09, 0.09, 0.1)
	_rotor_mat.metallic = 0.85
	_rotor_mat.roughness = 0.35
	_rotor_mat.emission_enabled = true
	_rotor_mat.emission = HEAT_COLD
	_rotor_mat.emission_energy_multiplier = 0.0
	var tube := CylinderMesh.new()
	tube.top_radius = 0.024
	tube.bottom_radius = 0.024
	tube.height = ROTOR_LEN
	tube.radial_segments = 8
	tube.rings = 1
	tube.material = _rotor_mat
	for i in ROTOR_BARRELS:
		var b := MeshInstance3D.new()
		b.name = "Barrel%d" % i
		b.mesh = tube
		var a := TAU * float(i) / float(ROTOR_BARRELS)
		b.position = Vector3(cos(a), sin(a), 0.0) * 0.082
		b.rotation.x = PI * 0.5 # cylinder axis (Y) onto the rotor's spin axis (Z)
		_rotor.add_child(b)
	var ring := CylinderMesh.new()
	ring.top_radius = 0.125
	ring.bottom_radius = 0.125
	ring.height = 0.035
	ring.radial_segments = 12
	ring.rings = 1
	var ring_mat := StandardMaterial3D.new() # clamps stay dark so the hot barrels read as barrels
	ring_mat.albedo_color = Color(0.09, 0.09, 0.1)
	ring_mat.metallic = 0.85
	ring_mat.roughness = 0.35
	ring.material = ring_mat
	for z in [-0.07, 0.05, 0.13]: # barrel tips stand 4 cm proud of the front clamp
		var r := MeshInstance3D.new()
		r.mesh = ring
		r.position = Vector3(0.0, 0.0, z)
		r.rotation.x = PI * 0.5
		_rotor.add_child(r)

## rad/s of the barrel cluster (probe hook: tests/gunner_siege_probe).
func rotor_spin() -> float:
	return _rotor_spin

## 0..1 barrel heat; each round of a burst adds, the reset window bleeds it off.
func barrel_heat() -> float:
	return _barrel_heat

func _update_rotor(delta: float) -> void:
	if _rotor == null:
		return
	var firing := state != State.DEAD and (_winding or _burst_left > 0)
	# Reaches full speed inside the windup. The gap between bursts is only ~1.3 s, so it
	# has to coast down (and the barrels cool) inside that, or the next spin-up reads as nothing.
	var rate := ROTOR_SPIN_MAX / maxf(windup * 0.8, 0.05) if firing else ROTOR_SPIN_MAX / 0.9
	_rotor_spin = move_toward(_rotor_spin, ROTOR_SPIN_MAX if firing else 0.0, rate * delta)
	_rotor.rotate_object_local(Vector3.BACK, _rotor_spin * delta)
	_barrel_heat = move_toward(_barrel_heat, 0.0, delta * 0.7)
	_rotor_mat.emission = HEAT_COLD.lerp(HEAT_HOT, _barrel_heat)
	_rotor_mat.emission_energy_multiplier = _barrel_heat * _barrel_heat * 2.2

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
	_barrel_heat = minf(1.0, _barrel_heat + 2.0 / float(burst_count))
	_muzzle_flash()
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -5.0, randf_range(0.88, 1.0))
