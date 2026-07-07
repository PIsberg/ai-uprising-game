extends Node3D
## Verifies the per-level COMBAT DIRECTIVE mutator: each directive's mult getters
## report correctly, the effects actually reach the player's incoming-damage hook,
## roll_directive respects DIRECTIVE_CHANCE, and the HUD announces the active one.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	var player := get_tree().get_first_node_in_group("player") as Node3D

	# Each directive reports its declared mults.
	for d in GameState.DIRECTIVES:
		GameState.directive = d
		GameState.directive_id = String(d["id"])
		print("%-12s dmg=%.2f in=%.2f move=%.2f loot=%.2f" % [
			d["id"], GameState.directive_damage_mult(), GameState.directive_incoming_mult(),
			GameState.directive_move_mult(), GameState.directive_pickup_mult()])

	# Effect reaches the player's incoming-damage hook (GLASS CANNON = +40% taken).
	GameState.directive = {}
	GameState.directive_id = ""
	var base_in: float = player.modify_incoming_damage(100.0, null)
	GameState.directive = {"id": "glass_cannon", "incoming": 1.4, "damage": 1.5}
	var glass_in: float = player.modify_incoming_damage(100.0, null)
	print("incoming: base=%.1f glass=%.1f ratio=%.2f (expect ~1.40)" % [
		base_in, glass_in, glass_in / base_in])

	# roll_directive distribution: ~60% should land a directive.
	var hits := 0
	for i in 400:
		GameState.roll_directive()
		if GameState.directive_id != "":
			hits += 1
	print("roll: %d/400 directives (expect ~240, chance=%.2f)" % [hits, GameState.DIRECTIVE_CHANCE])

	# Announce one on the HUD and screenshot the toast.
	GameState.directive = GameState.DIRECTIVES[0] # GLASS CANNON
	GameState.directive_id = "glass_cannon"
	GameState.directive_set.emit("GLASS CANNON", String(GameState.DIRECTIVES[0]["desc"]))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/directive.png")
	print("DIRECTIVE_PROBE_DONE")
	get_tree().quit()
