extends Node3D
## Probe: the FORK BOMB (enemy_forkbomb.gd).
## (1) wired: level builder, codex, mistral (1) and claude (2) rosters;
## (2) killed, generation 0 forks into two generation-1 copies (smaller,
##     weaker, in the "enemy" group), those into four generation 2, and the
##     last generation does not fork: seven kills in all;
## (3) a disintegrating (gauss) kill deletes the process: no fork;
## (4) a fork never lands a copy on the far side of a wall.
##   godot --headless --path . --audio-driver Dummy res://tests/forkbomb_probe.tscn

const SCENE := "res://scenes/enemies/forkbomb.tscn"
var ok := true

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
	# 1. Wiring.
	_check("level builder knows forkbomb", LevelBuilder.ENEMY_SCENES.get("forkbomb", "") == SCENE)
	_check("codex entry", EnemyCodex.has("forkbomb") and "forkbomb" in EnemyCodex.ORDER)
	for want in [["mistral", 1], ["claude", 2]]:
		var n := 0
		for en in LevelDefs.get_def(want[0]).get("enemies", []):
			if en.get("type", "") == "forkbomb":
				n += 1
		_check("%d on the %s roster" % [want[1], want[0]], n == want[1], str(n))

	var floor_body := StaticBody3D.new()
	var fcs := CollisionShape3D.new()
	var fbs := BoxShape3D.new()
	fbs.size = Vector3(200, 1, 200)
	fcs.shape = fbs
	fcs.position.y = -0.5
	floor_body.add_child(fcs)
	add_child(floor_body)

	# 2. The fork tree.
	var root := _bomb(Vector3(0, 0, 0))
	await _frames(3)
	_check("gen 0 stats", root.generation == 0 and root.hp.max_health == EnemyForkbomb.GEN_HEALTH[0]
			and is_equal_approx(root.scale.x, EnemyForkbomb.GEN_SCALE[0]))
	root.hp.apply_damage(99999.0, null)
	await _frames(4)
	var g1 := _alive_gen(1)
	_check("gen 0 forks into two", g1.size() == 2, "%d" % g1.size())
	if g1.size() == 2:
		var c: EnemyForkbomb = g1[0]
		_check("copies are smaller and weaker", c.hp.max_health == EnemyForkbomb.GEN_HEALTH[1]
				and c.scale.x < root.scale.x and c.is_in_group("enemy"),
				"hp %.0f scale %.2f" % [c.hp.max_health, c.scale.x])
	for c in g1:
		(c as EnemyForkbomb).hp.apply_damage(99999.0, null)
	await _frames(4)
	var g2 := _alive_gen(2)
	_check("gen 1 forks into four", g2.size() == 4, "%d" % g2.size())
	for c in g2:
		(c as EnemyForkbomb).hp.apply_damage(99999.0, null)
	await _frames(6)
	_check("the last generation does not fork", _alive_all().is_empty(), "%d alive" % _alive_all().size())

	# 3. Disintegration deletes the process.
	await _frames(150) # let the earlier wrecks clear
	var z := _bomb(Vector3(40, 0, 0))
	await _frames(3)
	KillFx.tag(z.hp, KillFx.DISINTEGRATE)
	z.hp.apply_damage(99999.0, null)
	KillFx.untag(z.hp)
	await _frames(6)
	_check("disintegrated: no fork", _alive_gen(1).is_empty())

	# 4. Never across a wall.
	var w := _bomb(Vector3(-40, 0, 0))
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(0.3, 3, 6)
	wcs.shape = wbs
	wall.add_child(wcs)
	add_child(wall)
	wall.global_position = Vector3(-39.5, 1.5, 0)
	await _frames(3)
	w.hp.apply_damage(99999.0, null) # no target: forks along +X / -X
	await _frames(4)
	var kids := _alive_gen(1)
	var crossed := false
	for k in kids:
		if (k as Node3D).global_position.x > -39.5:
			crossed = true
	_check("fork stays on this side of the wall", kids.size() == 2 and not crossed,
			"%d kids" % kids.size())

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _bomb(pos: Vector3) -> EnemyForkbomb:
	var e := (load(SCENE) as PackedScene).instantiate() as EnemyForkbomb
	add_child(e)
	e.global_position = pos
	return e

func _alive_all() -> Array:
	var out := []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n is EnemyForkbomb and (n as EnemyForkbomb).hp.is_alive():
			out.append(n)
	return out

func _alive_gen(g: int) -> Array:
	return _alive_all().filter(func(n): return (n as EnemyForkbomb).generation == g)
