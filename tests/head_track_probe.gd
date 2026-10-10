extends Node
## Probe: skinned robots turn their head (and torso, where the rig has one) to
## look at what they are fighting (HeadTrackModifier via RobotModel).
## For each of eight chassis families, with the body held still and the clip paused:
## (1) idle, no target: the head sits in its animated pose;
## (2) target 35 deg right and 20 deg up: the head swings to face it (< 7 deg);
## (3) target 160 deg round behind it: the turn stops at the yaw limit;
## (4) target dropped: the head eases back to rest;
## (5) dead: the modifier is off, so the corpse keeps its clip pose.
## The head's facing is measured as the head bone's world rotation since rest,
## applied to the body's forward, so it works whatever axis each rig's bone uses.
##   godot --headless --path . --audio-driver Dummy res://tests/head_track_probe.tscn

const SCENES := [
	"res://scenes/enemies/android.tscn",   # FBX mech (Leela)
	"res://scenes/enemies/brute.tscn",     # FBX mech (Mike)
	"res://scenes/enemies/mech.tscn",      # FBX mech (Stan)
	"res://scenes/enemies/gunner.tscn",    # Body / Head
	"res://scenes/enemies/sentinel.tscn",  # Torso / Neck / Head
	"res://scenes/enemies/rollback.tscn",  # Torso / Chest / Neck / Head
	"res://scenes/enemies/quantizer.tscn", # flyer: Head
	"res://scenes/enemies/alien.tscn",     # flyer: Body / Head
]
var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _wait(sec: float) -> void:
	var n := int(ceil(sec / 0.25))
	for i in n:
		await get_tree().create_timer(0.25).timeout

func _ready() -> void:
	_run.call_deferred()

## The head bone's world rotation as the renderer last skinned it: read in
## skeleton_updated, after the modifiers ran (outside it the pose is the clip's).
var _seen := {}
var _skels: Array[Skeleton3D] = []

## With the clip frozen nothing dirties the skeleton, so it would never re-run
## its modifiers; re-set the root bone's own pose each frame to keep it updating.
func _process(_delta: float) -> void:
	for sk in _skels:
		if is_instance_valid(sk):
			sk.set_bone_pose_position(0, sk.get_bone_pose_position(0))

func _watch(e: EnemyBase) -> void:
	var b: Dictionary = e._head_bone()
	var skel: Skeleton3D = b["skel"]
	var idx: int = b["idx"]
	_skels.append(skel)
	skel.skeleton_updated.connect(func():
		var g := skel.global_transform * skel.get_bone_global_pose(idx)
		_seen[e] = [g.basis.orthonormalized().get_rotation_quaternion(), g.origin])

func _head_q(e: EnemyBase) -> Quaternion:
	return _seen[e][0]

func _head_pos(e: EnemyBase) -> Vector3:
	return _seen[e][1]

## Where the body's forward points once the head's rotation since `rest` is applied.
func _facing(e: EnemyBase, rest: Quaternion) -> Vector3:
	var r := _head_q(e) * rest.inverse()
	return (r * -e.global_transform.basis.z).normalized()

func _dir(yaw_deg: float, pitch_deg: float) -> Vector3:
	# Body faces -Z; positive yaw turns to its right (+X), positive pitch looks up.
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))

func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	add_child(floor_body)
	var marker := Node3D.new()
	add_child(marker)

	for path in SCENES:
		var tag: String = String(path).get_file().get_basename()
		var e := (load(path) as PackedScene).instantiate() as EnemyBase
		add_child(e)
		await _wait(0.75) # fit + rig posed
		e.set_physics_process(false) # hold the body still: only the head moves
		e.velocity = Vector3.ZERO
		e.state = EnemyBase.State.IDLE
		e.target = null
		var anim := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			anim.active = false # freeze the clip: only the modifier moves the head
		if e._head_bone().is_empty():
			_check("%s has a head bone" % tag, false)
			e.queue_free()
			continue
		_watch(e)
		var mod := e.find_children("*", "HeadTrackModifier", true, false)
		_check("%s carries a HeadTrackModifier" % tag, mod.size() == 1, "found %d" % mod.size())
		await _wait(0.5)
		var rest := _head_q(e)
		var fwd := -e.global_transform.basis.z

		# 2. Look at an off-axis target inside the cone.
		var body := e.global_transform.basis.orthonormalized()
		var want := body * _dir(35.0, 20.0)
		marker.global_position = _head_pos(e) + want * 10.0
		e.target = marker
		e.state = EnemyBase.State.ATTACK
		await _wait(1.5)
		var f := _facing(e, rest)
		var err := rad_to_deg(f.angle_to((marker.global_position - _head_pos(e)).normalized()))
		_check("%s looks at a target 35 right / 20 up" % tag, err < 7.0, "off by %.1f deg" % err)

		# 3. Behind it: clamped at the yaw limit, never wrenched round.
		marker.global_position = _head_pos(e) + body * _dir(160.0, 0.0) * 10.0
		await _wait(1.5)
		f = _facing(e, rest)
		var turn := rad_to_deg(Vector2(f.x, f.z).angle_to(Vector2(fwd.x, fwd.z)))
		_check("%s stops at the yaw limit" % tag,
			absf(absf(turn) - HeadTrackModifier.MAX_YAW_DEG) < 6.0, "turned %.1f deg" % turn)

		# 4. Target dropped: back to rest.
		e.target = null
		e.state = EnemyBase.State.PATROL
		await _wait(1.5)
		f = _facing(e, rest)
		var back := rad_to_deg(f.angle_to(fwd))
		_check("%s eases back to rest" % tag, back < 3.0, "%.1f deg off rest" % back)

		# 5. Dead: modifier off.
		e.target = marker
		e.state = EnemyBase.State.ATTACK
		await _wait(0.5)
		e.state = EnemyBase.State.DEAD
		await _wait(0.5)
		_check("%s modifier is off once dead" % tag,
			mod.size() == 1 and not (mod[0] as SkeletonModifier3D).active)
		e.queue_free()
		await _wait(0.25)

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
