extends Node
## Dev probe: validates bone-collapse limb dismemberment.
## (1) crossing the CRITICAL damage threshold (2nd shed stage) severs a limb:
##     a severable bone's pose scale collapses to ~0 and the loss is recorded;
## (2) losses are capped at LIMB_LOSS_MAX and never re-sever the same subtree;
## (3) a chassis WITHOUT a skeleton no-ops cleanly (no errors, no loss count);
## (4) death tears one more limb off (up to the cap).
##   godot --headless --path . res://tests/limbloss_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true

	# 1+2. Skeleton chassis (mech: arms + legs) loses limbs at damage stages.
	var e: Node3D = load("res://scenes/enemies/mech.tscn").instantiate()
	get_tree().root.add_child(e)
	await get_tree().physics_frame
	var skel: Skeleton3D = e.find_children("*", "Skeleton3D", true, false)[0]
	# Damage to just past the 0.66 threshold (stage 1 = weak core, no limb yet)...
	e.hp.apply_damage(e.hp.max_health * 0.4, null)
	await get_tree().physics_frame
	var stage1_intact: bool = e._limb_losses == 0
	# ...then past 0.33 (stage 2): a limb must go.
	e.hp.apply_damage(e.hp.max_health * 0.35, null)
	await get_tree().physics_frame
	var lost_one: bool = e._limb_losses == 1
	var collapsed := false
	for i in skel.get_bone_count():
		if skel.get_bone_pose_scale(i).length() < 0.01:
			collapsed = true
			break
	print("SEVER: stage1_intact=%s lost_one=%s bone_collapsed=%s severed_marked=%d" % [stage1_intact, lost_one, collapsed, e._severed_bones.size()])
	if not (stage1_intact and lost_one and collapsed and e._severed_bones.size() >= 1):
		ok = false

	# 4. Death rips one more (cap 2).
	e.hp.apply_damage(99999.0, null)
	await get_tree().physics_frame
	var after_death: int = e._limb_losses
	print("DEATH: losses=%d (cap=%d)" % [after_death, e.LIMB_LOSS_MAX])
	if after_death != 2:
		ok = false
	e.queue_free()

	# 3. No-skeleton chassis no-ops.
	var d: Node3D = load("res://scenes/enemies/dog.tscn").instantiate()
	get_tree().root.add_child(d)
	d.global_position = Vector3(0, 0, 30)
	await get_tree().physics_frame
	var did: bool = d._dismember_limb(Vector3.FORWARD)
	print("NOSKEL: dismember_returned=%s losses=%d" % [did, d._limb_losses])
	if did or d._limb_losses != 0:
		ok = false
	d.queue_free()

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
