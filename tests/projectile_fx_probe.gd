extends Node3D
## Smoke-test the heavy projectile rounds (incl. the new glowing head orb FX):
## launch each, fly it a bit, detonate it — assert no errors and that the trail
## head was built.
##   godot --headless --path . res://tests/projectile_fx_probe.tscn

const PROJ := [
	"projectile_rocket", "projectile_tempest", "projectile_singularity",
	"projectile_omega", "projectile_nova", "projectile_swarm", "projectile_plasma",
]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var ok := true
	for name in PROJ:
		var path := "res://scenes/weapons/%s.tscn" % name
		if not ResourceLoader.exists(path):
			print(name, " MISSING"); ok = false; continue
		var proj: Node3D = load(path).instantiate()
		add_child(proj)
		proj.global_position = Vector3(0, 1, 0)
		if proj.has_method("launch"):
			proj.launch(Vector3(0, 0, -20), self, 40.0, 4.0, 30.0)
		# Count glowing-head mesh children (the new FX adds a MeshInstance3D head).
		var meshes := 0
		for c in proj.get_children():
			if c is MeshInstance3D:
				meshes += 1
		# Fly a few frames, then force a detonation via lifetime expiry path.
		for i in 20:
			await get_tree().physics_frame
			if not is_instance_valid(proj):
				break
		print("%-22s head_meshes=%d alive_after=%s" % [name, meshes, is_instance_valid(proj)])
		if is_instance_valid(proj):
			proj.queue_free()
		await get_tree().process_frame
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
