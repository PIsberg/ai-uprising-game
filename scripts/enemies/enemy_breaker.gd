class_name EnemyBreaker
extends EnemyDrone
## BREAKER — a hovering bronze sphere-bot built around a glowing core, dragging a
## massive piston hammer. It floats in, bobbing, then dives to slam you with the
## hammer before drifting back up out of reach. Pure melee — shoot it down before
## it closes.
##
## The hammer (combat_steampunk.glb's `Object_7`, its own mesh) hangs from a
## root at the top of the chassis down to its head at the lower left, so it
## swings as a pendulum (PartRig, about the body's X axis through the root):
## trailing behind the chassis as it flies and bobbing with the hover; on an
## attack it winds back for `WIND_T`, then whips forward through the target
## for `STRIKE_T`, and the damage lands at the end of that stroke, not when
## the attack is decided. `breaker_hammer_probe`.

@export var smash_damage: float = 26.0

const HAMMER := "Object_7"
const WIND_T := 0.14        ## s the hammer draws back before the stroke
const WIND_ANGLE := -0.7    ## rad back (about +X: positive swings the hanging head forward)
const STRIKE_T := 0.10      ## s of the stroke; the hit lands at its end
const STRIKE_ANGLE := 1.3   ## rad forward at the end of the stroke
const RECOVER_RATE := 6.0   ## ease back to the hanging pendulum after a stroke
const SWAY_PER_MS := 0.05   ## rad the hammer trails per m/s of forward flight
const SWAY_MAX := 0.35
const BOB := 0.08           ## rad of pendulum bob with the hover

var _hammer_e: Array = []
var _hammer_root := Vector3.ZERO ## body frame
var _hammer_tried := false
var _hammer_angle := 0.0
var _swing_t := -1.0             ## time since the attack was decided; -1 = hanging

func _ready() -> void:
	super._ready()
	max_health = 150.0
	move_speed = 6.0
	sight_range = 38.0
	attack_range = 3.6
	preferred_range = 3.2
	attack_cooldown = 1.1
	hover_height = 2.0
	hover_amplitude = 0.5
	score_value = 220
	drops_loot = true
	hp.max_health = max_health
	hp.current_health = max_health

## Hammer stroke instead of the drone's projectile: the swing starts here
## and the hit lands at the end of the stroke (`_land_stroke`).
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	recoil = 1.0
	_swing_t = 0.0
	AudioBus.play_synth_at("drone_hum", global_position, -6.0, 0.7)

func _land_stroke() -> void:
	if target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(smash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -2.0, 0.8)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _dying:
		_tick_hammer(delta)

## Find the hammer and its root (the top inner corner of its bounds, where
## the arm leaves the chassis) once RobotModel's fit has landed.
func _setup_hammer() -> void:
	var mi := find_child(HAMMER, true, false) as MeshInstance3D
	if mi == null or not mi.is_visible_in_tree():
		return
	_hammer_tried = true
	var box: AABB = rig_frame().affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())
	_hammer_root = Vector3(box.end.x - 0.02, box.end.y - 0.03, box.position.z + 0.06)
	_hammer_e = PartRig.entry(self, mi)

## Pendulum at rest (trailing the flight, bobbing with the hover), wind back
## and stroke on an attack, then settle.
func _tick_hammer(delta: float) -> void:
	if not _hammer_tried:
		_setup_hammer()
		return
	if _hammer_e.is_empty():
		return
	var fwd := velocity.dot(-global_transform.basis.z)
	var hang := -clampf(fwd * SWAY_PER_MS, -SWAY_MAX, SWAY_MAX) + sin(_hover_phase) * BOB
	var want := hang
	var rate := RECOVER_RATE
	if _swing_t >= 0.0:
		var before := _swing_t
		_swing_t += delta
		if _swing_t < WIND_T:
			want = WIND_ANGLE
			rate = 30.0
		elif _swing_t < WIND_T + STRIKE_T:
			want = STRIKE_ANGLE
			rate = 40.0
		else:
			if before < WIND_T + STRIKE_T:
				_land_stroke()
			want = hang
			if _swing_t > WIND_T + STRIKE_T + 1.0:
				_swing_t = -1.0
	_hammer_angle = lerpf(_hammer_angle, want, 1.0 - exp(-delta * rate))
	PartRig.pose(_hammer_e, PartRig.turn(_hammer_root, Vector3.RIGHT, _hammer_angle))
