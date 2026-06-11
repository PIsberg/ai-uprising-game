extends Node3D
## Headless regression for the imported robot models: every enemy scene that
## carries a RobotModel must resolve its AnimationPlayer and every configured
## clip, and have visible meshes. Run:
##   godot --headless --path . res://tests/robot_models_check.tscn --quit-after 240

const SCENES := [
	"res://scenes/enemies/android.tscn",
	"res://scenes/enemies/mech.tscn",
	"res://scenes/enemies/colossus.tscn",
	"res://scenes/enemies/brute.tscn",
	"res://scenes/enemies/sniper.tscn",
	"res://scenes/enemies/spider.tscn",
	"res://scenes/enemies/drone.tscn",
	"res://scenes/enemies/seeker.tscn",
	"res://scenes/enemies/overseer.tscn",
]

func _ready() -> void:
	var failures: Array[String] = []
	for path in SCENES:
		var ps: PackedScene = load(path)
		if ps == null:
			failures.append(path + ": scene failed to load")
			continue
		var inst := ps.instantiate()
		var model := inst.get_node_or_null("Model")
		if model == null or not (model is RobotModel):
			failures.append(path + ": no RobotModel on $Model")
			inst.free()
			continue
		var rm := model as RobotModel
		var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim == null:
			failures.append(path + ": no AnimationPlayer under Model")
		else:
			for clip in [rm.anim_idle, rm.anim_walk, rm.anim_attack, rm.anim_stagger]:
				if clip != "" and not anim.has_animation(clip):
					failures.append("%s: missing animation '%s'" % [path, clip])
		if model.find_children("*", "MeshInstance3D", true, false).is_empty():
			failures.append(path + ": no MeshInstance3D under Model")
		inst.free()
	# Live phase: spawn each enemy into the tree for a few frames so _ready and
	# RobotModel's animation/material setup actually run.
	for path in SCENES:
		var bot: Node3D = (load(path) as PackedScene).instantiate()
		add_child(bot)
		bot.global_position = Vector3(0, 0.1, 0)
		for i in 5:
			await get_tree().physics_frame
		var rm := bot.get_node("Model") as RobotModel
		var anim := rm.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim == null or anim.current_animation == "":
			failures.append(path + ": no animation playing after spawn")
		bot.queue_free()
		await get_tree().process_frame
	for f in failures:
		printerr("MODEL_CHECK FAIL ", f)
	print("MODEL_CHECK %s (%d scenes)" % ["OK" if failures.is_empty() else "FAIL", SCENES.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
