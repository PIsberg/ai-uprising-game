extends Node3D
## Hazard surges (flood_surge.gd): a survive wave's "flood" telegraphs, rises,
## burns whoever is still on the flooded ground, spares a deck above it, clears
## on death and re-runs its warning for the in-place respawn, and drains when the
## hold completes. Then every campaign flood: beds scale with the world, land
## with time left in the hold, never overlap each other (z-fight), leave the exit
## and enough decks dry, and every later wave supply sits on dry ground. Live:
## each flood level is built, its surge forced, and real bodies on the exit and
## in a bed show the built geometry agrees with the def.
##   godot --headless --path . --audio-driver Dummy res://tests/flood_surge_probe.tscn

const SLAB_HALF := 0.8   # LavaHazard damage box is 1.6 tall around the surface
const SURFACE := 0.06    # LavaHazard.surface_y
## Flood levels must leave this many decks dry: a refuge, not a single pillar.
const MIN_DRY_DECKS := 3

var _fails: Array[String] = []

class StubPlayer extends CharacterBody3D:
	var hp: Damageable

func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails.append(what)

func _ready() -> void:
	# Let autoload boot settle first: an early state write gets overwritten.
	await _frames(10)
	var prev_state = GameState.current_state
	GameState.current_state = GameState.State.PLAYING
	await _unit()
	_campaign()
	await _live()
	GameState.current_state = prev_state
	print("RESULT " + ("PASS" if _fails.is_empty() else "FAIL"))
	for f in _fails:
		print("  - " + f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

## Physics frames until `secs` of game time have passed (never one long timer).
func _wait(secs: float) -> void:
	await _frames(int(ceil(secs * Engine.physics_ticks_per_second)) + 2)

func _stub(pos: Vector3, group: bool = false) -> StubPlayer:
	var p := StubPlayer.new()
	if group:
		p.add_to_group("player")
	p.collision_layer = 2
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = CapsuleShape3D.new() # 2 m tall, 0.5 radius
	cs.position.y = 1.0             # feet at the node's origin
	p.add_child(cs)
	p.hp = Damageable.new()
	p.hp.name = "Damageable" # hazards look the component up by name
	p.hp.max_health = 100000.0
	p.add_child(p.hp)
	p.position = pos
	add_child(p)
	return p

func _unit() -> void:
	print("unit:")
	GameState.reset_tasks()
	GameState.register_task("srv", "Hold", 60.0)
	var low := _stub(Vector3(1, 0, 1), true)     # on the doomed floor
	var deck := _stub(Vector3(-1, 1.6, -1))       # on a deck over the same bed
	var dry := _stub(Vector3(20, 0, 0))           # off the bed entirely
	var fs := FloodSurge.new()
	fs.task_id = "srv"
	fs.warn_seconds = 0.8
	fs.rise_seconds = 0.3
	fs.beds = [{"pos": Vector3.ZERO, "size": Vector2(8, 8), "dmg": 20.0}]
	add_child(fs)
	await _wait(0.4)
	_check(fs.phase == FloodSurge.Phase.WARN, "starts with a warning, not a burn")
	_check(fs.get_children().any(func(c): return c is MeshInstance3D), "the warning marks the doomed footprint")
	_check(is_equal_approx(low.hp.current_health, low.hp.max_health), "no damage during the warning")
	await _wait(0.4 + 0.3 + 0.5)
	_check(fs.phase == FloodSurge.Phase.LIVE and fs.live_beds().size() == 1, "the bed rises after the warning")
	_check(low.hp.current_health < low.hp.max_health, "the risen bed burns a body left on the floor (%.0f lost)" % (low.hp.max_health - low.hp.current_health))
	_check(is_equal_approx(deck.hp.current_health, deck.hp.max_health), "a deck 1.6 m up stays dry (control: same footprint)")
	_check(is_equal_approx(dry.hp.current_health, dry.hp.max_health), "ground outside the bed stays dry")
	# Death: the respawn is in place and may be on the flooded floor, so the
	# beds go at once and the warning runs again when play resumes.
	var deaths: int = GameState.level_deaths
	GameState.on_player_died("probe")
	await _frames(3)
	_check(fs.live_beds().is_empty(), "death clears the risen beds at once")
	GameState.current_state = GameState.State.PLAYING
	GameState.level_deaths = deaths
	await _frames(3)
	_check(fs.phase == FloodSurge.Phase.WARN, "play resuming re-runs the warning")
	var hp_r: float = low.hp.current_health
	await _wait(0.4)
	_check(is_equal_approx(hp_r, low.hp.current_health), "no burn during the second warning")
	await _wait(0.4 + 0.3 + 0.5)
	_check(fs.live_beds().size() == 1 and low.hp.current_health < hp_r, "the surge comes back after the respawn warning")
	# Hold won: the flood drains and stops burning at once.
	GameState.complete_task("srv")
	await _frames(2)
	_check(fs.phase == FloodSurge.Phase.DRAINED, "completing the hold drains the flood")
	var hp_d: float = low.hp.current_health
	await _wait(0.6)
	_check(is_equal_approx(hp_d, low.hp.current_health), "a draining bed no longer burns")
	await _wait(1.8)
	_check(not fs.get_children().any(func(c): return c is LavaHazard), "drained beds are freed")
	for n in [fs, low, deck, dry]:
		n.queue_free()
	GameState.reset_tasks()
	await _frames(3)

## Is `p` (a body's feet) inside the bed's damage box?
func _in_bed(b: Dictionary, p: Vector3) -> bool:
	var c: Vector3 = b["pos"]
	var s: Vector2 = b["size"]
	var top := c.y + SURFACE + SLAB_HALF
	var bottom := c.y + SURFACE - SLAB_HALF
	# A 2 m body overlaps the slab when its feet are below the top and its head above the bottom.
	return absf(p.x - c.x) < s.x * 0.5 and absf(p.z - c.z) < s.y * 0.5 and p.y < top and p.y + 2.0 > bottom

## Every flood a level authors: on a survive wave (lands mid-hold) or on a task
## itself (runs while that stage is live; "wave" is empty).
func _floods(def: Dictionary) -> Array:
	var out: Array = []
	for t in def.get("tasks", []):
		if t.has("flood"):
			out.append({"task": t, "wave": {}, "flood": t["flood"]})
		if t.get("type", "") != "survive":
			continue
		for w in t.get("waves", []):
			if w.has("flood"):
				out.append({"task": t, "wave": w, "flood": w["flood"]})
	return out

func _campaign() -> void:
	print("campaign:")
	var n := 0
	var raw_defs := LevelDefs._defs()
	for id in raw_defs.keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var raw_floods := _floods(raw_defs[id])
		var floods := _floods(def)
		var s: float = float(raw_defs[id].get("world_scale", LevelDefs.WORLD_SCALE))
		for i in floods.size():
			n += 1
			var f: Dictionary = floods[i]
			var flood: Dictionary = f["flood"]
			var beds: Array = flood.get("beds", [])
			var hold: float = float(f["task"].get("seconds", 0.0))
			var at: float = float(f["wave"].get("at", 0.0))
			var lands := at + float(flood.get("warn", 3.0)) + float(flood.get("rise", 1.2))
			_check(not beds.is_empty(), "%s: flood has beds" % id)
			if not (f["wave"] as Dictionary).is_empty():
				_check(hold - lands >= 5.0, "%s: flood lands with >= 5 s of hold left (lands %.0f s of %.0f)" % [id, lands, hold])
			elif (f["task"] as Dictionary).has("pos"):
				# A task's own flood must not drown the objective it guards.
				var tp: Vector3 = f["task"]["pos"]
				_check(not beds.any(func(b): return _in_bed(b, tp)), "%s: the flooded task's objective %v stays dry" % [id, tp])
			_check(String(flood.get("warn_title", "")) != "", "%s: flood warning is announced" % id)
			var raw_beds: Array = raw_floods[i]["flood"].get("beds", [])
			for j in beds.size():
				var b: Dictionary = beds[j]
				var rb: Dictionary = raw_beds[j]
				_check((b["size"] as Vector2).is_equal_approx((rb["size"] as Vector2) * s)
					and is_equal_approx((b["pos"] as Vector3).x, (rb["pos"] as Vector3).x * s)
					and is_equal_approx((b["pos"] as Vector3).y, (rb["pos"] as Vector3).y),
					"%s: bed %d scales with the world (pos xz and size, height kept)" % [id, j])
				for k in range(j + 1, beds.size()):
					_check(not _beds_overlap(b, beds[k]), "%s: beds %d and %d do not overlap (z-fight)" % [id, j, k])
			# The exit must stay dry, or the level cannot be finished while flooded.
			var ex: Vector3 = def.get("exit", Vector3.ZERO)
			_check(not beds.any(func(b): return _in_bed(b, ex)), "%s: exit %v stays dry" % [id, ex])
			var dry := 0
			for pl in def.get("platforms", []):
				var top: Vector3 = (pl["pos"] as Vector3) + Vector3(0, (pl["size"] as Vector3).y * 0.5, 0)
				if not beds.any(func(b): return _in_bed(b, top)):
					dry += 1
			_check(dry >= MIN_DRY_DECKS, "%s: %d decks stay dry (>= %d)" % [id, dry, MIN_DRY_DECKS])
			# Supplies vented at or after the flood wave must be reachable dry.
			for w in f["task"].get("waves", []):
				if float(w.get("at", 0.0)) < at:
					continue
				for sup in w.get("supplies", []):
					var sp: Vector3 = sup.get("pos", Vector3.ZERO)
					_check(not beds.any(func(b): return _in_bed(b, sp - Vector3(0, 0.1, 0))),
						"%s: supply %v vented after the flood is on dry ground" % [id, sp])
	_check(n >= 2, "campaign authors floods (%d)" % n)

func _beds_overlap(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx((a["pos"] as Vector3).y, (b["pos"] as Vector3).y):
		return false
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	var sa: Vector2 = a["size"]
	var sb: Vector2 = b["size"]
	var ox := (sa.x + sb.x) * 0.5 - absf(pa.x - pb.x)
	var oz := (sa.y + sb.y) * 0.5 - absf(pa.z - pb.z)
	return ox > 0.01 and oz > 0.01

## Build each flood level for real, force its surge, and put bodies on the exit
## (must stay dry) and in each bed (must burn).
func _live() -> void:
	print("live:")
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		var floods := _floods(def)
		if floods.is_empty():
			continue
		var path := "res://scenes/levels/level_%s.tscn" % id
		var lvl: LevelBuilder = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		for i in 10:
			await get_tree().create_timer(0.25).timeout
		GameState.current_state = GameState.State.PLAYING
		for f in floods:
			var flood: Dictionary = (f["flood"] as Dictionary).duplicate(true)
			flood["warn"] = 0.2
			flood["rise"] = 0.2
			lvl._start_flood(flood, "probe_never_done")
			var ex: Vector3 = def.get("exit", Vector3.ZERO)
			var on_exit := _stub(ex + Vector3(0, 0.05, 0))
			var in_beds: Array = []
			for b in flood["beds"]:
				var c: Vector3 = b["pos"]
				var sz: Vector2 = b["size"]
				in_beds.append(_stub(c + Vector3(sz.x * 0.3, 0.0, sz.y * 0.3)))
			await _wait(1.2)
			_check(is_equal_approx(on_exit.hp.current_health, on_exit.hp.max_health), "%s live: a body on the exit stays dry" % id)
			for j in in_beds.size():
				var st: StubPlayer = in_beds[j]
				_check(st.hp.current_health < st.hp.max_health, "%s live: bed %d burns a body inside it" % [id, j])
			on_exit.queue_free()
			for st in in_beds:
				st.queue_free()
		lvl.queue_free()
		await _frames(3)
