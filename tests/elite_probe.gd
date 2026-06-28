extends Node
## Dev probe: exercises Elite.maybe_apply the way the spawners do — on a freshly
## instantiated enemy BEFORE it enters the tree — with a forced roll, to catch the
## "absolute get_node from outside the tree" regression and confirm an affix lands.
##   godot --headless --path . res://tests/elite_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene: PackedScene = load("res://scenes/enemies/android.tscn")
	var ok := true
	var applied := 0
	for i in 12:
		var e: Node3D = scene.instantiate()
		Elite.maybe_apply(e, 1.0)   # chance 1.0 -> always rolls; called pre-add (the real path)
		if String(e.get("elite")) != "":
			applied += 1
		get_tree().root.add_child(e) # let _ready + Elite._finalize run
		e.queue_free()
		await get_tree().process_frame
	print("ELITE forced=12 affixed=%d" % applied)
	if applied != 12:
		ok = false
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
