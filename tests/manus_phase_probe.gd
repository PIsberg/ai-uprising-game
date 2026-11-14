extends Node
## MANUS wounded escalation: three health-keyed phases (like every other boss).
##   (1) fresh: phase 1, attack cooldowns at their authored values, ONE finger
##       eruption per spike;
##   (2) at <=33% HP: phase 3, the phase-change punch fires once, cooldowns
##       shrink by PHASE_CD_MULT[2], and the spike erupts TWICE — the second
##       burst leading the player's velocity;
##   (3) the difficulty tier (#73): an arm spawned on EASY, NORMAL and HARD is
##       wounded and starts each attack. Cooldowns come back slower and windups
##       and the eruption's warning ring last longer on an easier tier; HARD is
##       the authored arm.
##   godot --headless --path . --audio-driver Dummy res://tests/manus_phase_probe.tscn

var _fail: Array[String] = []

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_fail.append(label)

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

## Finger spears are CylinderMesh instances 2.6 m tall parented to the current
## scene (this node) by _spawn_spike_fingers — nothing else here matches.
func _spears() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c in get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh \
				and is_equal_approx(((c as MeshInstance3D).mesh as CylinderMesh).height, 2.6):
			out.append(c)
	return out

func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_make_floor()
	var player := _make_player(Vector3(20, 1.0, 0))
	var manus: Node3D = load("res://scenes/enemies/manus.tscn").instantiate()
	get_tree().root.add_child(manus)
	manus.global_position = Vector3.ZERO
	await _wait(150) # entrance + wake
	manus.target = player
	var fps := Engine.physics_ticks_per_second
	var sample_frames := int(ceil((manus.spike_windup + 0.45) * fps))

	# --- fresh ------------------------------------------------------------
	_check(manus._phase() == 1, "full HP is phase 1")
	manus._begin_sweep()
	_check(is_equal_approx(manus._sweep_cd, manus.sweep_cooldown),
		"phase 1 sweep cooldown = authored %.2f (got %.2f)" % [manus.sweep_cooldown, manus._sweep_cd])
	manus._spike_cd = 0.0
	manus._begin_spike()
	await _wait(sample_frames)
	var n1 := _spears().size()
	_check(n1 == 5, "phase 1 spike erupts once (5 spears, got %d)" % n1)
	await _wait(int(2.5 * fps)) # let the spears withdraw and free

	# --- wounded ----------------------------------------------------------
	manus.hp.current_health = manus.hp.max_health * 0.30
	await _wait(2)
	_check(manus._phase() == 3, "30%% HP is phase 3 (got %d)" % manus._phase())
	_check(manus._last_phase == 3, "phase-change punch fired (last_phase=%d)" % manus._last_phase)
	manus._begin_sweep()
	# Behavioural bar first (materially faster than authored — not derived from
	# the constant, so a neutered table still fails), then the exact value.
	_check(manus._sweep_cd < manus.sweep_cooldown * 0.75,
		"phase 3 sweep cooldown is at most 75%% of authored (got %.2f of %.2f)" % [manus._sweep_cd, manus.sweep_cooldown])
	var want: float = manus.sweep_cooldown * manus.PHASE_CD_MULT[2]
	_check(absf(manus._sweep_cd - want) < 0.01,
		"phase 3 sweep cooldown = %.2f (got %.2f)" % [want, manus._sweep_cd])
	manus._begin_grab()
	_check(manus._grab_cd < manus.grab_cooldown * 0.75,
		"phase 3 grab cooldown is at most 75%% of authored (got %.2f)" % manus._grab_cd)
	# Second eruption leads the run: player "moving" +X at 5 m/s.
	player.velocity = Vector3(5.0, 0.0, 0.0)
	var px: float = player.global_position.x
	manus._spike_cd = 0.0
	manus._begin_spike()
	await _wait(sample_frames)
	var spears := _spears()
	_check(spears.size() == 10, "phase 3 spike erupts twice (10 spears, got %d)" % spears.size())
	var led := 0
	for s in spears:
		if s.global_position.x > px + 2.0:
			led += 1
	_check(led >= 3, "second burst leads the player's velocity (%d spears ahead)" % led)
	manus.queue_free()
	await _wait(120) # the spears withdraw

	# --- the difficulty tier (#73) ------------------------------------------
	# No tier reached MANUS's own cooldowns and windups: EASY met HARD's 2.11 s
	# phase-3 sweep. Each tier's arm, given the tier's multipliers the way
	# EnemySpawner gives them (before add_child), is wounded and starts each
	# attack; the eruption's ring is timed from its warning to its spears.
	var cd := {}
	var wind := {}
	var ring := {}
	for tier: int in [GameState.Difficulty.EASY, GameState.Difficulty.NORMAL, GameState.Difficulty.HARD]:
		var cfg: Dictionary = GameState.DIFFICULTY_CONFIG[tier]
		var m: Node3D = load("res://scenes/enemies/manus.tscn").instantiate()
		m.set("_cooldown_mult", float(cfg["cooldown_mult"]))
		m.set("_reaction_mult", float(cfg["reaction_mult"]))
		get_tree().root.add_child(m)
		m.global_position = Vector3.ZERO
		await _wait(150)
		m.set_physics_process(false)
		m.target = player
		player.velocity = Vector3.ZERO
		var hp: Node = m.get_node("Damageable")
		hp.current_health = hp.max_health * 0.5 # phase 2: one eruption, not two
		m._begin_spike()
		var spike_cd: float = m._spike_cd
		var t := 0
		while _spears().is_empty() and t < 240:
			await get_tree().physics_frame
			t += 1
		ring[tier] = float(t) / fps
		hp.current_health = hp.max_health * 0.2
		m._begin_sweep()
		m._begin_slam()
		m._begin_grab()
		cd[tier] = [m._sweep_cd, m._slam_cd, m._grab_cd, spike_cd]
		wind[tier] = [m._sweep_windup_t, m._slam_windup_t]
		print("  %s: wounded sweep/slam/grab back in %.2f / %.2f / %.2f s, wound up %.2f / %.2f s; eruption ring %.2f s" % [
			cfg["label"], cd[tier][0], cd[tier][1], cd[tier][2], wind[tier][0], wind[tier][1], ring[tier]])
		m.queue_free()
		await _wait(120)
	var ez: int = GameState.Difficulty.EASY
	var nm: int = GameState.Difficulty.NORMAL
	var hd: int = GameState.Difficulty.HARD
	var slower := true
	for k in 4:
		slower = slower and cd[ez][k] > cd[nm][k] * 1.2 and cd[nm][k] >= cd[hd][k]
	_check(slower, "an easier tier's attacks come back slower (wounded sweep %.2f / %.2f / %.2f s)" % [cd[ez][0], cd[nm][0], cd[hd][0]])
	_check(wind[ez][0] > wind[nm][0] * 1.2 and wind[nm][0] >= wind[hd][0] and wind[ez][1] > wind[nm][1] * 1.2 and wind[nm][1] >= wind[hd][1],
		"an easier tier's windups last longer (sweep %.2f / %.2f / %.2f s)" % [wind[ez][0], wind[nm][0], wind[hd][0]])
	_check(ring[ez] > ring[nm] + 0.2 and ring[nm] >= ring[hd],
		"an easier tier's eruption ring warns longer (%.2f / %.2f / %.2f s)" % [ring[ez], ring[nm], ring[hd]])
	_check(absf(cd[hd][0] - 3.4 * 0.62) < 0.01 and absf(wind[hd][0] - 0.45) < 0.01 and absf(ring[hd] - 0.75) < 0.06,
		"HARD is the authored MANUS, not a harder one (sweep %.2f s back, %.2f s windup, ring %.2f s)" % [cd[hd][0], wind[hd][0], ring[hd]])

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
