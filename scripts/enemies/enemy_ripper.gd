class_name EnemyRipper
extends EnemyAndroid
## RIPPER — a walking minigun platform (robot_minigun.glb: a stocky mech with
## a three-barrel minigun slung at its hips; the barrel cluster was pure
## dressing while this fired like any android with a longer burst, from a
## point up at its left shoulder). Now it fights like the model looks:
##  - SPIN-UP: the barrels wind up, audibly and visibly, for a beat before
##    the saw starts — the cue to get moving (the android fires instantly;
##    this one telegraphs).
##  - WALKING SAW: the stream aims at a point that TRAILS the player and only
##    slowly catches up, so the line of tracers visibly walks onto you —
##    strafing out of it is real counter-play, not a dice roll. The gun
##    itself turns onto that point, so you see it walking.
##  - GRINDING ADVANCE: it never plants while sawing — it closes at a slow,
##    implacable walk, denying the "trade from one piece of cover" stalemate.
##
## Rig. The model ships the gun as two meshes under the animated Body_top:
## the barrel cluster (`Weapon_MinigunBarrel`, under a `Barrel` node whose
## +Z runs down the gun's axis) and the housing (`Weapon_Minigun`).
## `_setup_rig` takes both once the fit has landed, hangs the muzzle on the
## housing at the cluster's far end, and aims the whole gun about the rear
## of the housing with an `AimedPart` while the cluster spins about the
## axis in its own frame: wound up through the spin-up (0 to BARREL_SPIN
## rad/s; the saw starts the moment it is at speed), held through the saw,
## run down after. Each shot leaves the cluster's tip. tests/ripper_rig_probe.

const BARREL_SPIN := 45.0     ## rad/s, the saw running
const SPIN_UP := 100.0        ## rad/s^2 through the spin-up tell (0.45 s)
const SPIN_DOWN := 30.0       ## rad/s^2 once the saw stops
const GUN_RATE := 6.0         ## 1/s the gun eases onto the saw point and back
const BARREL_NAME := "Weapon_MinigunBarrel_SimpleMilitary_Weapon_MiniGun_0"
const HOUSING_NAME := "Weapon_Minigun_SimpleMilitary_Weapon_MiniGun_0"

var _saw_aim: Vector3 = Vector3.ZERO
var _spinning: bool = false
var _rig_ready := false
var _gun: AimedPart = null
var _barrels_e: Array = []
var _housing_e: Array = []
var _barrels_rest: Transform3D  ## the cluster's rest transform in its parent
var _axis_local := Vector3.FORWARD ## the gun's axis in the cluster's own frame
var _pivot_local := Vector3.ZERO   ## a point on it, likewise
var _spin := 0.0
var _spin_rate := 0.0

func _ready() -> void:
	super._ready()
	max_health = 170.0
	move_speed = 3.6
	turn_speed = 6.0
	attack_range = 28.0
	preferred_range = 15.0
	hitscan_damage = 5.0
	burst_count = 12      # a long minigun saw
	score_value = 230
	hp.max_health = max_health
	hp.current_health = max_health

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state != State.DEAD:
		_tick_rig(delta)

func _state_attack(delta: float) -> void:
	super._state_attack(delta)
	# Grinding advance: while the saw runs, keep walking at the target.
	if _burst_remaining > 0 and target and is_instance_valid(target):
		var to := target.global_position - global_position
		to.y = 0.0
		if to.length() > 3.0:
			var d := to.normalized()
			velocity.x = d.x * chase_speed() * 0.45
			velocity.z = d.z * chase_speed() * 0.45

## Spin-up gate in front of the android's instant burst: the saw starts when
## the barrels reach speed (BARREL_SPIN / SPIN_UP = 0.45 s), in _tick_rig.
func _start_burst() -> void:
	if _spinning:
		return
	_spinning = true
	AudioBus.play_synth_at("charge", global_position, -4.0, 0.7)
	recoil = 1.0 # the wind-up jolt fires the attack clip early
	if target and is_instance_valid(target):
		_saw_aim = target.global_position + Vector3.UP * 0.6 # saw starts where you WERE

## The walking saw: each shot chases a lagging aim point instead of the
## android's per-shot perfect tracking.
func _fire_one_shot() -> void:
	if target == null or muzzle == null:
		return
	_saw_aim = _saw_aim.lerp(target.global_position + Vector3.UP * 0.6, 0.22)
	recoil = 1.0
	if muzzle_flash_scene:
		muzzle.add_child(muzzle_flash_scene.instantiate())
	AudioBus.play_synth_at("drone_shot", muzzle.global_position, -5.0, randf_range(1.25, 1.35))
	var origin := muzzle.global_position
	var dir := scatter_aim((_saw_aim - origin).normalized(), burst_spread_deg)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0)
	q.collision_mask = 0b0000011 # world + player
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	var end_point := origin + dir * 80.0
	if not hit.is_empty():
		end_point = hit.position
		var col: Node = hit.collider
		var d: Node = col.get_node_or_null("Damageable") if col else null
		if d:
			d.apply_damage(hitscan_damage, self)
	if tracer_scene:
		var t := tracer_scene.instantiate()
		get_tree().current_scene.add_child(t)
		if t.has_method("setup"):
			t.setup(origin, end_point)

## The saw is running up or running: the gun tracks the saw point.
func _sawing() -> bool:
	return _spinning or _burst_remaining > 0

## Take the gun's two meshes once the fit has landed (RobotModel hides the
## mesh until then). The model's Barrel node sits on the gun's axis with
## its +Z down the barrels; the tip is the cluster's far end on that line.
func _setup_rig() -> void:
	var model := get_node_or_null("Model")
	var barrels := model.find_child(BARREL_NAME, true, false) as MeshInstance3D if model else null
	var housing := model.find_child(HOUSING_NAME, true, false) as MeshInstance3D if model else null
	var marker := model.find_child("Barrel", true, false) as Node3D if model else null
	if barrels == null or housing == null or marker == null or not barrels.is_visible_in_tree():
		return
	_rig_ready = true # one attempt: a model without the parts fires as before
	_barrels_e = PartRig.entry(self, barrels)
	_housing_e = PartRig.entry(self, housing)
	_barrels_rest = _barrels_e[1]
	var in_barrels: Transform3D = barrels.global_transform.affine_inverse() * marker.global_transform
	_axis_local = in_barrels.basis.z.normalized()
	_pivot_local = in_barrels.origin
	var frame := rig_frame()
	var on_axis: Vector3 = frame.affine_inverse() * marker.global_transform.origin
	var fwd: Vector3 = (frame.basis.inverse() * marker.global_transform.basis.z).normalized()
	var far := AimedPart.band_mean(PartRig.body_points(self, barrels), fwd, 0.03)
	var tip: Vector3 = on_axis + fwd * (far - on_axis).dot(fwd)
	# The muzzle: a node on the housing (it does not spin) at the tip, its
	# -Z down the gun as the scene's Muzzle node had it.
	var m := Node3D.new()
	m.name = "GunMuzzle"
	housing.add_child(m)
	m.global_transform = Transform3D(Basis.looking_at(frame.basis * fwd, Vector3.UP), frame * tip)
	muzzle = m
	# The gun pivots on the rear of the housing, on its axis.
	var rear := AimedPart.band_mean(PartRig.body_points(self, housing), -fwd, 0.03)
	var pivot: Vector3 = on_axis + fwd * (rear - on_axis).dot(fwd)
	_gun = AimedPart.new([_barrels_e, _housing_e], pivot, tip, GUN_RATE)

## Spin the barrels and aim the gun (see the class doc).
func _tick_rig(delta: float) -> void:
	if not _rig_ready:
		_setup_rig()
	var want := BARREL_SPIN if _sawing() else 0.0
	_spin_rate = move_toward(_spin_rate, want, (SPIN_UP if want > _spin_rate else SPIN_DOWN) * delta)
	_spin = fposmod(_spin + _spin_rate * delta, TAU)
	if _spinning and _spin_rate >= BARREL_SPIN:
		_spinning = false
		_burst_remaining = burst_count
		_burst_timer = 0.0
		_bark_attack()
	if _gun == null:
		return
	# The spin lives in the cluster's rest: AimedPart poses each entry as
	# aim * rest, so a rest that already carries the turn about the gun's
	# own axis spins the cluster inside whatever aim the gun is at.
	_barrels_e[1] = _barrels_rest * PartRig.turn(_pivot_local, _axis_local, _spin)
	var aim: Variant = _saw_aim if _sawing() else null
	_gun.tick(self, aim, _sawing(), delta)
