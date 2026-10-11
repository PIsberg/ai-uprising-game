extends Node3D
## Probe: a special-move clip plays through instead of being taken back by
## RobotModel's idle/walk blend on the next tick (#242).
## (1) SNIPER: _perform_attack starts its "Charge" clip; it is still the
##     current clip for 80%+ of the frames over the next second of the charge,
##     even after a 900 ms frame stall right as it starts (the hold counts
##     game time, not wall time);
## (2) RAPTOR: _try_rake on a target in reach starts "CharacterArmature|Attack";
##     it stays current for 80%+ of the frames over the clip's first 0.5 s;
## (3) the intro cast (AI off, model animating): IntroCutscene.strike_clip
##     holds each robot's combat clip 80%+ of the next 20 frames (or its length).
##   godot --headless --path . --audio-driver Dummy res://tests/special_clip_probe.tscn

var ok := true

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

## Fraction of `frames` physics frames on which `clip` is the current clip.
func _held(ap: AnimationPlayer, clip: String, frames: int) -> float:
	var n := 0
	for i in frames:
		await get_tree().physics_frame
		if ap.current_animation == clip:
			n += 1
	return float(n) / float(frames)

func _run() -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	sb.add_child(cs)
	add_child(sb)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.7
	pcs.shape = cap
	pcs.position = Vector3(0, 0.9, 0)
	player.add_child(pcs)
	var pdmg := Damageable.new()
	pdmg.name = "Damageable"
	pdmg.max_health = 1.0e9
	player.add_child(pdmg)
	add_child(player)

	# 1. Sniper charge.
	var sn: EnemyBase = (load("res://scenes/enemies/sniper.tscn") as PackedScene).instantiate()
	add_child(sn)
	sn.global_position = Vector3(0, 0.2, -14.0)
	sn.rotation.y = PI
	for i in 20:
		await get_tree().physics_frame
	var sap: AnimationPlayer = sn.find_children("*", "AnimationPlayer", true, false)[0]
	sn.target = player
	sn.call("_perform_attack")
	# A 900 ms frame stall right after the clip starts (an on-demand synth
	# sound does this on a loaded machine): the hold must count game time, so
	# no game time passing must not eat the clip.
	OS.delay_msec(900)
	var sheld: float = await _held(sap, "Charge", 60)
	_check("sniper's Charge clip plays through the charge", sap.has_animation("Charge") and sheld >= 0.8,
			"held %.0f%% of 60 frames" % (sheld * 100.0))
	sn.queue_free()

	# 2. Raptor rake.
	var rp: EnemyBase = (load("res://scenes/enemies/raptor.tscn") as PackedScene).instantiate()
	add_child(rp)
	rp.global_position = Vector3(0, 1.2, -1.5)
	for i in 20:
		await get_tree().physics_frame
	var rap: AnimationPlayer = rp.find_children("*", "AnimationPlayer", true, false)[0]
	rp.target = player
	rp.global_position = Vector3(0, 1.2, -1.5)
	var hp0 := pdmg.current_health
	rp.call("_try_rake")
	var rheld: float = await _held(rap, "CharacterArmature|Attack", 30)
	_check("raptor's rake clip plays through", pdmg.current_health < hp0 and rheld >= 0.8,
			"raked=%s held %.0f%% of 30 frames" % [pdmg.current_health < hp0, rheld * 100.0])

	rp.queue_free()

	# 3. The intro's cast, AI off as the intro spawns them: each combat clip
	#    (the mech's Punch is not its routine attack clip) is held on strike.
	var intro: GDScript = load("res://scripts/cutscene/intro_cutscene.gd")
	var cast: Dictionary = intro.get_script_constant_map()["CAST"]
	for type in cast:
		var clip := String(cast[type]["attack"])
		if clip == "":
			continue
		var bot: Node3D = (load(String(cast[type]["scene"])) as PackedScene).instantiate()
		add_child(bot)
		bot.global_position = Vector3(4, 0, 0)
		bot.set_physics_process(false) # as the intro does: no AI, the model keeps animating
		for i in 10:
			await get_tree().physics_frame
		var bap: AnimationPlayer = bot.find_children("*", "AnimationPlayer", true, false)[0]
		intro.strike_clip(bot.get_node("Model"), clip)
		# Sample at most the clip's own length (the spider's Attack is ~16 frames).
		var n := clampi(int(bap.get_animation(clip).length * 60.0) - 2, 4, 20) if bap.has_animation(clip) else 20
		var bheld: float = await _held(bap, clip, n)
		_check("intro %s holds its %s strike" % [type, clip], bap.has_animation(clip) and bheld >= 0.8,
				"held %.0f%% of %d frames" % [bheld * 100.0, n])
		bot.queue_free()

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
