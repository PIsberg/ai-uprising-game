extends Node
## MANUS wounded escalation: three health-keyed phases (like every other boss).
##   (1) fresh: phase 1, attack cooldowns at their authored values, ONE finger
##       eruption per spike;
##   (2) at <=33% HP: phase 3, the phase-change punch fires once, cooldowns
##       shrink by PHASE_CD_MULT[2], and the spike erupts TWICE — the second
##       burst leading the player's velocity.
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

	print("RESULT ", "FAIL" if _fail.size() > 0 else "PASS")
	get_tree().quit()
