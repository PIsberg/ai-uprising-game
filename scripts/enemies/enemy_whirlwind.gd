class_name EnemyWhirlwind
extends EnemyDrone
## WHIRLWIND — a hovering buzzsaw drone: a boxer-bodied core gripping two long
## blades in one fist (reaper_whirlwind.glb, cut offline into `Core` and
## `Blades`, tools/blender/cfg_reaper_whirlwind_parts.json). It floats over
## the battlefield, then dives in to rake you with the whirling blades before
## pulling back up. No ranged attack — it kills up close.
##
## Rig. The blades whirl about the fist that holds them (the hub, read from
## the blades' root once RobotModel's fit has landed; the fit centres the
## model's BOX, which hung the core a metre off to one side of the collision
## sphere, so `_setup_rig` shifts the model to put that fist on the body's
## axis) while the core keeps still and faces you. The whirl idles lazily,
## runs up when it has you, and revs to a scream through a dive, when the
## blades also lift from their hanging droop toward level, so the dive leads
## with a flat spinning disc at your height. Dead, it winds down as it falls.
## The whole model used to spin as one piece about the box's centre, core
## and all: a streak with no face. tests/whirlwind_rig_probe.

@export var slash_damage: float = 22.0
@export var spin_speed: float = 7.5 ## rad/s — the buzzsaw whirl with you in sight

const HUB_Y := 0.1             ## m the fist sits above the body's centre after the shift
const SPIN_IDLE := 1.6         ## rad/s with no one in sight
const SPIN_DIVE := 18.0        ## rad/s through a dive
const REV_UP := 26.0           ## rad/s^2 running up
const REV_DOWN := 10.0         ## rad/s^2 winding down
const LIFT_DIVE := 0.36        ## rad the blades lift toward level through a dive
const LIFT_RATE := 2.4         ## rad/s
var _rig_ready := false
var _blades_e: Array = []
var _hub := Vector3.ZERO           ## body frame
var _lift_axis := Vector3.RIGHT    ## body frame; a positive turn about it raises the tips
var _spin := 0.0
var _spin_rate := 0.0
var _lift := 0.0
var _was_diving := false

func _ready() -> void:
	super._ready()
	max_health = 120.0
	move_speed = 7.2
	sight_range = 40.0
	attack_range = 3.4          # melee reach for the blades
	preferred_range = 3.0       # stays close and dives in
	attack_cooldown = 0.7
	hover_height = 2.2
	hover_amplitude = 0.4
	score_value = 190
	drops_loot = true
	hp.max_health = max_health
	hp.current_health = max_health

## _process, not physics, so the codex preview (physics disabled) whirls too.
func _process(delta: float) -> void:
	super._process(delta)
	_tick_rig(delta)

## Spinning-blade melee instead of the drone's projectile.
func _perform_attack() -> void:
	if target == null or not is_instance_valid(target):
		return
	recoil = 1.0
	if global_position.distance_to(target.global_position) <= attack_range * 1.3:
		var d = target.get_node_or_null("Damageable")
		if d:
			d.apply_damage(slash_damage, self)
		AudioBus.play_synth_at("impact_metal", global_position, -4.0, 1.7)

## Find the parts once the fit has landed (RobotModel hides the mesh until
## then). The hub is the blades' root, the top 12 cm of them: they hang from
## the fist. The model is shifted so the hub sits on the body's axis, HUB_Y
## up, and the blades' reach from it gives the axis they lift about.
func _setup_rig() -> void:
	var model := get_node_or_null("Model") as RobotModel
	var blades := model.find_child("Blades", true, false) as MeshInstance3D if model else null
	if blades == null or not blades.is_visible_in_tree():
		return
	_rig_ready = true # one attempt: a model without the parts keeps still
	if model.find_child("Core", true, false) == null:
		return
	var top := -INF
	var faces: PackedVector3Array = blades.mesh.get_faces()
	for v in faces:
		top = maxf(top, (blades.global_transform * v).y)
	var root := PackedVector3Array()
	for v in faces:
		var w: Vector3 = blades.global_transform * v
		if w.y > top - 0.12:
			root.append(model.to_local(w))
	model.recentre(PartRig.mean(root), HUB_Y)
	_hub = Vector3(0.0, HUB_Y, 0.0)
	var reach := Vector3.ZERO
	for p in PartRig.body_points(self, blades):
		var d := p - _hub
		if d.length() > 1.5:
			reach += Vector3(d.x, 0.0, d.z)
	_lift_axis = reach.normalized().cross(Vector3.UP)
	_blades_e = PartRig.entry(self, blades)
	_spin_rate = SPIN_IDLE

func _engaged() -> bool:
	return target != null and is_instance_valid(target) and state in [State.ALERT, State.CHASE, State.ATTACK]

## Whirl, rev and lift the blades (see the class doc).
func _tick_rig(delta: float) -> void:
	if not _rig_ready:
		_setup_rig()
		return
	if _blades_e.is_empty():
		return
	var dead := state == State.DEAD or _dying
	var want := 0.0
	if not dead:
		want = SPIN_DIVE if _diving else (spin_speed if _engaged() else SPIN_IDLE)
	if _diving and not _was_diving and not dead:
		AudioBus.play_synth_at("rotor_whir", global_position, -4.0, 2.1)
	_was_diving = _diving
	_spin_rate = move_toward(_spin_rate, want, (REV_UP if want > _spin_rate else REV_DOWN) * delta)
	_spin = fposmod(_spin + _spin_rate * delta, TAU)
	_lift = move_toward(_lift, LIFT_DIVE if _diving and not dead else 0.0, LIFT_RATE * delta)
	PartRig.pose(_blades_e, PartRig.turn(_hub, Vector3.UP, _spin) * PartRig.turn(_hub, _lift_axis, _lift))
