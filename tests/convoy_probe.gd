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
		# Friendly fire: hits from ANOTHER enemy bounce off; source-less
		# (environmental) damage must still land. (Self-damage is deliberately
		# allowed — kamikaze mechanics — so the source must be a distinct foe.)
		var foe := Node3D.new()
		foe.add_to_group("enemy")
		get_tree().current_scene.add_child(foe)
		var hp = brute.get("hp")
		var before: float = hp.current_health
		hp.apply_damage(50.0, foe)
		var blocked: bool = hp.current_health == before
		hp.apply_damage(50.0, null)
		ff_ok = blocked and hp.current_health < before
		print("friendly-fire blocked=%s env-damage lands=%s" % [blocked, hp.current_health < before])
		foe.queue_free()
	# --- zipline / demo-platform loop ---
	var plats: Array = ride.get("_platforms")
	var plat_ok: bool = plats.size() == 2
	var p0: Dictionary = plats[0]
	var anchor: Node3D = p0["anchor"]
	# Outbound zip: winch the player from the truck to the platform.
	player.call("zipline_to", anchor)
	await get_tree().create_timer(3.0).timeout
	var flat := Vector2(player.global_position.x - anchor.global_position.x,
		player.global_position.z - anchor.global_position.z)
	var on_platform := player.global_position.y > 5.0 and flat.length() < 6.0
	print("zip out: player=%s anchor=%s on_platform=%s" % [player.global_position, anchor.global_position, on_platform])
	# Detonate with the swarm converging on the player: flyers must die en masse.
	var live_before := _live_enemies()
	ride.call("_on_detonator", player, p0)
	await get_tree().create_timer(2.0).timeout
	var live_after := _live_enemies()
	var boom_ok: bool = p0["spent"] and live_after <= live_before - 4
	print("boom: enemies alive %d -> %d spent=%s" % [live_before, live_after, p0["spent"]])
	# Clear the battlefield first: a boarded brute WILL slam the player off the
	# tail mid-check — fair combat, but this leg asserts the zip, not the fight.
	for e in get_tree().get_nodes_in_group("enemy"):
		(e as Node).queue_free()
	await get_tree().physics_frame
	# Return zip: the anchor is riding the still-moving truck.
	player.call("zipline_to", ride.get("_truck_anchor"))
	await get_tree().create_timer(4.0).timeout
	var back := absf(player.global_position.z - truck.global_position.z) < 8.0 \
		and player.global_position.y > 0.9
	print("zip back: player=%s truck_z=%.1f back=%s" % [player.global_position, truck.global_position.z, back])
	# Pursuit gun-trucks: at least one spawned by now, with a live crew.
	var vehicles: Array = ride.get("_vehicles")
	var veh_ok := vehicles.size() >= 1
	print("pursuit vehicles=%d" % vehicles.size())
	print("truck moved %.1fm (z %.1f -> %.1f)" % [moved, z0, z1])
	print("player aboard=%s (p=%s truck_z=%.1f)" % [rides, player.global_position, truck.global_position.z])
	print("enemies spawned=%d" % enemies)
	var ok := moved > 15.0 and rides and enemies >= 2 and boarded and ff_ok \
		and plat_ok and on_platform and boom_ok and back and veh_ok
	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _live_enemies() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		var hp = e.get("hp")
		if hp and hp.is_alive():
			n += 1
	return n
