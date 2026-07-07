extends Node3D
## Balance-cohesion check for the stacked buff systems: the COMBINED movement
## multiplier is capped (controllable) while a single buff passes through, and the
## intended damage/fire-rate power spikes are reported for the record.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as Node3D

	# All buffs off -> baseline speed.
	GameState.overdrive_left = 0.0
	GameState.rampage_tier = 0
	GameState.adrenaline_left = 0.0
	GameState.directive = {}
	var base: float = player._current_speed()

	# Single buff (rampage only, 1.12x) -> passes through uncapped.
	GameState.rampage_tier = 3 # speed mult 1.12
	var single_ratio: float = player._current_speed() / base

	# Full stack: overdrive 1.35 x rampage 1.12 x adrenaline 1.15 x blitz 1.2 = 2.09.
	GameState.overdrive_left = 10.0
	GameState.adrenaline_left = 5.0
	GameState.directive = {"move": 1.2}
	var raw := 1.35 * 1.12 * 1.15 * 1.2
	var stacked_ratio: float = player._current_speed() / base
	print("move: single=%.2f (uncapped, ~1.12), raw_stack=%.2f, capped=%.2f (cap=%.2f)" % [
		single_ratio, raw, stacked_ratio, player.MAX_MOVE_MULT])

	# Report the intended offensive spikes (deliberately uncapped power fantasy).
	for k in GameState.upgrades:
		GameState.upgrades[k] = GameState.UPGRADE_MAX
	GameState.activate_overclock()
	GameState.directive = {"damage": 1.5}
	var dmg := GameState.upgrade_mult("damage") * GameState.damage_mult() \
		* GameState.rampage_damage_mult() * GameState.adrenaline_damage_mult() * GameState.directive_damage_mult()
	var fire := GameState.fire_rate_mult() * GameState.rampage_fire_mult() * GameState.adrenaline_fire_mult()
	print("peak offense (rare confluence): damage x%.1f, fire-rate x%.1f (intended power fantasy)" % [dmg, fire])
	print("BALANCE_PROBE_DONE")
	get_tree().quit()
