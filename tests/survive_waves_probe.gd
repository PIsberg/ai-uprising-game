extends Node3D
## Campaign-wide net for "survive" holds. A hold with no `waves` is a countdown
## the player sits out behind cover; GPT Foundry was the only level that authored
## any (tests/purge_probe covers its arc + the timer itself). This probe asserts
## EVERY campaign survive hold escalates, and that no wave can silently do
## nothing or spawn into a hazard:
##   - >= 2 waves, ascending, all strictly inside the hold, each announced
##   - every wave enemy / supply type resolves to a real scene
##   - airborne spawns (y >= AIR_Y) are only used for types that actually fly
##   - ground spawns stand on a platform or clear every lava/water bed by the
##     spawner's scatter (2.5 m when "count" > 1) — enemies are NOT relocated
##     out of hazards, and on the two sea levels the whole floor is one
##   - sharks are the exception: they must spawn IN a water bed
##   - a clustered ground spawn ("count" > 1) never sits on a platform: the
##     2.5 m scatter is wider than a 2.6 m catwalk
##   - LIVE: each level is built and every walking wave spawn must sit on the
##     baked navmesh with a path to the player spawn
##   godot --headless --path . --audio-driver Dummy res://tests/survive_waves_probe.tscn

## Holds that are deliberately bare, with the reason. Anything not listed here
## must author waves.
const EXEMPT := {
	"convoy": "the ride's own boarder/flyer director is the escalation (convoy_ride.gd)",
}

const AIR_Y := 2.5
## Units that live IN the flood: these must spawn inside a `"water": true` bed.
const SWIMMERS := ["shark"]
## Ranged units allowed to hold a platform with no walkable route off it.
const PERCHERS := ["sniper"]
const FLYERS := ["drone", "raptor", "seeker", "fishbot", "breaker", "whirlwind", "mender", "reaper"]

var _ok := true

func _check(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		print("BAD  %s %s" % [name, detail])
		_ok = false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	await get_tree().process_frame
	var holds := 0
	for id in LevelDefs._defs().keys():
		var def: Dictionary = LevelDefs.get_def(id)
		for t in def.get("tasks", []):
			if t.get("type", "") != "survive":
				continue
			if EXEMPT.has(id):
				_check("%s: exempt hold stays bare (else drop it from EXEMPT)" % id,
					(t.get("waves", []) as Array).is_empty())
				continue
			holds += 1
			_check_hold(id, def, t)
	_check("campaign has wave-driven holds", holds >= 6, "%d" % holds)
	await _check_live()
	print("survive holds checked: %d" % holds)
	print("RESULT ", "PASS" if _ok else "FAIL")
	get_tree().quit()

## The def checks above know beds and platforms, not the baked navmesh. A walker
## spawned off-mesh stands still for the whole hold, so build each level for real
## and require every walking wave spawn to sit on (or right above) the mesh, with
## a path from there to the player spawn.
func _check_live() -> void:
	for id in LevelDefs._defs().keys():
		if EXEMPT.has(id):
			continue
		var def: Dictionary = LevelDefs.get_def(id)
		var walkers: Array = []
		for t in def.get("tasks", []):
			if t.get("type", "") != "survive":
				continue
			for w in t.get("waves", []):
				for en in w.get("enemies", []):
					var type: String = en.get("type", "")
					var p: Vector3 = en.get("pos", Vector3.ZERO)
					if SWIMMERS.has(type) or (FLYERS.has(type) and p.y >= AIR_Y):
						continue
					walkers.append({"type": type, "pos": p})
		if walkers.is_empty():
			continue
		var path := "res://scenes/levels/level_%s.tscn" % id
		if not ResourceLoader.exists(path):
			_check("%s: level scene exists for the live check" % id, false, path)
			continue
		var lvl: Node = (load(path) as PackedScene).instantiate()
		add_child(lvl)
		# Short waits, not one long timer: a long SceneTreeTimer stalls headless.
		for i in 10:
			await get_tree().create_timer(0.25).timeout
		var map := get_world_3d().get_navigation_map()
		var spawn: Vector3 = def.get("spawn", Vector3.ZERO)
		for wk in walkers:
			var p: Vector3 = wk["pos"]
			var near := NavigationServer3D.map_get_closest_point(map, p)
			var off := Vector2(near.x - p.x, near.z - p.z).length()
			_check("%s '%s' @%v stands on the navmesh" % [id, wk["type"], p], off < 1.0,
				"%.1f m off" % off)
			# A sniper on an unramped vantage deck is the campaign's own idiom
			# (desert places three that way): it shoots from there, it never walks.
			if PERCHERS.has(wk["type"]) and _on_platform(def, p, 0.5):
				continue
			var route := NavigationServer3D.map_get_path(map, near, spawn, true)
			var gap := 999.0
			if route.size() > 0:
				var e: Vector3 = route[route.size() - 1]
				gap = Vector2(e.x - spawn.x, e.z - spawn.z).length()
			_check("%s '%s' @%v can reach the player spawn" % [id, wk["type"], p], gap < 5.0,
				"gap %.1f" % gap)
		print("live: %s, %d walking wave spawns checked" % [id, walkers.size()])
		lvl.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

func _check_hold(id: String, def: Dictionary, t: Dictionary) -> void:
	var waves: Array = t.get("waves", [])
	var hold: float = float(t.get("seconds", 0.0))
	_check("%s: hold escalates" % id, waves.size() >= 2, "%d waves over %.0fs" % [waves.size(), hold])
	var prev := -1.0
	var bodies := 0
	for w in waves:
		var at: float = float(w.get("at", 0.0))
		_check("%s wave @%.0f fires inside the hold" % [id, at], at < hold, "%.0f < %.0f" % [at, hold])
		_check("%s wave @%.0f is ordered" % [id, at], at > prev)
		_check("%s wave @%.0f is announced" % [id, at], String(w.get("label", "")) != "")
		prev = at
		for en in w.get("enemies", []):
			var type: String = en.get("type", "")
			var count: int = maxi(1, int(en.get("count", 1)))
			bodies += count
			_check("%s wave enemy '%s' resolves" % [id, type], LevelBuilder.ENEMY_SCENES.has(type))
			_check_spawn(id, def, type, en.get("pos", Vector3.ZERO), count)
		for s in w.get("supplies", []):
			var kind: String = s.get("type", "")
			_check("%s supply '%s' resolves" % [id, kind], LevelBuilder.PICKUP_SCENES.has(kind))
			var sp: Vector3 = s.get("pos", Vector3.ZERO)
			_check("%s supply '%s' @%v is on safe ground" % [id, kind, sp],
				_on_platform(def, sp, 0.3) or not _in_any_bed(def, sp, 0.0))
	if not waves.is_empty():
		_check("%s: waves bring a real fight" % id, bodies >= 5, "%d enemies" % bodies)

func _check_spawn(id: String, def: Dictionary, type: String, p: Vector3, count: int) -> void:
	var tag := "%s '%s' @%v" % [id, type, p]
	if SWIMMERS.has(type):
		_check("%s swims, so must spawn in water" % tag, _in_any_bed(def, p, 0.0, true))
		return
	# Platform first: a sniper on a 2.7 m vantage deck is standing, not flying.
	if _on_platform(def, p, 0.5):
		_check("%s: clustered spawn on a platform scatters off it" % tag, count == 1)
		return
	if p.y >= AIR_Y:
		_check("%s is airborne, so must be a flyer" % tag, FLYERS.has(type))
		return
	var scatter := 2.5 if count > 1 else 0.0
	_check("%s clears every hazard bed" % tag, not _in_any_bed(def, p, scatter + 0.5))

## Is `p` standing on a platform top, `inset` metres in from its edge?
func _on_platform(def: Dictionary, p: Vector3, inset: float) -> bool:
	for pl in def.get("platforms", []):
		var c: Vector3 = pl["pos"]
		var s: Vector3 = pl["size"]
		var top: float = c.y + s.y * 0.5
		if p.y < top - 0.1 or p.y > top + 1.2:
			continue
		if absf(p.x - c.x) <= s.x * 0.5 - inset and absf(p.z - c.z) <= s.z * 0.5 - inset:
			return true
	return false

func _in_any_bed(def: Dictionary, p: Vector3, margin: float, water_only: bool = false) -> bool:
	for bed in def.get("lava", []):
		if water_only and not bed.get("water", false):
			continue
		var c: Vector3 = bed["pos"]
		var s: Vector2 = bed["size"]
		if absf(p.x - c.x) < s.x * 0.5 + margin and absf(p.z - c.z) < s.y * 0.5 + margin:
			return true
	return false
