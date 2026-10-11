extends Node
## Probe: every clip an enemy scene asks its RobotModel to play exists in that
## model. RobotModel skips a missing name silently (has_animation), so a typo
## or a clip from another rig leaves the robot frozen in its rest pose with no
## error. Covers every scene in LevelBuilder.ENEMY_SCENES: anim_idle,
## anim_walk, anim_attack and anim_stagger, when set. A static model (no
## AnimationPlayer at all) has nothing to play and is skipped.
##   godot --headless --path . --audio-driver Dummy res://tests/robot_anim_names_probe.tscn

const FIELDS := ["anim_idle", "anim_walk", "anim_attack", "anim_stagger"]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	var checked := 0
	var paths: Array = LevelBuilder.ENEMY_SCENES.values()
	paths.sort()
	var seen := {}
	for path in paths:
		if seen.has(path):
			continue
		seen[path] = true
		var e: Node = (load(String(path)) as PackedScene).instantiate()
		e.set_process_mode(Node.PROCESS_MODE_DISABLED)
		add_child(e)
		var model: Node = e.get_node_or_null("Model")
		if model and model.get_script() == preload("res://scripts/enemies/robot_model.gd"):
			var aps := model.find_children("*", "AnimationPlayer", true, false)
			var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
			for f in (FIELDS if ap != null else []):
				var want := String(model.get(f))
				if want == "":
					continue
				checked += 1
				if not ap.has_animation(want):
					ok = false
					print("FAIL %s: %s = \"%s\" is not a clip of its model (has: %s)" % [String(path).get_file(), f, want,
							", ".join(Array(ap.get_animation_list()).slice(0, 6))])
		e.free()
	print("checked %d clip names across %d enemy scenes" % [checked, seen.size()])
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
