class_name EnemyBowler
extends EnemyBase
## STRIKER-9 — a heavy pitcher frame (a repainted brute chassis) that BOWLS
## Molten Orbs at you. It holds the high ground — ramp tops, walkway mouths —
## conjures a fresh orb in its fist and hurls it in a flat, skipping arc; the
## orb lands, keeps rolling under its own power, and hunts you. Kill the
## pitcher or you'll drown in bowling balls. Up close it falls back on a
## two-handed shove.

const ORB := preload("res://scenes/enemies/orb.tscn")
## The throwing hand. Mike's Punch clip draws the right fist back (0.20 s) and
## drives it out to full extension at 0.40-0.45 s: the orb leaves there.
const THROW_BONE := "PalmI.R"
const THROW_RELEASE := 0.42

@export var throw_speed: float = 16.0
@export var throw_up: float = 5.5
@export var shove_damage: float = 24.0
@export var max_live_orbs: int = 3

var _live_orbs: Array = []
var _throw_t: float = 0.0       ## >0: the swing is under way, the orb leaves at 0
var _held: MeshInstance3D       ## the molten orb glowing in its fist before the throw

func _ready() -> void:
	super._ready()
	max_health = 340.0
	move_speed = 3.0            # a planted artillery-pitcher, not a chaser
	turn_speed = 4.5
	sight_range = 46.0
	sight_angle_deg = 220.0
	attack_range = 38.0         # its "gun" is a thrown orb
	preferred_range = 18.0
	attack_cooldown = 5.5
	telegraph_time = 0.55       # the big wind-up IS the tell
	score_value = 300
	head_radius = 0.35
	stagger_threshold = 160.0
	flinch_knockback = 0.0
	hp.max_health = max_health
	hp.current_health = max_health
	hp.armor = 3.0
	muzzle_on_bone(THROW_BONE, Vector3.ZERO, false) # the Punch clip owns the throwing arm
	_build_held_orb()

## A molten ball in its right fist, lit from the wind-up (telegraph) until the
## swing lets it go: you see what is coming and which hand it comes from.
func _build_held_orb() -> void:
	_held = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.32
	s.height = 0.64
	s.radial_segments = 12
	s.rings = 6
	_held.mesh = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.08, 0.02)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.38, 0.08)
	mat.emission_energy_multiplier = 4.0
	_held.material_override = mat
	_held.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_held.visible = false
	add_child(_held) # an unscaled child of the body, placed on the fist each tick

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _throw_t > 0.0:
		_throw_t -= delta
		if _throw_t <= 0.0 and state != State.DEAD and state != State.STAGGER:
			_throw_orb()
	if _held:
		var winding_throw := _telegraphing and _lane_open() and target != null and is_instance_valid(target) \
				and global_position.distance_to(target.global_position) > 4.5 # not the close-range shove
		_held.visible = state != State.DEAD and (_throw_t > 0.0 or winding_throw)
		if _held.visible and muzzle:
			_held.global_position = muzzle.global_position

func _on_staggered() -> void:
	super._on_staggered()
	_throw_t = 0.0 # rocked mid-swing: the orb is dropped, not thrown

func _lane_open() -> bool:
	_live_orbs = _live_orbs.filter(func(o): return is_instance_valid(o) and not (o as EnemyBase).state == EnemyBase.State.DEAD)
	return _live_orbs.size() < max_live_orbs

func _perform_attack() -> void:
	if target == null or not is_instance_valid(target) or _throw_t > 0.0:
		return
	var dist := global_position.distance_to(target.global_position)
	if dist <= 4.5:
		_shove()
		return
	if not _lane_open():
		return  # lane's full — wait for a strike before racking another ball
	# The swing starts now (the Punch clip, off the recoil spike); the orb
	# leaves the fist at the extension, THROW_RELEASE later.
	_throw_t = THROW_RELEASE
	recoil = 1.0

func _throw_orb() -> void:
	var scene := get_tree().current_scene
	if scene == null or target == null or not is_instance_valid(target):
		return
	var orb := ORB.instantiate()
	orb.drop_chance = 0.0  # conjured ordnance isn't a loot pinata
	scene.add_child(orb)
	var from: Vector3 = muzzle.global_position if muzzle else global_position + Vector3.UP * 2.2 - global_transform.basis.z * 1.4
	(orb as Node3D).global_position = from
	# Lead the runner a touch; gravity and the slope do the rest — bowled down
	# a ramp the orb arrives carrying every metre of the drop.
	var predicted: Vector3 = target.global_position
	if "velocity" in target:
		predicted += (target.velocity as Vector3) * 0.4
	var flat := predicted - from
	flat.y = 0.0
	var vel := flat.normalized() * throw_speed + Vector3.UP * throw_up
	(orb as EnemyOrb).launch_throw(vel)
	_live_orbs.append(orb)
	AudioBus.play_synth_at("grenade_throw", global_position, 2.0, 0.7)
	AudioBus.play_synth_at("mech_step", global_position, -2.0, 0.6)
	_speak("atk", 0.4)

func _shove() -> void:
	var d = target.get_node_or_null("Damageable")
	if d and global_position.distance_to(target.global_position) <= 4.8:
		d.apply_damage(shove_damage, self)
		if "velocity" in target:
			var away: Vector3 = target.global_position - global_position
			away.y = 0.0
			target.velocity += away.normalized() * 9.0 + Vector3.UP * 3.0
		if target.has_method("shake"):
			target.shake(0.6)
	recoil = 1.0
	AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.2)
