extends Node
## Headless check of the Highway Breakout ride: the hauler rolls, the player
## rides it (position tracks the deck), and pursuit waves spawn.
##   godot --headless --path . --audio-driver Dummy res://tests/convoy_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	# Adding to /root inside _ready fails ("parent busy"); do it deferred.
	var lvl := (load("res://scenes/levels/level_convoy.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lvl)
	await get_tree().create_timer(2.5).timeout
	var ride := lvl.get_node("ConvoyRide")
	var truck: Node3D = ride.get("_truck")
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pdmg = player.get_node("Damageable")
	pdmg.invulnerable = true
	var z0: float = truck.global_position.z
	await get_tree().create_timer(8.0).timeout
	var z1: float = truck.global_position.z
	var moved := z0 - z1
	var rides := absf(player.global_position.z - truck.global_position.z) < 8.0 \
		and player.global_position.y > 0.9
	await get_tree().create_timer(6.0).timeout
	var enemies := get_tree().get_nodes_in_group("enemy").size()
	print("truck moved %.1fm (z %.1f -> %.1f)" % [moved, z0, z1])
	print("player aboard=%s (p=%s truck_z=%.1f)" % [rides, player.global_position, truck.global_position.z])
	print("enemies spawned=%d" % enemies)
	var ok := moved > 15.0 and rides and enemies >= 2
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
