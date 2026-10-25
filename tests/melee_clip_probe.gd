extends Node3D
## Probe: melee moves play the rig's own clips. The Quaternius bot rig has no
## arms: its Attack clip is a rear-back and lunge and its Jump a crouch, tuck
## and land, both unused while the RAVAGER (bladed fierce bot) swiped and
## leapt on the gun Shoot clip and the HUNTER dashed on none. Bone positions
## are read in the body frame off the Skeleton3D.
## RAVAGER (1) leap wind-up: the Jump clip plays and the Body bone drops 0.4+ m
##     (its crouch); (2) in flight the clip keeps playing and the feet tuck
##     0.8+ m up toward the body; (3) landed, the clip is let go within 0.4 s;
##     (4) a swipe plays the Attack clip, the Body bone lunges 1+ m forward,
##     and the hit (slam_damage x 0.6) lands at the lunge's peak (0.2-0.3 s),
##     not when the attack is decided.
## HUNTER (5) its blade dash plays the Attack clip while the lunge is in
##     flight and the rake still lands.
##   godot --headless --path . --audio-driver Dummy res://tests/melee_clip_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _bone(e: Node3D, sk: Skeleton3D, name: String) -> Vector3:
	var idx := sk.find_bone(name)
	return e.global_transform.affine_inverse() * (sk.global_transform * sk.get_bone_global_pose(idx).origin)

func _clip(e: Node3D) -> String:
	var ap := e.find_child("AnimationPlayer", true, false) as AnimationPlayer
	return ap.current_animation if ap else ""

func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	cs.shape = box
	cs.position = Vector3(0, -0.5, 0)
	body.add_child(cs)
	add_child(body)
	var player: CharacterBody3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0, 0.1, -9)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var php: Node = player.get_node("Damageable")
	php.max_health = 100000.0
	php.current_health = 100000.0

	# ---- RAVAGER
	var r: CharacterBody3D = (load("res://scenes/enemies/ravager.tscn") as PackedScene).instantiate()
	add_child(r)
	r.global_position = Vector3(0, 0.1, 0)
	r.set("_leap_cd", 999.0) # only the probe's leap; it would otherwise spring at a player 9 m off
	await _wait(0.3)
	var sk := r.find_child("Skeleton3D", true, false) as Skeleton3D
	var body_rest := _bone(r, sk, "Body")
	var foot_rest := _bone(r, sk, "Foot.L")
	print("  ravager rest body %s foot %s clip %s" % [body_rest, foot_rest, _clip(r)])
	r.set("target", player)
	r.set("_attack_timer", 999.0)
	# (1) wind-up
	r.call("_begin_windup")
	var crouch := 0.0
	var jump_in_windup := true
	var t := 0.0
	while t < float(r.get("leap_windup")) - 0.02:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		crouch = maxf(crouch, body_rest.y - _bone(r, sk, "Body").y)
		if _clip(r) != EnemyRavager.LEAP_CLIP:
			jump_in_windup = false
	_check("leap wind-up plays the Jump clip", jump_in_windup, "(%s)" % _clip(r))
	_check("it crouches through the wind-up", crouch >= 0.4, "(body down %.2f m)" % crouch)
	# (2) flight
	t = 0.0
	while t < 0.3 and not bool(r.get("_leaping")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("the leap launched", bool(r.get("_leaping")))
	var tuck := 0.0
	var jump_in_air := true
	t = 0.0
	while t < 2.5 and bool(r.get("_leaping")):
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var b := _bone(r, sk, "Body")
		var f := _bone(r, sk, "Foot.L")
		tuck = maxf(tuck, (f.y - b.y) - (foot_rest.y - body_rest.y))
		if _clip(r) != EnemyRavager.LEAP_CLIP:
			jump_in_air = false
	_check("the Jump clip plays through the flight", jump_in_air, "(%s)" % _clip(r))
	_check("the feet tuck up in the air", tuck >= 0.8, "(%.2f m)" % tuck)
	# (3) landed
	await _wait(0.4)
	_check("landed, the Jump clip is let go", _clip(r) != EnemyRavager.LEAP_CLIP, "(%s)" % _clip(r))
	# (4) swipe
	player.global_position = r.global_position + (-r.global_transform.basis.z) * 2.5 + Vector3(0, 0.0, 0)
	await get_tree().physics_frame
	var hp0: float = php.current_health
	r.set("_attack_timer", 999.0)
	r.call("_perform_attack")
	await get_tree().physics_frame
	_check("swipe plays the Attack clip", _clip(r) == EnemyRavager.SWIPE_CLIP, "(%s)" % _clip(r))
	_check("no damage when the swipe is decided", php.current_health == hp0)
	var lunge := 0.0
	var hit_at := -1.0
	t = 0.0
	while t < 0.6:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		lunge = maxf(lunge, body_rest.z - _bone(r, sk, "Body").z)
		if hit_at < 0.0 and php.current_health < hp0:
			hit_at = t
	_check("the swipe lunges forward", lunge >= 1.0, "(%.2f m)" % lunge)
	_check("the hit lands at the lunge's peak", hit_at >= 0.2 and hit_at <= 0.3, "(at %.2f s)" % hit_at)
	_check("the swipe hurts for 0.6 x slam_damage", is_equal_approx(hp0 - php.current_health, float(r.get("slam_damage")) * 0.6), "(%.1f)" % (hp0 - php.current_health))
	r.queue_free()

	# ---- HUNTER
	player.global_position = Vector3(0, 0.1, -10)
	var h: CharacterBody3D = (load("res://scenes/enemies/hunter.tscn") as PackedScene).instantiate()
	add_child(h)
	h.global_position = Vector3(0, 0.1, 0)
	await _wait(0.3)
	h.set("target", player)
	h.set("_attack_timer", 999.0)
	h.set("_dash_cd", 0.0)
	h.call("set_state", 4) # ATTACK
	t = 0.0
	while t < 0.5 and float(h.get("_lunge_time")) <= 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_check("the hunter dashed", float(h.get("_lunge_time")) > 0.0)
	var attack_in_dash := true
	t = 0.0
	while t < 1.0 and float(h.get("_lunge_time")) > 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _clip(h) != EnemyHunter.DASH_CLIP:
			attack_in_dash = false
	_check("the dash plays the Attack clip for its length", attack_in_dash, "(%s)" % _clip(h))
	_check("the rake still lands", bool(h.get("_raked")))
	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()
