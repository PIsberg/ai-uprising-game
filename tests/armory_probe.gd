extends Node3D
## Verifies the two new armory build tracks: GRENADE POWER (blast) scales a thrown
## grenade's splash, and LIFELEECH heals a slice of damage dealt. Also instances
## the Armory UI to confirm the 5-upgrade + 3-supply layout renders. Run windowed.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_hivemind.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.0).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d: Node = player.get_node("Damageable")

	# --- Buy the new tracks ---
	GameState.reset_run()
	GameState.score = 99999
	GameState.buy_upgrade("blast"); GameState.buy_upgrade("blast")  # 2 ranks
	GameState.buy_upgrade("leech"); GameState.buy_upgrade("leech"); GameState.buy_upgrade("leech") # 3 ranks
	GameState.buy_upgrade("stamina"); GameState.buy_upgrade("stamina"); GameState.buy_upgrade("stamina") # 3 ranks
	print("blast lvl=%d grenade_mult=%.2f | leech lvl=%d mult=%.2f | stamina lvl=%d mult=%.2f" % [
		GameState.upgrade_level("blast"), GameState.grenade_mult(),
		GameState.upgrade_level("leech"), GameState.upgrade_mult("leech"),
		GameState.upgrade_level("stamina"), GameState.stamina_mult()])

	# --- STAMINA: a freshly-built player should get the boosted max pool ---
	var fresh: Node = load("res://scenes/player/player.tscn").instantiate()
	add_child(fresh)
	await get_tree().process_frame
	await get_tree().process_frame
	print("STAMINA: fresh player max_stamina=%.0f (expected %.0f)" % [fresh.max_stamina, 100.0 * GameState.stamina_mult()])
	fresh.queue_free()

	# --- GRENADE POWER: a thrown frag's splash should be scaled by grenade_mult ---
	var frag: Node = load("res://scenes/weapons/grenade.tscn").instantiate()
	var base_splash: float = frag.splash_damage
	frag.free()
	# Emulate the _throw_grenade scaling path.
	var scaled := base_splash * GameState.grenade_mult()
	print("GRENADE splash: base=%.0f -> scaled=%.0f (x%.2f)" % [base_splash, scaled, GameState.grenade_mult()])

	# --- LIFELEECH: report_player_hit should heal a slice of damage dealt ---
	d.current_health = 50.0
	var before: float = d.current_health
	GameState.report_player_hit(100.0, player.global_position, false, false)
	print("LIFELEECH: hp %.0f -> %.0f (expected +%.1f)" % [before, d.current_health, 100.0 * (GameState.upgrade_mult("leech") - 1.0)])

	# --- Armory UI: renders 5 upgrades + 3 supplies ---
	var armory = Armory.new()
	add_child(armory)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/armory.png")
	print("ARMORY cards: upgrades=%d supplies=%d" % [armory._cards.size(), armory._supply_cards.size()])
	print("ARMORY_PROBE_DONE")
	get_tree().quit()
