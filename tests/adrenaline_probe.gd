extends Node3D
## Verifies the ADRENALINE SURGE clutch mechanic: a hit that drops the player to
## critical HP fires a surge (heal + dmg/fire/speed buff + banner), the buffs
## collapse when it ends, and a cooldown then locks out an immediate re-trigger.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var d = player.get_node("Damageable")

	# Baseline: no surge, all mults at 1.0.
	print("baseline: active=%s dmg=%.2f fire=%.2f speed=%.2f" % [
		GameState.adrenaline_left > 0.0, GameState.adrenaline_damage_mult(),
		GameState.adrenaline_fire_mult(), GameState.adrenaline_speed_mult()])

	# Drive the player to critical with a real hit -> the surge should fire.
	d.current_health = d.max_health * 0.30
	var hp_before: float = d.current_health
	d.apply_damage(d.max_health * 0.20, self)
	await get_tree().process_frame
	print("after crit hit: hp %.0f->%.0f active=%s dmg=%.2f fire=%.2f speed=%.2f" % [
		hp_before, d.current_health, GameState.adrenaline_left > 0.0,
		GameState.adrenaline_damage_mult(), GameState.adrenaline_fire_mult(),
		GameState.adrenaline_speed_mult()])

	# Screenshot the ADRENALINE banner + red edge pulse.
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/adrenaline.png")

	# Let the surge lapse -> buffs collapse, cooldown engages.
	GameState.adrenaline_left = 0.05
	await get_tree().create_timer(0.2).timeout
	print("after lapse: active=%s dmg=%.2f fire=%.2f speed=%.2f cd_locked=%s" % [
		GameState.adrenaline_left > 0.0, GameState.adrenaline_damage_mult(),
		GameState.adrenaline_fire_mult(), GameState.adrenaline_speed_mult(),
		not GameState.try_adrenaline()])
	print("ADRENALINE_PROBE_DONE")
	get_tree().quit()
