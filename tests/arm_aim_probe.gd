extends Node
## Probe: robots that shoot from a gun bone or a hand swing that gun onto their
## target, on top of the clip (HeadTrackModifier arm aim, issue #232).
## For each gun chassis, with the body held still and the clip frozen:
## (1) idle, no target: the gun sits in its animated pose;
## (2) target 25 deg right and 30 deg up: the barrel (pivot -> muzzle, or the
##     midline of a twin gun) points at it within 8 deg;
## (3) the muzzle shots leave from (EnemyBase.muzzle) is on the rendered,
##     aimed barrel, not where the clip alone would put it;
## (4) target dropped: the gun eases back to its clip pose;
## (5) dead: the gun stays where the clip puts it.
## The pivot is the joint the gun swings from, named per rig here: the Gun
## bone for the turret rigs, the upper arm for the STILT MECH's palm.
##   godot --headless --path . --audio-driver Dummy res://tests/arm_aim_probe.tscn

const CASES := [
	["hunter", "Gun"],
	["overfitter", "Gun"],
	["deepfake", "Gun"],
	["diffusion", "Gun"],
	["hive", "Gun"],
	["quantizer", "Gun"],
	["mech", "UpperArm.R"],
	["sniper", "Gun.L"],
]
const AIM_TOL_DEG := 8.0
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

## Rendered poses, read in skeleton_updated (after the modifiers ran; outside
## it the skeleton reports the clip's pose).
var _pivot_w := Vector3.ZERO
var _tip_w := Transform3D.IDENTITY
var _skel: Skeleton3D
var _pivot_idx := -1
var _tip_idx := -1

## A frozen clip never dirties the skeleton: re-set a bone each frame so the
## modifiers keep running.
func _process(_delta: float) -> void:
	if is_instance_valid(_skel):
		_skel.set_bone_pose_position(0, _skel.get_bone_pose_position(0))

func _on_skel_updated() -> void:
	if not is_instance_valid(_skel):
		return
	_pivot_w = (_skel.global_transform * _skel.get_bone_global_pose(_pivot_idx)).origin
	_tip_w = _skel.global_transform * _skel.get_bone_global_pose(_tip_idx)

## The rendered muzzle point: the tip bone's pose plus the muzzle offset in
## its frame (the same rule EnemyBase.bone_point uses).
func _muzzle_w(e: EnemyBase) -> Vector3:
	return _tip_w.origin + _tip_w.basis.orthonormalized() * e._muzzle_offset

## The gun's centre line: pivot to the muzzle, or to midway between the two
## barrels of a twin gun (HUNTER, OVERFITTER), which the gun as a whole faces.
func _barrel(e: EnemyBase) -> Vector3:
	var off: Vector3 = e._muzzle_offset
	if e.muzzle_bone_offset_alt != Vector3.ZERO and e._muzzle_bone.bone_name == e.muzzle_bone:
		off = (e.muzzle_bone_offset + e.muzzle_bone_offset_alt) * 0.5
	return (_tip_w.origin + _tip_w.basis.orthonormalized() * off - _pivot_w).normalized()

func _watch(e: EnemyBase, pivot: String) -> void:
	if is_instance_valid(_skel) and _skel.skeleton_updated.is_connected(_on_skel_updated):
		_skel.skeleton_updated.disconnect(_on_skel_updated)
	_skel = e._muzzle_bone.get_parent() as Skeleton3D
	_pivot_idx = _skel.find_bone(pivot)
	_tip_idx = e._muzzle_bone.bone_idx
	_skel.skeleton_updated.connect(_on_skel_updated)

func _dir(yaw_deg: float, pitch_deg: float) -> Vector3:
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

	for c in CASES:
		var tag: String = c[0]
		var e := (load("res://scenes/enemies/%s.tscn" % tag) as PackedScene).instantiate() as EnemyBase
		add_child(e)
		await _wait(0.75)
		e.set_physics_process(false) # hold the body still
		e.velocity = Vector3.ZERO
		e.state = EnemyBase.State.IDLE
		e.target = null
		var anim := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			anim.active = false
		if e._muzzle_bone == null:
			_check("%s has a bone muzzle" % tag, false)
			e.queue_free()
			continue
		_watch(e, c[1])
		if _pivot_idx < 0:
			_check("%s has pivot bone %s" % [tag, c[1]], false)
			e.queue_free()
			continue
		await _wait(0.5)
		var rest := _barrel(e)

		# 2. Aim at an off-axis target above and to the right.
		var body := e.global_transform.basis.orthonormalized()
		marker.global_position = _pivot_w + body * _dir(25.0, 30.0) * 10.0
		e.target = marker
		e.state = EnemyBase.State.ATTACK
		await _wait(1.5)
		var want := (marker.global_position - _pivot_w).normalized()
		var err := rad_to_deg(_barrel(e).angle_to(want))
		_check("%s barrel points at a target 25 right / 30 up" % tag, err < AIM_TOL_DEG,
			"off by %.1f deg (clip pose was %.1f off)" % [err, rad_to_deg(rest.angle_to(want))])

		# 3. Shots leave from the aimed barrel.
		e._follow_muzzle_bone()
		var gap := e.muzzle.global_position.distance_to(_muzzle_w(e))
		_check("%s muzzle rides the aimed barrel" % tag, gap < 0.15, "%.2f m off" % gap)

		# Sniper: the second barrel aims too.
		if tag == "sniper":
			e._use_barrel(1)
			_tip_idx = e._muzzle_bone.bone_idx
			_pivot_idx = _skel.find_bone("Gun.R")
			await _wait(0.5)
			want = (marker.global_position - _pivot_w).normalized()
			err = rad_to_deg(_barrel(e).angle_to(want))
			_check("sniper second barrel points at the target", err < AIM_TOL_DEG, "off by %.1f deg" % err)
			e._use_barrel(0)
			_tip_idx = e._muzzle_bone.bone_idx
			_pivot_idx = _skel.find_bone(c[1])
			await _wait(0.25)

		# 4. Target dropped: back to the clip pose.
		e.target = null
		e.state = EnemyBase.State.PATROL
		await _wait(1.75)
		var back := rad_to_deg(_barrel(e).angle_to(rest))
		_check("%s gun eases back to its clip pose" % tag, back < 3.0, "%.1f deg off" % back)

		# 5. Dead: the clip owns the gun.
		e.target = marker
		e.state = EnemyBase.State.ATTACK
		await _wait(0.5)
		e.state = EnemyBase.State.DEAD
		await _wait(1.75)
		back = rad_to_deg(_barrel(e).angle_to(rest))
		_check("%s dead gun keeps its clip pose" % tag, back < 3.0, "%.1f deg off" % back)
		e.queue_free()
		await _wait(0.25)

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
