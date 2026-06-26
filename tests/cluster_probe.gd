extends Node3D
## Confirms the OMEGA/NOVA cluster-carpet actually detonates its staggered
## bomblets. Counts grenade_explosion instances in the scene right after the
## primary blast vs after the cluster timers should have fired.
## Run: godot --headless --path . --quit-after 200 res://tests/cluster_probe.tscn

const OMEGA_PROJ := "res://scenes/weapons/projectile_omega.tscn"

func _blast_count() -> int:
	var n := 0
	for c in get_children():
		if c.scene_file_path.ends_with("grenade_explosion.tscn"):
			n += 1
	return n

func _ready() -> void:
	var proj: Projectile = (load(OMEGA_PROJ) as PackedScene).instantiate()
	add_child(proj)
	proj.global_position = Vector3.ZERO
	proj.launch(Vector3(0, 0, -1), self, 100.0, 5.0, 80.0)
	# Detonate immediately at the origin.
	proj._explode(Vector3.ZERO)
	await get_tree().process_frame
	var immediate := _blast_count()
	# Cluster: cluster_count * cluster_delay seconds of staggered timers.
	await get_tree().create_timer(1.0).timeout
	var after := _blast_count()
	print("CLUSTER immediate_blasts=%d  after_cluster=%d  bomblets=%d" % [immediate, after, after - immediate])
	print("CLUSTER ", "OK" if (after - immediate) >= 5 else "FAIL")
	get_tree().quit()
