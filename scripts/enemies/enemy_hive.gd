class_name EnemyHive
extends EnemyBase
## Networked hive-mind flanker. While it holds its link to the hive network it runs
## a near-impenetrable energy shield (shots splash off it) and coordinates with its
## siblings to SURROUND the player — the living hive is spread across evenly-spaced
## approach angles, recomputed as it thins, so they flank instead of stacking.
##
## The counter is the JAMMER: shoot a beacon to project a geofenced jam zone (see
## jam_zone.gd / jammer_controller.gd). Any hive unit inside loses its network link
## — the shield collapses AND it goes disoriented (inert, no fire), taking full
## damage. Bottleneck the hive into a zone, or isolate a heavy hitter, then finish
## them while they're cut off.

const PROJECTILE := preload("res://scenes/weapons/projectile_drone.tscn")

@export var proj_speed := 30.0
@export var proj_damage := 8.0
@export var shield_block := 0.05  ## fraction of damage that leaks through the shield while networked

var jammed: bool = false
var _jam_count: int = 0            ## number of jam zones currently containing me
var _shield: MeshInstance3D
var _shield_mat: StandardMaterial3D
var _shield_flare := 0.0

# Hive coordination — every live unit registers here so approach angles can be
# spread evenly across the survivors (perfect flank).
static var _hive: Array = []

func _ready() -> void:
	max_health = 70.0
	move_speed = 5.2
	turn_speed = 6.0
	sight_range = 46.0
	sight_angle_deg = 220.0
	attack_range = 24.0
	# CLOSE-range flanker: it rushes in and circle-strafes at short range instead of
	# plinking from 14 m. That's what makes the jammer work — a swarm that closes on
	# you runs THROUGH the zones you plant near yourself / at chokepoints, where a
	# distant strafer never would (playtest: 14 m strafers were effectively unjammable).
	preferred_range = 6.0
	attack_cooldown = 1.6
	telegraph_time = 0.3
	score_value = 130
	stagger_threshold = 60.0
	combat_strafe = true # circle-strafe at close range — a moving, flanking target
	super._ready()
	_build_shield()
	_hive.append(self)
	_reflow()
	hp.died.connect(func(_s): _deregister())
	tree_exiting.connect(_deregister)

func _build_shield() -> void:
	_shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	_shield_mat = StandardMaterial3D.new()
	_shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_shield_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.14)
	_shield_mat.emission_enabled = true
	_shield_mat.emission = Color(0.35, 0.75, 1.0)
	_shield_mat.emission_energy_multiplier = 0.4
	sm.material = _shield_mat
	_shield.mesh = sm
	_shield.position = Vector3(0, 1.0, 0)
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield)

func _deregister() -> void:
	_hive.erase(self)
	_reflow()

## Spread the LIVING hive evenly around the ring so they surround rather than
## stack — the "flanks perfectly" behaviour. Cheap; runs only on spawn/death.
static func _reflow() -> void:
	var live: Array = []
	for h in _hive:
		if is_instance_valid(h) and not (h as EnemyHive).is_dead():
			live.append(h)
	_hive = live
	var n := live.size()
	for i in n:
		(live[i] as EnemyBase)._approach_angle = TAU * float(i) / float(maxi(1, n))

func is_dead() -> bool:
	return state == State.DEAD or hp == null or not hp.is_alive()

# ---------- jamming ----------

## Called by a JamZone when I enter/leave its geofenced boundary. Zones stack, so
## I'm only un-jammed once I'm clear of ALL of them.
func enter_jam() -> void:
	_jam_count += 1
	_set_jammed(true)

func exit_jam() -> void:
	_jam_count = maxi(0, _jam_count - 1)
	if _jam_count == 0:
		_set_jammed(false)

func _set_jammed(on: bool) -> void:
	if jammed == on:
		return
	jammed = on
	if on:
		AudioBus.play_synth_at("overlord_glitch", global_position, -6.0, 1.4)
	else:
		AudioBus.play_synth_at("combo_up", global_position, -10.0, 0.8)

# ---------- shield (network link) ----------

## While networked the shield eats almost everything; jammed, damage lands full.
func modify_incoming_damage(amount: float, source) -> float:
	if jammed:
		return amount
	_shield_flare = 1.0
	notify_shield_hit(source)
	return amount * shield_block

func notify_shield_hit(_source) -> void:
	_shield_flare = 1.0
	if _shield_mat:
		_shield_mat.emission_energy_multiplier = 2.2

func _physics_process(delta: float) -> void:
	# Jammed units are cut off: keep them EMP-inert (disoriented, no fire) while
	# inside the zone — emp_disable already models "no perception/AI/attacks".
	if jammed and not is_dead():
		emp_disable(0.2)
	super._physics_process(delta)
	_update_shield_vis(delta)

func _update_shield_vis(delta: float) -> void:
	if _shield == null:
		return
	_shield_flare = maxf(0.0, _shield_flare - delta * 3.0)
	# Jammed → shield collapses (fades out); networked → a soft breathing bubble
	# that flares when it soaks a hit.
	var target_alpha := 0.0 if jammed else 0.14
	var a: Color = _shield_mat.albedo_color
	a.a = lerpf(a.a, target_alpha, delta * 8.0)
	_shield_mat.albedo_color = a
	var base := 0.0 if jammed else (0.4 + sin(_state_timer * 3.0) * 0.15)
	_shield_mat.emission_energy_multiplier = maxf(base, _shield_flare * 2.2)
	_shield.visible = _shield_mat.albedo_color.a > 0.01

# ---------- attack (crossfire) ----------

func _perform_attack() -> void:
	if jammed or target == null or not is_instance_valid(target):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP
	var proj := PROJECTILE.instantiate()
	scene.add_child(proj)
	(proj as Node3D).global_position = origin
	var dir := (target.global_position + Vector3.UP * 0.4 - origin).normalized()
	dir = scatter_aim(dir, 3.0)
	if proj.has_method("launch"):
		proj.launch(dir * proj_speed, self, proj_damage, 0.0, 0.0)
	recoil = 1.0
	_muzzle_flash()
	AudioBus.play_synth_at("plasma_fire", origin, -6.0, 1.2)
