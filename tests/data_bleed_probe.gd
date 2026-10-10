extends Node
## Probe: robots bleed data (scripts/fx/data_bleed.gd).
## (1) the glyph sheet has two frames, a "0" and a "1", and they differ;
## (2) a rifle hit on a robot spills glyphs at the hit, more on a crit, scaled
##     by damage inside HIT_MIN..HIT_MAX; a shot into a wall spills nothing;
## (3) many spills in one frame are capped at FRAME_BUDGET emitters;
## (4) a robot's death bursts BURST_AMOUNT glyphs from its body, whatever
##     killed it (the burst hangs off hp.died, so overrides cannot skip it);
## (5) every emitter frees itself.
##   godot --headless --path . --audio-driver Dummy res://tests/data_bleed_probe.tscn

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

func _bleeds() -> Array:
	return get_tree().get_nodes_in_group(DataBleed.GROUP)

func _box(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	add_child(b)
	b.global_position = pos
	return b

func _run() -> void:
	# 1. The glyph sheet.
	var img := DataBleed.glyph_texture().get_image()
	var w := img.get_width() / 2
	var differ := false
	for y in img.get_height():
		for x in w:
			if img.get_pixel(x, y).a != img.get_pixel(x + w, y).a:
				differ = true
	_check("glyph sheet: two square frames side by side", img.get_width() == img.get_height() * 2,
			"%dx%d" % [img.get_width(), img.get_height()])
	_check("glyph sheet: 0 and 1 differ", differ)

	_box(Vector3(0, -0.5, 0), Vector3(200, 1, 200))
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 90)
	var rifle: Weapon = (load("res://scenes/weapons/rifle.tscn") as PackedScene).instantiate()
	add_child(rifle)
	rifle._active_shooter = player
	var e: EnemyBase = (load("res://scenes/enemies/android.tscn") as PackedScene).instantiate()
	add_child(e)
	e.global_position = Vector3.ZERO
	await _frames(4)
	e.hp.max_health = 100000.0
	e.hp.current_health = 100000.0

	# 2. Hits spill at the hit point; walls do not.
	await _frames(2)
	var before := _bleeds().size()
	var at := e.global_position + Vector3.UP * 0.8
	rifle._do_hitscan(at + Vector3(0, 0, 10), Vector3(0, 0, -1))
	var after := _bleeds()
	_check("a body hit spills data", after.size() == before + 1, "%d -> %d" % [before, after.size()])
	var body_amt := 0
	if after.size() > before:
		var p: Node3D = after[after.size() - 1]
		body_amt = DataBleed.amount_of(p)
		_check("at the hit", p.global_position.distance_to(at) < 0.6, str(p.global_position))
		_check("hit amount inside HIT_MIN..HIT_MAX", body_amt >= DataBleed.HIT_MIN and body_amt <= DataBleed.HIT_MAX, str(body_amt))
	_check("a crit spills more", DataBleed.hit_amount(20.0, true) > DataBleed.hit_amount(20.0, false))
	_check("a harder hit spills more", DataBleed.hit_amount(60.0, false) > DataBleed.hit_amount(8.0, false))
	await _frames(2)
	var wall := _box(Vector3(8, 1, -3), Vector3(1, 3, 1))
	before = _bleeds().size()
	rifle._do_hitscan(Vector3(8, 1, 6), Vector3(0, 0, -1))
	_check("a wall hit spills nothing", _bleeds().size() == before)
	wall.queue_free()

	# 3. Frame budget.
	await _frames(2)
	before = _bleeds().size()
	for i in 50:
		DataBleed.spill(self, Vector3(0, 1, 0), Vector3.BACK, 6)
	_check("one frame's spills capped at FRAME_BUDGET", _bleeds().size() - before == DataBleed.FRAME_BUDGET,
			str(_bleeds().size() - before))

	# 4. Death burst, from a kill that never touches a weapon.
	await _frames(2)
	before = _bleeds().size()
	var died_at := e.global_position # it walks once shot at
	e.hp.apply_damage(1000000.0, player, false, e.global_position + Vector3.UP)
	var burst: Node3D = null
	for b in _bleeds():
		if DataBleed.amount_of(b) == DataBleed.BURST_AMOUNT:
			burst = b
	_check("death bursts BURST_AMOUNT glyphs", burst != null, "%d new" % (_bleeds().size() - before))
	if burst:
		var flat := Vector2(burst.global_position.x - died_at.x, burst.global_position.z - died_at.z).length()
		var up := burst.global_position.y - died_at.y
		_check("from the body", flat < 0.6 and up > 0.3 and up < 2.5,
				str(burst.global_position))

	# 5. They clean up after themselves.
	var t := 0
	while not _bleeds().is_empty() and t < 60 * 6:
		await get_tree().physics_frame
		t += 1
	_check("every emitter frees itself", _bleeds().is_empty(), "%d left" % _bleeds().size())

	print("RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit()
