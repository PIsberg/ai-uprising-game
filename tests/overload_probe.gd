extends Node3D
## Verifies the OVERLOAD ultimate: combat charges a per-level meter to full (firing
## the ready signal), unleashing damages + EMP-stuns every hostile in range, and
## consuming the meter empties it.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	GameState.reset_level_stats()
	var player := get_tree().get_first_node_in_group("player") as Node3D

	# Charge to full and confirm the ready signal fires.
	var ready_fired := [false]
	GameState.ultimate_ready.connect(func(): ready_fired[0] = true)
	while not GameState.ultimate_ready_state():
		GameState.add_ultimate_charge(0.1)
	print("charge=%.2f ready=%s ready_signal=%s" % [
		GameState.ultimate_charge, GameState.ultimate_ready_state(), ready_fired[0]])

	# Screenshot the READY gauge.
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/overload.png")

	# Drag three enemies into the blast, record HP, unleash.
	var targets: Array = []
	var i := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.hp != null and e.hp.is_alive() and i < 3:
			e.global_position = player.global_position + Vector3(3.0 + i * 2.0, 0, 0)
			e.hp.current_health = 400.0 # survive the 140 blast so the EMP stun is observable
			targets.append({"e": e, "hp": e.hp.current_health})
			i += 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.call("_unleash_overload")
	await get_tree().process_frame

	var hurt := 0
	var empd := 0
	for t in targets:
		var e: EnemyBase = t["e"]
		if not is_instance_valid(e):
			hurt += 1; empd += 1; continue # died from the blast — counts as both
		if e.hp.current_health < t["hp"]:
			hurt += 1
		if float(e.get("_emp_t")) > 0.0:
			empd += 1
	print("blast: %d/%d hurt, %d/%d emp-stunned" % [hurt, targets.size(), empd, targets.size()])

	# Consume empties the meter.
	while not GameState.ultimate_ready_state():
		GameState.add_ultimate_charge(0.2)
	var ok: bool = GameState.consume_ultimate()
	print("consume: ok=%s charge_after=%.2f (expect true, 0.00)" % [ok, GameState.ultimate_charge])
	print("OVERLOAD_PROBE_DONE")
	get_tree().quit()
