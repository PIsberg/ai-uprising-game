extends Node3D
## Verify the WAR-BOT's mood face flips in real combat: green/happy while idle,
## red/angry once it engages the player.
##   godot --headless --path . res://tests/warbot_face_probe.tscn

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fb := BoxShape3D.new(); fb.size = Vector3(40, 1, 40); fcs.shape = fb
	floor_body.add_child(fcs); floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var bot: Node3D = load("res://scenes/enemies/warbot.tscn").instantiate()
	add_child(bot)
	bot.global_position = Vector3(6, 0.6, 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var happy = bot.get("_happy")
	var angry = bot.get("_angry")
	var idle_happy: bool = happy.visible and not angry.visible
	# No player yet → should stay happy for a moment.
	for i in 20:
		await get_tree().physics_frame
	var still_happy: bool = happy.visible and not angry.visible
	# Spawn the player → it should engage and flip to angry.
	var player := StaticBody3D.new()
	player.add_to_group("player"); player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var pc := CapsuleShape3D.new(); pc.radius = 0.4; pc.height = 1.8; pcs.shape = pc
	player.add_child(pcs)
	var dmg := Node.new(); dmg.set_script(load("res://scripts/systems/damageable.gd"))
	dmg.name = "Damageable"; dmg.set("max_health", 100000.0); player.add_child(dmg)
	player.position = Vector3(0, 1, 0)
	add_child(player)
	var got_angry := false
	for i in 240:
		await get_tree().physics_frame
		if angry.visible and not happy.visible:
			got_angry = true
			break
	print("idle_happy=%s still_happy_no_player=%s flipped_angry_on_engage=%s"
		% [idle_happy, still_happy, got_angry])
	print("RESULT ", "PASS" if (idle_happy and still_happy and got_angry) else "FAIL")
	get_tree().quit()
