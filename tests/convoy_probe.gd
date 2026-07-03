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
	# Boarding wave: BOARDERS heavies drop onto the deck, not the roadside.
	ride.set("_wave_i", 5) # WAVES[5] carries a brute
	ride.call("_spawn_wave")
	await get_tree().create_timer(2.0).timeout
	var brute := get_tree().get_first_node_in_group("shield_enemies") as Node3D
	var boarded := false
	var ff_ok := false
	if brute:
		var rel: Vector3 = brute.global_position - truck.global_position
		boarded = absf(rel.x) <= 3.2 and rel.z >= -6.5 and rel.z <= 7.0 \
			and brute.global_position.y >= 1.0
		print("brute deck-relative pos=%s boarded=%s" % [rel, boarded])
		# Friendly fire: enemy-sourced hits bounce off enemies; source-less
		# (environmental) damage must still land.
		var hp = brute.get("hp")
		var before: float = hp.current_health
		hp.apply_damage(50.0, brute)
		var blocked: bool = hp.current_health == before
		hp.apply_damage(50.0, null)
		ff_ok = blocked and hp.current_health < before
		print("friendly-fire blocked=%s env-damage lands=%s" % [blocked, hp.current_health < before])
	print("truck moved %.1fm (z %.1f -> %.1f)" % [moved, z0, z1])
	print("player aboard=%s (p=%s truck_z=%.1f)" % [rides, player.global_position, truck.global_position.z])
	print("enemies spawned=%d" % enemies)
	var ok := moved > 15.0 and rides and enemies >= 2 and boarded and ff_ok
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
