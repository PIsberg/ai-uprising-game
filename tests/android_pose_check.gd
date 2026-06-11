extends Node3D
## Headless pose regression for the posable helper-robot rig the intro cutscene
## uses (the combat android now uses an imported model): hands and rifle must
## sit in FRONT of the body (-Z, the facing direction), not behind it. Checks
## both the rest pose and the animated idle pose.

func _ready() -> void:
	var bot: Node3D = load("res://scenes/cutscene/helper_robot.tscn").instantiate()
	add_child(bot)
	bot.set_physics_process(false)
	# Rest pose first, like level_briefing.gd shows it.
	var at := bot.get_node("AnimationTree") as AnimationTree
	at.active = false
	await get_tree().process_frame
	var hand := bot.get_node("Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR/HandR") as Node3D
	var muzzle := bot.get_node("Rig/Hips/Spine/ClavicleR/UpperArmR/LowerArmR/HandR/Gun/Muzzle") as Node3D
	var rest_hand_z := hand.global_position.z
	var rest_muzzle_z := muzzle.global_position.z
	# Then the animated idle pose.
	at.active = true
	for i in 5:
		await get_tree().process_frame
	var idle_hand_z := hand.global_position.z
	var idle_muzzle_z := muzzle.global_position.z
	print("POSE_CHECK rest_hand=%.2f rest_muzzle=%.2f idle_hand=%.2f idle_muzzle=%.2f"
		% [rest_hand_z, rest_muzzle_z, idle_hand_z, idle_muzzle_z])
	var ok := rest_hand_z < 0.0 and rest_muzzle_z < rest_hand_z \
		and idle_hand_z < 0.0 and idle_muzzle_z < idle_hand_z
	print("POSE_CHECK %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
