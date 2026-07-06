extends Node3D
## Pits Optic (cutting beam) and Roller (ground ram) against a stationary player
## dummy and captures a burst of frames so the new signature behaviour reads.
## Enemies are face-oriented and force-acquired at their trigger distance (a bare
## probe has no navmesh, so they can't path in — but the beam/ram are distance-
## triggered, so we spawn them already in range). Windowed:
##   godot --path . tests/enemy_behavior_probe.tscn

const CASES := [
	{"id": "optic", "dist": 16.0, "frames": [30, 45, 60, 80, 105, 135]}, # windup(0.7s)+beam(1.0s)
	{"id": "roller", "dist": 9.0, "frames": [20, 32, 44, 56, 70, 90]},    # windup+charge
]

func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(120, 1, 120); cs.shape = box
	body.position = Vector3(0, -0.5, 0); body.add_child(cs); add_child(body)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(120, 120)
	var fmat := StandardMaterial3D.new(); fmat.albedo_color = Color(0.3, 0.32, 0.38); pm.material = fmat
	fl.mesh = pm; add_child(fl)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 25, 0); sun.light_energy = 1.4; add_child(sun)
	var we := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.08, 0.1, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75); env.ambient_light_energy = 0.7
	env.glow_enabled = true; we.environment = env; add_child(we)

	var cam := Camera3D.new(); cam.fov = 55.0; add_child(cam); cam.make_current()

	for case in CASES:
		var id: String = case["id"]
		var dist: float = case["dist"]
		var player := CharacterBody3D.new()
		player.add_to_group("player")
		var pcs := CollisionShape3D.new()
		var pcap := CapsuleShape3D.new(); pcap.radius = 0.4; pcap.height = 1.7; pcs.shape = pcap
		player.add_child(pcs)
		player.collision_layer = 0b10
		player.position = Vector3(0, 1.0, dist)
		var dmg := Node.new(); dmg.name = "Damageable"; dmg.set_script(load("res://scripts/systems/damageable.gd"))
		player.add_child(dmg)
		if "max_health" in dmg: dmg.max_health = 100000.0
		add_child(player)
		var pmesh := MeshInstance3D.new()
		var cap := CapsuleMesh.new(); cap.radius = 0.4; cap.height = 1.7
		var cmat := StandardMaterial3D.new(); cmat.albedo_color = Color(0.3, 0.7, 1.0); cap.material = cmat
		pmesh.mesh = cap; player.add_child(pmesh)

		var e: Node3D = (load("res://scenes/enemies/%s.tscn" % id) as PackedScene).instantiate()
		add_child(e)
		e.global_position = Vector3(0, 0.6, 0)
		await get_tree().physics_frame
		# Face the dummy (look_at points local -Z, which is the enemy forward) and
		# force-acquire so it engages immediately without needing to scan/path.
		e.look_at(Vector3(0, 0.6, dist), Vector3.UP)
		if "target" in e: e.set("target", player)
		if e.has_method("set_state"): e.call("set_state", 4) # State.ATTACK for beam; roller re-derives
		# Side-on camera so a beam ray or a grounded charge (vs a leap) is obvious.
		cam.look_at_from_position(Vector3(dist * 0.5 + 8.0, 3.0, dist * 0.5), Vector3(0, 1.0, dist * 0.5), Vector3.UP)

		var fr := 0
		var shot := 0
		var want: Array = case["frames"]
		while fr <= int(want.back()) + 2:
			await get_tree().process_frame
			fr += 1
			if shot < want.size() and fr >= int(want[shot]):
				get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/behav_%s_%d.png" % [id, shot])
				print("SAVED behav_%s_%d (frame %d) enemy_y=%.2f dist=%.1f" % [id, shot, fr, e.global_position.y, e.global_position.distance_to(player.global_position)])
				shot += 1
		e.queue_free(); player.queue_free()
		await get_tree().process_frame
	print("DONE")
	get_tree().quit()
