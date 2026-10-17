extends Node3D
## Probe: a dead skinned robot's limbs go limp (#259). Physics wrecks
## (WreckBody) threw each robot as one rigid box and the rig tumbled stiff in
## its last clip pose. For a legged GUNNER, an armed STILT MECH and a SENTINEL
## (arms, legs, head): kill it 15 m up, then hold its wreck still on its side in mid-air.
## Read in skeleton_updated (the pose that renders, after every modifier), the
## limb bones (LimpLimbsModifier.is_limb) of a stiff rig point sideways; limp
## ones hang: their mean angle from straight down must fall by LIMP_DEG within
## 1.5 s. A wreck on the floor stays above it (FLOOR_GAP), checked separately.
##   godot --headless --path . --audio-driver Dummy res://tests/limb_flop_probe.tscn

const LIMP_DEG := 20.0

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _floor() -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_position = Vector3(0, -0.5, 0)

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _spawn(scene: String, pos: Vector3) -> EnemyBase:
	var e := (load("res://scenes/enemies/%s.tscn" % scene) as PackedScene).instantiate() as EnemyBase
	add_child(e)
	e.global_position = pos
	await _wait(40)
	e.set_physics_process(false)
	e.velocity = Vector3.ZERO
	e.global_position = pos
	return e

func _wreck_of(e: Node) -> WreckBody:
	for b in get_tree().get_nodes_in_group("wreck_bodies"):
		if (b as WreckBody).follower == e:
			return b
	return null

## Mean angle (deg) between each limb bone's rendered +Y axis and straight down,
## and the lowest limb joint height, from the next skeleton_updated. Outside
## that signal the skeleton holds the stiff clip pose again, so "low_stiff" is
## the same measure without the modifier.
func _limbs(sk: Skeleton3D) -> Dictionary:
	var out := {}
	var grab := func() -> void:
		var sum := 0.0
		var n := 0
		var low := INF
		for i in sk.get_bone_count():
			if not LimpLimbsModifier.is_limb(sk.get_bone_name(i)):
				continue
			var pose := sk.get_bone_global_pose(i)
			if pose.basis.get_scale().x < 0.01:
				continue
			var ax := (sk.global_transform.basis * pose.basis.y).normalized()
			sum += rad_to_deg(ax.angle_to(Vector3.DOWN))
			n += 1
			for c in sk.get_bone_children(i):
				low = minf(low, (sk.global_transform * sk.get_bone_global_pose(c)).origin.y)
		out["deg"] = sum / maxf(n, 1)
		out["n"] = n
		out["low"] = low
	sk.skeleton_updated.connect(grab, CONNECT_ONE_SHOT)
	for i in 3:
		await get_tree().process_frame
		if out.has("deg"):
			break
	var limp := out.duplicate()
	if limp.is_empty():
		# Nothing modifies the paused rig, so it never updates: the stored
		# pose is the rendered one.
		sk.skeleton_updated.disconnect(grab)
	grab.call()
	if limp.is_empty():
		limp = out.duplicate()
	limp["low_stiff"] = out["low"]
	return limp

func _run() -> void:
	_floor()
	var x := -12.0
	for scene in ["gunner", "mech", "sentinel"]:
		var e := await _spawn(scene, Vector3(x, 15.0, 0))
		x += 12.0
		var sk := e.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		e.hp.apply_damage(99999.0, self)
		await _wait(2)
		var wb := _wreck_of(e)
		_check("%s: dies into a physics wreck" % scene, wb != null)
		if wb == null:
			continue
		# Hold it on its side in mid-air: a stiff rig's limbs point sideways now.
		wb.freeze = true
		wb.linear_velocity = Vector3.ZERO
		wb.angular_velocity = Vector3.ZERO
		wb.global_transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), wb.global_position)
		await _wait(2)
		var before := await _limbs(sk)
		await _wait(90)
		var after := await _limbs(sk)
		_check("%s: has limb bones to flop" % scene, int(before.get("n", 0)) >= 2, "%d" % int(before.get("n", 0)))
		_check("%s: its limbs hang toward the ground" % scene,
			float(before.get("deg", 0.0)) - float(after.get("deg", 0.0)) >= LIMP_DEG,
			"mean %.0f -> %.0f deg from straight down" % [float(before.get("deg", 0.0)), float(after.get("deg", 0.0))])
		# Killed on the floor: until its wreck settles (and starts its sink), no
		# limb joint goes through the floor.
		var f := await _spawn(scene, Vector3(x - 12.0, 0.05, 20.0))
		var fsk := f.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		f.hp.apply_damage(99999.0, self)
		await _wait(2)
		var fwb := _wreck_of(f)
		var settled := [false]
		if fwb:
			fwb.settled.connect(func() -> void: settled[0] = true)
		var lowest := INF
		var lowest_stiff := INF
		for i in 30:
			if settled[0] or not is_instance_valid(f):
				break
			var l := await _limbs(fsk)
			lowest = minf(lowest, float(l.get("low", INF)))
			lowest_stiff = minf(lowest_stiff, float(l.get("low_stiff", INF)))
			await _wait(5)
		# The chassis box is an approximation, so a stiff rig can already reach
		# into the floor (the gunner's long legs, ~0.8 m): hanging must not
		# take a limb any deeper than that, or under the floor at all otherwise.
		_check("%s: falling over on the floor, its limbs go no deeper than stiff ones" % scene,
			lowest > minf(lowest_stiff, 0.0) - 0.15,
			"lowest limb joint y %.2f (stiff %.2f)" % [lowest, lowest_stiff])
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
