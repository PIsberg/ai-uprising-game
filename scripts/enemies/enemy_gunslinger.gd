class_name EnemyGunslinger
extends EnemyAndroid
## GUNSLINGER — a brass steampunk automaton with a heavy revolver arm. It fires
## single, hard-hitting slugs on a slow cadence rather than spraying, and dances
## to the side between shots. Punishing if you stand still; easy to bait into a
## wasted shot.
## Its revolver hangs at the end of its right forearm. Engaged, it raises the
## forearm about the elbow onto you (both forearms are one mesh in the GLB,
## Object_158, split per side by PartRig) and every slug leaves the gun's
## tip; disengaged the arm drops back to its side. tests/gunslinger_arm_probe.
## It walks on its legs (tests/biped_gait_probe): the GLB is cut offline
## (tools/blender/cfg_steampunk_robot_parts.json) into `Body`, `LegL` and
## `LegR` below the hips, and a `BipedGait` swings each leg about its hip (the
## top of its bounds), the two in opposition, at a cadence from ground speed.

const FOREARMS := "Object_158"
const LEGS := ["LegL", "LegR"]
var _gait := BipedGait.new(1.2, 0.42) ## 1.2 m a stride, 0.42 rad each side at full speed
var _gait_tried := false
const ARM_RATE := 6.0 ## 1/s: arm up in about 0.17 s
var _arm: AimedPart

func _ready() -> void:
	super._ready()
	max_health = 130.0
	move_speed = 6.2      # lean, nimble duelist — quicker than a standard android
	turn_speed = 9.5
	attack_range = 32.0
	preferred_range = 18.0
	hitscan_damage = 26.0
	burst_count = 1       # one heavy slug
	score_value = 200
	hp.max_health = max_health
	hp.current_health = max_health

## Duelist footwork: every slug is punctuated by a sidestep, so the gunslinger is
## always sliding to a new angle between shots — the "dances to the side" the
## brass-revolver model promises — instead of planting like a stock android. It
## reuses the android's own juke movement by kicking its dodge state on each shot
## (alternating direction for a deliberate weave, not the occasional random juke).
func _physics_process(delta: float) -> void:
	if state != State.DEAD:
		_tick_arm(delta) # before the slug this tick may fire
		_tick_gait(delta)
	super._physics_process(delta)

## Find the leg parts once RobotModel's fit has landed; each hip is the top
## of its leg's bounds on the leg's own centre line.
func _setup_gait() -> void:
	var parts: Array = []
	for n in LEGS:
		var mi := find_child(n, true, false) as MeshInstance3D
		if mi == null:
			return # a model without the cut parts (a stale import) keeps still, quietly
		parts.append(mi)
	if not (parts[0] as MeshInstance3D).is_visible_in_tree():
		return
	_gait_tried = true
	for side in 2:
		var mi: MeshInstance3D = parts[side]
		var box: AABB = rig_frame().affine_inverse() * (mi.global_transform * mi.mesh.get_aabb())
		var c := box.get_center()
		_gait.add_leg([PartRig.entry(self, mi)], Vector3(c.x, box.end.y - 0.02, c.z), side)

func _tick_gait(delta: float) -> void:
	if not _gait_tried:
		_setup_gait()
		return
	_gait.tick(delta, Vector2(velocity.x, velocity.z).length(), move_speed)

## Split the forearms once RobotModel's fit has landed; the gun-arm is the
## right one (x > 0): elbow its top band, tip its far end.
func _setup_arm() -> void:
	var mi := find_child(FOREARMS, true, false) as MeshInstance3D
	if mi == null or not mi.is_visible_in_tree():
		return
	var halves := PartRig.split_x(self, mi, 0.0)
	if halves[1] == null:
		return
	var pts := PartRig.body_points(self, halves[1][0])
	var elbow := AimedPart.band_mean(pts, Vector3.UP, 0.04)
	_arm = AimedPart.new([halves[1]], elbow, AimedPart.far_mean(pts, elbow, 0.03), ARM_RATE)

func _tick_arm(delta: float) -> void:
	if _arm == null:
		_setup_arm()
		return
	var live := target != null and is_instance_valid(target)
	var engaged := live and state in [State.CHASE, State.ATTACK]
	var at: Variant = target.global_position + Vector3.UP * 0.6 if live else null
	var tip := _arm.tick(self, at, engaged, delta)
	if muzzle:
		muzzle.global_position = tip

func _start_burst() -> void:
	super._start_burst()
	_dodge_dir = -_dodge_dir
	_dodge_time = 0.4
	_dodge_cd = 0.8   # space the next natural juke so the weave stays per-shot, not constant
