extends Node3D
## Diagnostic: instantiate the Tesla, simulate holding the trigger, and report
## whether the ElectricBeam activates (lightning visible).
##   godot --headless --path . res://tests/tesla_beam_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(0, 1, 0)
	var w: Node3D = load("res://scenes/weapons/tesla.tscn").instantiate()
	add_child(w)
	await get_tree().process_frame
	await get_tree().process_frame
	var data = w.get("data")
	print("fire_mode=", data.fire_mode, " (BEAM=", WeaponData.FireMode.BEAM, ")")
	print("mag=", w.get("mag"), " visible=", w.visible, " muzzle=", w.get("muzzle"))
	# Hold the trigger and run several frames.
	for i in 6:
		w.try_fire(true, false, cam, self)
		await get_tree().process_frame
	var beam = w.get("_beam")
	var core_vis := false
	var arcs_vis := 0
	if beam:
		var core = beam.get("_core")
		if core:
			core_vis = core.visible
		for seg in beam.get("_arcs"):
			if seg.visible:
				arcs_vis += 1
	print("beam_exists=", beam != null, " core_visible=", core_vis, " arcs_visible=", arcs_vis)
	var ok := beam != null and core_vis and arcs_vis > 0
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
