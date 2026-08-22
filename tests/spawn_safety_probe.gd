extends Node3D
## Playtest instrument: SPAWN SAFETY. For every campaign level, loads the level and
## lets the real player stand at the spawn point with ZERO input, sampling health
## across the opening-seconds attack grace (GameState.start_attack_grace, 2.5s —
## 4.5s on the first level).
##
## Two distinct signals, deliberately not conflated:
##   * DURING grace  — enemies must not land damage at all. Any loss here is a
##     defect: an ungated attack path, or a spawn point sitting in a hazard.
##     This is what the probe FAILS on.
##   * AFTER grace   — the player is fair game. Reported as DPS-on-idle so the
##     difficulty curve can be read across levels; high is a balance note, not a
##     failure, since a real player would be moving and shooting back.
##   godot --headless --path . --audio-driver Dummy res://tests/spawn_safety_probe.tscn

const BUILD_WAIT := 2.4   ## level build + navmesh bake + spawner first tick
const POST_GRACE := 3.0   ## seconds of exposure measured after grace lapses
const SLICE := 0.25       ## short sampling slices keep autoload _process ticking

var _lvl: Node
var _fails: PackedStringArray = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("SPAWN  level         maxHP  duringGrace   afterGrace(dps)  grounded  flags")
	for path in GameState.CAMPAIGN:
		await _check(path)
	print("SPAWN_SAFETY fails=%d %s" % [_fails.size(), " ".join(_fails)])
	print("RESULT %s" % ("PASS" if _fails.is_empty() else "FAIL"))
	get_tree().quit()

func _check(path: String) -> void:
	var id := path.get_file().trim_prefix("level_").trim_suffix(".tscn")
	if not ResourceLoader.exists(path):
		print("SPAWN %-13s SKIP (no scene)" % id); return
	_lvl = (load(path) as PackedScene).instantiate()
	add_child(_lvl)
	# Poll for the player instead of sleeping through the build: the damage that
	# matters lands in the FIRST seconds, so the tap has to be connected the
	# moment the player node exists, not after a fixed wait.
	var player: CharacterBody3D = null
	var hp: Damageable = null
	var culprits: Dictionary = {}
	var waited := 0.0
	while waited < BUILD_WAIT:
		await get_tree().create_timer(SLICE).timeout
		waited += SLICE
		if player == null:
			player = get_tree().get_first_node_in_group("player") as CharacterBody3D
			if player != null:
				GameState.set_state(GameState.State.PLAYING)
				hp = player.get("hp")
				if hp != null:
					hp.damaged.connect(_blame.bind(culprits))
	if player == null:
		print("SPAWN %-13s NO-PLAYER" % id); _fails.append(id + ":no-player"); await _teardown(); return
	if hp == null:
		print("SPAWN %-13s NO-HP" % id); _fails.append(id + ":no-hp"); await _teardown(); return
	var hp_max: float = hp.max_health
	var p0: Vector3 = player.global_position
	# BASELINE IS max_health, NOT the health observed now: BUILD_WAIT already sits
	# inside the grace window, so anything that hit the player during those first
	# seconds must count as a leak too (that is exactly how lava at a spawn point
	# hid itself the first time round).
	var hp0: float = hp_max

	# Phase 1 — idle until the attack grace lapses. Nothing may damage the player.
	# Accounted from the `damaged` signal, testing attack_grace_active() AT THE
	# MOMENT OF THE HIT (see _blame). Polling health on a timer cannot do this:
	# an enemy holding its attack fires the instant grace lapses, so any sampling
	# loop straddles the boundary and blames the grace window for a fair hit.
	while GameState.attack_grace_active():
		await get_tree().create_timer(SLICE).timeout
	var during: float = 0.0
	for k in culprits: during += float(culprits[k])

	# Phase 2 — idle a fixed window with grace gone; measure incoming DPS.
	var t := 0.0
	var post_low: float = hp.current_health
	var hp_at_grace_end: float = hp.current_health
	while t < POST_GRACE and hp.is_alive():
		await get_tree().create_timer(SLICE).timeout
		t += SLICE
		post_low = minf(post_low, hp.current_health)
	var after: float = hp_at_grace_end - post_low
	var dps: float = after / maxf(t, SLICE)

	var grounded := player.is_on_floor()
	var fell: float = p0.y - player.global_position.y
	var flags: PackedStringArray = []
	if during > 0.01: flags.append("GRACE-LEAK")
	if not grounded: flags.append("NOT-GROUNDED")
	if fell > 3.0: flags.append("FELL")
	var blame := ""
	if not culprits.is_empty():
		var parts: PackedStringArray = []
		for k in culprits: parts.append("%s=%.0f" % [k, culprits[k]])
		blame = "  <- " + ", ".join(parts)
	print("SPAWN %-13s %5.0f  %8.1f  %10.1f (%5.1f/s)  %-8s %s%s" % [
		id, hp_max, during, after, dps, grounded, " ".join(flags), blame])
	if not flags.is_empty():
		_fails.append(id + ":" + "/".join(flags))
	await _teardown()

## Records what landed on the player while the fairness grace was active. The
## source NAME is the point — a bare number cannot tell a hazard from an ungated
## attack, and the two need opposite fixes.
func _blame(amount: float, source: Node, culprits: Dictionary) -> void:
	if not GameState.attack_grace_active():
		return
	var who := "unknown"
	if is_instance_valid(source):
		who = str(source.name)
		var sc = source.get_script()
		if sc: who = str(sc.resource_path).get_file().trim_suffix(".gd")
	culprits[who] = float(culprits.get(who, 0.0)) + amount

func _teardown() -> void:
	if is_instance_valid(_lvl):
		_lvl.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e): e.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
