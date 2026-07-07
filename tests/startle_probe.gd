extends Node3D
## Verifies enemy startle-scatter on a player power spike: startle_enemies affects
## only in-radius, non-boss, non-EMP units, and reaching GODLIKE broadcasts it.

func _ready() -> void:
	var lvl: Node = (load("res://scenes/levels/level_gpt.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(1.5).timeout
	GameState.current_state = GameState.State.PLAYING
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pp := player.global_position

	# Three enemies at 5 / 15 / 25 m from the player.
	var es: Array = []
	var i := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.hp != null and e.hp.is_alive() and i < 3:
			e.global_position = pp + Vector3([5.0, 15.0, 25.0][i], 0, 0)
			es.append(e)
			i += 1
	await get_tree().physics_frame
	if es.size() < 3:
		print("not enough enemies: %d" % es.size()); get_tree().quit(); return

	for e in es:
		e.set("_evade_t", 0.0)
	GameState.startle_enemies(pp, 18.0, 1.0)
	print("radius test: 5m=%.2f 15m=%.2f 25m=%.2f (expect >0, >0, 0)" % [
		float(es[0].get("_evade_t")), float(es[1].get("_evade_t")), float(es[2].get("_evade_t"))])

	# EMP'd unit ignores the startle.
	es[0].emp_disable(2.0)
	es[0].set("_evade_t", 0.0)
	es[0].startle(pp, 1.0)
	print("emp'd startle: _evade_t=%.2f (expect 0)" % float(es[0].get("_evade_t")))

	# GODLIKE broadcast: reaching tier 3 scatters the nearby (non-EMP) unit.
	es[1].set("_evade_t", 0.0)
	GameState._reset_combo()
	# Player must be near for the broadcast centre; es[1] is 15m out (< 18m).
	while GameState.combo < 18:
		GameState.add_kill(100, "HOSTILE")
		GameState.combo_timer = GameState.COMBO_WINDOW
	print("godlike broadcast: tier=%d 15m_evade=%.2f (expect 3, >0)" % [
		GameState.rampage_tier, float(es[1].get("_evade_t"))])
	print("STARTLE_PROBE_DONE")
	get_tree().quit()
