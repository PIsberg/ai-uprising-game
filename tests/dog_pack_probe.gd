extends Node3D
## Probe: the K-9 HUNTER's PACK HUNT (EnemyDog.pack_hunt). Every dog used to
## pounce on its own timer, so a pack of four reared together and landed four
## 22-damage pounces in the same half second. Now, with four real dogs 8 m out
## round a stand-in player, over 14 s:
##   - only one pounce is ever under way (rearing or in the air);
##   - a dog does not rear until PACK_GAP after the last pounce landed;
##   - no two pounce bites land within half a second of each other;
##   - the pack still pounces (4 or more) and every dog gets a turn;
##   - the dogs waiting their turn run a ring round the prey: on the move, and
##     neither in its face nor gone;
## and
##   - a lone dog is unchanged: it rears at once, closes to bite afterwards,
##     and pounces again after its own cooldown;
##   - a dog killed while rearing does not hold the pack's turn;
##   - ORB and ROLLER (which extend the dog) do not pack hunt.
## Timed in physics frames.
##   godot --headless --path . --audio-driver Dummy res://tests/dog_pack_probe.tscn

const GAP := 0.7 ## spec, mirrored by EnemyDog.PACK_GAP
const POUNCE := 22.0

var ok := true
var player: CharacterBody3D
var hp: Damageable
var hits: Array = [] ## [frame, amount]
var frame := 0

func _check(label: String, cond: bool, detail: String = "") -> void:
	print("%s %s %s" % ["PASS" if cond else "FAIL", label, detail])
	if not cond:
		ok = false

func _ready() -> void:
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	frame += 1

func _busy(d: Node) -> bool:
	return is_instance_valid(d) and d.state != EnemyBase.State.DEAD and (bool(d.get("_pouncing")) or float(d.get("_pounce_windup_t")) > 0.0)

func _run() -> void:
	GameState.set_state(GameState.State.PLAYING)
	var nav := NavigationRegion3D.new()
	add_child(nav)
	var fmi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(160, 60)
	fmi.mesh = pm
	nav.add_child(fmi)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(160, 1, 60)
	fcs.shape = fbox
	fcs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcs)
	nav.add_child(floor_body)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.agent_radius = 0.5
	nm.cell_size = 0.25
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh()
	for i in 10:
		await get_tree().physics_frame
	player = CharacterBody3D.new()
	player.add_to_group("player")
	player.collision_layer = 2
	player.collision_mask = 0
	var pcs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	pcs.shape = cap
	pcs.position.y = 0.9
	player.add_child(pcs)
	hp = Damageable.new()
	hp.name = "Damageable"
	hp.max_health = 100000.0
	player.add_child(hp)
	add_child(player)
	hp.current_health = 100000.0
	hp.damaged.connect(func(amount: float, _src: Node) -> void: hits.append([frame, amount]))
	await get_tree().physics_frame

	# 1. A pack of four.
	var pack: Array = await _stage(Vector3.ZERO, [Vector3(8, 0, 0), Vector3(-8, 0, 0), Vector3(0, 0, 8), Vector3(0, 0, -8)])
	var was: Array = [false, false, false, false] ## busy last frame
	var air: Array = [false, false, false, false] ## _pouncing last frame
	var most := 0
	var rears: Array = [] ## [frame, dog index]
	var lands: Array = [] ## frames
	var early := "" ## a rear that came too soon after a landing
	var wait_speed := 0.0
	var wait_dist := 0.0
	var wait_n := 0
	var near := INF
	var far := 0.0
	for f in 14 * 60:
		await get_tree().physics_frame
		var busy := 0
		for i in 4:
			var d: Node = pack[i]
			var b := _busy(d)
			if b:
				busy += 1
			if b and not was[i]:
				if not lands.is_empty() and frame - int(lands[-1]) < int(GAP * 60.0) - 3:
					early = "dog %d reared %d frames after a landing" % [i, frame - int(lands[-1])]
				rears.append([frame, i])
			var a := bool(d.get("_pouncing"))
			if air[i] and not a:
				lands.append(frame)
			was[i] = b
			air[i] = a
		most = maxi(most, busy)
		if busy >= 1 and f > 30:
			for i in 4:
				var d: CharacterBody3D = pack[i]
				if _busy(d) or not d.is_on_floor():
					continue
				var off := d.global_position - player.global_position
				off.y = 0.0
				wait_n += 1
				wait_speed += Vector2(d.velocity.x, d.velocity.z).length()
				wait_dist += off.length()
				near = minf(near, off.length())
				far = maxf(far, off.length())
	var who := {}
	for r in rears:
		who[r[1]] = true
	_check("only one pounce is ever under way", most == 1, "%d at once" % most)
	_check("a dog does not rear until PACK_GAP after the last landing", early == "" and lands.size() >= 3, "%s (%d landings)" % [early, lands.size()])
	var bites: Array = hits.filter(func(h: Array) -> bool: return absf(float(h[1]) - POUNCE) < 0.5)
	var close := 0
	for i in range(1, bites.size()):
		if int(bites[i][0]) - int(bites[i - 1][0]) < 30:
			close += 1
	var total := 0.0
	for h in hits:
		total += float(h[1])
	_check("no two pounce bites land within half a second", close == 0 and bites.size() >= 2, "%d pairs, %d pounce bites, %.0f damage in 14 s" % [close, bites.size(), total])
	_check("the pack still pounces and every dog gets a turn", rears.size() >= 4 and who.size() == 4, "%d pounces by %d dogs" % [rears.size(), who.size()])
	var mean_speed := wait_speed / maxf(1.0, float(wait_n))
	var mean_dist := wait_dist / maxf(1.0, float(wait_n))
	_check("the dogs waiting their turn are on the move", wait_n > 200 and mean_speed > 3.0, "%.1f m/s mean over %d samples" % [mean_speed, wait_n])
	_check("and run a ring round the prey, neither in its face nor gone", mean_dist > 4.5 and mean_dist < 10.0 and far < 16.0, "mean %.1f m, %.1f to %.1f m" % [mean_dist, near, far])
	await _clear(pack)

	# 2. A lone dog is unchanged.
	pack = await _stage(Vector3(60, 0, 0), [Vector3(8, 0, 0)])
	var lone: CharacterBody3D = pack[0]
	var first := -1
	var second := -1
	var landed := -1
	var closest := INF
	var circled := false
	var prev := false
	var prev_air := false
	var start := frame
	for f in 9 * 60:
		await get_tree().physics_frame
		var b := _busy(lone)
		if b and not prev:
			if first < 0:
				first = frame - start
			elif second < 0:
				second = frame - start
		var a := bool(lone.get("_pouncing"))
		if prev_air and not a and landed < 0:
			landed = frame - start
		prev = b
		prev_air = a
		if lone.get("circling") == true:
			circled = true
		if landed >= 0:
			closest = minf(closest, lone.global_position.distance_to(player.global_position))
	_check("a lone dog rears at once", first >= 0 and first < 60, "%d frames" % first)
	_check("closes to bite after its pounce and never circles", closest < 3.5 and not circled, "%.1f m, circled %s" % [closest, circled])
	_check("and pounces again after its own cooldown", second > landed + int(lone.pounce_cooldown * 60.0) - 6 and second >= 0, "landed at %d, reared again at %d" % [landed, second])
	await _clear(pack)

	# 3. A dog killed while rearing does not hold the turn.
	pack = await _stage(Vector3(-60, 0, 0), [Vector3(8, 0, 0), Vector3(-8, 0, 0)])
	var killed := -1
	for f in 120:
		await get_tree().physics_frame
		for i in 2:
			if killed < 0 and float(pack[i].get("_pounce_windup_t")) > 0.0:
				killed = i
		if killed >= 0:
			break
	for f in 8:
		await get_tree().physics_frame
	if killed >= 0:
		pack[killed].hp.apply_damage(100000.0, null)
	var other: Node = pack[1 - maxi(killed, 0)]
	var took := -1
	for f in 150:
		await get_tree().physics_frame
		if _busy(other):
			took = f
			break
	_check("a dog killed while rearing does not hold the pack's turn", killed >= 0 and took >= 0 and took < 90, "the other reared %d frames later" % took)
	await _clear(pack)

	# 4. The dog's subclasses keep their own attacks.
	for path: String in ["res://scenes/enemies/orb.tscn", "res://scenes/enemies/roller.tscn"]:
		var e: Node = (load(path) as PackedScene).instantiate()
		_check("%s does not pack hunt" % path.get_file().get_basename(), e.get("pack_hunt") != true)
		e.free()

	print("RESULT %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)

## The stand-in at `at`, one fresh dog per offset, all awake and on it.
func _stage(at: Vector3, offsets: Array) -> Array:
	player.global_position = at
	var out: Array = []
	for o: Vector3 in offsets:
		var d: EnemyBase = (load("res://scenes/enemies/dog.tscn") as PackedScene).instantiate()
		add_child(d)
		d.global_position = at + o + Vector3.UP * 0.3
		out.append(d)
	for i in 3:
		await get_tree().physics_frame
	for d: EnemyBase in out:
		d.target = player
		d.set_state(EnemyBase.State.CHASE)
	hits.clear()
	return out

func _clear(pack: Array) -> void:
	for d in pack:
		if is_instance_valid(d):
			d.queue_free()
	for i in 4:
		await get_tree().physics_frame
	hits.clear()
