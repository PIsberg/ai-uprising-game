extends Node
## Dev probe: validates the ROOTED MANUS rework.
## (1) engaged at range, the arm holds its spawn position (no pursuit drift);
## (2) beyond sweep range it answers with the FINGER ERUPTION (player standing
##     on the telegraph takes spike damage);
## (3) the grab is now a YANK: _begin_grab with the target inside grab_reach
##     connects (reels the target toward the palm) without the body moving.
##   godot --headless --path . res://tests/manus_rooted_probe.tscn

func _make_player(at: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.add_to_group("player")
	p.collision_layer = 2
	p.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.height = 1.8
	cs.shape = sh
	p.add_child(cs)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 1000.0
	p.add_child(d)
	get_tree().root.add_child(p)
	p.global_position = at
	return p

func _make_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(300, 1, 300)
	cs.shape = sh
	body.add_child(cs)
	get_tree().root.add_child(body)
	body.global_position = Vector3(0, -0.5, 0)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ok := true
	_make_floor()
	var player := _make_player(Vector3(20, 1.0, 0))
	var manus: Node3D = load("res://scenes/enemies/manus.tscn").instantiate()
	get_tree().root.add_child(manus)
	manus.global_position = Vector3.ZERO
	var spawn: Vector3 = manus.global_position
	# Ride out the entrance + wake (invulnerable window).
	for i in 150:
		await get_tree().physics_frame

	# 1+2. Engaged at 20m: no movement, and the deck eruption punishes camping.
	var hp0: float = player.get_node("Damageable").current_health
	for i in 420: # ~7s: initial spike cd 2.5 + windup 0.75 -> at least one eruption
		await get_tree().physics_frame
	var drift: float = (manus.global_position - spawn).length()
	var hp1: float = player.get_node("Damageable").current_health
	var rooted: bool = drift < 0.6
	var spiked: bool = hp1 < hp0
	print("ROOTED: drift=%.2fm target=%s state=%d" % [drift, manus.target, manus.state])
	print("SPIKE: hp %.0f -> %.0f (hit=%s)" % [hp0, hp1, spiked])
	if not (rooted and spiked):
		ok = false

	# 3. The yank: target inside reach -> grab connects, body stays put.
	player.global_position = Vector3(8, 0, 0)
	player.velocity = Vector3.ZERO
	manus.target = player
	manus._grab_cd = 0.0
	manus._begin_grab()
	for i in 50: # > the 0.55s tell
		await get_tree().physics_frame
	var grabbed: bool = manus._grabbed == player
	var still_rooted: bool = (manus.global_position - spawn).length() < 0.6
	print("YANK: grabbed=%s still_rooted=%s" % [grabbed, still_rooted])
	if not (grabbed and still_rooted):
		ok = false

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
