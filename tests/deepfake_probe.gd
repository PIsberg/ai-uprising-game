extends Node
## Probe: the DEEPFAKE and its projected copies (enemy_deepfake.gd, deepfake_decoy.gd).
## (1) it is wired: level builder, codex, and the GROK roster;
## (2) in a fight it projects two copies on its own, about SPREAD to either side,
##     and none of the three spots is shared;
## (3) the copies stay out of the "enemy" group (kill_all, radar, homing) and
##     cast no shadow;
## (4) when it fires, every copy fires the same burst, and the copies' rounds
##     hurt nobody while its own do;
## (5) a real weapon hit pops a copy without paying score or counting as an
##     accuracy hit;
## (6) a wall beside it blocks that side's copy;
## (7) its death collapses the copies.
##   godot --headless --path . --audio-driver Dummy res://tests/deepfake_probe.tscn

const SCENE := "res://scenes/enemies/deepfake.tscn"
const TRACER := "res://scenes/fx/tracer_red.tscn"
var ok := true
var _tracers := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().node_added.connect(func(n: Node) -> void:
			if n.scene_file_path == TRACER:
				_tracers += 1)
	# 1. Wiring.
	_check("level builder knows deepfake", LevelBuilder.ENEMY_SCENES.get("deepfake", "") == SCENE)
	_check("codex entry", EnemyCodex.has("deepfake") and "deepfake" in EnemyCodex.ORDER)
	var on_grok := 0
	for en in LevelDefs.get_def("grok").get("enemies", []):
		if en.get("type", "") == "deepfake":
			on_grok += 1
	_check("two deepfakes on the GROK roster", on_grok == 2, str(on_grok))

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)

	# A player stand-in that can be shot (layer 2, like the player).
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 1
	var pcs := CollisionShape3D.new()
	var pcap := CapsuleShape3D.new()
	pcap.radius = 0.4
	pcap.height = 1.8
	pcs.shape = pcap
	pcs.position.y = 0.9
	player.add_child(pcs)
	var php := Damageable.new()
	php.name = "Damageable"
	php.max_health = 100000.0
	php.invulnerable = false
	player.add_child(php)
	add_child(player)
	player.global_position = Vector3(0, 0, 14)

	# 2. Projects on its own in a fight.
	var e: EnemyDeepfake = (load(SCENE) as PackedScene).instantiate()
	add_child(e)
	e.global_position = Vector3(0, 0, 0)
	GameState.current_state = GameState.State.PLAYING
	await _frames(4)
	e.target = player
	e.set_state(EnemyBase.State.ATTACK)
	for i in 240:
		await get_tree().physics_frame
		if not e.decoys.is_empty():
			break
	_check("projects copies in a fight", e.decoys.size() == 2, "%d copies" % e.decoys.size())
	if e.decoys.size() == 2:
		var spots: Array[Vector3] = [e.global_position, e.decoys[0].global_position, e.decoys[1].global_position]
		var min_gap := 999.0
		for a in 3:
			for b in range(a + 1, 3):
				var g := Vector2(spots[a].x - spots[b].x, spots[a].z - spots[b].z).length()
				min_gap = minf(min_gap, g)
		_check("three distinct spots ~SPREAD apart", min_gap > EnemyDeepfake.SPREAD * 0.7, "min gap %.2f m" % min_gap)

		# 3. Out of the enemy group, no shadows.
		var d0: DeepfakeDecoy = e.decoys[0]
		_check("copy not in the enemy group", not d0.is_in_group("enemy") and d0.is_in_group("deepfake_decoy"))
		var shadowless := true
		var nmesh := 0
		for mi in d0.find_children("*", "MeshInstance3D", true, false):
			nmesh += 1
			if (mi as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				shadowless = false
		_check("copy wears the model, casts no shadow", nmesh > 0 and shadowless, "%d meshes" % nmesh)

		# 4. Copies fire with it; only its rounds hurt.
		e.process_mode = Node.PROCESS_MODE_DISABLED # freeze its own AI; drive the bursts by hand
		await _frames(30)
		var t0 := _tracers
		var h0 := php.current_health
		for d in e.decoys:
			d.fake_burst(e.burst_count)
		await _frames(40)
		_check("copies' bursts draw tracers", _tracers - t0 == e.burst_count * 2, "%d tracers" % (_tracers - t0))
		_check("copies' rounds do no damage", php.current_health == h0, "%.0f -> %.0f" % [h0, php.current_health])
		e.process_mode = Node.PROCESS_MODE_INHERIT
		# Its own burst is aimed with real scatter (burst spread + difficulty), so
		# a thin capsule 14 m out was missed by all 5 rounds on one CI run. Step
		# the stand-in to 6 m and fatten it: every round of the burst lands.
		pcap.radius = 1.5
		pcap.height = 4.0
		pcs.position.y = 2.0
		player.global_position = e.global_position + Vector3(0, 0, 6)
		await _frames(2)
		t0 = _tracers
		e._attack_timer = 999.0 # no AI burst on top of the forced one
		e._start_burst()
		await _frames(40)
		_check("its burst fires every copy too", _tracers - t0 >= e.burst_count * 3, "%d tracers" % (_tracers - t0))
		_check("its own rounds hurt", php.current_health < h0, "%.0f -> %.0f" % [h0, php.current_health])

		# 5. A real hit pops a copy, pays nothing, is not an accuracy hit.
		var gun: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
		add_child(gun)
		gun._active_shooter = player
		var target_copy: DeepfakeDecoy = e.decoys[0]
		var score0 := GameState.score
		var hits0 := GameState.stat_hits
		var aim_from := target_copy.global_position + Vector3(0, 1.1, 6)
		gun._do_hitscan(aim_from, (target_copy.global_position + Vector3(0, 1.1, 0) - aim_from).normalized())
		await _frames(20)
		_check("a hit pops the copy", not is_instance_valid(target_copy))
		_check("no score for a copy", GameState.score == score0, "%d -> %d" % [score0, GameState.score])
		_check("not an accuracy hit", GameState.stat_hits == hits0, "%d -> %d" % [hits0, GameState.stat_hits])

		# 7. Death collapses the rest.
		var left := e.decoys.duplicate()
		e.hp.apply_damage(999999.0, player)
		await _frames(20)
		var any_left := false
		for d in left:
			if is_instance_valid(d):
				any_left = true
		_check("its death collapses its copies", not any_left)

	# 6. A wall on one side blocks that copy.
	var f: EnemyDeepfake = (load(SCENE) as PackedScene).instantiate()
	f.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(f)
	f.global_position = Vector3(40, 0, 0)
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(0.5, 4, 6)
	wcs.shape = wbs
	wall.add_child(wcs)
	add_child(wall)
	wall.global_position = Vector3(41.8, 2, 0)
	var p2 := Node3D.new()
	add_child(p2)
	p2.global_position = Vector3(40, 0, 14)
	await _frames(4)
	f.target = p2
	var n := f.project()
	_check("a wall blocks that side's copy", n == 1, "%d copies" % n)
	for d in f.decoys:
		_check("the copy landed on the open side", d.global_position.x < 40.0 or f.global_position.x < 40.0,
				"copy x %.1f, robot x %.1f" % [d.global_position.x, f.global_position.x])

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
