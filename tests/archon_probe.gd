extends Node3D
## Dev probe: stands ARCHON up next to a fake player and runs its full lifecycle
## (boot-up → first wave spawn → exposure → energy fire → death cascade) so the
## boss logic can be exercised headlessly for script errors.
##   godot --headless --path . res://tests/archon_probe.tscn --quit-after 600

func _ready() -> void:
	# Minimal lit world.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, 40, 0)
	add_child(key)

	# A floor body so spawned minions have ground.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(120, 1, 120)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)

	# Fake player in range so the brain engages and fires.
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var pshape := CapsuleShape3D.new()
	pcs.shape = pshape
	player.add_child(pcs)
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	player.add_child(pdmg)
	add_child(player)
	player.global_position = Vector3(6, 1.6, 8)

	var boss := (load("res://scenes/enemies/archon.tscn") as PackedScene).instantiate()
	boss.position = Vector3(0, 0.5, 0)
	add_child(boss)

	_run(boss)

func _run(boss) -> void:
	# Let it boot, build the brain, and fully deploy the opening wave.
	await get_tree().create_timer(6.0).timeout
	print("PROBE alive_after_boot=", is_instance_valid(boss), " minions=", boss._living_minions(), " mode=", boss._mode, " spawning=", boss._spawning)

	# Force exposure to exercise the shield-shatter + energy-fire path: clear the
	# tracked legion so the brain finds itself undefended.
	for m in boss._minions:
		if is_instance_valid(m):
			m.queue_free()
	await get_tree().create_timer(1.5).timeout
	print("PROBE after_expose mode=", boss._mode, " invuln=", boss.hp.invulnerable)

	# Now lethal damage should kill it (exposed = vulnerable) → death cascade.
	if is_instance_valid(boss):
		boss.hp.invulnerable = false
		boss.hp.apply_damage(99999.0, get_tree().get_first_node_in_group("player"))
	await get_tree().create_timer(3.0).timeout
	print("PROBE after_kill freed=", not is_instance_valid(boss))
	get_tree().quit()
