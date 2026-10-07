extends Node
## Every boss escalates as it is wounded, measured on what it DOES, not on the
## phase number (MANUS has its own deeper probe, tests/manus_phase_probe):
##   OVERSEER    volley bolts grow 3 -> 5, the phase-3 volley spits a Seeker, the
##               rocket barrage grows by 2
##   COLOSSUS    artillery volley grows 3 -> 5; at the same range it opens with
##               artillery fresh, the sweeping beam wounded, the ground slam at 30%
##   TITAN       never phase-blinks fresh, blinks once wounded
##   ARCHON      the wave it pours out at 30% is bigger than at full health
##   TERMINATOR  the beam sweeps toward the player faster when it is wounded
##   SMASHER     its smash, slam and rake come back faster when it is wounded
## Each boss's own AI is paused (physics/process off) so only the call under test
## acts; the bosses' internal entry points are called directly.
##   godot --headless --path . --audio-driver Dummy res://tests/boss_phase_probe.tscn

var _fail: Array[String] = []
var _player: CharacterBody3D

func _check(cond: bool, label: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + label)
	if not cond:
		_fail.append(label)

func _ready() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _make_floor() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_position = Vector3(0, -0.5, 0)

func _make_player() -> void:
	_player = CharacterBody3D.new()
	_player.add_to_group("player")
	_player.collision_layer = 2
	_player.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.height = 1.8
	cs.shape = sh
	_player.add_child(cs)
	var d := Damageable.new()
	d.name = "Damageable"
	d.max_health = 100000.0
	d.invulnerable = true
	_player.add_child(d)
	add_child(_player)

func _spawn(scene: String, at: Vector3) -> Node:
	var b: Node = load("res://scenes/enemies/%s.tscn" % scene).instantiate()
	add_child(b)
	(b as Node3D).global_position = at
	await _frames(3)
	b.set_physics_process(false)
	b.set_process(false)
	b.target = _player
	return b

func _set_frac(b: Node, frac: float) -> void:
	b.hp.current_health = b.hp.max_health * frac

## Nodes added under the probe (the current scene) since `before`.
func _added(before: Array) -> Array:
	var out := []
	for c in get_children():
		if not before.has(c):
			out.append(c)
	return out

func _clear(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()

func _run() -> void:
	_make_floor()
	_make_player()
	await _frames(2)
	await _overseer()
	await _colossus()
	await _titan()
	await _archon()
	await _terminator()
	await _smasher()
	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit(0 if _fail.is_empty() else 1)

func _overseer() -> void:
	print("OVERSEER")
	_player.global_position = Vector3(0, 1, 0)
	var o: Node = await _spawn("overseer", Vector3(0, 8, -20))
	var bolts := []
	var seekers := []
	for frac in [1.0, 0.5, 0.2]:
		_set_frac(o, frac)
		o._barrage_cd = 99.0
		o._summon_cd = 0.0
		var before := get_children()
		o._perform_attack()
		var added := _added(before)
		var nb := 0
		var ns := 0
		for n in added:
			if n is EnemyBase:
				ns += 1
			elif n.has_method("launch"):
				nb += 1
		bolts.append(nb)
		seekers.append(ns)
		_clear(added)
	_check(bolts[2] > bolts[0], "volley grows when wounded (bolts %s)" % str(bolts))
	_check(seekers[0] == 0 and seekers[2] >= 1, "only the phase-3 volley spits a Seeker (seekers %s)" % str(seekers))
	var rockets := []
	for frac in [1.0, 0.2]:
		_set_frac(o, frac)
		o._barrage_cd = 0.0
		var before := get_children()
		o._perform_attack()
		var added := _added(before)
		rockets.append(added.size())
		_clear(added)
	_check(rockets[1] >= rockets[0] + 2, "rocket barrage grows when wounded (rockets %s)" % str(rockets))
	o.queue_free()
	await _frames(3)

func _colossus() -> void:
	print("COLOSSUS")
	var c: Node = await _spawn("colossus", Vector3(0, 0, 0))
	_player.global_position = Vector3(0, 1, 13.0)
	var volleys := []
	for frac in [1.0, 0.2]:
		_set_frac(c, frac)
		var before := get_children()
		c._fire_artillery()
		var added := _added(before)
		var n := 0
		for a in added:
			if a.has_method("launch"):
				n += 1
		volleys.append(n)
		_clear(added)
	_check(volleys[1] > volleys[0], "artillery volley grows when wounded (rockets %s)" % str(volleys))
	var picks := []
	for frac in [1.0, 0.5, 0.2]:
		_set_frac(c, frac)
		c._artillery_cd = 0.0
		c._beam_cd = 0.0
		c._slam_cd = 0.0
		c._beam_time = 0.0
		c._slam_windup = 0.0
		var before := get_children()
		c._choose_attack(13.0)
		var pick := "none"
		if c._slam_windup > 0.0:
			pick = "slam"
		elif c._beam_time > 0.0:
			pick = "beam"
		elif c._artillery_cd > 0.0:
			pick = "artillery"
		picks.append(pick)
		_clear(_added(before))
	_check(picks == ["artillery", "beam", "slam"], "at 13 m: artillery fresh, beam wounded, slam at 30%% (got %s)" % str(picks))
	c.queue_free()
	await _frames(3)

func _titan() -> void:
	print("TITAN")
	var t: Node = await _spawn("titan", Vector3(0, 0, 0))
	var far: float = t.preferred_range * 1.5
	_player.global_position = Vector3(0, 1, far)
	var blinked := []
	for frac in [1.0, 0.5]:
		_set_frac(t, frac)
		t._blink_cd = 0.0
		t.global_position = Vector3.ZERO
		var before := get_children()
		blinked.append(t._try_blink(far))
		_clear(_added(before))
	_check(blinked == [false, true], "phase-blinks only once wounded (fresh, 50%%: %s)" % str(blinked))
	t.queue_free()
	await _frames(3)

func _archon() -> void:
	print("ARCHON")
	_player.global_position = Vector3(0, 1, 30)
	var a: Node = await _spawn("archon", Vector3(0, 0, 0))
	# Its boot sequence pours out the first wave on its own; let that finish so
	# it does not land in the counts below.
	await _frames(int(8.0 * Engine.physics_ticks_per_second))
	_clear(get_children().filter(func(n): return n is EnemyBase and n != a))
	await _frames(3)
	# Count what ARCHON itself emits (its _minions list), not what is alive at
	# the end: the minions fight, and a Seeker that reaches the player is gone.
	var sizes := []
	for frac in [1.0, 0.2]:
		_set_frac(a, frac)
		a._minions.clear()
		var before := get_children()
		a._start_wave()
		await _frames(int(6.0 * Engine.physics_ticks_per_second))
		sizes.append(a._minions.size())
		_clear(_added(before))
		await _frames(3)
	_check(sizes[0] > 0 and sizes[1] > sizes[0], "the 30%% wave is bigger than the first (minions %s)" % str(sizes))
	a.queue_free()
	await _frames(3)

func _terminator() -> void:
	print("TERMINATOR")
	var m: Node = await _spawn("terminator", Vector3(0, 0, 0))
	_player.global_position = Vector3(20, 1, 0)
	var turned := []
	for frac in [1.0, 0.25]:
		_set_frac(m, frac)
		m._beam_windup = 0.0
		m._beam_time = 5.0
		var origin: Vector3 = m._beam_origin()
		var to_player: Vector3 = (_player.global_position + Vector3.UP * 0.7 - origin).normalized()
		m._beam_dir = to_player.rotated(Vector3.UP, deg_to_rad(80.0)).normalized()
		var start: Vector3 = m._beam_dir
		var before := get_children()
		m._process_beam(1.0 / 60.0)
		turned.append(rad_to_deg(start.angle_to(m._beam_dir)))
		_clear(_added(before).filter(func(n): return n != m._beam))
	_check(turned[1] > turned[0] * 1.5, "the beam sweeps faster when wounded (deg per tick %.2f -> %.2f)" % [turned[0], turned[1]])
	m.queue_free()
	await _frames(3)

func _smasher() -> void:
	print("SMASHER")
	_player.global_position = Vector3(0, 1, 6)
	var s: Node = await _spawn("smasher", Vector3(0, 0, 0))
	var cds := {}
	for frac in [1.0, 0.2]:
		_set_frac(s, frac)
		s._begin_smash()
		s._begin_slam()
		s._begin_rake()
		cds[frac] = [s._smash_cd, s._slam_cd, s._rake_cd]
		s._smash_windup_t = 0.0
		s._slam_windup_t = 0.0
		s._rake_windup_t = 0.0
	var fresh: Array = cds[1.0]
	var hurt: Array = cds[0.2]
	_check(is_equal_approx(fresh[0], s.smash_cooldown), "fresh smash cooldown is the authored %.2f (got %.2f)" % [s.smash_cooldown, fresh[0]])
	_check(hurt[0] < fresh[0] * 0.75 and hurt[1] < fresh[1] * 0.75 and hurt[2] < fresh[2] * 0.75,
		"smash / slam / rake cooldowns at 20%% are under 75%% of fresh (%s -> %s)" % [str(fresh), str(hurt)])
	s.queue_free()
	await _frames(3)
